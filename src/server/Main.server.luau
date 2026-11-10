--!strict
-- Server entry point for stage 1: world scale, proving ground, five cars.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DrivingSim")
local Constants = require(Shared.Constants)
local Vehicles = require(Shared.Config.Vehicles)
local TestTrack = require(script.Parent.TestTrack)
local VehicleService = require(script.Parent.VehicleService)
local VehicleSpawner = require(script.Parent.VehicleSpawner)

-- Real gravity at 0.28 m per stud; the vehicle physics depends on it.
Workspace.Gravity = Constants.GRAVITY_STUDS
-- Keep walking characters sensible under the lower gravity.
StarterPlayer.CharacterUseJumpPower = false
StarterPlayer.CharacterJumpHeight = 3.5

-- A default template baseplate would sit exactly at road height.
local baseplate = Workspace:FindFirstChild("Baseplate")
if baseplate then
	baseplate:Destroy()
end

TestTrack.build()
VehicleService.start()

local frames = TestTrack.spawnFrames(#Vehicles.list)
for index, config in Vehicles.list do
	VehicleSpawner.spawn(config, frames[index])
end
