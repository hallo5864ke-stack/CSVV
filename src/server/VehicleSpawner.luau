--!strict
-- Creates vehicles in the world. Every car lives in Workspace.Vehicles and
-- carries the vehicle tag so client systems can find it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DrivingSim")
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local VehicleBuilder = require(script.Parent.VehicleBuilder)
local VehicleService = require(script.Parent.VehicleService)

local VehicleSpawner = {}

local function vehiclesFolder(): Instance
	local folder = Workspace:FindFirstChild("Vehicles")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Vehicles"
		folder.Parent = Workspace
	end
	return folder :: Instance
end

-- `ground` is a point on the road surface; the car faces its look vector.
function VehicleSpawner.spawn(config: Types.VehicleConfig, ground: CFrame): Model
	local model = VehicleBuilder.build(config)
	-- Dropped from just above ride height so the suspension settles itself.
	local frame = ground * CFrame.new(0, (config.dimensions.comHeight + 0.1) * Constants.STUDS_PER_METER, 0)
	model:PivotTo(frame)
	model.Parent = vehiclesFolder()
	CollectionService:AddTag(model, Constants.VEHICLE_TAG)
	VehicleService.register(model, config, frame)
	return model
end

return VehicleSpawner
