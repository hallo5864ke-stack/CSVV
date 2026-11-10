--!strict
-- Stage 1 proving ground, generated at runtime into Workspace.TestTrack.
-- It exists to test the cars; the open-world map replaces it in stage 3.
-- All coordinates are studs; road surfaces sit at y = 0.
--
--   Pad       287 x 287 m asphalt square around the origin (spawn, slalom,
--             speed bumps, 15 % hill)
--   Straight  2.87 km, 18 m wide, running north (-Z) from the pad, with a
--             distance board every 100 m
--   Wet / Dirt strips beside the first 290 m of the straight

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DrivingSim")
local Constants = require(Shared.Constants)

local SPM = Constants.STUDS_PER_METER

local TestTrack = {}

local PAD = 1024
local SEGMENT = 2048
local SEGMENTS = 5
local ROAD_WIDTH = 64
local STRIP_OFFSET = 110
local STRIP_WIDTH = 48
local STRIP_LENGTH = 1024

local ASPHALT = Color3.fromRGB(52, 53, 56)
local WHITE = Color3.fromRGB(235, 235, 235)

local function slab(
	parent: Instance,
	name: string,
	size: Vector3,
	frame: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = frame
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Flat surface whose top face is at height `top`.
local function ground(
	parent: Instance,
	name: string,
	sizeX: number,
	sizeZ: number,
	x: number,
	z: number,
	color: Color3,
	material: Enum.Material,
	top: number?
): Part
	return slab(parent, name, Vector3.new(sizeX, 2, sizeZ), CFrame.new(x, (top or 0) - 1, z), color, material)
end

local function paint(parent: Instance, name: string, sizeX: number, sizeZ: number, x: number, z: number)
	local line =
		slab(parent, name, Vector3.new(sizeX, 0.04, sizeZ), CFrame.new(x, 0.02, z), WHITE, Enum.Material.SmoothPlastic)
	line.CanCollide = false
	line.CanQuery = false
	line.CastShadow = false
end

-- Roadside board whose text faces traffic heading north (-Z).
local function board(parent: Instance, text: string, x: number, z: number, color: Color3)
	local post = slab(
		parent,
		"Post",
		Vector3.new(0.5, 7, 0.5),
		CFrame.new(x, 3.5, z),
		Color3.fromRGB(120, 120, 120),
		Enum.Material.Metal
	)
	post.CanQuery = false
	local face = slab(
		parent,
		"Board",
		Vector3.new(14, 5, 0.3),
		CFrame.new(x, 9.5, z) * CFrame.Angles(0, math.pi, 0),
		color,
		Enum.Material.SmoothPlastic
	)
	face.CanQuery = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.Text = text
	label.Parent = gui
	gui.Parent = face
end

-- Ground point and heading for each of the five starting bays.
function TestTrack.spawnFrames(count: number): { CFrame }
	local frames = {}
	for index = 1, count do
		local x = (index - (count + 1) / 2) * 30
		frames[index] = CFrame.new(x, 0, 200)
	end
	return frames
end

function TestTrack.build(): Instance
	local track = Instance.new("Folder")
	track.Name = "TestTrack"

	local grass = Color3.fromRGB(74, 104, 58)
	ground(track, "PadGrass", SEGMENT, SEGMENT, 0, 0, grass, Enum.Material.Grass, -0.3)
	local pad = ground(track, "Pad", PAD, PAD, 0, 0, ASPHALT, Enum.Material.Asphalt)
	pad:SetAttribute("Surface", "Asphalt")

	-- High-speed straight.
	local startZ = -PAD / 2
	for index = 0, SEGMENTS - 1 do
		local z = startZ - SEGMENT / 2 - index * SEGMENT
		ground(track, "StraightGrass", 600, SEGMENT, 0, z, grass, Enum.Material.Grass, -0.3)
		local road = ground(track, "Straight", ROAD_WIDTH, SEGMENT, 0, z, ASPHALT, Enum.Material.Asphalt)
		road:SetAttribute("Surface", "Asphalt")
		paint(track, "CentreLine", 0.5, SEGMENT, 0, z)
		paint(track, "EdgeLineL", 0.5, SEGMENT, -ROAD_WIDTH / 2 + 1.5, z)
		paint(track, "EdgeLineR", 0.5, SEGMENT, ROAD_WIDTH / 2 - 1.5, z)
	end
	local lengthMeters = SEGMENTS * SEGMENT / SPM
	for meters = 0, lengthMeters, 100 do
		local z = startZ - meters * SPM
		paint(track, "DistanceLine", ROAD_WIDTH, 0.6, 0, z)
		board(
			track,
			if meters == 0 then "СТАРТ" else `{meters} м`,
			ROAD_WIDTH / 2 + 10,
			z,
			Color3.fromRGB(20, 80, 160)
		)
	end

	-- Grip comparison strips.
	local stripZ = startZ - STRIP_LENGTH / 2
	local wet = ground(
		track,
		"WetStrip",
		STRIP_WIDTH,
		STRIP_LENGTH,
		STRIP_OFFSET,
		stripZ,
		Color3.fromRGB(30, 31, 34),
		Enum.Material.Asphalt
	)
	wet.Reflectance = 0.25
	wet:SetAttribute("Surface", "WetAsphalt")
	board(
		track,
		"МОКРЫЙ АСФАЛЬТ",
		STRIP_OFFSET + STRIP_WIDTH / 2 + 10,
		startZ,
		Color3.fromRGB(30, 110, 150)
	)
	local dirt = ground(
		track,
		"DirtStrip",
		STRIP_WIDTH,
		STRIP_LENGTH,
		-STRIP_OFFSET,
		stripZ,
		Color3.fromRGB(110, 86, 60),
		Enum.Material.Ground
	)
	dirt:SetAttribute("Surface", "Dirt")
	board(track, "ГРУНТ", -STRIP_OFFSET + STRIP_WIDTH / 2 + 10, startZ, Color3.fromRGB(120, 80, 30))

	-- 15 % hill for handbrake and hill-start checks: up, plateau, down.
	local angle = math.atan(0.15)
	local rampLength, rampWidth, hillX, hillZ = 220, 40, 380, 150
	local rise = rampLength * math.sin(angle)
	local run = rampLength * math.cos(angle)
	local function ramp(name: string, startTop: Vector3, pitch: number)
		local frame = CFrame.new(startTop) * CFrame.Angles(pitch, 0, 0) * CFrame.new(0, -1, -rampLength / 2)
		slab(track, name, Vector3.new(rampWidth, 2, rampLength), frame, ASPHALT, Enum.Material.Asphalt)
	end
	ramp("HillUp", Vector3.new(hillX, 0, hillZ), angle)
	ground(track, "HillTop", rampWidth, 80, hillX, hillZ - run - 40, ASPHALT, Enum.Material.Asphalt, rise)
	ramp("HillDown", Vector3.new(hillX, rise, hillZ - run - 80), -angle)
	board(track, "ПОДЪЁМ 15 %", hillX + rampWidth / 2 + 10, hillZ, Color3.fromRGB(150, 30, 30))

	-- Speed bumps (7 cm) for the suspension.
	for index = 0, 3 do
		local bump = slab(
			track,
			"SpeedBump",
			Vector3.new(40, 0.25, 1.6),
			CFrame.new(-380, 0.125, 100 - index * 60),
			Color3.fromRGB(230, 190, 30),
			Enum.Material.Concrete
		)
		bump:SetAttribute("Surface", "Asphalt")
	end
	board(track, "НЕРОВНОСТИ", -350, 150, Color3.fromRGB(150, 110, 20))

	-- Slalom cones, 18 m apart.
	for index = 0, 7 do
		local cone = Instance.new("Part")
		cone.Name = "Cone"
		cone.Size = Vector3.new(1.2, 2.5, 1.2)
		cone.Position = Vector3.new(-200, 1.25, 100 - index * 18 * SPM)
		cone.Color = Color3.fromRGB(240, 110, 20)
		cone.Material = Enum.Material.SmoothPlastic
		cone.TopSurface = Enum.SurfaceType.Smooth
		cone.BottomSurface = Enum.SurfaceType.Smooth
		cone.Parent = track
	end
	board(track, "ЗМЕЙКА", -180, 150, Color3.fromRGB(170, 80, 20))

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(16, 1, 16)
	spawn.Position = Vector3.new(0, 0.5, 300)
	spawn.Color = Color3.fromRGB(70, 70, 75)
	spawn.Material = Enum.Material.Concrete
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Parent = track

	track.Parent = Workspace
	return track
end

return TestTrack
