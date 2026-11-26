-- UpgradeUI: ventana para comprar niveles de estadisticas.
-- Se abre sola en la fase de Mejoras y con la tecla U fuera de la noche.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local GameState = require(Shared.GameState)
local UIKit = require(script.Parent.UIKit)
local HUD = require(script.Parent.HUD)

local player = Players.LocalPlayer
local C = UIKit.COLORS

local UpgradeUI = {}

local window, statusLabel, moneyLabel
local rows = {}
local busy = false

local function isNight(): boolean
	return GameState.Folder:GetAttribute("Phase") == "Night"
end

local function setStatus(message: string, good: boolean?)
	statusLabel.Text = message
	statusLabel.TextColor3 = if good then C.Good else C.Bad
end

-- Icono, color y unidad de cada estadistica
local STAT_STYLE = {
	Health = { Glyph = "♥", Color = Color3.fromRGB(225, 75, 75), Unit = " de vida" },
	Stamina = { Glyph = "»", Color = Color3.fromRGB(235, 195, 65), Unit = " de estamina" },
	Battery = { Glyph = "☀", Color = Color3.fromRGB(120, 190, 255), Unit = " s de luz" },
	WalkSpeed = { Glyph = "👟", Color = Color3.fromRGB(100, 220, 140), Unit = " de velocidad" },
}
local DEFAULT_STYLE = { Glyph = "+", Color = C.Accent, Unit = "" }

local function num(v: number): string
	return if v % 1 == 0 then tostring(v) else string.format("%.1f", v)
end

local function refresh()
	if not window then
		return
	end
	local money = player:GetAttribute("Money") or 0
	moneyLabel.Text = Util.formatMoney(money)
	for statName, row in rows do
		local stat = Config.Stats[statName]
		local style = STAT_STYLE[statName] or DEFAULT_STYLE
		local level = player:GetAttribute("Level_" .. statName) or 0
		local cost = Config.getUpgradeCost(statName, level)
		local now = stat.PerLevel * level
		if cost then
			row.Level.Text = string.format(
				'Nivel <b>%d</b>/%d   ·   +%s <font color="#FFC850">→ +%s</font>%s',
				level,
				stat.MaxLevel,
				num(now),
				num(now + stat.PerLevel),
				style.Unit
			)
		else
			row.Level.Text = string.format('Nivel <b>%d</b>/%d   ·   +%s%s   <font color="#6EDC82">COMPLETA</font>', level, stat.MaxLevel, num(now), style.Unit)
		end
		for i, pip in row.Pips do
			pip.BackgroundColor3 = if i <= level then style.Color else C.Track
			pip.BackgroundTransparency = if i <= level then 0 else 0.1
		end
		local affordable = cost ~= nil and money >= cost
		if cost then
			row.Price.Text = Util.formatMoney(cost)
			row.Caption.Text = if affordable then "MEJORAR" else "TE FALTA " .. Util.formatMoney(cost - money)
			row.Button.BackgroundColor3 = if affordable then C.Button else C.ButtonOff
			row.Price.TextColor3 = if affordable then C.Text else C.Dim
		else
			row.Price.Text = "MÁX"
			row.Caption.Text = "nivel máximo"
			row.Button.BackgroundColor3 = C.ButtonOff
			row.Price.TextColor3 = C.Good
		end
		row.Stroke.Transparency = if affordable then 0.35 else 0.75
	end
end

-- Destello de la fila al comprar (y salto de la casilla nueva)
local function celebrate(statName: string)
	local row = rows[statName]
	if not row then
		return
	end
	local style = STAT_STYLE[statName] or DEFAULT_STYLE
	row.Frame.BackgroundColor3 = UIKit.shade(style.Color, -0.45)
	UIKit.tween(row.Frame, 0.6, { BackgroundColor3 = C.Row })
	local level = player:GetAttribute("Level_" .. statName) or 0
	local pip = row.Pips[level]
	if pip then
		local s = pip:FindFirstChildOfClass("UIScale")
		if s then
			s.Scale = 1.8
			UIKit.tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
end

local function requestUpgrade(statName: string)
	if busy then
		return
	end
	busy = true
	local ok, result, message = pcall(function()
		return Remotes.func("RequestUpgrade"):InvokeServer(statName)
	end)
	busy = false
	if not ok then
		warn("[UpgradeUI] RequestUpgrade fallo:", result)
		setStatus("Error: " .. tostring(result))
	elseif result then
		setStatus("✓ " .. Config.Stats[statName].DisplayName .. " mejorada", true)
		refresh()
		celebrate(statName)
	else
		setStatus(message or "No se pudo mejorar")
	end
	refresh()
end

function UpgradeUI.Open()
	if isNight() then
		HUD.Toast("Las mejoras no están disponibles durante la noche.", "bad")
		return
	end
	setStatus("")
	refresh()
	window.Visible = true
end

function UpgradeUI.Close()
	window.Visible = false
end

function UpgradeUI.Toggle()
	if window.Visible then
		UpgradeUI.Close()
	else
		UpgradeUI.Open()
	end
end

local function build()
	local gui = UIKit.make("ScreenGui", {
		Name = "UpgradeUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
		Parent = player:WaitForChild("PlayerGui"),
	})
	UIKit.adapt(gui) -- escala segun la pantalla y respeta el notch
	local content
	local ROW = 82
	window, content = UIKit.window(gui, "MEJORAS", Vector2.new(560, 130 + #Config.StatOrder * ROW), UpgradeUI.Close)

	-- Billetes: pastilla arriba con la nota de que duran esta partida
	local moneyPill = UIKit.make("Frame", {
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = UIKit.shade(C.Accent, -0.8),
		ZIndex = 22,
		Parent = content,
	}, {
		UIKit.corner(15),
		UIKit.make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
	})
	UIKit.stroke(moneyPill, C.Accent, 1, 0.4)
	moneyLabel = UIKit.text({
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 18,
		Font = UIKit.FONT_BLACK,
		TextColor3 = C.Accent,
		ZIndex = 23,
		Parent = moneyPill,
	})
	UIKit.text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(1, -170, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 13,
		Font = UIKit.FONT_LIGHT,
		TextColor3 = C.Dim,
		Text = "Las mejoras duran esta partida",
		ZIndex = 22,
		Parent = content,
	})

	for i, statName in Config.StatOrder do
		local stat = Config.Stats[statName]
		local style = STAT_STYLE[statName] or DEFAULT_STYLE
		local row = UIKit.make("Frame", {
			Position = UDim2.fromOffset(0, 40 + (i - 1) * ROW),
			Size = UDim2.new(1, 0, 0, ROW - 8),
			BackgroundColor3 = C.Row,
			ZIndex = 22,
			Parent = content,
		}, { UIKit.corner(10) })
		local stroke = UIKit.stroke(row, style.Color, 1, 0.75)
		UIKit.iconBox({
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(50, 50),
			Radius = 10,
			ZIndex = 23,
			Parent = row,
		}, style.Glyph, style.Color)
		UIKit.text({
			Position = UDim2.fromOffset(72, 8),
			Size = UDim2.new(1, -220, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 18,
			Font = UIKit.FONT_BLACK,
			Text = UIKit.upper(stat.DisplayName),
			ZIndex = 23,
			Parent = row,
		})
		local levelLabel = UIKit.text({
			Position = UDim2.fromOffset(72, 30),
			Size = UDim2.new(1, -220, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 13,
			Font = UIKit.FONT_LIGHT,
			RichText = true,
			TextColor3 = C.Dim,
			ZIndex = 23,
			Parent = row,
		})
		-- Casillas de nivel
		local pipsFrame = UIKit.make("Frame", {
			Position = UDim2.fromOffset(72, 52),
			Size = UDim2.new(1, -220, 0, 10),
			BackgroundTransparency = 1,
			ZIndex = 23,
			Parent = row,
		}, {
			UIKit.make("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 3),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local pips = {}
		for p = 1, stat.MaxLevel do
			local pip = UIKit.make("Frame", {
				Size = UDim2.new(1 / stat.MaxLevel, -3, 1, 0),
				BackgroundColor3 = C.Track,
				BorderSizePixel = 0,
				LayoutOrder = p,
				ZIndex = 24,
				Parent = pipsFrame,
			}, { UIKit.corner(3), UIKit.make("UIScale", {}) })
			pips[p] = pip
		end
		local button = UIKit.button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(128, 54),
			Text = "",
			ZIndex = 23,
			Parent = row,
		}, function()
			requestUpgrade(statName)
		end)
		UIKit.gloss(button, 0.3)
		local price = UIKit.text({
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.new(1, 0, 0, 24),
			TextSize = 20,
			Font = UIKit.FONT_BLACK,
			ZIndex = 24,
			Parent = button,
		})
		local caption = UIKit.text({
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.new(1, 0, 0, 16),
			TextSize = 11,
			Font = UIKit.FONT,
			TextColor3 = Color3.fromRGB(215, 235, 215),
			ZIndex = 24,
			Parent = button,
		})
		rows[statName] = {
			Frame = row,
			Level = levelLabel,
			Button = button,
			Price = price,
			Caption = caption,
			Pips = pips,
			Stroke = stroke,
		}
	end

	statusLabel = UIKit.text({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 15,
		Text = "",
		ZIndex = 22,
		Parent = content,
	})
end

function UpgradeUI.Start()
	build()

	player:GetAttributeChangedSignal("Money"):Connect(refresh)
	for statName in Config.Stats do
		player:GetAttributeChangedSignal("Level_" .. statName):Connect(refresh)
	end

	GameState.Folder:GetAttributeChangedSignal("Phase"):Connect(function()
		local phase = GameState.Folder:GetAttribute("Phase")
		if phase == "Upgrades" then
			-- Dejar ver unos segundos los resultados antes de abrir
			task.delay(4, function()
				if GameState.Folder:GetAttribute("Phase") == "Upgrades" then
					UpgradeUI.Open()
				end
			end)
		elseif phase == "Night" then
			UpgradeUI.Close()
		end
	end)

	ContextActionService:BindAction("Upgrades", function(_, state)
		if state == Enum.UserInputState.Begin then
			UpgradeUI.Toggle()
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.U)
	ContextActionService:SetTitle("Upgrades", "⬆")
	-- (posicion: la coloca Roblox)
end

return UpgradeUI
