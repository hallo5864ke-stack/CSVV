--!strict
-- Headless verification of the vehicle simulation: `lune run tests/run`.
-- Runs the shipped physics modules against two simple rigid-body rigs
-- (straight line and planar) and checks each car against realistic ranges.

local process = require("@lune/process")
local Loader = require("./loader")

local shared = Loader.root("src/shared")
local Vehicles = Loader.require(shared.Config.Vehicles)
local VehicleSim = Loader.require(shared.Physics.VehicleSim)
local Powertrain = Loader.require(shared.Physics.Powertrain)
local TireModel = Loader.require(shared.Physics.TireModel)
local Steering = Loader.require(shared.Physics.Steering)

local G = 9.81
local DT = 1 / 60
local KMH = 3.6

local failures = 0
local function check(condition: boolean, message: string)
	if not condition then
		failures += 1
		print("  FAIL  " .. message)
	end
end
local function inRange(value: number, lo: number, hi: number, message: string)
	check(value >= lo and value <= hi, `{message}: {string.format("%.2f", value)} not in [{lo}, {hi}]`)
end

local function input(throttle: number, brake: number, steer: number?, handbrake: boolean?)
	return { throttle = throttle, brake = brake, steer = steer or 0, handbrake = handbrake or false, ignition = true }
end

-- Straight-line rig: one degree of freedom plus quasi-static load transfer.
local function lineRig(config, mu: number?, slopeG: number?)
	local sim = VehicleSim.new(config)
	local d = config.dimensions
	local rig = { sim = sim, v = 0, x = 0, accel = 0, t = 0 }
	local contacts = {}
	for i = 1, 4 do
		contacts[i] = {
			grounded = true,
			compression = 0,
			compressionRate = 0,
			vF = 0,
			vR = 0,
			gF = 0,
			gR = 0,
			mu = 1,
			rolling = 1,
		}
	end
	function rig.step(drive)
		local transfer = config.mass * rig.accel * d.comHeight / d.wheelbase
		local front = math.clamp(config.mass * G * d.weightFront - transfer, 0, config.mass * G)
		local rear = config.mass * G - front
		for i, contact in contacts do
			local geo = sim.geometry.wheels[i]
			contact.compression = (if geo.front then front else rear) / 2 / geo.springRate
			contact.vF = rig.v
			contact.gF = slopeG or 0
			contact.mu = mu or 1
		end
		sim:step(DT, drive, contacts, { forwardSpeed = rig.v, lateralSpeed = 0, speed = math.abs(rig.v) })
		local force = -math.sign(rig.v) * sim.dragForce
		for _, wheel in sim.wheels do
			force += wheel.forceF
		end
		local accel = force / config.mass
		local vMid = rig.v + accel * DT
		local vEnd = vMid + (slopeG or 0) * DT
		rig.x += (vMid + vEnd) / 2 * DT
		rig.v = vEnd
		rig.accel += (accel - rig.accel) * 0.3
		rig.t += DT
	end
	function rig.run(drive, seconds: number, stop: (() -> boolean)?)
		for _ = 1, math.ceil(seconds / DT) do
			rig.step(drive)
			if stop and stop() then
				return true
			end
		end
		return false
	end
	return rig
end

-- Planar rig: forward speed u, rightward speed w, yaw rate r (positive right).
local function planarRig(config, mu: number?)
	local sim = VehicleSim.new(config)
	local d = config.dimensions
	local geo = sim.geometry
	local inertia = config.mass * ((0.9 * d.length) ^ 2 + (0.9 * d.width) ^ 2) / 12
	local rig = { sim = sim, u = 0, w = 0, r = 0, ax = 0, ay = 0, heading = 0 }
	local contacts = {}
	for i = 1, 4 do
		contacts[i] = {
			grounded = true,
			compression = 0,
			compressionRate = 0,
			vF = 0,
			vR = 0,
			gF = 0,
			gR = 0,
			mu = mu or 1,
			rolling = 1,
		}
	end
	local function rollStiffness(index: number, bar: number, track: number): number
		return (geo.wheels[index].springRate + 2 * bar) * track * track / 2
	end
	local rollFront = rollStiffness(1, config.suspension.antiRollFront, d.trackFront)
	local rollRear = rollStiffness(3, config.suspension.antiRollRear, d.trackRear)

	function rig.step(drive)
		local weight = config.mass * G
		local frontAxle =
			math.clamp(weight * d.weightFront - config.mass * rig.ax * d.comHeight / d.wheelbase, 0, weight)
		local rollMoment = config.mass * rig.ay * d.comHeight
		for axle = 0, 1 do
			local left, right = axle * 2 + 1, axle * 2 + 2
			local axleLoad = if axle == 0 then frontAxle else weight - frontAxle
			local track = if axle == 0 then d.trackFront else d.trackRear
			local bar = if axle == 0 then config.suspension.antiRollFront else config.suspension.antiRollRear
			local share = (if axle == 0 then rollFront else rollRear) / (rollFront + rollRear)
			-- Turning right loads the left (outer) wheels.
			local transfer = math.clamp(rollMoment * share / track, -axleLoad / 2, axleLoad / 2)
			local spring = geo.wheels[left].springRate
			local sum = axleLoad / spring
			local diff = 2 * transfer / (spring + 2 * bar)
			contacts[left].compression = (sum + diff) / 2
			contacts[right].compression = (sum - diff) / 2
		end
		for i, contact in contacts do
			local wheel = geo.wheels[i]
			contact.vF = rig.u - rig.r * wheel.x
			contact.vR = rig.w + rig.r * -wheel.z
		end
		local speed = math.sqrt(rig.u * rig.u + rig.w * rig.w)
		sim:step(DT, drive, contacts, { forwardSpeed = rig.u, lateralSpeed = rig.w, speed = speed })
		local forceF, forceR, moment = 0, 0, 0
		for i, wheel in sim.wheels do
			forceF += wheel.forceF
			forceR += wheel.forceR
			moment += wheel.forceR * -geo.wheels[i].z - wheel.forceF * geo.wheels[i].x
		end
		if speed > 0.01 then
			forceF -= sim.dragForce * rig.u / speed
			forceR -= sim.dragForce * rig.w / speed
		end
		local ax, ay = forceF / config.mass, forceR / config.mass
		local u, w = rig.u, rig.w
		rig.u = u + (ax + rig.r * w) * DT
		rig.w = w + (ay - rig.r * u) * DT
		rig.r += moment / inertia * DT
		rig.heading += rig.r * DT
		rig.ax += (ax - rig.ax) * 0.3
		rig.ay += (ay - rig.ay) * 0.3
	end
	function rig.sideslipDeg(): number
		return math.deg(math.atan2(rig.w, math.max(math.abs(rig.u), 0.5)))
	end
	-- Holds a road speed with the pedals while applying steering.
	function rig.cruise(targetKmh: number, steer: number, seconds: number, handbrake: boolean?, each: (() -> ())?)
		for _ = 1, math.ceil(seconds / DT) do
			local err = targetKmh / KMH - rig.u
			rig.step(input(math.clamp(err * 0.6, 0, 1), 0, steer, handbrake))
			if each then
				each()
			end
		end
	end
	return rig
end

local function accelerateTo(rig, kmh: number, limit: number): number?
	local start = rig.t
	if rig.run(input(1, 0), limit, function()
		return rig.v * KMH >= kmh
	end) then
		return rig.t - start
	end
	return nil
end

local function brakingDistance(config, fromKmh: number, mu: number?, handbrakeOnly: boolean?): number
	local rig = lineRig(config, mu)
	assert(accelerateTo(rig, fromKmh, 120), "could not reach braking speed")
	local start = rig.x
	local drive = if handbrakeOnly then input(0, 0, 0, true) else input(0, 1)
	rig.run(drive, 60, function()
		return rig.v <= 0.02
	end)
	return rig.x - start
end

-- Expected ranges per car: {0-100 s, top km/h, 100-0 m, skidpad g}.
local expected = {
	LadogaPremier = { accel = { 5.8, 7.6 }, top = { 238, 242 }, brake = { 35, 40 }, grip = { 0.90, 1.10 } },
	AuroraSenat = { accel = { 4.5, 5.6 }, top = { 248, 252 }, brake = { 36, 41 }, grip = { 0.88, 1.08 } },
	SokolGT = { accel = { 3.6, 4.6 }, top = { 288, 292 }, brake = { 30, 35 }, grip = { 1.05, 1.25 } },
	TaigaGrand = { accel = { 6.4, 8.2 }, top = { 223, 227 }, brake = { 38, 44 }, grip = { 0.75, 0.95 } },
	NevaSport = { accel = { 5.2, 6.6 }, top = { 253, 257 }, brake = { 34, 39 }, grip = { 0.95, 1.15 } },
}

local rows = {}
local function fmt(value: number?, pattern: string): string
	return if value then string.format(pattern, value) else "-"
end

print("== Unit checks ==")
do
	local curve = { { 1000, 100 }, { 3000, 300 }, { 5000, 200 } }
	check(Powertrain.torqueAt(curve, 500) == 100, "torque below curve clamps to first point")
	check(Powertrain.torqueAt(curve, 2000) == 200, "torque interpolates")
	check(Powertrain.torqueAt(curve, 9000) == 200, "torque above curve clamps to last point")

	check(math.abs(TireModel.curve(0.05, 16, 1.5) + TireModel.curve(-0.05, 16, 1.5)) < 1e-9, "tyre curve is odd")
	local peak = 0
	for i = 0, 900 do
		peak = math.max(peak, TireModel.curve(math.rad(i / 10), 16, 1.5))
	end
	inRange(peak, 0.999, 1.0001, "tyre curve peaks at 1")
	check(TireModel.curve(math.rad(60), 16, 1.5) < 0.9, "tyre curve falls off past the peak")

	-- Friction circle holds for arbitrary combined inputs.
	local seed = 12345
	local function random(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local worst = 0
	for _ = 1, 20000 do
		local fz, mu = 1000 + random() * 9000, 0.2 + random()
		local fx, fy = TireModel.solve({
			fz = fz,
			mu = mu,
			vLong = (random() - 0.5) * 120,
			vLat = (random() - 0.5) * 30,
			gLong = (random() - 0.5) * 4,
			gLat = (random() - 0.5) * 4,
			dt = DT,
			driveForce = (random() - 0.5) * 30000,
			brakeForce = random() * 20000,
			rollingForce = 100,
			locked = random() < 0.2,
			stopMass = 200 + random() * 2000,
			stiffness = 16,
			shape = 1.5,
			assist = 0.96,
		})
		worst = math.max(worst, math.sqrt(fx * fx + fy * fy) / (mu * fz))
	end
	inRange(worst, 0.9, 1.0001, "combined tyre force stays inside the friction circle")
end

for _, config in Vehicles.list do
	local want = expected[config.id]
	print(`== {config.id} ==`)
	check(want ~= nil, "no expected ranges for this car")

	local sim = VehicleSim.new(config)
	for _, wheel in sim.geometry.wheels do
		check(wheel.staticCompression < wheel.travel, `{wheel.name} static compression exceeds travel`)
		check(
			wheel.y + wheel.travel - wheel.staticCompression < config.body.beltline,
			`{wheel.name} suspension top above body`
		)
	end
	local powerHp = sim.peakPowerKw * 1.3596

	-- Acceleration and top speed.
	local rig = lineRig(config)
	local t100 = accelerateTo(rig, 100, 60)
	local t200 = t100 and accelerateTo(rig, 200, 120)
	if t100 and t200 then
		t200 += t100
	end
	rig.run(input(1, 0), 150)
	local top = rig.v * KMH
	local topGear = rig.sim.power.gear
	inRange(t100 or 999, want.accel[1], want.accel[2], "0-100 km/h time")
	inRange(top, want.top[1], want.top[2], "top speed")
	inRange(rig.sim.power.rpm, config.engine.idleRpm, config.engine.limiterRpm, "rpm at top speed")
	check(rig.sim.fuel < config.fuel.tankLitres, "fuel is consumed")
	inRange(rig.sim.temperature, 80, 110, "engine temperature after a hard run")

	-- Lifting off: engine braking and drag slow the car, gearbox shifts down.
	rig.run(input(0, 0), 20)
	check(rig.v * KMH < top - 40, "coasting slows the car")

	-- Braking distances.
	local brake100 = brakingDistance(config, 100)
	local brakeWet = brakingDistance(config, 100, 0.7)
	local brakeDirt = brakingDistance(config, 100, 0.55)
	local handbrake60 = brakingDistance(config, 60, 1, true)
	local brake60 = brakingDistance(config, 60)
	inRange(brake100, want.brake[1], want.brake[2], "100-0 km/h braking distance")
	check(brakeWet > brake100 * 1.25, "wet asphalt lengthens braking")
	check(brakeDirt > brakeWet * 1.1, "dirt lengthens braking further")
	check(handbrake60 > brake60 * 1.8, "handbrake alone stops much later than the foot brake")

	-- Reverse: hold the brake pedal from rest.
	local reverse = lineRig(config)
	reverse.run(input(0, 1), 20)
	check(reverse.sim.power.gear == -1, "holding brake at standstill selects reverse")
	inRange(-reverse.v * KMH, config.limits.reverseKmh - 3, config.limits.reverseKmh + 1, "reverse speed is limited")
	reverse.run(input(1, 0), 20, function()
		return reverse.v > 1
	end)
	check(reverse.sim.power.gear >= 1 and reverse.v > 1, "accelerator brakes then selects drive again")

	-- Standing still: no creep on the flat, handbrake and foot brake hold a 15 % hill.
	local still = lineRig(config)
	still.run(input(0, 0), 5)
	check(math.abs(still.x) < 0.005 and math.abs(still.v) < 0.005, "car stays put on the flat")
	local slope = -G * math.sin(math.atan(0.15))
	local parked = lineRig(config, 1, slope)
	parked.run(input(0, 0, 0, true), 10)
	check(math.abs(parked.x) < 0.02, `handbrake holds a 15 % hill (moved {string.format("%.3f", parked.x)} m)`)
	-- Facing downhill the brake pedal holds until it selects reverse.
	local held = lineRig(config, 1, -slope)
	held.run(input(0, 1), 0.3)
	check(math.abs(held.x) < 0.005, `foot brake holds a 15 % hill (moved {string.format("%.3f", held.x)} m)`)
	local rolling = lineRig(config, 1, slope)
	rolling.run({ throttle = 0, brake = 0, steer = 0, handbrake = false, ignition = false }, 5)
	check(rolling.x < -3, "car rolls back on a hill with no brakes")

	-- Low-speed stability: a nudge at rest dies out instead of oscillating.
	local nudge = planarRig(config)
	nudge.w, nudge.r = 0.3, 0.2
	local worstRate = 0
	for step = 1, 120 do
		nudge.step(input(0, 0))
		if step > 30 then
			worstRate = math.max(worstRate, math.abs(nudge.r), math.abs(nudge.w))
		end
	end
	check(worstRate < 0.01, `sideways nudge at rest settles (residual {string.format("%.4f", worstRate)})`)

	-- Skidpad: full steering input at 80 km/h.
	local pad = planarRig(config)
	pad.cruise(80, 0, 12)
	local gripSum, slipMax, samples = 0, 0, 0
	local elapsed = 0
	pad.cruise(80, 1, 8, false, function()
		elapsed += DT
		if elapsed > 4 then
			gripSum += pad.ay / G
			samples += 1
			slipMax = math.max(slipMax, math.abs(pad.sideslipDeg()))
		end
	end)
	local lateralG = gripSum / samples
	inRange(lateralG, want.grip[1], want.grip[2], "skidpad lateral acceleration")
	check(slipMax < 10, `car does not spin on the skidpad (sideslip {string.format("%.1f", slipMax)} deg)`)
	pad.cruise(80, 0, 3)
	check(math.abs(pad.r) < 0.02, "yaw settles after releasing the steering")

	-- Lane change at 130 km/h stays stable.
	local lane = planarRig(config)
	lane.cruise(130, 0, 20)
	local laneSlip = 0
	local function track()
		laneSlip = math.max(laneSlip, math.abs(lane.sideslipDeg()))
	end
	lane.cruise(130, 1, 0.7, false, track)
	lane.cruise(130, -1, 1.2, false, track)
	lane.cruise(130, 0, 3, false, track)
	check(laneSlip < 12, `lane change keeps the car in line (sideslip {string.format("%.1f", laneSlip)} deg)`)
	check(math.abs(lane.r) < 0.03, "yaw settles after the lane change")

	-- Handbrake turn: locking the rear axle makes the tail step out.
	local slide = planarRig(config)
	slide.cruise(60, 0, 8)
	local slideSlip = 0
	for _ = 1, 90 do
		slide.step(input(0, 0, 1, true))
		slideSlip = math.max(slideSlip, math.abs(slide.sideslipDeg()))
	end
	check(
		slideSlip > 15,
		`handbrake with steering breaks the rear loose (sideslip {string.format("%.1f", slideSlip)} deg)`
	)

	-- Speed-sensitive steering and Ackermann geometry.
	check(Steering.maxAngle(config, 50) < Steering.maxAngle(config, 15), "steering lock shrinks with speed")
	check(Steering.maxAngle(config, 0) == math.rad(config.steering.lockDeg), "full lock at rest")
	local leftAngle, rightAngle = Steering.ackermann(config, math.rad(20))
	check(rightAngle > leftAngle and leftAngle > 0, "inner wheel steers more in a right turn")

	table.insert(rows, {
		config = config,
		line = string.format(
			"%-14s %5d kg %4.0f hp %s %6s s %6s s %5.0f km/h (gear %d) %6.1f m %6.1f m %6.1f m %5.2f g",
			config.id,
			config.mass,
			powerHp,
			config.drivetrain.layout,
			fmt(t100, "%.1f"),
			fmt(t200, "%.1f"),
			top,
			topGear,
			brake100,
			brakeWet,
			brakeDirt,
			lateralG
		),
		t100 = t100 or 999,
		top = top,
		brake100 = brake100,
		lateralG = lateralG,
	})
end

print("\n== Cross-car checks ==")
for i = 1, #rows do
	for j = i + 1, #rows do
		local a, b = rows[i], rows[j]
		local pair = `{a.config.id} vs {b.config.id}`
		check(a.config.mass ~= b.config.mass, pair .. ": same mass")
		check(math.abs(a.t100 - b.t100) > 0.15, pair .. ": 0-100 times too close")
		check(math.abs(a.top - b.top) > 3, pair .. ": top speeds too close")
		check(math.abs(a.brake100 - b.brake100) > 0.3, pair .. ": braking distances too close")
		check(math.abs(a.lateralG - b.lateralG) > 0.01, pair .. ": cornering grip too close")
	end
end

print("\ncar              mass    power drv  0-100    0-200    top speed          100-0   wet     dirt   skidpad")
for _, row in rows do
	print(row.line)
end

if failures > 0 then
	print(`\n{failures} check(s) failed`)
	process.exit(1)
end
print("\nAll checks passed")
