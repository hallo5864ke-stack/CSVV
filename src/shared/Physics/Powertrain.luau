--!strict
-- Engine + automatic gearbox model. Pure math.
-- The drivetrain is treated as locked to the wheels (no wheel-spin state);
-- below the converter stall speed the engine slips against the wheels.

local Types = require(script.Parent.Parent.Types)

local Powertrain = {}

export type State = {
	-- -1 reverse, 0 neutral, 1..n forward.
	gear: number,
	rpm: number,
	shiftTimer: number,
	shiftCooldown: number,
	slipping: boolean,
	engineTorque: number,
	powerKw: number,
}

function Powertrain.new(): State
	return {
		gear = 1,
		rpm = 0,
		shiftTimer = 0,
		shiftCooldown = 0,
		slipping = true,
		engineTorque = 0,
		powerKw = 0,
	}
end

function Powertrain.torqueAt(curve: { { number } }, rpm: number): number
	if rpm <= curve[1][1] then
		return curve[1][2]
	end
	for i = 2, #curve do
		local a, b = curve[i - 1], curve[i]
		if rpm <= b[1] then
			return a[2] + (b[2] - a[2]) * (rpm - a[1]) / (b[1] - a[1])
		end
	end
	return curve[#curve][2]
end

function Powertrain.peakPowerKw(config: Types.VehicleConfig): number
	local best = 0
	for rpm = config.engine.idleRpm, config.engine.limiterRpm, 50 do
		best = math.max(best, Powertrain.torqueAt(config.engine.torqueCurve, rpm) * rpm * math.pi / 30000)
	end
	return best
end

-- Signed overall ratio: negative in reverse, zero in neutral.
function Powertrain.ratio(config: Types.VehicleConfig, gear: number): number
	local t = config.transmission
	if gear == -1 then
		return -t.reverse * t.finalDrive
	elseif gear == 0 then
		return 0
	end
	return t.gears[gear] * t.finalDrive
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Advances the powertrain and returns the total drive force at the wheels
-- (N, positive = pushing the car forward).
function Powertrain.step(
	state: State,
	config: Types.VehicleConfig,
	dt: number,
	throttle: number,
	wheelSpeed: number,
	wheelRadius: number,
	running: boolean
): number
	local e, t = config.engine, config.transmission
	if not running then
		state.rpm = math.max(0, state.rpm - dt * 1500)
		state.engineTorque = 0
		state.powerKw = 0
		state.slipping = true
		return 0
	end

	local ratio = Powertrain.ratio(config, state.gear)
	local coupledRpm = math.max(0, wheelSpeed / (2 * math.pi * wheelRadius) * 60 * ratio)

	state.shiftTimer = math.max(0, state.shiftTimer - dt)
	state.shiftCooldown = math.max(0, state.shiftCooldown - dt)
	if state.gear >= 1 and state.shiftTimer <= 0 and state.shiftCooldown <= 0 then
		local upRpm = lerp(t.upshiftLow, t.upshiftHigh, throttle)
		if state.gear < #t.gears and coupledRpm > upRpm then
			state.gear += 1
			state.shiftTimer = t.shiftTime
			state.shiftCooldown = t.shiftTime + 0.35
		elseif state.gear > 1 then
			local rpmAfter = coupledRpm * t.gears[state.gear - 1] / t.gears[state.gear]
			-- The second test stops the box hunting between two gears.
			if coupledRpm < lerp(t.downshiftLow, t.downshiftHigh, throttle) and rpmAfter < upRpm * 0.9 then
				state.gear -= 1
				state.shiftTimer = t.shiftTime
				state.shiftCooldown = t.shiftTime + 0.35
			end
		end
		ratio = Powertrain.ratio(config, state.gear)
		coupledRpm = math.max(0, wheelSpeed / (2 * math.pi * wheelRadius) * 60 * ratio)
	end

	local slipRpm = e.idleRpm + throttle * (e.stallRpm - e.idleRpm)
	if state.gear == 0 then
		slipRpm = e.idleRpm + throttle * (e.redlineRpm - e.idleRpm)
	end
	local rpm = math.max(coupledRpm, slipRpm)
	state.slipping = coupledRpm < slipRpm

	local torque = 0
	if state.shiftTimer <= 0 and state.gear ~= 0 then
		local limiterCut = math.clamp((e.limiterRpm - rpm) / 150, 0, 1)
		local drive = Powertrain.torqueAt(e.torqueCurve, rpm) * throttle * limiterCut
		local engineBrake = if state.slipping then 0 else e.engineBrakeTorque * (rpm / e.redlineRpm) * (1 - throttle)
		torque = drive - engineBrake
	end

	state.rpm += (math.min(rpm, e.limiterRpm) - state.rpm) * math.min(1, dt * 14)
	state.engineTorque = torque
	state.powerKw = math.max(0, torque) * rpm * math.pi / 30000

	return torque * ratio * t.efficiency / wheelRadius
end

return Powertrain
