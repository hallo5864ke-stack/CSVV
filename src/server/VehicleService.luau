--!strict
-- Server authority over vehicles: who drives what, network ownership,
-- validation of everything the driver's client reports, and physics for
-- cars nobody is driving. Clients never name a vehicle in a request; the
-- server always uses the one the sender is seated in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("DrivingSim")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local VehiclePhysics = require(Shared.VehiclePhysics)

local SPM = Constants.STUDS_PER_METER
local MPS = Constants.METERS_PER_STUD

local PARKED_INPUT: Types.DriveInput = { throttle = 0, brake = 0, steer = 0, handbrake = true, ignition = false }
-- A parked car is anchored once it has been still this long (s).
local REST_TIME = 1.5
local ACTIONS_PER_SECOND = 20
local TELEMETRY_PER_SECOND = 40
-- Speed above the car's limit that counts as tampering (ratio, plus km/h).
local SPEED_TOLERANCE = 1.25
local SPEED_MARGIN_KMH = 25
local VOID_HEIGHT = -150

type Record = {
	model: Model,
	config: Types.VehicleConfig,
	chassis: BasePart,
	seat: Seat,
	prompt: ProximityPrompt,
	physics: VehiclePhysics.VehiclePhysics,
	driver: Player?,
	restTime: number,
	spawnFrame: CFrame,
}

type Budget = { window: number, actions: number, telemetry: number }

local VehicleService = {}

local records: { [Model]: Record } = {}
local byPlayer: { [Player]: Record } = {}
local budgets: { [Player]: Budget } = {}

local VALID_SIGNALS = {
	[Constants.SIGNAL_OFF] = true,
	[Constants.SIGNAL_LEFT] = true,
	[Constants.SIGNAL_RIGHT] = true,
	[Constants.SIGNAL_HAZARD] = true,
}

local function isNumber(value: any, lo: number, hi: number): boolean
	return typeof(value) == "number" and value == value and value >= lo and value <= hi
end

-- Per-player rate limit shared by both remotes.
local function withinBudget(player: Player, kind: "actions" | "telemetry"): boolean
	local now = os.clock()
	local current = budgets[player]
	local budget: Budget = if current and now - current.window < 1
		then current
		else { window = now, actions = 0, telemetry = 0 }
	budgets[player] = budget
	if kind == "actions" then
		budget.actions += 1
		return budget.actions <= ACTIONS_PER_SECOND
	end
	budget.telemetry += 1
	return budget.telemetry <= TELEMETRY_PER_SECOND
end

local function release(record: Record)
	local driver = record.driver
	if driver and byPlayer[driver] == record then
		byPlayer[driver] = nil
	end
	record.driver = nil
	record.restTime = 0
	record.model:SetAttribute("DriverUserId", 0)
	record.model:SetAttribute("Braking", false)
	record.model:SetAttribute("Reversing", false)
	record.model:SetAttribute("Steer", 0)
	record.model:SetAttribute("Rpm", 0)
	if record.model:GetAttribute("Signal") ~= Constants.SIGNAL_HAZARD then
		record.model:SetAttribute("Signal", Constants.SIGNAL_OFF)
	end
	record.prompt.Enabled = true
	if record.chassis:IsDescendantOf(workspace) and not record.chassis.Anchored then
		record.chassis:SetNetworkOwner(nil)
	end
end

local function onOccupantChanged(record: Record)
	local humanoid = record.seat.Occupant
	local player = humanoid and Players:GetPlayerFromCharacter(humanoid.Parent)
	if not player then
		if record.driver then
			release(record)
		end
		return
	end
	local previous = byPlayer[player]
	if previous and previous ~= record then
		release(previous)
	end
	record.driver = player
	byPlayer[player] = record
	record.prompt.Enabled = false
	record.chassis.Anchored = false
	record.chassis:SetNetworkOwner(player)
	record.model:SetAttribute("DriverUserId", player.UserId)
end

-- Puts a car back on its wheels where it is (or at its spawn point).
local function recover(record: Record, toSpawn: boolean)
	local chassis = record.chassis
	local driver = record.driver
	chassis.Anchored = false
	chassis:SetNetworkOwner(nil)
	local target = record.spawnFrame
	if not toSpawn then
		local look = chassis.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
		local position = chassis.Position + Vector3.new(0, 1 * SPM, 0)
		target = CFrame.lookAt(position, position + flat)
	end
	record.model:PivotTo(target)
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	record.restTime = 0
	-- Hand physics back to the driver once the corrected pose has replicated.
	task.delay(0.2, function()
		if driver and record.driver == driver and not chassis.Anchored then
			chassis:SetNetworkOwner(driver)
		end
	end)
end

local function onAction(player: Player, action: any, value: any)
	if not withinBudget(player, "actions") or typeof(action) ~= "string" then
		return
	end
	local record = byPlayer[player]
	if not record then
		return
	end
	if action == "Signal" then
		if typeof(value) == "string" and VALID_SIGNALS[value] then
			record.model:SetAttribute("Signal", value)
		end
	elseif action == "Headlights" then
		if
			value == Constants.HEADLIGHTS_OFF
			or value == Constants.HEADLIGHTS_LOW
			or value == Constants.HEADLIGHTS_HIGH
		then
			record.model:SetAttribute("Headlights", value)
		end
	elseif action == "Exit" then
		local humanoid = record.seat.Occupant
		local character = player.Character
		if humanoid and character then
			local side = record.chassis.CFrame
				* CFrame.new(-(record.config.dimensions.width / 2 + 1.2) * SPM, 1 * SPM, 0)
			humanoid.Sit = false
			task.defer(function()
				if character.Parent then
					character:PivotTo(CFrame.new(side.Position) * record.chassis.CFrame.Rotation)
				end
			end)
		end
	elseif action == "Recover" then
		-- Only for a car that is stuck or on its roof, not as a teleport.
		if record.chassis.AssemblyLinearVelocity.Magnitude * MPS < 3 then
			recover(record, false)
		end
	end
end

local function onTelemetry(
	player: Player,
	steer: any,
	braking: any,
	reversing: any,
	rpm: any,
	gear: any,
	fuel: any,
	temperature: any
)
	if not withinBudget(player, "telemetry") then
		return
	end
	local record = byPlayer[player]
	if not record then
		return
	end
	local config = record.config
	if
		not isNumber(steer, -1, 1)
		or typeof(braking) ~= "boolean"
		or typeof(reversing) ~= "boolean"
		or not isNumber(rpm, 0, config.engine.limiterRpm + 100)
		or not isNumber(gear, -1, #config.transmission.gears)
		or not isNumber(fuel, 0, config.fuel.tankLitres)
		or not isNumber(temperature, -50, 150)
	then
		return
	end
	local model = record.model
	model:SetAttribute("Steer", math.round(steer * 20) / 20)
	model:SetAttribute("Braking", braking)
	model:SetAttribute("Reversing", reversing)
	model:SetAttribute("Rpm", math.round(rpm / 50) * 50)
	model:SetAttribute("Gear", math.round(gear))
	-- Fuel only ever goes down; a client cannot refill its own tank.
	local known = model:GetAttribute("Fuel")
	if typeof(known) == "number" then
		model:SetAttribute("Fuel", math.min(known, math.round(fuel * 10) / 10))
	end
	model:SetAttribute("EngineTemp", math.round(temperature))
end

-- Physics for cars without a driver: handbrake on, then anchor at rest.
local function stepParked(dt: number)
	for _, record in records do
		local chassis = record.chassis
		if record.driver or chassis.Anchored then
			continue
		end
		record.physics:Step(dt, PARKED_INPUT)
		local still = chassis.AssemblyLinearVelocity.Magnitude < 0.2
			and chassis.AssemblyAngularVelocity.Magnitude < 0.05
		record.restTime = if still then record.restTime + dt else 0
		if record.restTime >= REST_TIME then
			chassis.AssemblyLinearVelocity = Vector3.zero
			chassis.AssemblyAngularVelocity = Vector3.zero
			chassis.Anchored = true
		end
	end
end

-- Catches impossible speeds from a tampered client and cars that left the map.
local function audit()
	for _, record in records do
		local chassis = record.chassis
		if chassis.Position.Y < VOID_HEIGHT then
			recover(record, true)
			continue
		end
		if record.driver then
			local kmh = chassis.AssemblyLinearVelocity.Magnitude * MPS * Constants.MS_TO_KMH
			if kmh > record.config.limits.topSpeedKmh * SPEED_TOLERANCE + SPEED_MARGIN_KMH then
				warn(
					`[DrivingSim] {record.driver.Name} exceeded the speed envelope of {record.config.id}: {math.round(
						kmh
					)} km/h`
				)
				recover(record, false)
			end
		end
	end
end

function VehicleService.register(model: Model, config: Types.VehicleConfig, spawnFrame: CFrame)
	local chassis = model.PrimaryPart
	assert(chassis, "vehicle has no chassis")
	local seat = model:FindFirstChild("DriverSeat", true)
	local prompt = model:FindFirstChild("EnterPrompt", true)
	assert(seat and seat:IsA("Seat"), "vehicle has no DriverSeat")
	assert(prompt and prompt:IsA("ProximityPrompt"), "vehicle has no EnterPrompt")

	model:SetAttribute("DriverUserId", 0)
	model:SetAttribute("Headlights", Constants.HEADLIGHTS_OFF)
	model:SetAttribute("Signal", Constants.SIGNAL_OFF)
	model:SetAttribute("Braking", false)
	model:SetAttribute("Reversing", false)
	model:SetAttribute("Steer", 0)
	model:SetAttribute("Rpm", 0)
	model:SetAttribute("Gear", 1)
	model:SetAttribute("Fuel", config.fuel.tankLitres)
	model:SetAttribute("EngineTemp", 20)

	local record: Record = {
		model = model,
		config = config,
		chassis = chassis,
		seat = seat,
		prompt = prompt,
		physics = VehiclePhysics.new(model, config),
		driver = nil,
		restTime = 0,
		spawnFrame = spawnFrame,
	}
	records[model] = record

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		onOccupantChanged(record)
	end)
	prompt.Triggered:Connect(function(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and not seat.Occupant and not byPlayer[player] then
			seat:Sit(humanoid)
		end
	end)
	model.Destroying:Connect(function()
		release(record)
		records[model] = nil
	end)
end

function VehicleService.start()
	Remotes.action().OnServerEvent:Connect(onAction)
	Remotes.telemetry().OnServerEvent:Connect(onTelemetry)
	RunService.PreSimulation:Connect(stepParked)
	Players.PlayerRemoving:Connect(function(player)
		budgets[player] = nil
		local record = byPlayer[player]
		if record then
			release(record)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			audit()
		end
	end)
end

return VehicleService
