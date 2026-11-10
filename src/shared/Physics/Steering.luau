--!strict
-- Steering rack model. Pure math.
-- Keyboard input is rate-limited, and the reachable road-wheel angle shrinks
-- with speed so full input asks for roughly the tyres' cornering limit
-- instead of full lock at motorway speed.

local Types = require(script.Parent.Parent.Types)

local Steering = {}

-- Largest bicycle-model steer angle (rad) available at a speed (m/s).
function Steering.maxAngle(config: Types.VehicleConfig, speed: number): number
	local s = config.steering
	local lock = math.rad(s.lockDeg)
	if speed < 1 then
		return lock
	end
	local geometric = math.atan(config.dimensions.wheelbase * s.latAccel / (speed * speed))
	return math.min(lock, geometric + math.rad(s.slipAllowanceDeg))
end

-- Moves the rack position (-1..1) toward the input and returns it.
function Steering.update(
	config: Types.VehicleConfig,
	position: number,
	input: number,
	speed: number,
	dt: number
): number
	local s = config.steering
	local returning = math.abs(input) < math.abs(position) or input * position < 0
	local rate = if returning then s.returnRate else s.rate
	-- Hands move slower relative to the reduced lock at speed.
	rate /= 1 + speed / 60
	local delta = math.clamp(input - position, -rate * dt, rate * dt)
	return math.clamp(position + delta, -1, 1)
end

-- Ackermann angles for the left and right front wheels (rad, positive = right).
function Steering.ackermann(config: Types.VehicleConfig, angle: number): (number, number)
	if math.abs(angle) < 1e-4 then
		return angle, angle
	end
	local d = config.dimensions
	local radius = d.wheelbase / math.tan(math.abs(angle))
	local inner = math.atan(d.wheelbase / math.max(radius - d.trackFront / 2, 0.1))
	local outer = math.atan(d.wheelbase / (radius + d.trackFront / 2))
	if angle > 0 then
		return outer, inner
	end
	return -inner, -outer
end

return Steering
