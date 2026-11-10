--!strict
-- Headless check of the vehicle builder: `lune run tests/builder`.
-- Runs the shipped VehicleBuilder against Lune's Roblox instance library and
-- verifies each generated model's structure and proportions.

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./loader")

local rbx = roblox :: any
local shared = Loader.root("src/shared")
local server = Loader.root("src/server")

local fakeGame = {
	GetService = function(_, name: string)
		if name == "ReplicatedStorage" then
			return {
				WaitForChild = function()
					return shared
				end,
			}
		end
		error("unexpected service " .. name)
	end,
}
Loader.globals = {
	game = fakeGame,
	Instance = rbx.Instance,
	Vector3 = rbx.Vector3,
	CFrame = rbx.CFrame,
	Color3 = rbx.Color3,
	UDim2 = rbx.UDim2,
	Enum = rbx.Enum,
	PhysicalProperties = rbx.PhysicalProperties,
}

local Constants = Loader.require(shared.Constants)
local Vehicles = Loader.require(shared.Config.Vehicles)
local VehicleBuilder = Loader.require(server.VehicleBuilder)

local MPS = Constants.METERS_PER_STUD
local failures = 0
local function check(condition: boolean, message: string)
	if not condition then
		failures += 1
		print("  FAIL  " .. message)
	end
end
local function near(value: number, target: number, tolerance: number, message: string)
	check(
		math.abs(value - target) <= tolerance,
		string.format("%s: %.3f, expected %.3f +/- %.3f", message, value, target, tolerance)
	)
end

-- Lune's instance library has no defaults for some properties and no
-- derived ones (Position, GetMass), so read them defensively.
local function prop(item: any, name: string, default: any): any
	local ok, value = pcall(function()
		return item[name]
	end)
	return if ok and value ~= nil then value else default
end
local function at(part: any): any
	return part.CFrame.Position
end
local function chassisMass(part: any): number
	local size = part.Size
	return part.CustomPhysicalProperties.Density * size.X * size.Y * size.Z
end

-- World-space bounds of a part, allowing for rotation.
local function bounds(part: any): (any, any)
	local half = part.Size / 2
	local lo = rbx.Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local corner = part.CFrame:PointToWorldSpace(rbx.Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
				lo = lo:Min(corner)
				hi = hi:Max(corner)
			end
		end
	end
	return lo, hi
end

print("car             parts  length  width  height  clearance")
for _, config in Vehicles.list do
	local model = VehicleBuilder.build(config)
	local d = config.dimensions
	local chassis = model.PrimaryPart
	check(chassis ~= nil and chassis.Name == "Chassis", config.id .. ": PrimaryPart is the chassis")
	-- The chassis centre is the centre of mass; the ground is comHeight below.
	local groundY = at(chassis).Y - d.comHeight / MPS

	local lo = rbx.Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	local lowestSolid = math.huge
	local parts, anchored, heavy = 0, 0, 0
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			parts += 1
			local size = item.Size
			check(
				size.X > 0.005 and size.Y > 0.005 and size.Z > 0.005,
				`{config.id}: {item.Name} has a degenerate size`
			)
			if prop(item, "Anchored", false) then
				anchored += 1
			end
			if item ~= chassis and not prop(item, "Massless", false) then
				heavy += 1
			end
			if item ~= chassis and item.Name ~= "Hub" then
				local a, b = bounds(item)
				lo = lo:Min(a)
				hi = hi:Max(b)
				if prop(item, "CanCollide", true) then
					lowestSolid = math.min(lowestSolid, a.Y)
				end
			end
		end
	end
	check(anchored == 0, config.id .. ": no part is anchored")
	check(heavy == 0, config.id .. ": only the chassis carries mass")

	local length = (hi.Z - lo.Z) * MPS
	local width = (hi.X - lo.X) * MPS
	local height = (hi.Y - groundY) * MPS
	local clearance = (lowestSolid - groundY) * MPS
	near(length, d.length, 0.12, config.id .. " length")
	-- Door mirrors add about 0.22 m per side to the body width.
	near(width, d.width + 0.44, 0.06, config.id .. " width over mirrors")
	near(height, d.height, 0.02, config.id .. " height")
	near(clearance, d.groundClearance, 0.03, config.id .. " ground clearance")
	near((lo.Y - groundY) * MPS, 0, 0.01, config.id .. " tyres touch the ground")
	near(chassisMass(chassis), config.mass, 1, config.id .. " chassis mass")

	-- Wheels: four welds on the chassis, tyres at the configured track and wheelbase.
	local axleZ = {}
	for _, name in { "FL", "FR", "RL", "RR" } do
		local weld = chassis:FindFirstChild("Wheel_" .. name)
		local wheel = model.Wheels:FindFirstChild(name)
		check(weld ~= nil and weld:IsA("Weld") and weld.Part0 == chassis, `{config.id}: weld for {name}`)
		if wheel and weld then
			check(weld.Part1 == wheel.Hub, `{config.id}: {name} weld drives its hub`)
			local tire = wheel.Tire
			near(tire.Size.Y * MPS, d.wheelRadius * 2, 0.001, `{config.id} {name} tyre diameter`)
			near((at(tire).Y - groundY) * MPS, d.wheelRadius, 0.005, `{config.id} {name} axle height`)
			local isFront = name:sub(1, 1) == "F"
			local track = if isFront then d.trackFront else d.trackRear
			near(math.abs(at(tire).X - at(chassis).X) * MPS, track / 2, 0.005, `{config.id} {name} track`)
			check((at(tire).X < at(chassis).X) == (name:sub(2, 2) == "L"), `{config.id}: {name} is on its own side`)
			axleZ[name] = at(tire).Z
			-- The tyre must stay inside the body's outer skin.
			check(
				math.abs(at(tire).X - at(chassis).X) * MPS + d.wheelWidth / 2 <= d.width / 2 + 0.005,
				`{config.id}: {name} tyre inside the body`
			)
		end
	end
	if axleZ.FL and axleZ.RL then
		near((axleZ.RL - axleZ.FL) * MPS, d.wheelbase, 0.005, config.id .. " wheelbase")
		check(axleZ.FL < axleZ.RL, config.id .. ": front axle is toward -Z")
		-- Static axle loads from the chassis (centre of mass) position.
		local frontShare = (axleZ.RL - at(chassis).Z) / (axleZ.RL - axleZ.FL)
		near(frontShare, d.weightFront, 0.002, config.id .. " front weight share")
	end

	-- Lights, seat and entry prompt.
	local roles = {}
	for _, lamp in model.Lights:GetChildren() do
		local role = lamp:GetAttribute("Role")
		roles[role] = (roles[role] or 0) + 1
		local side = at(lamp).X - at(chassis).X
		if role == "TurnL" then
			check(side < 0, `{config.id}: {lamp.Name} is on the left`)
		elseif role == "TurnR" then
			check(side > 0, `{config.id}: {lamp.Name} is on the right`)
		end
		local atFront = at(lamp).Z < at(chassis).Z
		if role == "Head" then
			check(atFront, `{config.id}: {lamp.Name} is at the front`)
			check(lamp:FindFirstChildOfClass("SpotLight") ~= nil, `{config.id}: {lamp.Name} has a beam`)
		elseif role == "Tail" or role == "Brake" or role == "Reverse" then
			check(not atFront, `{config.id}: {lamp.Name} is at the rear`)
		end
	end
	check(
		roles.Head == 2 and roles.Tail == 2 and roles.Reverse == 2,
		config.id .. ": head, tail and reverse lamp pairs"
	)
	check(roles.Brake == 3, config.id .. ": two brake lamps and a high-level lamp")
	check(roles.TurnL == 3 and roles.TurnR == 3, config.id .. ": front, mirror and rear indicators per side")

	local seat = model:FindFirstChild("DriverSeat", true)
	check(seat ~= nil and seat:IsA("Seat"), config.id .. ": driver's seat")
	if seat then
		check(at(seat).X < at(chassis).X, config.id .. ": left-hand drive")
		local seatTop = (at(seat).Y + seat.Size.Y / 2 - groundY) * MPS
		near(seatTop, config.body.seatHeight, 0.005, config.id .. " seat height")
		-- Seated R15 character: head top about 0.95 m above the cushion.
		check(
			seatTop + 0.95 < d.height + 0.08,
			`{config.id}: headroom ({string.format("%.2f", d.height - seatTop)} m under the roof)`
		)
	end
	check(model:FindFirstChild("EnterPrompt", true) ~= nil, config.id .. ": entry prompt")
	check(model:GetAttribute("ConfigId") == config.id, config.id .. ": ConfigId attribute")

	print(string.format("%-14s  %5d  %6.2f  %5.2f  %6.2f  %9.2f", config.id, parts, length, width, height, clearance))
end

if failures > 0 then
	print(`\n{failures} check(s) failed`)
	process.exit(1)
end
print("\nAll checks passed")
