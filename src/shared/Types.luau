--!strict
-- Type definitions shared by configs, physics and builders. All values are SI
-- (metres, kilograms, newtons, seconds) unless a field name says otherwise.

export type VehicleConfig = {
	id: string,
	displayName: string,
	class: string,
	description: string,
	plate: string,
	mass: number,

	dimensions: {
		length: number,
		width: number,
		height: number,
		wheelbase: number,
		trackFront: number,
		trackRear: number,
		wheelRadius: number,
		wheelWidth: number,
		groundClearance: number,
		comHeight: number,
		-- Fraction of static weight on the front axle.
		weightFront: number,
	},

	engine: {
		idleRpm: number,
		redlineRpm: number,
		limiterRpm: number,
		-- Torque-converter stall speed: engine rpm at full throttle from rest.
		stallRpm: number,
		-- Engine braking torque at redline with closed throttle (Nm).
		engineBrakeTorque: number,
		-- {rpm, Nm} points, ascending rpm.
		torqueCurve: { { number } },
	},

	transmission: {
		gears: { number },
		reverse: number,
		finalDrive: number,
		efficiency: number,
		shiftTime: number,
		upshiftLow: number,
		upshiftHigh: number,
		downshiftLow: number,
		downshiftHigh: number,
	},

	drivetrain: {
		layout: "FWD" | "RWD" | "AWD",
		-- Fraction of drive torque sent to the front axle.
		frontSplit: number,
	},

	brakes: {
		-- Total brake force capacity as a multiple of vehicle weight.
		capacityG: number,
		frontBias: number,
		-- Fraction of available grip ABS / traction control lets the tyre use.
		assist: number,
	},

	tires: {
		grip: number,
		-- Normalised cornering stiffness (1/rad).
		stiffnessFront: number,
		stiffnessRear: number,
		shape: number,
		loadSensitivity: number,
		rollingResistance: number,
	},

	aero: {
		cdA: number,
		clA: number,
	},

	suspension: {
		frequencyFront: number,
		frequencyRear: number,
		damping: number,
		bumpTravel: number,
		-- Anti-roll bar rate: N per metre of left/right compression difference.
		antiRollFront: number,
		antiRollRear: number,
	},

	-- Electronic stability control: brakes the outer front wheel once the
	-- body sideslip angle passes the threshold.
	stability: {
		slipThresholdDeg: number,
		-- Peak corrective brake force as a multiple of vehicle weight.
		strength: number,
	},

	steering: {
		lockDeg: number,
		-- Steering input rate, fraction of lock per second.
		rate: number,
		returnRate: number,
		-- Lateral acceleration (m/s^2) the speed-sensitive limiter aims for.
		latAccel: number,
		slipAllowanceDeg: number,
		-- Steering wheel turns lock to lock (used by the interior in stage 2).
		wheelTurns: number,
	},

	limits: {
		topSpeedKmh: number,
		reverseKmh: number,
	},

	fuel: {
		tankLitres: number,
		-- Brake specific fuel consumption, g/kWh.
		bsfc: number,
		idleLitresPerHour: number,
	},

	body: {
		style: "sedan" | "limo" | "coupe" | "suv" | "hatch",
		frontOverhang: number,
		rearOverhang: number,
		hoodLength: number,
		windshieldRun: number,
		rearWindowRun: number,
		trunkLength: number,
		beltline: number,
		seatHeight: number,
		color: { number },
		trimColor: { number },
		interiorColor: { number },
	},
}

export type WheelGeometry = {
	name: string,
	front: boolean,
	-- -1 = left, 1 = right.
	side: number,
	-- Wheel centre at static ride height, relative to the centre of mass
	-- (x right, y up, z rearward).
	x: number,
	y: number,
	z: number,
	radius: number,
	width: number,
	springRate: number,
	damperRate: number,
	staticCompression: number,
	travel: number,
	staticLoad: number,
}

export type Geometry = {
	wheels: { WheelGeometry },
	-- Centre of mass distance behind the front axle / ahead of the rear axle.
	comToFront: number,
	comToRear: number,
	-- Car-space origin (ground under the wheelbase midpoint) relative to COM.
	originY: number,
	originZ: number,
	frontZ: number,
	rearZ: number,
}

export type DriveInput = {
	throttle: number,
	brake: number,
	steer: number,
	handbrake: boolean,
	ignition: boolean,
}

export type WheelContact = {
	grounded: boolean,
	compression: number,
	compressionRate: number,
	-- Contact patch velocity along the body's forward / right directions
	-- projected on the ground plane (m/s).
	vF: number,
	vR: number,
	-- Gravity along the same two directions (m/s^2), non-zero on slopes.
	gF: number,
	gR: number,
	mu: number,
	rolling: number,
}

export type BodyState = {
	forwardSpeed: number,
	-- Velocity of the centre of mass toward the car's right side (m/s).
	lateralSpeed: number,
	speed: number,
}

return {}
