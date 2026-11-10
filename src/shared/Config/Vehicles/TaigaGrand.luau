--!strict
-- Тайга Гранд: large diesel SUV. High centre of mass, long suspension travel,
-- all-wheel drive, low-revving engine with a lot of torque.

local Types = require(script.Parent.Parent.Parent.Types)

local config: Types.VehicleConfig = {
	id = "TaigaGrand",
	displayName = "Тайга Гранд",
	class = "Премиальный внедорожник",
	description = "3.0 V6 турбодизель, полный привод, 8-ступенчатый автомат",
	plate = "Т 500 АЕ 50",
	mass = 2480,

	dimensions = {
		length = 5.05,
		width = 2.00,
		height = 1.80,
		wheelbase = 3.00,
		trackFront = 1.70,
		trackRear = 1.70,
		wheelRadius = 0.40,
		wheelWidth = 0.28,
		groundClearance = 0.24,
		comHeight = 0.72,
		weightFront = 0.50,
	},

	engine = {
		idleRpm = 700,
		redlineRpm = 4400,
		limiterRpm = 4700,
		stallRpm = 1900,
		engineBrakeTorque = 180,
		torqueCurve = {
			{ 700, 380 },
			{ 1300, 620 },
			{ 1600, 700 },
			{ 2800, 700 },
			{ 3500, 650 },
			{ 4000, 600 },
			{ 4400, 520 },
			{ 4700, 430 },
		},
	},

	transmission = {
		gears = { 4.714, 3.143, 2.106, 1.667, 1.285, 1.000, 0.839, 0.667 },
		reverse = 3.295,
		finalDrive = 3.31,
		efficiency = 0.89,
		shiftTime = 0.35,
		upshiftLow = 1700,
		upshiftHigh = 4200,
		downshiftLow = 1050,
		downshiftHigh = 2600,
	},

	drivetrain = { layout = "AWD", frontSplit = 0.45 },
	brakes = { capacityG = 1.5, frontBias = 0.62, assist = 0.95 },

	tires = {
		grip = 1.00,
		stiffnessFront = 13,
		stiffnessRear = 14.5,
		shape = 1.45,
		loadSensitivity = 0.13,
		rollingResistance = 0.013,
	},

	aero = { cdA = 1.02, clA = 0 },

	suspension = {
		frequencyFront = 1.15,
		frequencyRear = 1.30,
		damping = 0.32,
		bumpTravel = 0.13,
		antiRollFront = 20000,
		antiRollRear = 14000,
	},

	stability = { slipThresholdDeg = 3.0, strength = 0.45 },

	steering = {
		lockDeg = 35,
		rate = 1.4,
		returnRate = 2.2,
		latAccel = 6.8,
		slipAllowanceDeg = 2.0,
		wheelTurns = 3.0,
	},

	limits = { topSpeedKmh = 225, reverseKmh = 40 },
	fuel = { tankLitres = 90, bsfc = 215, idleLitresPerHour = 1.0 },

	body = {
		style = "suv",
		frontOverhang = 0.95,
		rearOverhang = 1.10,
		hoodLength = 1.40,
		windshieldRun = 0.65,
		rearWindowRun = 0.35,
		trunkLength = 0.15,
		beltline = 1.18,
		seatHeight = 0.52,
		color = { 228, 228, 224 },
		trimColor = { 24, 24, 26 },
		interiorColor = { 60, 44, 36 },
	},
}

return config
