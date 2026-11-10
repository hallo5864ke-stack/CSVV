--!strict
-- Draws every vehicle's lights from its replicated attributes (Headlights,
-- Signal, Braking, Reversing). Runs on each client so indicators blink in
-- step for all players (phase comes from the shared server clock) and the
-- driver's own brake lights react without network delay.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DrivingSim")
local Constants = require(Shared.Constants)
local VehicleController = require(script.Parent.VehicleController)

type Lamp = {
	part: BasePart,
	role: string,
	onColor: Color3,
	offColor: Color3,
	light: Light?,
	lit: boolean?,
}

type Entry = {
	lamps: { Lamp },
	headlights: number,
}

local VehicleLights = {}

local entries: { [Model]: Entry } = {}

local function track(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local folder = model:WaitForChild("Lights", 10)
	if not folder then
		return
	end
	local lamps: { Lamp } = {}
	for _, part in folder:GetChildren() do
		local role = part:GetAttribute("Role")
		local onColor, offColor = part:GetAttribute("OnColor"), part:GetAttribute("OffColor")
		if
			part:IsA("BasePart")
			and typeof(role) == "string"
			and typeof(onColor) == "Color3"
			and typeof(offColor) == "Color3"
		then
			table.insert(lamps, {
				part = part,
				role = role,
				onColor = onColor,
				offColor = offColor,
				light = part:FindFirstChildWhichIsA("Light"),
				lit = nil,
			})
		end
	end
	entries[model] = { lamps = lamps, headlights = -1 }
end

local function setLamp(lamp: Lamp, lit: boolean)
	if lamp.lit == lit then
		return
	end
	lamp.lit = lit
	lamp.part.Material = if lit then Enum.Material.Neon else Enum.Material.Glass
	lamp.part.Color = if lit then lamp.onColor else lamp.offColor
	if lamp.light then
		lamp.light.Enabled = lit
	end
end

local function update()
	local blinkOn = (Workspace:GetServerTimeNow() * Constants.BLINK_HZ) % 1 < 0.5
	local session = VehicleController.getSession()
	for model, entry in entries do
		local headlights = model:GetAttribute("Headlights")
		local signal = model:GetAttribute("Signal")
		local braking = model:GetAttribute("Braking") == true
		local reversing = model:GetAttribute("Reversing") == true
		if session and session.model == model then
			braking = session.physics.sim.braking
			reversing = session.physics.sim.reversing
		end
		local level = if typeof(headlights) == "number" then headlights else 0
		local left = blinkOn and (signal == Constants.SIGNAL_LEFT or signal == Constants.SIGNAL_HAZARD)
		local right = blinkOn and (signal == Constants.SIGNAL_RIGHT or signal == Constants.SIGNAL_HAZARD)

		for _, lamp in entry.lamps do
			if lamp.role == "Head" then
				setLamp(lamp, level > 0)
				if entry.headlights ~= level and lamp.light and lamp.light:IsA("SpotLight") then
					local high = level == Constants.HEADLIGHTS_HIGH
					lamp.light.Range = if high then 60 else 42
					lamp.light.Brightness = if high then 6 else 3
					lamp.light.Angle = if high then 55 else 75
				end
			elseif lamp.role == "Tail" then
				setLamp(lamp, level > 0)
			elseif lamp.role == "Brake" then
				setLamp(lamp, braking)
			elseif lamp.role == "Reverse" then
				setLamp(lamp, reversing)
			elseif lamp.role == "TurnL" then
				setLamp(lamp, left)
			elseif lamp.role == "TurnR" then
				setLamp(lamp, right)
			end
		end
		entry.headlights = level
	end
end

function VehicleLights.start()
	CollectionService:GetInstanceAddedSignal(Constants.VEHICLE_TAG):Connect(function(model)
		task.spawn(track, model)
	end)
	CollectionService:GetInstanceRemovedSignal(Constants.VEHICLE_TAG):Connect(function(model)
		entries[model :: Model] = nil
	end)
	for _, model in CollectionService:GetTagged(Constants.VEHICLE_TAG) do
		task.spawn(track, model)
	end
	RunService.Heartbeat:Connect(update)
end

return VehicleLights
