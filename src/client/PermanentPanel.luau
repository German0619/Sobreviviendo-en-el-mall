-- PermanentPanel (solo en el lobby): puesto MEJORAS, mejoras permanentes.
--
--   Arriba   puntos de mejora (del reinicio) y el boton REINICIAR (Robux, producto
--            PermanentReset): devuelve todo lo gastado como puntos para repartir.
--   Tarjetas una por mejora (Config.PermanentUpgradeOrder): nivel, efecto actual y
--            siguiente, y el boton de comprar (pide confirmar con un segundo toque).
--            Se paga primero con puntos y lo que falte con diamantes.
--
-- Estado en atributos del Player (DataService): Perm_<id>, UpgradePoints, Diamonds.
-- El servidor (PermanentUpgradeService) valida todo. No confundir con UpgradeUI, que son
-- las mejoras de billetes que duran una partida en el mall.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local NativeUI = require(script.Parent.NativeUI)
local LobbyPanels = require(script.Parent.LobbyPanels)

local COLORS = NativeUI.COLORS
local label, button, frame, corner, stroke = NativeUI.label, NativeUI.button, NativeUI.frame, NativeUI.corner, NativeUI.stroke

local PermanentPanel = {}

local player = Players.LocalPlayer
local DIAMOND = "💎"
local POINTS = "✦"
local ACCENT = Color3.fromRGB(120, 200, 255)
local POINTS_COLOR = Color3.fromRGB(190, 150, 255)

local window: Frame
local diamondsLabel: TextLabel
local pointsLabel: TextLabel
local resetButton: TextButton
local statusLabel: TextLabel
local cards: { [string]: Frame } = {}
local confirmId: string? = nil -- compra pendiente de confirmar
local busy = false
local resetPrice = "R$"

local function levelOf(upgradeId: string): number
	local level = player:GetAttribute("Perm_" .. upgradeId)
	return if type(level) == "number" then level else 0
end

local function points(): number
	return player:GetAttribute("UpgradePoints") or 0
end

local function diamonds(): number
	return player:GetAttribute("Diamonds") or 0
end

local function spentTotal(): number
	local total = 0
	for upgradeId in Config.PermanentUpgrades do
		total += Config.getPermanentSpent(upgradeId, levelOf(upgradeId))
	end
	return total
end

local function setStatus(text: string, good: boolean?)
	statusLabel.Text = text
	statusLabel.TextColor3 = if good == true then COLORS.Good elseif good == false then COLORS.Bad else COLORS.Dim
end

-- "180 💎", "180 ✦" o "50 ✦ + 130 💎" segun los puntos que tengas.
local function priceText(cost: number): string
	local fromPoints = math.min(points(), cost)
	local fromDiamonds = cost - fromPoints
	if fromPoints <= 0 then
		return string.format("%d %s", cost, DIAMOND)
	elseif fromDiamonds <= 0 then
		return string.format("%d %s", cost, POINTS)
	end
	return string.format("%d %s + %d %s", fromPoints, POINTS, fromDiamonds, DIAMOND)
end

----------------------------------------------------------------------
-- Refresco
----------------------------------------------------------------------

local function refresh()
	if not window then
		return
	end
	diamondsLabel.Text = string.format("%s %d", DIAMOND, diamonds())
	pointsLabel.Text = string.format("%s %d puntos de mejora", POINTS, points())
	pointsLabel.TextColor3 = if points() > 0 then POINTS_COLOR else COLORS.Dim

	local spent = spentTotal()
	resetButton.Text = if spent > 0
		then string.format("Reiniciar (+%d %s) · %s", spent, POINTS, resetPrice)
		else "Reiniciar · nada que devolver"
	resetButton.BackgroundColor3 = if spent > 0 then Color3.fromRGB(200, 150, 30) else COLORS.Off

	for _, upgradeId in Config.PermanentUpgradeOrder do
		local upgrade = Config.PermanentUpgrades[upgradeId]
		local card = cards[upgradeId]
		local level = levelOf(upgradeId)
		local maxLevel = #upgrade.Costs
		local cost = Config.getPermanentCost(upgradeId, level)

		;(card:FindFirstChild("Level") :: TextLabel).Text = string.format("Nivel %d / %d", level, maxLevel)
		-- Puntos de nivel (llenos = comprados)
		local pips = card:FindFirstChild("Pips") :: Frame
		for n = 1, maxLevel do
			local pip = pips:FindFirstChild(tostring(n)) :: Frame
			pip.BackgroundColor3 = if n <= level then ACCENT else Color3.fromRGB(20, 22, 34)
		end
		local effect = card:FindFirstChild("Effect") :: TextLabel
		if cost then
			effect.Text = string.format("%s  →  %s", Config.getPermanentEffectText(upgradeId, level), Config.getPermanentEffectText(upgradeId, level + 1))
		else
			effect.Text = Config.getPermanentEffectText(upgradeId, level) .. "  (máximo)"
		end

		local b = card:FindFirstChild("Buy") :: TextButton
		local s = card:FindFirstChildOfClass("UIStroke") :: UIStroke
		if not cost then
			b.Text = "✓ Máximo"
			b.BackgroundColor3 = COLORS.Off
			s.Color = COLORS.Good
			s.Transparency = 0.4
		elseif confirmId == upgradeId then
			b.Text = "¿Confirmar?"
			b.BackgroundColor3 = COLORS.Buy
			s.Color = ACCENT
			s.Transparency = 0.1
		else
			local affordable = points() + diamonds() >= cost
			b.Text = "Mejorar · " .. priceText(cost)
			b.BackgroundColor3 = if affordable then COLORS.Buy else Color3.fromRGB(45, 48, 70)
			s.Transparency = 1
		end
	end
end

----------------------------------------------------------------------
-- Acciones
----------------------------------------------------------------------

local function onBuy(upgradeId: string)
	if busy or not Config.getPermanentCost(upgradeId, levelOf(upgradeId)) then
		return
	end
	if confirmId ~= upgradeId then
		-- Primer toque: pedir confirmacion (3 s)
		confirmId = upgradeId
		refresh()
		task.delay(3, function()
			if confirmId == upgradeId then
				confirmId = nil
				refresh()
			end
		end)
		return
	end
	confirmId = nil
	busy = true
	local ok, success, message = pcall(function()
		return Remotes.func("RequestBuyPermanent"):InvokeServer(upgradeId)
	end)
	busy = false
	setStatus(if ok then tostring(message) else "Error, inténtalo de nuevo", ok and success == true)
	refresh()
end

----------------------------------------------------------------------
-- Construccion
----------------------------------------------------------------------

local function buildCard(grid: Frame, upgradeId: string, order: number)
	local upgrade = Config.PermanentUpgrades[upgradeId]
	local card = frame(grid, upgradeId, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), COLORS.Panel)
	card.LayoutOrder = order
	corner(card, 0.1)
	stroke(card, ACCENT, 1, 1.5)

	label(card, "Name", UDim2.fromScale(0.6, 0.22), UDim2.fromScale(0.03, 0.06), 20, {
		Text = upgrade.DisplayName,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	label(card, "Level", UDim2.fromScale(0.34, 0.18), UDim2.fromScale(0.63, 0.08), 15, {
		TextColor3 = ACCENT,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	label(card, "Description", UDim2.fromScale(0.94, 0.2), UDim2.fromScale(0.03, 0.29), 14, {
		Text = upgrade.Description,
		Font = Enum.Font.Gotham,
		TextColor3 = COLORS.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	})
	-- Puntos de nivel
	local pips = frame(card, "Pips", UDim2.fromScale(0.36, 0.08), UDim2.fromScale(0.03, 0.53))
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0.03, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = pips
	local maxLevel = #upgrade.Costs
	for n = 1, maxLevel do
		local pip = frame(pips, tostring(n), UDim2.fromScale((1 - 0.03 * (maxLevel - 1)) / 5, 1), UDim2.fromScale(0, 0), COLORS.Row)
		pip.LayoutOrder = n
		corner(pip, 0.5)
	end
	label(card, "Effect", UDim2.fromScale(0.55, 0.14), UDim2.fromScale(0.42, 0.5), 14, {
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.Good,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local b = button(card, "Buy", UDim2.fromScale(0.94, 0.26), UDim2.fromScale(0.03, 0.69), COLORS.Off, 18)
	b.Activated:Connect(function()
		task.spawn(onBuy, upgradeId)
	end)
	cards[upgradeId] = card
end

local function build(gui: ScreenGui)
	local close, plus
	window, diamondsLabel, close, plus = NativeUI.window(gui, "MEJORAS", ACCENT)
	close.Activated:Connect(function()
		PermanentPanel.Close()
	end)
	plus.Activated:Connect(function()
		LobbyPanels.open("Shop")
	end)

	local body = frame(window, "Body", UDim2.fromScale(1, 0.89), UDim2.fromScale(0, 0.11))

	-- Barra de arriba: puntos de mejora y reinicio
	local top = frame(body, "Top", UDim2.fromScale(1, 0.11), UDim2.fromScale(0, 0), COLORS.Panel)
	corner(top, 0.2)
	pointsLabel = label(top, "Points", UDim2.fromScale(0.5, 0.7), UDim2.fromScale(0.02, 0.15), 20, {
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	resetButton = button(top, "Reset", UDim2.fromScale(0.44, 0.76), UDim2.fromScale(0.55, 0.12), COLORS.Off, 17)
	resetButton.Activated:Connect(function()
		if spentTotal() <= 0 then
			setStatus("Aún no has comprado mejoras.")
			return
		end
		Remotes.event("RequestBuyProduct"):FireServer("PermanentReset")
	end)

	label(body, "Section", UDim2.fromScale(0.55, 0.05), UDim2.fromScale(0, 0.13), 15, {
		Text = "Valen en todas tus partidas  ·  toca dos veces para comprar",
		TextColor3 = COLORS.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	statusLabel = label(body, "Status", UDim2.fromScale(0.44, 0.05), UDim2.fromScale(0.56, 0.13), 15, {
		TextColor3 = COLORS.Dim,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	-- Tarjetas en dos columnas
	local grid = frame(body, "Grid", UDim2.fromScale(1, 0.8), UDim2.fromScale(0, 0.2))
	local gridLayout = Instance.new("UIGridLayout")
	local rows = math.ceil(#Config.PermanentUpgradeOrder / 2)
	gridLayout.CellPadding = UDim2.fromScale(0.015, 0.02)
	gridLayout.CellSize = UDim2.fromScale(0.4925, (1 - 0.02 * (rows - 1)) / rows)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	for i, upgradeId in Config.PermanentUpgradeOrder do
		buildCard(grid, upgradeId, i)
	end

	-- Precio real del reinicio (sale del producto de Roblox)
	task.spawn(function()
		if Config.DevProducts.PermanentReset == 0 then
			return
		end
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(Config.DevProducts.PermanentReset, Enum.InfoType.Product)
		end)
		if ok and info and type(info.PriceInRobux) == "number" then
			resetPrice = "R$ " .. info.PriceInRobux
			refresh()
		end
	end)
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function PermanentPanel.Open()
	if not window then
		return
	end
	confirmId = nil
	setStatus("")
	refresh()
	window.Visible = true
end

function PermanentPanel.Close()
	if window then
		window.Visible = false
	end
end

function PermanentPanel.IsOpen(): boolean
	return window ~= nil and window.Visible
end

function PermanentPanel.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PermanentPanel"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 7
	gui.Parent = player:WaitForChild("PlayerGui")
	build(gui)

	player.AttributeChanged:Connect(function(name: string)
		if window.Visible and (name == "Diamonds" or name == "UpgradePoints" or string.sub(name, 1, 5) == "Perm_") then
			refresh()
		end
	end)
end

return PermanentPanel
