--!strict
-- Animates wheels on every client: suspension travel, steering angle and
-- rolling. The car being driven locally uses the exact simulation state;
-- other cars are reconstructed from their replicated motion and "Steer"
-- attribute. Only the wheel Weld offsets change, so physics is unaffected.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DrivingSim")
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local Vehicles = require(Shared.Config.Vehicles)
local Geometry = require(Shared.Physics.Geometry)
local Steering = require(Shared.Physics.Steering)
local VehicleController = require(script.Parent.VehicleController)

local SPM = Constants.STUDS_PER_METER
local MPS = Constants.METERS_PER_STUD
local MAX_DISTANCE = 500

type Entry = {
	chassis: BasePart,
	config: Types.VehicleConfig,
	geometry: Types.Geometry,
	welds: { Weld },
	rest: { CFrame },
	spin: { number },
	steer: number,
	settled: boolean,
}

local WheelVisuals = {}

local entries: { [Model]: Entry } = {}

local function track(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local chassis = model:WaitForChild("Chassis", 10)
	local id = model:GetAttribute("ConfigId")
	local config = if typeof(id) == "string" then Vehicles.get(id) else nil
	if not chassis or not chassis:IsA("BasePart") or not config then
		return
	end
	local geometry = Geometry.compute(config)
	local welds: { Weld } = {}
	local rest: { CFrame } = {}
	for index, wheel in geometry.wheels do
		local weld = chassis:WaitForChild("Wheel_" .. wheel.name, 10)
		if not weld or not weld:IsA("Weld") then
			return
		end
		welds[index] = weld
		rest[index] = CFrame.new(Vector3.new(wheel.x, wheel.y, wheel.z) * SPM)
	end
	entries[model] = {
		chassis = chassis,
		config = config,
		geometry = geometry,
		welds = welds,
		rest = rest,
		spin = { 0, 0, 0, 0 },
		steer = 0,
		settled = false,
	}
end

local function pose(entry: Entry, index: number, lift: number, steerAngle: number, spin: number)
	-- Positive steer is a right turn, which is a negative rotation about +Y;
	-- rolling forward (-Z) is a negative rotation about +X.
	entry.welds[index].C0 = entry.rest[index]
		* CFrame.new(0, lift * SPM, 0)
		* CFrame.Angles(0, -steerAngle, 0)
		* CFrame.Angles(-spin, 0, 0)
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	local session = VehicleController.getSession()
	for model, entry in entries do
		if session and session.model == model then
			local sim = session.physics.sim
			for index, wheel in sim.wheels do
				local geo = entry.geometry.wheels[index]
				-- Airborne wheels hang at full droop.
				local compression = if wheel.grounded then wheel.compression else 0
				pose(entry, index, compression - geo.staticCompression, wheel.steerAngle, wheel.spin)
			end
			entry.settled = false
			continue
		end

		local chassis = entry.chassis
		local velocity = chassis.AssemblyLinearVelocity
		local steerAttribute = model:GetAttribute("Steer")
		local targetSteer = if typeof(steerAttribute) == "number" then steerAttribute else 0
		local moving = velocity.Magnitude > 0.05 or math.abs(targetSteer - entry.steer) > 0.001
		if not moving and entry.settled then
			continue
		end
		if camera and (camera.CFrame.Position - chassis.Position).Magnitude > MAX_DISTANCE then
			continue
		end
		local forwardSpeed = velocity:Dot(chassis.CFrame.LookVector) * MPS
		entry.steer += (targetSteer - entry.steer) * math.min(1, dt * 10)
		local angle = entry.steer * Steering.maxAngle(entry.config, math.abs(forwardSpeed))
		local leftAngle, rightAngle = Steering.ackermann(entry.config, angle)
		for index, geo in entry.geometry.wheels do
			entry.spin[index] = (entry.spin[index] + forwardSpeed / geo.radius * dt) % (2 * math.pi)
			local steerAngle = if not geo.front then 0 elseif geo.side < 0 then leftAngle else rightAngle
			pose(entry, index, 0, steerAngle, entry.spin[index])
		end
		entry.settled = not moving
	end
end

function WheelVisuals.start()
	CollectionService:GetInstanceAddedSignal(Constants.VEHICLE_TAG):Connect(function(model)
		task.spawn(track, model)
	end)
	CollectionService:GetInstanceRemovedSignal(Constants.VEHICLE_TAG):Connect(function(model)
		entries[model :: Model] = nil
	end)
	for _, model in CollectionService:GetTagged(Constants.VEHICLE_TAG) do
		task.spawn(track, model)
	end
	RunService.PreRender:Connect(update)
end

return WheelVisuals
