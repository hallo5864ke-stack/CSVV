--!strict
-- Shared constants. The whole game uses one scale: 1 stud = 0.28 m, and
-- Workspace.Gravity is set to 9.81 m/s^2 in studs so SI formulas hold.

local METERS_PER_STUD = 0.28

return table.freeze({
	METERS_PER_STUD = METERS_PER_STUD,
	STUDS_PER_METER = 1 / METERS_PER_STUD,
	GRAVITY = 9.81,
	GRAVITY_STUDS = 9.81 / METERS_PER_STUD,
	MS_TO_KMH = 3.6,
	AIR_DENSITY = 1.225,

	VEHICLE_TAG = "DS_Vehicle",
	REMOTES_FOLDER = "DS_Remotes",

	-- GOST R 41.6: direction indicators flash 90 +/- 30 times per minute.
	BLINK_HZ = 1.5,
	TELEMETRY_HZ = 12,

	HEADLIGHTS_OFF = 0,
	HEADLIGHTS_LOW = 1,
	HEADLIGHTS_HIGH = 2,

	SIGNAL_OFF = "Off",
	SIGNAL_LEFT = "Left",
	SIGNAL_RIGHT = "Right",
	SIGNAL_HAZARD = "Hazard",
})
