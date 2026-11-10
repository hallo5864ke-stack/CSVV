--!strict
-- Аврора Сенат: full-size V8 limousine. Heaviest car, soft long-travel
-- suspension, all-wheel drive, calm steering.

local Types = require(script.Parent.Parent.Parent.Types)

local config: Types.VehicleConfig = {
	id = "AuroraSenat",
	displayName = "Аврора Сенат",
	class = "Представительский лимузин",
	description = "4.4 V8, полный привод, 9-ступенчатый автомат",
	plate = "А 001 МР 77",
	mass = 2650,

	dimensions = {
		length = 5.60,
		width = 2.00,
		height = 1.66,
		wheelbase = 3.30,
		trackFront = 1.70,
		trackRear = 1.70,
		wheelRadius = 0.385,
		wheelWidth = 0.26,
		groundClearance = 0.20,
		comHeight = 0.62,
		weightFront = 0.52,
	},

	engine = {
		idleRpm = 650,
		redlineRpm = 6000,
		limiterRpm = 6300,
		stallRpm = 2000,
		engineBrakeTorque = 160,
		torqueCurve = {
			{ 650, 430 },
			{ 1500, 640 },
			{ 2000, 720 },
			{ 4600, 720 },
			{ 5500, 690 },
			{ 6000, 620 },
			{ 6300, 540 },
		},
	},

	transmission = {
		gears = { 5.35, 3.24, 2.25, 1.64, 1.21, 1.00, 0.86, 0.72, 0.60 },
		reverse = 4.80,
		finalDrive = 2.65,
		efficiency = 0.88,
		shiftTime = 0.32,
		upshiftLow = 1900,
		upshiftHigh = 5800,
		downshiftLow = 1150,
		downshiftHigh = 3600,
	},

	drivetrain = { layout = "AWD", frontSplit = 0.40 },
	brakes = { capacityG = 1.6, frontBias = 0.64, assist = 0.96 },

	tires = {
		grip = 1.08,
		stiffnessFront = 15,
		stiffnessRear = 17,
		shape = 1.5,
		loadSensitivity = 0.10,
		rollingResistance = 0.011,
	},

	aero = { cdA = 0.80, clA = 0 },

	suspension = {
		frequencyFront = 1.05,
		frequencyRear = 1.15,
		damping = 0.34,
		bumpTravel = 0.10,
		antiRollFront = 22000,
		antiRollRear = 16000,
	},

	stability = { slipThresholdDeg = 3.0, strength = 0.45 },

	steering = {
		lockDeg = 36,
		rate = 1.6,
		returnRate = 2.6,
		latAccel = 7.5,
		slipAllowanceDeg = 2.0,
		wheelTurns = 2.9,
	},

	limits = { topSpeedKmh = 250, reverseKmh = 40 },
	fuel = { tankLitres = 100, bsfc = 255, idleLitresPerHour = 1.3 },

	body = {
		style = "limo",
		frontOverhang = 1.05,
		rearOverhang = 1.25,
		hoodLength = 1.65,
		windshieldRun = 0.75,
		rearWindowRun = 0.65,
		trunkLength = 1.05,
		beltline = 1.08,
		seatHeight = 0.42,
		color = { 12, 12, 16 },
		trimColor = { 205, 205, 210 },
		interiorColor = { 120, 82, 58 },
	},
}

return config
