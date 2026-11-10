--!strict
-- Нева Спорт: front-drive hot hatch. Lightest car, nose-heavy, short
-- wheelbase; traction-limited off the line and eager to rotate on the brakes.

local Types = require(script.Parent.Parent.Parent.Types)

local config: Types.VehicleConfig = {
	id = "NevaSport",
	displayName = "Нева Спорт",
	class = "Спортивный хэтчбек",
	description = "2.0 турбо, передний привод, 7-ступенчатый робот",
	plate = "Н 300 ЕВ 47",
	mass = 1430,

	dimensions = {
		length = 4.30,
		width = 1.80,
		height = 1.44,
		wheelbase = 2.64,
		trackFront = 1.55,
		trackRear = 1.53,
		wheelRadius = 0.33,
		wheelWidth = 0.235,
		groundClearance = 0.14,
		comHeight = 0.52,
		weightFront = 0.61,
	},

	engine = {
		idleRpm = 800,
		redlineRpm = 6500,
		limiterRpm = 6800,
		stallRpm = 2500,
		engineBrakeTorque = 80,
		torqueCurve = {
			{ 800, 220 },
			{ 1700, 360 },
			{ 2000, 400 },
			{ 5200, 400 },
			{ 5600, 376 },
			{ 6500, 310 },
			{ 6800, 280 },
		},
	},

	transmission = {
		gears = { 3.58, 2.16, 1.45, 1.08, 0.86, 0.71, 0.60 },
		reverse = 3.30,
		finalDrive = 4.06,
		efficiency = 0.92,
		shiftTime = 0.18,
		upshiftLow = 2100,
		upshiftHigh = 6300,
		downshiftLow = 1300,
		downshiftHigh = 4000,
	},

	drivetrain = { layout = "FWD", frontSplit = 1 },
	brakes = { capacityG = 1.7, frontBias = 0.68, assist = 0.96 },

	tires = {
		grip = 1.15,
		stiffnessFront = 18,
		stiffnessRear = 18.5,
		shape = 1.5,
		loadSensitivity = 0.11,
		rollingResistance = 0.011,
	},

	aero = { cdA = 0.70, clA = 0.10 },

	suspension = {
		frequencyFront = 1.5,
		frequencyRear = 1.7,
		damping = 0.40,
		bumpTravel = 0.08,
		antiRollFront = 20000,
		antiRollRear = 26000,
	},

	stability = { slipThresholdDeg = 4.0, strength = 0.40 },

	steering = {
		lockDeg = 36,
		rate = 2.3,
		returnRate = 3.2,
		latAccel = 9.5,
		slipAllowanceDeg = 2.4,
		wheelTurns = 2.3,
	},

	limits = { topSpeedKmh = 255, reverseKmh = 45 },
	fuel = { tankLitres = 50, bsfc = 255, idleLitresPerHour = 0.85 },

	body = {
		style = "hatch",
		frontOverhang = 0.88,
		rearOverhang = 0.78,
		hoodLength = 1.25,
		windshieldRun = 0.75,
		rearWindowRun = 0.45,
		trunkLength = 0.12,
		beltline = 0.97,
		seatHeight = 0.34,
		color = { 235, 190, 20 },
		trimColor = { 22, 22, 24 },
		interiorColor = { 34, 34, 38 },
	},
}

return config
