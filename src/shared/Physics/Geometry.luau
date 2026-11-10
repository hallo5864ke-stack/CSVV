--!strict
-- Derives wheel positions and suspension rates from a vehicle config.
-- Pure math: used by the physics, the model builder and the headless tests.

local Types = require(script.Parent.Parent.Types)

local GRAVITY = 9.81

local Geometry = {}

function Geometry.compute(config: Types.VehicleConfig): Types.Geometry
	local d = config.dimensions
	local s = config.suspension
	local comToFront = d.wheelbase * (1 - d.weightFront)
	local comToRear = d.wheelbase - comToFront

	local wheels: { Types.WheelGeometry } = {}
	local function addWheel(name: string, front: boolean, side: number)
		local cornerMass = config.mass * (if front then d.weightFront else 1 - d.weightFront) / 2
		local frequency = if front then s.frequencyFront else s.frequencyRear
		local springRate = (2 * math.pi * frequency) ^ 2 * cornerMass
		local staticCompression = cornerMass * GRAVITY / springRate
		local track = if front then d.trackFront else d.trackRear
		table.insert(wheels, {
			name = name,
			front = front,
			side = side,
			x = side * track / 2,
			y = d.wheelRadius - d.comHeight,
			z = if front then -comToFront else comToRear,
			radius = d.wheelRadius,
			width = d.wheelWidth,
			springRate = springRate,
			damperRate = 2 * s.damping * math.sqrt(springRate * cornerMass),
			staticCompression = staticCompression,
			travel = staticCompression + s.bumpTravel,
			staticLoad = cornerMass * GRAVITY,
		})
	end
	addWheel("FL", true, -1)
	addWheel("FR", true, 1)
	addWheel("RL", false, -1)
	addWheel("RR", false, 1)

	local originZ = d.wheelbase / 2 - comToFront
	return {
		wheels = wheels,
		comToFront = comToFront,
		comToRear = comToRear,
		originY = -d.comHeight,
		originZ = originZ,
		frontZ = originZ - d.wheelbase / 2 - config.body.frontOverhang,
		rearZ = originZ + d.wheelbase / 2 + config.body.rearOverhang,
	}
end

return Geometry
