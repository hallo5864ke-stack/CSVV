--!strict
-- Raycast-suspension chassis: connects the engine-independent VehicleSim to
-- a Roblox vehicle model. Each step it casts one ray per wheel, feeds the
-- contact data to the simulation and applies the resulting forces to the
-- chassis. Runs on whichever machine owns the chassis physics: the driver's
-- client while driving, the server while the car is parked.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Constants = require(script.Parent.Constants)
local Surfaces = require(script.Parent.Config.Surfaces)
local Types = require(script.Parent.Types)
local VehicleSim = require(script.Parent.Physics.VehicleSim)

local SPM = Constants.STUDS_PER_METER
local MPS = Constants.METERS_PER_STUD
-- The ray starts this far (m) above the fully compressed wheel centre so a
-- wheel pushed past its travel still finds the ground.
local HEADROOM = 0.25
-- Ground steeper than this (normal . up) is a wall, not a road.
local MIN_GROUND_DOT = 0.35
local IGNORE_REFRESH = 2

local VehiclePhysics = {}
VehiclePhysics.__index = VehiclePhysics

type Hit = {
	position: Vector3,
	normal: Vector3,
	forward: Vector3,
	right: Vector3,
}

type Fields = {
	model: Model,
	chassis: BasePart,
	config: Types.VehicleConfig,
	sim: VehicleSim.Sim,
	params: RaycastParams,
	contacts: { Types.WheelContact },
	hits: { Hit },
	body: Types.BodyState,
	ignoreAge: number,
}
export type VehiclePhysics = typeof(setmetatable({} :: Fields, VehiclePhysics))

function VehiclePhysics.new(model: Model, config: Types.VehicleConfig): VehiclePhysics
	local chassis = model.PrimaryPart
	assert(chassis, "vehicle model has no PrimaryPart")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	params.RespectCanCollide = true

	local contacts: { Types.WheelContact } = {}
	local hits: { Hit } = {}
	for i = 1, 4 do
		contacts[i] = {
			grounded = false,
			compression = 0,
			compressionRate = 0,
			vF = 0,
			vR = 0,
			gF = 0,
			gR = 0,
			mu = 1,
			rolling = 1,
		}
		hits[i] = { position = Vector3.zero, normal = Vector3.yAxis, forward = Vector3.zAxis, right = Vector3.xAxis }
	end

	local fields: Fields = {
		model = model,
		chassis = chassis,
		config = config,
		sim = VehicleSim.new(config),
		params = params,
		contacts = contacts,
		hits = hits,
		body = { forwardSpeed = 0, lateralSpeed = 0, speed = 0 },
		ignoreAge = math.huge,
	}
	return setmetatable(fields, VehiclePhysics)
end

-- Wheel rays must pass through player characters (including the driver).
local function refreshIgnoreList(self: VehiclePhysics)
	local list: { Instance } = { self.model }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	self.params.FilterDescendantsInstances = list
	self.ignoreAge = 0
end

function VehiclePhysics.Step(self: VehiclePhysics, frameTime: number, input: Types.DriveInput)
	local chassis = self.chassis
	if chassis.Anchored then
		return
	end
	local dt = math.clamp(frameTime, 1 / 240, 1 / 30)
	self.ignoreAge += dt
	if self.ignoreAge > IGNORE_REFRESH then
		refreshIgnoreList(self)
	end

	local sim = self.sim
	local cframe = chassis.CFrame
	local up, forward, right = cframe.UpVector, cframe.LookVector, cframe.RightVector
	local velocity = chassis.AssemblyLinearVelocity * MPS
	local body = self.body
	body.forwardSpeed = velocity:Dot(forward)
	body.lateralSpeed = velocity:Dot(right)
	body.speed = velocity.Magnitude

	for i, geo in sim.geometry.wheels do
		local contact = self.contacts[i]
		local reach = HEADROOM + geo.travel + geo.radius
		local originLocal = Vector3.new(geo.x, geo.y + geo.travel - geo.staticCompression + HEADROOM, geo.z) * SPM
		local result = Workspace:Raycast(cframe:PointToWorldSpace(originLocal), -up * reach * SPM, self.params)
		if result and result.Normal:Dot(up) > MIN_GROUND_DOT then
			local normal = result.Normal
			local position = result.Position
			local pointVelocity = chassis:GetVelocityAtPosition(position)
			local ground = result.Instance
			if not ground.Anchored then
				pointVelocity -= ground:GetVelocityAtPosition(position)
			end
			pointVelocity *= MPS
			local groundForward = forward - normal * forward:Dot(normal)
			groundForward = if groundForward.Magnitude > 1e-3 then groundForward.Unit else forward
			local groundRight = groundForward:Cross(normal)
			local surface = Surfaces.resolve(ground, result.Material)

			contact.grounded = true
			contact.compression = reach - result.Distance * MPS
			contact.compressionRate = -pointVelocity:Dot(normal)
			contact.vF = pointVelocity:Dot(groundForward)
			contact.vR = pointVelocity:Dot(groundRight)
			contact.gF = -Constants.GRAVITY * groundForward.Y
			contact.gR = -Constants.GRAVITY * groundRight.Y
			contact.mu = surface.mu
			contact.rolling = surface.rolling

			local hit = self.hits[i]
			hit.position = position
			hit.normal = normal
			hit.forward = groundForward
			hit.right = groundRight
		else
			contact.grounded = false
		end
	end

	sim:step(dt, input, self.contacts, body)

	-- Mass is authored in kilograms and lengths in studs, so newtons scale
	-- by studs-per-metre to become Roblox force units.
	local impulseScale = dt * SPM
	for i, wheel in sim.wheels do
		if wheel.grounded then
			local hit = self.hits[i]
			local force = hit.normal * wheel.load + hit.forward * wheel.forceF + hit.right * wheel.forceR
			chassis:ApplyImpulseAtPosition(force * impulseScale, hit.position)
		end
	end
	if body.speed > 0.1 then
		chassis:ApplyImpulse((-velocity.Unit * sim.dragForce - up * sim.downforce) * impulseScale)
	end
end

return VehiclePhysics
