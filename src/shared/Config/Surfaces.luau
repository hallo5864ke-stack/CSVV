--!strict
-- Road surface grip. A part can name its surface with a "Surface" string
-- attribute (used for wet asphalt); otherwise the material decides.

export type Surface = {
	-- Friction coefficient for a reference tyre.
	mu: number,
	-- Rolling resistance multiplier.
	rolling: number,
}

local Surfaces = {}

Surfaces.named = {
	Asphalt = { mu = 1.0, rolling = 1 },
	WetAsphalt = { mu = 0.7, rolling = 1.1 },
	Concrete = { mu = 0.95, rolling = 1 },
	Cobblestone = { mu = 0.8, rolling = 1.6 },
	Dirt = { mu = 0.55, rolling = 3 },
	Gravel = { mu = 0.6, rolling = 2.5 },
	Grass = { mu = 0.45, rolling = 4 },
	Sand = { mu = 0.4, rolling = 8 },
	Snow = { mu = 0.3, rolling = 3 },
	Ice = { mu = 0.12, rolling = 1 },
} :: { [string]: Surface }

local byMaterial: { [Enum.Material]: Surface } = {
	[Enum.Material.Asphalt] = Surfaces.named.Asphalt,
	[Enum.Material.Concrete] = Surfaces.named.Concrete,
	[Enum.Material.Pavement] = Surfaces.named.Concrete,
	[Enum.Material.Cobblestone] = Surfaces.named.Cobblestone,
	[Enum.Material.Brick] = Surfaces.named.Cobblestone,
	[Enum.Material.Ground] = Surfaces.named.Dirt,
	[Enum.Material.Mud] = Surfaces.named.Dirt,
	[Enum.Material.Pebble] = Surfaces.named.Gravel,
	[Enum.Material.Slate] = Surfaces.named.Gravel,
	[Enum.Material.Grass] = Surfaces.named.Grass,
	[Enum.Material.LeafyGrass] = Surfaces.named.Grass,
	[Enum.Material.Sand] = Surfaces.named.Sand,
	[Enum.Material.Snow] = Surfaces.named.Snow,
	[Enum.Material.Ice] = Surfaces.named.Ice,
	[Enum.Material.Glacier] = Surfaces.named.Ice,
}

function Surfaces.resolve(instance: Instance, material: Enum.Material): Surface
	local name = instance:GetAttribute("Surface")
	if typeof(name) == "string" and Surfaces.named[name] then
		return Surfaces.named[name]
	end
	return byMaterial[material] or Surfaces.named.Asphalt
end

return Surfaces
