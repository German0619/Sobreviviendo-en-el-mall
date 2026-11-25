-- LockerPanel (solo en el lobby): puesto TAQUILLA, la taquilla del conserje.
--
-- Una tarjeta por objeto (Config.Locker.Order): cuantos tienes guardados y el boton de
-- comprar uno con diamantes. Al empezar cada partida se entrega 1 de cada objeto guardado.
--
-- Estado en atributos del Player (DataService): Locker_<objeto>, Diamonds.
-- El servidor (LockerService) valida todo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local NativeUI = require(script.Parent.NativeUI)
local LobbyPanels = require(script.Parent.LobbyPanels)

local COLORS = NativeUI.COLORS
local label, button, frame, corner, stroke = NativeUI.label, NativeUI.button, NativeUI.frame, NativeUI.corner, NativeUI.stroke

local LockerPanel = {}

local player = Players.LocalPlayer
local DIAMOND = "💎"
local ACCENT = Color3.fromRGB(255, 170, 70)
local L = Config.Locker

local window: Frame
local diamondsLabel: TextLabel
local statusLabel: TextLabel
local cards: { [string]: Frame } = {}
local busy = false

local function storedOf(itemId: string): number
	local n = player:GetAttribute("Locker_" .. itemId)
	return if type(n) == "number" then n else 0
end

local function setStatus(text: string, good: boolean?)
	statusLabel.Text = text
	statusLabel.TextColor3 = if good == true then COLORS.Good elseif good == false then COLORS.Bad else COLORS.Dim
end

local function refresh()
	if not window then
		return
	end
	local diamonds = player:GetAttribute("Diamonds") or 0
	diamondsLabel.Text = string.format("%s %d", DIAMOND, diamonds)
	for _, itemId in L.Order do
		local entry = L.Items[itemId]
		local card = cards[itemId]
		local stored = storedOf(itemId)
		local count = card:FindFirstChild("Count") :: TextLabel
		count.Text = string.format("Guardados: %d / %d", stored, entry.Max)
		count.TextColor3 = if stored > 0 then COLORS.Good else COLORS.Dim
		local b = card:FindFirstChild("Buy") :: TextButton
		if stored >= entry.Max then
			b.Text = "Taquilla llena"
			b.BackgroundColor3 = COLORS.Off
		else
			b.Text = string.format("Guardar uno · %d %s", entry.Price, DIAMOND)
			b.BackgroundColor3 = if diamonds >= entry.Price then COLORS.Buy else Color3.fromRGB(45, 48, 70)
		end
	end
end

local function onBuy(itemId: string)
	if busy then
		return
	end
	busy = true
	local ok, success, message = pcall(function()
		return Remotes.func("RequestBuyLocker"):InvokeServer(itemId)
	end)
	busy = false
	setStatus(if ok then tostring(message) else "Error, inténtalo de nuevo", ok and success == true)
	refresh()
end

local function build(gui: ScreenGui)
	local close, plus
	window, diamondsLabel, close, plus = NativeUI.window(gui, "TAQUILLA DEL CONSERJE", ACCENT)
	close.Activated:Connect(function()
		LockerPanel.Close()
	end)
	plus.Activated:Connect(function()
		LobbyPanels.open("Shop")
	end)

	local body = frame(window, "Body", UDim2.fromScale(1, 0.89), UDim2.fromScale(0, 0.11))

	local info = frame(body, "Info", UDim2.fromScale(1, 0.12), UDim2.fromScale(0, 0), COLORS.Panel)
	corner(info, 0.2)
	label(info, "Text", UDim2.fromScale(0.96, 0.8), UDim2.fromScale(0.02, 0.1), 17, {
		Text = string.format(
			"Lo que guardes aquí te espera en el mall: al empezar cada partida recibes %d de cada objeto guardado.",
			L.PerRun
		),
		Font = Enum.Font.Gotham,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	statusLabel = label(body, "Status", UDim2.fromScale(1, 0.05), UDim2.fromScale(0, 0.14), 15, {
		TextColor3 = COLORS.Dim,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	-- Tarjetas en dos columnas
	local grid = frame(body, "Grid", UDim2.fromScale(1, 0.79), UDim2.fromScale(0, 0.21))
	local layout = Instance.new("UIGridLayout")
	local rows = math.ceil(#L.Order / 2)
	layout.CellPadding = UDim2.fromScale(0.015, 0.03)
	layout.CellSize = UDim2.fromScale(0.4925, (1 - 0.03 * (rows - 1)) / rows)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for i, itemId in L.Order do
		local item = Config.ShopItems[itemId]
		local card = frame(grid, itemId, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), COLORS.Panel)
		card.LayoutOrder = i
		corner(card, 0.08)
		stroke(card, ACCENT, 0.6, 1.5)
		label(card, "Name", UDim2.fromScale(0.94, 0.2), UDim2.fromScale(0.03, 0.06), 24, {
			Text = item.DisplayName,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		label(card, "Description", UDim2.fromScale(0.94, 0.2), UDim2.fromScale(0.03, 0.28), 15, {
			Text = item.Description,
			Font = Enum.Font.Gotham,
			TextColor3 = COLORS.Dim,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		label(card, "Count", UDim2.fromScale(0.94, 0.14), UDim2.fromScale(0.03, 0.5), 16, {
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local b = button(card, "Buy", UDim2.fromScale(0.94, 0.26), UDim2.fromScale(0.03, 0.69), COLORS.Off, 20)
		b.Activated:Connect(function()
			task.spawn(onBuy, itemId)
		end)
		cards[itemId] = card
	end
end

function LockerPanel.Open()
	if not window then
		return
	end
	setStatus("")
	refresh()
	window.Visible = true
end

function LockerPanel.Close()
	if window then
		window.Visible = false
	end
end

function LockerPanel.IsOpen(): boolean
	return window ~= nil and window.Visible
end

function LockerPanel.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "LockerPanel"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 7
	gui.Parent = player:WaitForChild("PlayerGui")
	build(gui)

	player.AttributeChanged:Connect(function(name: string)
		if window.Visible and (name == "Diamonds" or string.sub(name, 1, 7) == "Locker_") then
			refresh()
		end
	end)
end

return LockerPanel
