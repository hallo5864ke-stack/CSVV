--!strict
-- Driver-side vehicle control. While the local player sits in a driver's
-- seat this module reads input, runs VehiclePhysics for that car every
-- physics frame and reports state to the server.
--
-- Keys: W/S accelerate / brake-reverse, A/D steer, Space handbrake,
-- Q/E turn signals, H hazards, L headlights, F leave the car, R recover.
-- Gamepad: R2 / L2, left stick, A handbrake.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("DrivingSim")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Vehicles = require(Shared.Config.Vehicles)
local VehiclePhysics = require(Shared.VehiclePhysics)

local HANDBRAKE_ACTION = "DS_Handbrake"
-- Steering past this fraction of lock arms the turn-signal self-cancel.
local CANCEL_ARM = 0.3
local CANCEL_RELEASE = 0.06

export type Session = {
	model: Model,
	config: Types.VehicleConfig,
	physics: VehiclePhysics.VehiclePhysics,
	input: Types.DriveInput,
}

local VehicleController = {}

local player = Players.LocalPlayer
local session: Session? = nil
local connections: { RBXScriptConnection } = {}
local handbrakeHeld = false
local signalArmed = false
local telemetryClock = 0
local gamepad = { throttle = 0, brake = 0, steer = 0 }

local actionRemote: RemoteEvent
local telemetryRemote: UnreliableRemoteEvent

function VehicleController.getSession(): Session?
	return session
end

local function key(code: Enum.KeyCode): number
	return if UserInputService:IsKeyDown(code) then 1 else 0
end

local function readInput(input: Types.DriveInput)
	if UserInputService:GetFocusedTextBox() then
		input.throttle, input.brake, input.steer = 0, 0, 0
		input.handbrake = handbrakeHeld
		return
	end
	input.throttle = math.max(key(Enum.KeyCode.W), key(Enum.KeyCode.Up), gamepad.throttle)
	input.brake = math.max(key(Enum.KeyCode.S), key(Enum.KeyCode.Down), gamepad.brake)
	local keyboardSteer = math.max(key(Enum.KeyCode.D), key(Enum.KeyCode.Right))
		- math.max(key(Enum.KeyCode.A), key(Enum.KeyCode.Left))
	input.steer = if keyboardSteer ~= 0 then keyboardSteer else gamepad.steer
	input.handbrake = handbrakeHeld
end

local function setSignal(model: Model, wanted: string)
	local current = model:GetAttribute("Signal")
	actionRemote:FireServer("Signal", if current == wanted then Constants.SIGNAL_OFF else wanted)
	signalArmed = false
end

local function onKey(inputObject: InputObject, processed: boolean)
	local active = session
	if processed or not active then
		return
	end
	local code = inputObject.KeyCode
	if code == Enum.KeyCode.Q or code == Enum.KeyCode.DPadLeft then
		setSignal(active.model, Constants.SIGNAL_LEFT)
	elseif code == Enum.KeyCode.E or code == Enum.KeyCode.DPadRight then
		setSignal(active.model, Constants.SIGNAL_RIGHT)
	elseif code == Enum.KeyCode.H or code == Enum.KeyCode.DPadDown then
		setSignal(active.model, Constants.SIGNAL_HAZARD)
	elseif code == Enum.KeyCode.L or code == Enum.KeyCode.DPadUp then
		local current = active.model:GetAttribute("Headlights")
		actionRemote:FireServer("Headlights", ((if typeof(current) == "number" then current else 0) + 1) % 3)
	elseif code == Enum.KeyCode.F or code == Enum.KeyCode.ButtonY then
		actionRemote:FireServer("Exit")
	elseif code == Enum.KeyCode.R then
		actionRemote:FireServer("Recover")
	end
end

local function onGamepad(inputObject: InputObject)
	if inputObject.UserInputType ~= Enum.UserInputType.Gamepad1 then
		return
	end
	if inputObject.KeyCode == Enum.KeyCode.ButtonR2 then
		gamepad.throttle = inputObject.Position.Z
	elseif inputObject.KeyCode == Enum.KeyCode.ButtonL2 then
		gamepad.brake = inputObject.Position.Z
	elseif inputObject.KeyCode == Enum.KeyCode.Thumbstick1 then
		local x = inputObject.Position.X
		gamepad.steer = if math.abs(x) > 0.12 then x else 0
	end
end

-- Turn signals switch themselves off once the wheel returns after a turn.
local function updateSelfCancel(active: Session)
	local signal = active.model:GetAttribute("Signal")
	local direction = if signal == Constants.SIGNAL_LEFT then -1 elseif signal == Constants.SIGNAL_RIGHT then 1 else 0
	if direction == 0 then
		signalArmed = false
		return
	end
	local steer = active.physics.sim.steer * direction
	if steer > CANCEL_ARM then
		signalArmed = true
	elseif signalArmed and steer < CANCEL_RELEASE then
		signalArmed = false
		actionRemote:FireServer("Signal", Constants.SIGNAL_OFF)
	end
end

local function step(dt: number)
	local active = session
	if not active then
		return
	end
	readInput(active.input)
	active.physics:Step(dt, active.input)
	updateSelfCancel(active)

	telemetryClock += dt
	if telemetryClock >= 1 / Constants.TELEMETRY_HZ then
		telemetryClock = 0
		local sim = active.physics.sim
		telemetryRemote:FireServer(
			sim.steer,
			sim.braking,
			sim.reversing,
			sim.power.rpm,
			sim.power.gear,
			sim.fuel,
			sim.temperature
		)
	end
end

local function stopDriving()
	if not session then
		return
	end
	session = nil
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	ContextActionService:UnbindAction(HANDBRAKE_ACTION)
	ProximityPromptService.Enabled = true
	handbrakeHeld = false
end

local function startDriving(model: Model)
	stopDriving()
	local id = model:GetAttribute("ConfigId")
	local config = if typeof(id) == "string" then Vehicles.get(id) else nil
	if not config or not model.PrimaryPart then
		return
	end
	local physics = VehiclePhysics.new(model, config)
	-- Carry over what the car had when the last driver left it.
	local fuel = model:GetAttribute("Fuel")
	if typeof(fuel) == "number" then
		physics.sim.fuel = fuel
	end
	local temperature = model:GetAttribute("EngineTemp")
	if typeof(temperature) == "number" then
		physics.sim.temperature = temperature
	end
	session = {
		model = model,
		config = config,
		physics = physics,
		input = { throttle = 0, brake = 0, steer = 0, handbrake = false, ignition = true },
	}
	signalArmed = false
	telemetryClock = 0
	-- No entry prompts for other cars while driving.
	ProximityPromptService.Enabled = false

	-- Space is the handbrake; sinking it here keeps the character from
	-- jumping out of the seat.
	ContextActionService:BindActionAtPriority(HANDBRAKE_ACTION, function(_, state)
		handbrakeHeld = state == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 50, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)

	table.insert(connections, RunService.PreSimulation:Connect(step))
	table.insert(connections, UserInputService.InputBegan:Connect(onKey))
	table.insert(connections, UserInputService.InputChanged:Connect(onGamepad))
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local function refresh()
		local seat = humanoid.SeatPart
		local model = if seat and seat.Name == "DriverSeat" then seat:FindFirstAncestorOfClass("Model") else nil
		if model and model:HasTag(Constants.VEHICLE_TAG) then
			startDriving(model)
		else
			stopDriving()
		end
	end
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(refresh)
	humanoid.Died:Connect(stopDriving)
	refresh()
end

function VehicleController.start()
	actionRemote = Remotes.action()
	telemetryRemote = Remotes.telemetry()
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
end

return VehicleController
