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

local function refresh()
	if not window then
		return
	end
	local money = player:GetAttribute("Money") or 0
	moneyLabel.Text = "Billetes: " .. Util.formatMoney(money) .. "   (las mejoras duran esta partida)"
	for statName, row in rows do
		local stat = Config.Stats[statName]
		local level = player:GetAttribute("Level_" .. statName) or 0
		local cost = Config.getUpgradeCost(statName, level)
		local perLevel = if stat.PerLevel % 1 == 0 then tostring(stat.PerLevel) else string.format("%.1f", stat.PerLevel)
		row.Level.Text = string.format("Nivel %d / %d   ·   +%s por nivel", level, stat.MaxLevel, perLevel)
		if cost then
			row.Button.Text = Util.formatMoney(cost)
			row.Button.BackgroundColor3 = if money >= cost then C.Button else C.ButtonOff
		else
			row.Button.Text = "MÁX"
			row.Button.BackgroundColor3 = C.ButtonOff
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
		setStatus(Config.Stats[statName].DisplayName .. " mejorada", true)
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
	window, content = UIKit.window(gui, "MEJORAS", Vector2.new(460, 400), UpgradeUI.Close)

	moneyLabel = UIKit.text({
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Accent,
		ZIndex = 22,
		Parent = content,
	})

	for i, statName in Config.StatOrder do
		local stat = Config.Stats[statName]
		local row = UIKit.make("Frame", {
			Position = UDim2.fromOffset(0, 32 + (i - 1) * 64),
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = C.Row,
			ZIndex = 22,
			Parent = content,
		}, { UIKit.corner(8) })
		UIKit.text({
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -140, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = stat.DisplayName,
			ZIndex = 23,
			Parent = row,
		})
		local levelLabel = UIKit.text({
			Position = UDim2.fromOffset(12, 30),
			Size = UDim2.new(1, -140, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 13,
			Font = UIKit.FONT_LIGHT,
			TextColor3 = C.Dim,
			ZIndex = 23,
			Parent = row,
		})
		local button = UIKit.button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(110, 36),
			ZIndex = 23,
			Parent = row,
		}, function()
			requestUpgrade(statName)
		end)
		rows[statName] = { Level = levelLabel, Button = button }
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
