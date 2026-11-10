--!strict
-- Client entry point for stage 1.

local VehicleController = require(script.Parent.VehicleController)
local VehicleLights = require(script.Parent.VehicleLights)
local WheelVisuals = require(script.Parent.WheelVisuals)
local TelemetryHud = require(script.Parent.TelemetryHud)

VehicleController.start()
VehicleLights.start()
WheelVisuals.start()
TelemetryHud.start()
