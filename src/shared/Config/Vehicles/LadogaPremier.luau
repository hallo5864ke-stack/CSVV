--!strict
-- Ладога Премьер: rear-drive business sedan. The balanced reference car:
-- moderate power, comfortable but controlled suspension.

local Types = require(script.Parent.Parent.Parent.Types)

local config: Types.VehicleConfig = {
	id = "LadogaPremier",
	displayName = "Ладога Премьер",
	class = "Бизнес-седан",
	description = "2.0 турбо, задний привод, 8-ступенчатый автомат",
	plate = "Е 245 КХ 99",
	mass = 1780,

	dimensions = {
		length = 4.95,
		width = 1.87,
		height = 1.47,
		wheelbase = 2.95,
		trackFront = 1.60,
		trackRear = 1.60,
		wheelRadius = 0.34,
		wheelWidth = 0.24,
		groundClearance = 0.15,
		comHeight = 0.54,
		weightFront = 0.51,
	},

	engine = {
		idleRpm = 750,
		redlineRpm = 6200,
		limiterRpm = 6500,
		stallRpm = 2300,
		engineBrakeTorque = 90,
		torqueCurve = {
			{ 750, 200 },
			{ 1400, 330 },
			{ 1600, 370 },
			{ 4500, 370 },
			{ 5200, 340 },
			{ 6000, 290 },
			{ 6500, 250 },
		},
	},

	transmission = {
		gears = { 4.714, 3.143, 2.106, 1.667, 1.285, 1.000, 0.839, 0.667 },
		reverse = 3.295,
		finalDrive = 3.08,
		efficiency = 0.91,
		shiftTime = 0.25,
		upshiftLow = 2000,
		upshiftHigh = 6000,
		downshiftLow = 1200,
		downshiftHigh = 3800,
	},

	drivetrain = { layout = "RWD", frontSplit = 0 },
	brakes = { capacityG = 1.6, frontBias = 0.63, assist = 0.96 },

	tires = {
		grip = 1.10,
		stiffnessFront = 16,
		stiffnessRear = 18.5,
		shape = 1.5,
		loadSensitivity = 0.11,
		rollingResistance = 0.011,
	},

	aero = { cdA = 0.62, clA = 0.05 },

	suspension = {
		frequencyFront = 1.25,
		frequencyRear = 1.40,
		damping = 0.36,
		bumpTravel = 0.09,
		antiRollFront = 24000,
		antiRollRear = 14000,
	},

	stability = { slipThresholdDeg = 3.5, strength = 0.42 },

	steering = {
		lockDeg = 35,
		rate = 1.9,
		returnRate = 2.9,
		latAccel = 8.5,
		slipAllowanceDeg = 2.2,
		wheelTurns = 2.6,
	},

	limits = { topSpeedKmh = 240, reverseKmh = 45 },
	fuel = { tankLitres = 66, bsfc = 250, idleLitresPerHour = 0.9 },

	body = {
		style = "sedan",
		frontOverhang = 0.90,
		rearOverhang = 1.10,
		hoodLength = 1.55,
		windshieldRun = 0.80,
		rearWindowRun = 0.75,
		trunkLength = 0.95,
		beltline = 0.98,
		seatHeight = 0.36,
		color = { 28, 44, 78 },
		trimColor = { 200, 200, 205 },
		interiorColor = { 196, 178, 150 },
	},
}

return config
