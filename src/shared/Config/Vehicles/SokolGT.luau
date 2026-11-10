--!strict
-- Сокол GT: rear-drive sports coupe. Lightest on its tyres, stiffest
-- suspension, fastest steering and gear changes, highest top speed.

local Types = require(script.Parent.Parent.Parent.Types)

local config: Types.VehicleConfig = {
	id = "SokolGT",
	displayName = "Сокол GT",
	class = "Спортивное купе",
	description = "3.0 R6 битурбо, задний привод, 8-ступенчатый автомат",
	plate = "С 777 СС 78",
	mass = 1560,

	dimensions = {
		length = 4.70,
		width = 1.90,
		height = 1.36,
		wheelbase = 2.78,
		trackFront = 1.62,
		trackRear = 1.62,
		wheelRadius = 0.345,
		wheelWidth = 0.28,
		groundClearance = 0.12,
		comHeight = 0.47,
		weightFront = 0.51,
	},

	engine = {
		idleRpm = 800,
		redlineRpm = 7000,
		limiterRpm = 7200,
		stallRpm = 2600,
		engineBrakeTorque = 110,
		torqueCurve = {
			{ 800, 300 },
			{ 1800, 560 },
			{ 2400, 600 },
			{ 5500, 600 },
			{ 6000, 560 },
			{ 7000, 480 },
			{ 7200, 440 },
		},
	},

	transmission = {
		gears = { 4.714, 3.143, 2.106, 1.667, 1.285, 1.000, 0.839, 0.667 },
		reverse = 3.295,
		finalDrive = 3.15,
		efficiency = 0.92,
		shiftTime = 0.15,
		upshiftLow = 2200,
		upshiftHigh = 6800,
		downshiftLow = 1300,
		downshiftHigh = 4200,
	},

	drivetrain = { layout = "RWD", frontSplit = 0 },
	brakes = { capacityG = 1.8, frontBias = 0.62, assist = 0.97 },

	tires = {
		grip = 1.25,
		stiffnessFront = 20,
		stiffnessRear = 22,
		shape = 1.55,
		loadSensitivity = 0.10,
		rollingResistance = 0.012,
	},

	aero = { cdA = 0.64, clA = 0.25 },

	suspension = {
		frequencyFront = 1.7,
		frequencyRear = 1.9,
		damping = 0.42,
		bumpTravel = 0.07,
		antiRollFront = 30000,
		antiRollRear = 20000,
	},

	stability = { slipThresholdDeg = 4.5, strength = 0.40 },

	steering = {
		lockDeg = 34,
		rate = 2.4,
		returnRate = 3.4,
		latAccel = 10.5,
		slipAllowanceDeg = 2.5,
		wheelTurns = 2.2,
	},

	limits = { topSpeedKmh = 290, reverseKmh = 45 },
	fuel = { tankLitres = 59, bsfc = 265, idleLitresPerHour = 1.0 },

	body = {
		style = "coupe",
		frontOverhang = 0.90,
		rearOverhang = 1.02,
		hoodLength = 1.65,
		windshieldRun = 0.85,
		rearWindowRun = 1.00,
		trunkLength = 0.55,
		beltline = 0.90,
		seatHeight = 0.30,
		color = { 150, 16, 22 },
		trimColor = { 30, 30, 32 },
		interiorColor = { 28, 28, 30 },
	},
}

return config
