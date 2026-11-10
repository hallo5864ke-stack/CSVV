--!strict
-- Tyre force model for one wheel. Pure math.
-- Lateral force follows a simplified Pacejka curve of the slip angle; at
-- walking pace it blends into a static-friction solve so the car can stand
-- still on a slope. Longitudinal and lateral forces share one friction circle.

local GRAVITY = 9.81
-- Speeds (m/s) between which the static solve hands over to the slip curve.
local STATIC_SPEED = 1.5
local DYNAMIC_SPEED = 5
local SLIP_SPEED_FLOOR = 2.5
-- Under-relaxation of the static solve keeps yaw stable at 60 Hz.
local STATIC_RELAX = 0.8
-- A locked, sliding tyre has less grip than a rolling one.
local LOCKED_GRIP = 0.85

local TireModel = {}

export type Params = {
	fz: number,
	mu: number,
	vLong: number,
	vLat: number,
	gLong: number,
	gLat: number,
	dt: number,
	driveForce: number,
	-- Brake force capacity for this wheel (N, >= 0).
	brakeForce: number,
	rollingForce: number,
	locked: boolean,
	-- Mass (kg) this wheel has to bring to rest when it brakes. Larger than
	-- its own load share when only some of the wheels are braking.
	stopMass: number,
	stiffness: number,
	shape: number,
	assist: number,
}

-- Normalised lateral force (-1..1) for a slip angle in radians.
function TireModel.curve(slipAngle: number, stiffness: number, shape: number): number
	return math.sin(shape * math.atan(stiffness / shape * slipAngle))
end

-- Friction coefficient falls slightly as a tyre is loaded above its static load.
function TireModel.loadedMu(mu: number, fz: number, staticLoad: number, sensitivity: number): number
	return mu * math.clamp(1 - sensitivity * (fz / staticLoad - 1), 0.6, 1.15)
end

local function smoothstep(lo: number, hi: number, x: number): number
	local t = math.clamp((x - lo) / (hi - lo), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Returns longitudinal force, lateral force (N, wheel frame) and whether the
-- tyre is at its grip limit.
function TireModel.solve(p: Params): (number, number, boolean)
	if p.fz <= 0 then
		return 0, 0, false
	end
	local limit = p.mu * p.fz
	-- Force that cancels 1 m/s of contact velocity in one step for the mass
	-- this wheel carries.
	local kill = p.fz / GRAVITY / p.dt
	local killLong = p.stopMass / p.dt
	-- Gravity acts over the coming step; half of it is anticipated so a
	-- stationary car neither creeps down nor up a slope.
	local vLong = p.vLong + p.gLong * p.dt * 0.5
	local vLat = p.vLat + p.gLat * p.dt * 0.5

	if p.locked then
		local fx, fy = -vLong * killLong, -vLat * kill
		local magnitude = math.sqrt(fx * fx + fy * fy)
		local cap = limit * LOCKED_GRIP
		if magnitude > cap then
			return fx * cap / magnitude, fy * cap / magnitude, true
		end
		return fx, fy, false
	end

	-- Brakes and rolling resistance oppose motion and can at most stop it.
	local fx = p.driveForce
	local resist = p.brakeForce + p.rollingForce
	local vAfterDrive = vLong + fx / killLong
	fx += math.clamp(-vAfterDrive * killLong, -resist, resist)
	local capX = limit * p.assist
	local slipping = math.abs(fx) > capX
	fx = math.clamp(fx, -capX, capX)

	local slipAngle = math.atan2(vLat, math.max(math.abs(p.vLong), SLIP_SPEED_FLOOR))
	local fyDynamic = -limit * TireModel.curve(slipAngle, p.stiffness, p.shape)
	local fyStatic = math.clamp(-vLat * kill * STATIC_RELAX, -limit, limit)
	local blend = smoothstep(STATIC_SPEED, DYNAMIC_SPEED, math.abs(p.vLong))
	local fy = fyStatic + (fyDynamic - fyStatic) * blend
	-- Never push past zero lateral velocity within one step.
	local capKill = math.abs(vLat) * kill
	fy = math.clamp(fy, -capKill, capKill)
	local capY = math.sqrt(math.max(limit * limit - fx * fx, 0))
	if math.abs(fy) > capY then
		slipping = true
		fy = math.clamp(fy, -capY, capY)
	end
	return fx, fy, slipping
end

return TireModel
