--!strict
-- Complete vehicle simulation step, independent of the Roblox engine.
-- The caller (VehiclePhysics in Roblox, or the headless tests) measures each
-- wheel's contact with the ground and applies the forces this returns.
-- Wheel order is always FL, FR, RL, RR.

local Types = require(script.Parent.Parent.Types)
local Geometry = require(script.Parent.Geometry)
local Powertrain = require(script.Parent.Powertrain)
local Steering = require(script.Parent.Steering)
local TireModel = require(script.Parent.TireModel)

local GRAVITY = 9.81
local AIR_DENSITY = 1.225
local FUEL_DENSITY = 745 -- g per litre of petrol
local AMBIENT_TEMPERATURE = 20
local BUMP_STOP_STIFFNESS = 8
-- Below this speed (m/s) holding the opposite pedal selects the other direction.
local STANDSTILL_SPEED = 0.4
local REVERSE_DELAY = 0.35
local DRIVE_DELAY = 0.15

export type WheelState = {
	grounded: boolean,
	compression: number,
	load: number,
	-- Tyre force along the body's forward / right ground directions (N).
	forceF: number,
	forceR: number,
	steerAngle: number,
	angularVelocity: number,
	spin: number,
	slipping: boolean,
}

local VehicleSim = {}
VehicleSim.__index = VehicleSim

type Fields = {
	config: Types.VehicleConfig,
	geometry: Types.Geometry,
	power: Powertrain.State,
	wheels: { WheelState },
	peakPowerKw: number,
	-- 1 = drive, -1 = reverse.
	direction: number,
	directionTimer: number,
	steer: number,
	steerAngle: number,
	throttle: number,
	brake: number,
	braking: boolean,
	reversing: boolean,
	running: boolean,
	stabilityActive: boolean,
	speedKmh: number,
	dragForce: number,
	downforce: number,
	fuel: number,
	temperature: number,
}
export type Sim = typeof(setmetatable({} :: Fields, VehicleSim))

function VehicleSim.new(config: Types.VehicleConfig): Sim
	local wheels: { WheelState } = {}
	for _ = 1, 4 do
		table.insert(wheels, {
			grounded = false,
			compression = 0,
			load = 0,
			forceF = 0,
			forceR = 0,
			steerAngle = 0,
			angularVelocity = 0,
			spin = 0,
			slipping = false,
		})
	end
	local fields: Fields = {
		config = config,
		geometry = Geometry.compute(config),
		power = Powertrain.new(),
		wheels = wheels,
		peakPowerKw = Powertrain.peakPowerKw(config),
		direction = 1,
		directionTimer = 0,
		steer = 0,
		steerAngle = 0,
		throttle = 0,
		brake = 0,
		braking = false,
		reversing = false,
		running = false,
		stabilityActive = false,
		speedKmh = 0,
		dragForce = 0,
		downforce = 0,
		fuel = config.fuel.tankLitres,
		temperature = AMBIENT_TEMPERATURE,
	}
	return setmetatable(fields, VehicleSim)
end

-- Maps the two pedals to throttle / brake for the current direction and
-- switches between drive and reverse at standstill.
local function resolvePedals(self: Sim, dt: number, input: Types.DriveInput, forwardSpeed: number): (number, number)
	local forwardKey = math.clamp(input.throttle, 0, 1)
	local backKey = math.clamp(input.brake, 0, 1)
	if self.direction == 1 then
		if backKey > 0.1 and forwardKey < 0.1 and forwardSpeed < STANDSTILL_SPEED then
			self.directionTimer += dt
			if self.directionTimer >= REVERSE_DELAY then
				self.direction = -1
				self.power.gear = -1
				self.directionTimer = 0
			end
		else
			self.directionTimer = 0
		end
	else
		if forwardKey > 0.1 and backKey < 0.1 and forwardSpeed > -STANDSTILL_SPEED then
			self.directionTimer += dt
			if self.directionTimer >= DRIVE_DELAY then
				self.direction = 1
				self.power.gear = 1
				self.directionTimer = 0
			end
		else
			self.directionTimer = 0
		end
	end
	if self.direction == 1 then
		return forwardKey, backKey
	end
	return backKey, forwardKey
end

function VehicleSim.step(
	self: Sim,
	dt: number,
	input: Types.DriveInput,
	contacts: { Types.WheelContact },
	body: Types.BodyState
)
	local config = self.config
	local geometry = self.geometry
	local wheels = self.wheels

	self.running = input.ignition and self.fuel > 0
	local throttle, brake = resolvePedals(self, dt, input, body.forwardSpeed)
	self.speedKmh = body.speed * 3.6
	local directionalKmh = body.forwardSpeed * self.direction * 3.6
	local limitKmh = if self.direction == 1 then config.limits.topSpeedKmh else config.limits.reverseKmh
	throttle *= math.clamp((limitKmh - directionalKmh) / 2, 0, 1)
	if not self.running then
		throttle = 0
	end

	-- Stability control: sideslip to the left means the tail is swinging
	-- right, so the left front brake pulls the nose back, and vice versa.
	local stabilityLeft, stabilityRight = 0, 0
	self.stabilityActive = false
	if body.forwardSpeed > 8 and not input.handbrake then
		local sideslip = math.deg(math.atan2(body.lateralSpeed, body.forwardSpeed))
		local excess = math.clamp((math.abs(sideslip) - config.stability.slipThresholdDeg) / 4, 0, 1)
		if excess > 0 then
			local force = excess * config.stability.strength * config.mass * GRAVITY
			if sideslip < 0 then
				stabilityLeft = force
			else
				stabilityRight = force
			end
			throttle *= 1 - excess
			self.stabilityActive = true
		end
	end
	self.throttle = throttle
	self.brake = brake
	self.braking = brake > 0.05
	self.reversing = self.direction == -1

	self.steer = Steering.update(config, self.steer, math.clamp(input.steer, -1, 1), body.speed, dt)
	self.steerAngle = self.steer * Steering.maxAngle(config, body.speed)
	wheels[1].steerAngle, wheels[2].steerAngle = Steering.ackermann(config, self.steerAngle)

	-- Suspension: spring + damper + bump stop.
	for i, wheel in wheels do
		local contact = contacts[i]
		local geo = geometry.wheels[i]
		wheel.grounded = contact.grounded
		if contact.grounded then
			local x = math.max(contact.compression, 0)
			local load = geo.springRate * x + geo.damperRate * contact.compressionRate
			if x > geo.travel then
				load += BUMP_STOP_STIFFNESS * geo.springRate * (x - geo.travel)
			end
			wheel.compression = math.min(x, geo.travel)
			wheel.load = math.clamp(load, 0, geo.staticLoad * 6)
		else
			wheel.compression = 0
			wheel.load = 0
		end
	end
	-- Anti-roll bars move load from the extended side to the compressed side.
	for axle = 0, 1 do
		local left, right = wheels[axle * 2 + 1], wheels[axle * 2 + 2]
		if left.grounded or right.grounded then
			local rate = if axle == 0 then config.suspension.antiRollFront else config.suspension.antiRollRear
			local transfer = rate * (left.compression - right.compression)
			left.load = math.max(0, left.load + transfer)
			right.load = math.max(0, right.load - transfer)
		end
	end

	-- Road speed seen by the gearbox: average of the grounded driven wheels.
	local frontSplit = config.drivetrain.frontSplit
	local drivenSpeed, drivenCount = 0, 0
	for i, wheel in wheels do
		local driven = if geometry.wheels[i].front then frontSplit > 0 else frontSplit < 1
		if driven and wheel.grounded then
			local contact = contacts[i]
			drivenSpeed += contact.vF * math.cos(wheel.steerAngle) + contact.vR * math.sin(wheel.steerAngle)
			drivenCount += 1
		end
	end
	local wheelSpeed = if drivenCount > 0 then drivenSpeed / drivenCount else body.forwardSpeed
	local driveForce =
		Powertrain.step(self.power, config, dt, throttle, wheelSpeed, config.dimensions.wheelRadius, self.running)

	local brakeCapacity = brake * config.brakes.capacityG * config.mass * GRAVITY
	-- Load carried by the wheels that are braking: together they must be able
	-- to hold the whole car, not just their own share of it.
	local brakingLoad = 0
	for i, wheel in wheels do
		if wheel.grounded and (brake > 0 or (input.handbrake and not geometry.wheels[i].front)) then
			brakingLoad += wheel.load
		end
	end
	for i, wheel in wheels do
		local contact = contacts[i]
		local geo = geometry.wheels[i]
		local locked = input.handbrake and not geo.front
		local braked = locked or brake > 0
		if wheel.grounded and wheel.load > 0 then
			local cos, sin = math.cos(wheel.steerAngle), math.sin(wheel.steerAngle)
			local vLong = contact.vF * cos + contact.vR * sin
			local share = if geo.front then frontSplit / 2 else (1 - frontSplit) / 2
			local bias = if geo.front then config.brakes.frontBias else 1 - config.brakes.frontBias
			local fx, fy, slipping = TireModel.solve({
				fz = wheel.load,
				mu = TireModel.loadedMu(
					contact.mu * config.tires.grip,
					wheel.load,
					geo.staticLoad,
					config.tires.loadSensitivity
				),
				vLong = vLong,
				vLat = -contact.vF * sin + contact.vR * cos,
				gLong = contact.gF * cos + contact.gR * sin,
				gLat = -contact.gF * sin + contact.gR * cos,
				dt = dt,
				driveForce = if locked then 0 else driveForce * share,
				brakeForce = brakeCapacity * bias / 2
					+ (if not geo.front then 0 elseif geo.side < 0 then stabilityLeft else stabilityRight),
				rollingForce = config.tires.rollingResistance * contact.rolling * wheel.load,
				locked = locked,
				stopMass = if braked and brakingLoad > 0
					then config.mass * wheel.load / brakingLoad
					else wheel.load / GRAVITY,
				stiffness = if geo.front then config.tires.stiffnessFront else config.tires.stiffnessRear,
				shape = config.tires.shape,
				assist = config.brakes.assist,
			})
			wheel.forceF = fx * cos - fy * sin
			wheel.forceR = fx * sin + fy * cos
			wheel.slipping = slipping
			wheel.angularVelocity = if locked then 0 else vLong / geo.radius
		else
			wheel.forceF = 0
			wheel.forceR = 0
			wheel.slipping = false
			if locked then
				wheel.angularVelocity = 0
			end
		end
		wheel.spin = (wheel.spin + wheel.angularVelocity * dt) % (2 * math.pi)
	end

	local dynamicPressure = 0.5 * AIR_DENSITY * body.speed * body.speed
	self.dragForce = dynamicPressure * config.aero.cdA
	self.downforce = dynamicPressure * config.aero.clA

	if self.running then
		local litresPerSecond = (self.power.powerKw * config.fuel.bsfc / FUEL_DENSITY + config.fuel.idleLitresPerHour)
			/ 3600
		self.fuel = math.max(0, self.fuel - litresPerSecond * dt)
		local target = 90 + 15 * self.power.powerKw / self.peakPowerKw
		local tau = if self.temperature < target then 45 else 25
		self.temperature += (target - self.temperature) * (1 - math.exp(-dt / tau))
	else
		self.temperature += (AMBIENT_TEMPERATURE - self.temperature) * (1 - math.exp(-dt / 600))
	end
end

-- Gear as shown on the dashboard: "R", "N" or the forward gear number.
function VehicleSim.gearLabel(self: Sim): string
	local gear = self.power.gear
	if gear == -1 then
		return "R"
	elseif gear == 0 then
		return "N"
	end
	return tostring(gear)
end

return VehicleSim
