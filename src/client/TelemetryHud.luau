--!strict
-- Stage 1 driving readout: speed, gear, rpm, fuel, temperature, lights and
-- a braking-distance meter for testing. Compact and anchored to the bottom
-- right so it stays out of the driving view. The full UIController replaces
-- it in a later stage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DrivingSim")
local Constants = require(Shared.Constants)
local VehicleController = require(script.Parent.VehicleController)

local TelemetryHud = {}

local TEXT = Color3.fromRGB(240, 240, 240)
local DIM = Color3.fromRGB(110, 115, 120)
local GREEN = Color3.fromRGB(60, 220, 90)
local BLUE = Color3.fromRGB(80, 150, 255)
local RED = Color3.fromRGB(240, 60, 50)
local AMBER = Color3.fromRGB(255, 170, 30)

local HELP =
	"W / S  газ / тормоз, задний ход\nA / D  руль\nПробел  ручной тормоз\nQ / E  поворотники    H  аварийка\nL  фары    F  выйти    R  поставить на колёса"

local function label(
	parent: Instance,
	text: string,
	size: number,
	position: UDim2,
	extent: UDim2,
	align: Enum.TextXAlignment?
): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.GothamBold
	item.TextSize = size
	item.TextColor3 = TEXT
	item.TextXAlignment = align or Enum.TextXAlignment.Left
	item.Text = text
	item.Position = position
	item.Size = extent
	item.Parent = parent
	return item
end

local function bar(parent: Instance, position: UDim2, extent: UDim2): Frame
	local back = Instance.new("Frame")
	back.BackgroundColor3 = Color3.fromRGB(50, 52, 56)
	back.BorderSizePixel = 0
	back.Position = position
	back.Size = extent
	back.Parent = parent
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = TEXT
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = back
	return fill
end

function TelemetryHud.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DS_TelemetryHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -16, 1, -16)
	panel.Size = UDim2.fromOffset(300, 150)
	panel.BackgroundColor3 = Color3.fromRGB(14, 15, 18)
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local name = label(panel, "", 13, UDim2.fromOffset(14, 8), UDim2.fromOffset(272, 16))
	name.TextColor3 = DIM
	local speed = label(panel, "0", 46, UDim2.fromOffset(14, 26), UDim2.fromOffset(110, 48), Enum.TextXAlignment.Right)
	label(panel, "км/ч", 14, UDim2.fromOffset(130, 52), UDim2.fromOffset(50, 18)).TextColor3 = DIM
	local gear = label(panel, "1", 34, UDim2.fromOffset(236, 30), UDim2.fromOffset(50, 40), Enum.TextXAlignment.Right)
	local rpmText = label(panel, "0 об/мин", 12, UDim2.fromOffset(14, 78), UDim2.fromOffset(160, 14))
	local rpmFill = bar(panel, UDim2.fromOffset(14, 94), UDim2.fromOffset(272, 6))
	local fuelText = label(panel, "", 12, UDim2.fromOffset(14, 106), UDim2.fromOffset(130, 14))
	local tempText =
		label(panel, "", 12, UDim2.fromOffset(156, 106), UDim2.fromOffset(130, 14), Enum.TextXAlignment.Right)
	local leftArrow = label(panel, "◀", 18, UDim2.fromOffset(14, 124), UDim2.fromOffset(24, 20))
	local rightArrow = label(panel, "▶", 18, UDim2.fromOffset(42, 124), UDim2.fromOffset(24, 20))
	local lightsText = label(panel, "ФАРЫ", 12, UDim2.fromOffset(78, 127), UDim2.fromOffset(70, 14))
	local handbrakeText = label(panel, "РУЧНИК", 12, UDim2.fromOffset(150, 127), UDim2.fromOffset(60, 14))
	local stabilityText = label(panel, "ESC", 12, UDim2.fromOffset(216, 127), UDim2.fromOffset(30, 14))
	local absText = label(panel, "ABS", 12, UDim2.fromOffset(252, 127), UDim2.fromOffset(34, 14))

	local hint = label(gui, "", 14, UDim2.new(0, 16, 1, -16), UDim2.fromOffset(420, 96))
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.TextYAlignment = Enum.TextYAlignment.Bottom
	hint.TextStrokeTransparency = 0.5
	local brakeReadout =
		label(gui, "", 14, UDim2.new(1, -16, 1, -176), UDim2.fromOffset(300, 18), Enum.TextXAlignment.Right)
	brakeReadout.AnchorPoint = Vector2.new(1, 1)
	brakeReadout.TextStrokeTransparency = 0.5

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Braking-distance meter: from the moment the brake goes on to standstill.
	local brakeFrom: number? = nil
	local brakeDistance = 0
	local drivingTime = 0

	RunService.Heartbeat:Connect(function(dt)
		local session = VehicleController.getSession()
		panel.Visible = session ~= nil
		if not session then
			hint.Text =
				"Подойдите к автомобилю и удерживайте F, чтобы сесть за руль"
			brakeFrom = nil
			drivingTime = 0
			return
		end
		drivingTime += dt
		hint.Text = if drivingTime < 20 then HELP else ""

		local sim = session.physics.sim
		local model = session.model
		local config = session.config
		name.Text = `{config.displayName}  ·  {config.drivetrain.layout}  ·  {config.mass} кг`
		speed.Text = tostring(math.floor(sim.speedKmh + 0.5))
		gear.Text = sim:gearLabel()
		rpmText.Text = `{math.floor(sim.power.rpm / 10 + 0.5) * 10} об/мин`
		local rpmFraction = math.clamp(sim.power.rpm / config.engine.limiterRpm, 0, 1)
		rpmFill.Size = UDim2.fromScale(rpmFraction, 1)
		rpmFill.BackgroundColor3 = if sim.power.rpm >= config.engine.redlineRpm then RED else TEXT
		fuelText.Text = string.format("Топливо %.1f / %d л", sim.fuel, config.fuel.tankLitres)
		fuelText.TextColor3 = if sim.fuel < config.fuel.tankLitres * 0.1 then AMBER else TEXT
		tempText.Text = string.format("ОЖ %d °C", sim.temperature)
		tempText.TextColor3 = if sim.temperature > 110 then RED else TEXT

		local blinkOn = (Workspace:GetServerTimeNow() * Constants.BLINK_HZ) % 1 < 0.5
		local signal = model:GetAttribute("Signal")
		local left = signal == Constants.SIGNAL_LEFT or signal == Constants.SIGNAL_HAZARD
		local right = signal == Constants.SIGNAL_RIGHT or signal == Constants.SIGNAL_HAZARD
		leftArrow.TextColor3 = if left and blinkOn then GREEN else DIM
		rightArrow.TextColor3 = if right and blinkOn then GREEN else DIM
		local headlights = model:GetAttribute("Headlights")
		lightsText.Text = if headlights == Constants.HEADLIGHTS_HIGH
			then "ДАЛЬНИЙ"
			elseif headlights == Constants.HEADLIGHTS_LOW then "БЛИЖНИЙ"
			else "ФАРЫ"
		lightsText.TextColor3 = if headlights == Constants.HEADLIGHTS_HIGH
			then BLUE
			elseif headlights == Constants.HEADLIGHTS_LOW then GREEN
			else DIM
		handbrakeText.TextColor3 = if session.input.handbrake then RED else DIM
		stabilityText.TextColor3 = if sim.stabilityActive then AMBER else DIM
		local limited = false
		for _, wheel in sim.wheels do
			limited = limited or wheel.slipping
		end
		absText.TextColor3 = if limited and sim.braking then AMBER else DIM

		if sim.braking and not sim.reversing then
			if not brakeFrom and sim.speedKmh > 20 then
				brakeFrom = sim.speedKmh
				brakeDistance = 0
			end
			if brakeFrom then
				brakeDistance += sim.speedKmh / Constants.MS_TO_KMH * dt
				brakeReadout.Text =
					string.format("Тормозной путь с %d км/ч: %.1f м", brakeFrom, brakeDistance)
			end
		else
			brakeFrom = nil
		end
	end)
end

return TelemetryHud
