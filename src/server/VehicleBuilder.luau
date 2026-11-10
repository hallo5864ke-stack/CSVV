--!strict
-- Builds a vehicle model from its config: weighted chassis, body panels,
-- glazing, lights, wheels and the driver's seat. Positions are authored in
-- "car space" metres: origin on the ground under the wheelbase midpoint,
-- x to the right, y up, z rearward (the car faces -Z like a Roblox CFrame).
--
-- Model layout (names are relied on by other scripts):
--   <ConfigId> (Model, PrimaryPart = Chassis)
--     Chassis        the only part with mass; holds the wheel Welds
--     Body           panels, glass, trim
--     Interior       seats (DriverSeat is the Seat instance)
--     Lights         parts with a "Role" attribute
--     Wheels         FL / FR / RL / RR models, each with a Hub part

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DrivingSim")
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local Geometry = require(Shared.Physics.Geometry)

local SPM = Constants.STUDS_PER_METER

local VehicleBuilder = {}

type Options = {
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	collide: boolean?,
	rotation: CFrame?,
	class: string?,
	shape: Enum.PartType?,
	parent: Instance?,
}

type Context = {
	root: BasePart,
	offset: Vector3,
	body: Instance,
}

local BLACK = Color3.fromRGB(18, 18, 20)
local GLASS = Color3.fromRGB(40, 52, 60)
local CHROME = Color3.fromRGB(215, 215, 220)

local function rgb(value: { number }): Color3
	return Color3.fromRGB(value[1], value[2], value[3])
end

local function weld(root: BasePart, part: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = root
	constraint.Part1 = part
	constraint.Parent = part
end

-- Creates a part from a car-space centre and size (metres) and welds it on.
local function addPart(ctx: Context, name: string, size: Vector3, center: Vector3, options: Options?): BasePart
	local o: Options = options or {}
	local part = Instance.new(o.class or "Part") :: BasePart
	part.Name = name
	part.Size = size * SPM
	part.CFrame = ctx.root.CFrame * CFrame.new((center + ctx.offset) * SPM) * (o.rotation or CFrame.identity)
	part.Color = o.color or BLACK
	part.Material = o.material or Enum.Material.SmoothPlastic
	part.Transparency = o.transparency or 0
	part.Reflectance = o.reflectance or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Massless = true
	part.CanCollide = o.collide == true
	part.CanQuery = o.collide == true
	part.CanTouch = false
	part.CastShadow = o.collide == true
	if o.shape and part:IsA("Part") then
		part.Shape = o.shape
	end
	weld(ctx.root, part)
	part.Parent = o.parent or ctx.body
	return part
end

-- Same, from the two opposite corners of the box.
local function addBox(
	ctx: Context,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	options: Options?
): BasePart
	assert(y1 > y0 and z1 > z0, `{name}: inverted box`)
	return addPart(
		ctx,
		name,
		Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)),
		Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		options
	)
end

local function addLight(
	ctx: Context,
	lights: Instance,
	name: string,
	role: string,
	size: Vector3,
	center: Vector3,
	onColor: Color3,
	offColor: Color3
): BasePart
	local part = addPart(ctx, name, size, center, { color = offColor, material = Enum.Material.Glass, parent = lights })
	part:SetAttribute("Role", role)
	part:SetAttribute("OnColor", onColor)
	part:SetAttribute("OffColor", offColor)
	return part
end

local function addPlate(ctx: Context, name: string, text: string, center: Vector3, facingRear: boolean)
	local plate = addPart(ctx, name, Vector3.new(0.52, 0.112, 0.02), center, {
		color = Color3.fromRGB(245, 245, 245),
		rotation = if facingRear then CFrame.Angles(0, math.pi, 0) else nil,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 120
	gui.LightInfluence = 1
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(10, 10, 10)
	label.Text = text
	label.Parent = gui
	gui.Parent = plate
end

local function buildWheel(root: BasePart, wheels: Instance, geo: Types.WheelGeometry, trim: Color3)
	local wheel = Instance.new("Model")
	wheel.Name = geo.name
	local diameter = geo.radius * 2 * SPM
	local width = geo.width * SPM
	local hubFrame = CFrame.new(Vector3.new(geo.x, geo.y, geo.z) * SPM)

	local function wheelPart(
		name: string,
		size: Vector3,
		offset: CFrame,
		color: Color3,
		material: Enum.Material,
		shape: Enum.PartType?
	): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = root.CFrame * hubFrame * offset
		part.Color = color
		part.Material = material
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		if shape then
			part.Shape = shape
		end
		part.Parent = wheel
		return part
	end

	local hub = wheelPart("Hub", Vector3.new(0.2, 0.2, 0.2), CFrame.identity, BLACK, Enum.Material.SmoothPlastic)
	hub.Transparency = 1
	wheel.PrimaryPart = hub
	-- A Weld (not a WeldConstraint) so clients can animate C0 for suspension
	-- travel, steering and wheel spin without touching physics.
	local joint = Instance.new("Weld")
	joint.Name = "Wheel_" .. geo.name
	joint.Part0 = root
	joint.Part1 = hub
	joint.C0 = hubFrame
	joint.Parent = root

	local cylinder = Enum.PartType.Cylinder
	local parts = {
		wheelPart(
			"Tire",
			Vector3.new(width, diameter, diameter),
			CFrame.identity,
			BLACK,
			Enum.Material.Rubber,
			cylinder
		),
		wheelPart(
			"Rim",
			Vector3.new(width + 0.02, diameter * 0.68, diameter * 0.68),
			CFrame.identity,
			Color3.fromRGB(45, 45, 48),
			Enum.Material.Metal,
			cylinder
		),
		wheelPart(
			"Cap",
			Vector3.new(width + 0.06, diameter * 0.16, diameter * 0.16),
			CFrame.identity,
			trim,
			Enum.Material.Metal,
			cylinder
		),
	}
	-- Spokes make the rotation visible.
	for index = 0, 2 do
		table.insert(
			parts,
			wheelPart(
				"Spoke" .. index,
				Vector3.new(width + 0.04, diameter * 0.66, diameter * 0.07),
				CFrame.Angles(math.rad(index * 60), 0, 0),
				trim,
				Enum.Material.Metal
			)
		)
	end
	for _, part in parts do
		weld(hub, part)
	end
	wheel.Parent = wheels
end

function VehicleBuilder.build(config: Types.VehicleConfig): Model
	local d, b = config.dimensions, config.body
	local geometry = Geometry.compute(config)

	local model = Instance.new("Model")
	model.Name = config.id
	local body = Instance.new("Folder")
	body.Name = "Body"
	body.Parent = model
	local interior: Instance = Instance.new("Folder")
	interior.Name = "Interior"
	interior.Parent = model
	local lights = Instance.new("Folder")
	lights.Name = "Lights"
	lights.Parent = model
	local wheels = Instance.new("Folder")
	wheels.Name = "Wheels"
	wheels.Parent = model

	-- Chassis: carries all the mass, so its centre is the centre of mass and
	-- its box sets the rotational inertia. Body panels do the colliding.
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.CFrame = CFrame.identity
	chassis.Size = Vector3.new(d.width * 0.9, 0.8, d.length * 0.9) * SPM
	chassis.Transparency = 1
	chassis.CanCollide = false
	chassis.CanQuery = false
	chassis.CanTouch = false
	chassis.RootPriority = 100
	local volume = chassis.Size.X * chassis.Size.Y * chassis.Size.Z
	local density = config.mass / volume
	assert(density >= 0.01 and density <= 100, `{config.id}: chassis density out of range`)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(density, 0.3, 0.1, 1, 1)
	chassis.Parent = model
	model.PrimaryPart = chassis

	local ctx: Context = {
		root = chassis,
		offset = Vector3.new(0, geometry.originY, geometry.originZ),
		body = body,
	}

	local paint = rgb(b.color)
	local trim = rgb(b.trimColor)
	local cabin = rgb(b.interiorColor)
	local painted: Options = { color = paint, reflectance = 0.12 }
	local paintedSolid: Options = { color = paint, reflectance = 0.12, collide = true }
	local dark: Options = { color = BLACK }
	local chrome: Options =
		{ color = if trim.R > 0.5 then CHROME else trim, material = Enum.Material.Metal, reflectance = 0.3 }
	local glass: Options =
		{ color = GLASS, material = Enum.Material.Glass, transparency = 0.5, reflectance = 0.15, collide = true }

	local W, H, L = d.width, d.height, d.wheelbase
	local gc, r = d.groundClearance, d.wheelRadius
	local zF, zR = -L / 2 - b.frontOverhang, L / 2 + b.rearOverhang
	local zFA, zRA = -L / 2, L / 2
	local zWS = zF + b.hoodLength
	local zRoofF = zWS + b.windshieldRun
	local zTrunk = zR - b.trunkLength
	local zRoofR = zTrunk - b.rearWindowRun
	local zMid = zRoofF + (zRoofR - zRoofF) * 0.48
	local belt = b.beltline
	local shoulder = belt - 0.05
	local panel = d.wheelWidth + 0.04
	local coreHalf = W / 2 - panel
	local glassHalf = W / 2 - 0.14
	local roofY = H - 0.05
	local rise = roofY - belt
	local archHalf = r + 0.07
	local archTop = 2 * r + 0.08
	local floorTop = gc + 0.10

	-- Underbody, engine bay and luggage area.
	addBox(ctx, "Floor", -coreHalf, coreHalf, gc, floorTop, zF + 0.15, zR - 0.15, { color = BLACK, collide = true })
	addBox(ctx, "EngineBay", -coreHalf, coreHalf, floorTop, shoulder, zF + 0.15, zWS, paintedSolid)
	addBox(
		ctx,
		"RearBody",
		-coreHalf,
		coreHalf,
		floorTop,
		shoulder,
		math.min(zTrunk, zR - 0.45),
		zR - 0.15,
		paintedSolid
	)
	addBox(ctx, "Hood", -W / 2 + 0.02, W / 2 - 0.02, shoulder, belt, zF + 0.10, zWS + 0.05, painted)
	addBox(ctx, "TrunkLid", -W / 2 + 0.02, W / 2 - 0.02, shoulder, belt, zTrunk - 0.03, zR - 0.10, painted)
	addBox(ctx, "Dashboard", -coreHalf, coreHalf, shoulder - 0.28, shoulder, zWS, zWS + 0.38, dark)

	-- Bumpers and front fascia.
	addBox(ctx, "FrontBumper", -W / 2, W / 2, gc + 0.02, shoulder, zF, zF + 0.15, paintedSolid)
	addBox(ctx, "RearBumper", -W / 2, W / 2, gc + 0.02, shoulder, zR - 0.15, zR, paintedSolid)
	addBox(ctx, "FrontLip", -W / 2 + 0.08, W / 2 - 0.08, gc, gc + 0.08, zF - 0.01, zF + 0.12, dark)
	addBox(ctx, "RearDiffuser", -W / 2 + 0.08, W / 2 - 0.08, gc, gc + 0.10, zR - 0.12, zR + 0.01, dark)
	addBox(ctx, "GrilleFrame", -W * 0.22, W * 0.22, shoulder - 0.34, shoulder - 0.10, zF - 0.008, zF, chrome)
	addBox(ctx, "Grille", -W * 0.21, W * 0.21, shoulder - 0.33, shoulder - 0.11, zF - 0.014, zF, dark)
	for bar = 1, 3 do
		local y = shoulder - 0.33 + bar * 0.055
		addBox(ctx, "GrilleBar" .. bar, -W * 0.21, W * 0.21, y - 0.006, y + 0.006, zF - 0.02, zF, chrome)
	end
	addBox(ctx, "LowerIntake", -W * 0.30, W * 0.30, gc + 0.11, gc + 0.21, zF - 0.012, zF, dark)
	for _, side in { -1, 1 } do
		addBox(
			ctx,
			"Exhaust",
			side * (W / 2 - 0.42),
			side * (W / 2 - 0.30),
			gc + 0.03,
			gc + 0.10,
			zR - 0.02,
			zR + 0.03,
			chrome
		)
	end

	-- Sides: fenders, wheel arches, doors and trim, mirrored left and right.
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local inner, outer = side * coreHalf, side * W / 2
		addBox(ctx, "FrontFender" .. tag, inner, outer, gc + 0.04, shoulder, zF + 0.15, zFA - archHalf, paintedSolid)
		addBox(ctx, "FrontArch" .. tag, inner, outer, archTop, shoulder, zFA - archHalf, zFA + archHalf, painted)
		addBox(ctx, "FrontDoor" .. tag, inner, outer, gc + 0.04, shoulder, zFA + archHalf, zMid - 0.005, paintedSolid)
		addBox(ctx, "RearDoor" .. tag, inner, outer, gc + 0.04, shoulder, zMid + 0.005, zRA - archHalf, paintedSolid)
		addBox(ctx, "RearArch" .. tag, inner, outer, archTop, shoulder, zRA - archHalf, zRA + archHalf, painted)
		addBox(ctx, "RearQuarter" .. tag, inner, outer, gc + 0.04, shoulder, zRA + archHalf, zR - 0.15, paintedSolid)
		addBox(
			ctx,
			"Sill" .. tag,
			outer - side * 0.03,
			outer + side * 0.01,
			gc,
			gc + 0.07,
			zFA + archHalf,
			zRA - archHalf,
			dark
		)
		addBox(ctx, "Shoulder" .. tag, side * (glassHalf - 0.03), outer, shoulder, belt, zWS, zTrunk, painted)
		addBox(
			ctx,
			"Waistline" .. tag,
			outer,
			outer + side * 0.006,
			shoulder - 0.012,
			shoulder + 0.012,
			zWS,
			zTrunk,
			chrome
		)
		addBox(
			ctx,
			"FrontHandle" .. tag,
			outer,
			outer + side * 0.02,
			shoulder - 0.13,
			shoulder - 0.10,
			zMid - 0.24,
			zMid - 0.08,
			chrome
		)
		if b.style ~= "coupe" then
			addBox(
				ctx,
				"RearHandle" .. tag,
				outer,
				outer + side * 0.02,
				shoulder - 0.13,
				shoulder - 0.10,
				zRA - archHalf - 0.24,
				zRA - archHalf - 0.08,
				chrome
			)
		end

		-- Greenhouse side: glass, quarter lights and pillars.
		local glassX = side * glassHalf
		addBox(ctx, "SideGlass" .. tag, glassX - 0.008, glassX + 0.008, belt, roofY, zRoofF, zRoofR, glass)
		addPart(
			ctx,
			"FrontQuarterGlass" .. tag,
			Vector3.new(0.016, rise, b.windshieldRun),
			Vector3.new(glassX, belt + rise / 2, zWS + b.windshieldRun / 2),
			{ class = "WedgePart", color = GLASS, material = Enum.Material.Glass, transparency = 0.5 }
		)
		addPart(
			ctx,
			"RearQuarterGlass" .. tag,
			Vector3.new(0.016, rise, b.rearWindowRun),
			Vector3.new(glassX, belt + rise / 2, zRoofR + b.rearWindowRun / 2),
			{
				class = "WedgePart",
				color = GLASS,
				material = Enum.Material.Glass,
				transparency = 0.5,
				rotation = CFrame.Angles(0, math.pi, 0),
			}
		)
		addPart(
			ctx,
			"PillarA" .. tag,
			Vector3.new(0.07, 0.04, math.sqrt(rise ^ 2 + b.windshieldRun ^ 2)),
			Vector3.new(glassX, belt + rise / 2, zWS + b.windshieldRun / 2),
			{ color = paint, reflectance = 0.12, rotation = CFrame.Angles(-math.atan2(rise, b.windshieldRun), 0, 0) }
		)
		addPart(
			ctx,
			"PillarC" .. tag,
			Vector3.new(0.10, 0.04, math.sqrt(rise ^ 2 + b.rearWindowRun ^ 2)),
			Vector3.new(glassX, belt + rise / 2, zRoofR + b.rearWindowRun / 2),
			{ color = paint, reflectance = 0.12, rotation = CFrame.Angles(math.atan2(rise, b.rearWindowRun), 0, 0) }
		)
		addBox(ctx, "PillarB" .. tag, glassX - 0.015, glassX + 0.015, belt, roofY, zMid - 0.04, zMid + 0.04, dark)

		-- Door mirror.
		addBox(
			ctx,
			"MirrorArm" .. tag,
			outer - side * 0.02,
			outer + side * 0.06,
			belt + 0.02,
			belt + 0.05,
			zWS + 0.22,
			zWS + 0.28,
			dark
		)
		addBox(
			ctx,
			"Mirror" .. tag,
			outer + side * 0.04,
			outer + side * 0.22,
			belt + 0.02,
			belt + 0.15,
			zWS + 0.20,
			zWS + 0.29,
			painted
		)
		addBox(
			ctx,
			"MirrorGlass" .. tag,
			outer + side * 0.05,
			outer + side * 0.21,
			belt + 0.03,
			belt + 0.14,
			zWS + 0.29,
			zWS + 0.295,
			{
				color = Color3.fromRGB(150, 160, 170),
				material = Enum.Material.Glass,
				reflectance = 0.6,
			}
		)
	end

	-- Roof and front / rear glass.
	addBox(ctx, "Roof", -glassHalf, glassHalf, roofY, H, zRoofF - 0.03, zRoofR + 0.03, paintedSolid)
	addPart(
		ctx,
		"Windshield",
		Vector3.new(glassHalf * 2 - 0.06, 0.02, math.sqrt(rise ^ 2 + b.windshieldRun ^ 2)),
		Vector3.new(0, belt + rise / 2, zWS + b.windshieldRun / 2),
		{
			color = GLASS,
			material = Enum.Material.Glass,
			transparency = 0.55,
			reflectance = 0.15,
			collide = true,
			rotation = CFrame.Angles(-math.atan2(rise, b.windshieldRun), 0, 0),
		}
	)
	addPart(
		ctx,
		"RearWindow",
		Vector3.new(glassHalf * 2 - 0.06, 0.02, math.sqrt(rise ^ 2 + b.rearWindowRun ^ 2)),
		Vector3.new(0, belt + rise / 2, zRoofR + b.rearWindowRun / 2),
		{
			color = GLASS,
			material = Enum.Material.Glass,
			transparency = 0.5,
			reflectance = 0.15,
			collide = true,
			rotation = CFrame.Angles(math.atan2(rise, b.rearWindowRun), 0, 0),
		}
	)

	-- Seats. The full interior (dashboard, instruments, wheel) is stage 2.
	local seatZ = zRoofF + 0.42
	local seatY = b.seatHeight
	local seatOptions: Options = { color = cabin, material = Enum.Material.Fabric, parent = interior }
	local seatTilt = CFrame.Angles(math.rad(-14), 0, 0)
	for _, side in { -1, 1 } do
		local x = side * 0.38
		local tag = if side < 0 then "Driver" else "Passenger"
		if side > 0 then
			addPart(
				ctx,
				"PassengerSeat",
				Vector3.new(0.50, 0.10, 0.50),
				Vector3.new(x, seatY - 0.05, seatZ),
				seatOptions
			)
		end
		addPart(ctx, tag .. "Backrest", Vector3.new(0.50, 0.62, 0.10), Vector3.new(x, seatY + 0.30, seatZ + 0.33), {
			color = cabin,
			material = Enum.Material.Fabric,
			parent = interior,
			rotation = seatTilt,
		})
		addPart(
			ctx,
			tag .. "Headrest",
			Vector3.new(0.26, 0.18, 0.09),
			Vector3.new(x, seatY + 0.70, seatZ + 0.42),
			seatOptions
		)
	end
	if b.style ~= "coupe" then
		local benchZ = math.min(zRoofR - 0.05, zRA - 0.35)
		addPart(
			ctx,
			"RearBench",
			Vector3.new(coreHalf * 2 - 0.1, 0.12, 0.50),
			Vector3.new(0, seatY - 0.04, benchZ),
			seatOptions
		)
		addPart(
			ctx,
			"RearBackrest",
			Vector3.new(coreHalf * 2 - 0.1, 0.60, 0.10),
			Vector3.new(0, seatY + 0.30, benchZ + 0.32),
			{
				color = cabin,
				material = Enum.Material.Fabric,
				parent = interior,
				rotation = seatTilt,
			}
		)
	end
	local seat = Instance.new("Seat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(0.50, 0.10, 0.50) * SPM
	seat.CFrame = chassis.CFrame * CFrame.new((Vector3.new(-0.38, seatY - 0.05, seatZ) + ctx.offset) * SPM)
	seat.Color = cabin
	seat.Material = Enum.Material.Fabric
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.Massless = true
	seat.CanCollide = false
	weld(chassis, seat)
	seat.Parent = interior

	-- Entry prompt on the driver's door (left-hand drive).
	local door = Instance.new("Attachment")
	door.Name = "DriverDoor"
	door.Position = (Vector3.new(-W / 2 - 0.1, shoulder - 0.1, seatZ) + ctx.offset) * SPM
	door.Parent = chassis
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EnterPrompt"
	prompt.ActionText = "Сесть за руль"
	prompt.ObjectText = config.displayName
	prompt.HoldDuration = 0.3
	-- F both enters and leaves; E is the right turn signal.
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = door

	-- Lights. Roles: Head, Tail, Brake, Reverse, TurnL, TurnR.
	local white, offWhite = Color3.fromRGB(255, 250, 235), Color3.fromRGB(170, 175, 180)
	local red, offRed = Color3.fromRGB(255, 20, 20), Color3.fromRGB(90, 12, 12)
	local amber, offAmber = Color3.fromRGB(255, 150, 0), Color3.fromRGB(120, 75, 20)
	local lampY = shoulder - 0.13
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local turnRole = "Turn" .. tag
		local head = addLight(
			ctx,
			lights,
			"Headlight" .. tag,
			"Head",
			Vector3.new(0.34, 0.11, 0.04),
			Vector3.new(side * (W / 2 - 0.33), lampY, zF - 0.015),
			white,
			offWhite
		)
		local beam = Instance.new("SpotLight")
		beam.Name = "Beam"
		beam.Face = Enum.NormalId.Front
		beam.Angle = 70
		beam.Range = 60
		beam.Brightness = 3
		beam.Color = white
		beam.Shadows = true
		beam.Enabled = false
		beam.Parent = head
		addLight(
			ctx,
			lights,
			"TurnFront" .. tag,
			turnRole,
			Vector3.new(0.12, 0.08, 0.04),
			Vector3.new(side * (W / 2 - 0.08), lampY, zF - 0.015),
			amber,
			offAmber
		)
		addLight(
			ctx,
			lights,
			"TurnMirror" .. tag,
			turnRole,
			Vector3.new(0.14, 0.02, 0.012),
			Vector3.new(side * (W / 2 + 0.13), belt + 0.085, zWS + 0.197),
			amber,
			offAmber
		)
		addLight(
			ctx,
			lights,
			"Tail" .. tag,
			"Tail",
			Vector3.new(0.30, 0.05, 0.04),
			Vector3.new(side * (W / 2 - 0.26), lampY + 0.04, zR + 0.015),
			red,
			offRed
		)
		local brake = addLight(
			ctx,
			lights,
			"Brake" .. tag,
			"Brake",
			Vector3.new(0.30, 0.05, 0.04),
			Vector3.new(side * (W / 2 - 0.26), lampY - 0.015, zR + 0.015),
			red,
			offRed
		)
		local glow = Instance.new("PointLight")
		glow.Name = "Beam"
		glow.Range = 10
		glow.Brightness = 1.5
		glow.Color = red
		glow.Enabled = false
		glow.Parent = brake
		addLight(
			ctx,
			lights,
			"TurnRear" .. tag,
			turnRole,
			Vector3.new(0.10, 0.105, 0.04),
			Vector3.new(side * (W / 2 - 0.055), lampY + 0.0125, zR + 0.015),
			amber,
			offAmber
		)
		addLight(
			ctx,
			lights,
			"Reverse" .. tag,
			"Reverse",
			Vector3.new(0.12, 0.05, 0.04),
			Vector3.new(side * (W / 2 - 0.50), lampY - 0.015, zR + 0.015),
			white,
			offWhite
		)
	end
	addLight(
		ctx,
		lights,
		"BrakeHigh",
		"Brake",
		Vector3.new(0.40, 0.025, 0.03),
		Vector3.new(0, roofY - 0.03, zRoofR + 0.06),
		red,
		offRed
	)

	addPlate(ctx, "PlateFront", config.plate, Vector3.new(0, gc + 0.30, zF - 0.012), false)
	addPlate(ctx, "PlateRear", config.plate, Vector3.new(0, lampY - 0.16, zR + 0.012), true)

	for _, geo in geometry.wheels do
		buildWheel(chassis, wheels, geo, if trim.R > 0.5 then CHROME else Color3.fromRGB(120, 120, 125))
	end

	model:SetAttribute("ConfigId", config.id)
	model:SetAttribute("DisplayName", config.displayName)
	return model
end

return VehicleBuilder
