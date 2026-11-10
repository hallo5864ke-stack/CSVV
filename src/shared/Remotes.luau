--!strict
-- Network endpoints. The server creates them; clients wait for them.
--   Action    (RemoteEvent, client -> server): discrete driver commands.
--   Telemetry (UnreliableRemoteEvent, client -> server): driver state stream.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(script.Parent.Constants)

local Remotes = {}

local function folder(): Instance
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(Constants.REMOTES_FOLDER)
		if existing then
			return existing
		end
		local created = Instance.new("Folder")
		created.Name = Constants.REMOTES_FOLDER
		local action = Instance.new("RemoteEvent")
		action.Name = "Action"
		action.Parent = created
		local telemetry = Instance.new("UnreliableRemoteEvent")
		telemetry.Name = "Telemetry"
		telemetry.Parent = created
		created.Parent = ReplicatedStorage
		return created
	end
	return ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER)
end

function Remotes.action(): RemoteEvent
	return folder():WaitForChild("Action") :: RemoteEvent
end

function Remotes.telemetry(): UnreliableRemoteEvent
	return folder():WaitForChild("Telemetry") :: UnreliableRemoteEvent
end

return Remotes
