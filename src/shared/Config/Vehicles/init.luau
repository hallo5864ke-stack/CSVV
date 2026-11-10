--!strict
-- Registry of the five playable vehicles, in spawn order.

local Types = require(script.Parent.Parent.Types)

local ordered: { Types.VehicleConfig } = {
	require(script.LadogaPremier),
	require(script.AuroraSenat),
	require(script.SokolGT),
	require(script.TaigaGrand),
	require(script.NevaSport),
}

local byId: { [string]: Types.VehicleConfig } = {}
for _, config in ordered do
	byId[config.id] = config
end

local Vehicles = {}

Vehicles.list = ordered

function Vehicles.get(id: string): Types.VehicleConfig?
	return byId[id]
end

return Vehicles
