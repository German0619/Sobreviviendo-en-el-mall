-- AchievementsPanel (solo en el lobby): panel LOGROS (boton del trofeo).
--
--   Arriba   bono diario VIP: los VIP reclaman Config.VIP.DailyDiamonds al dia;
--            los demas ven que incluye el VIP y un boton para comprarlo.
--   Lista    los logros (Config.AchievementOrder) con su progreso. Los
--            desbloqueados se reclaman aqui y dan diamantes. Orden: primero los
--            que se pueden reclamar, luego los que faltan (por avance), al final
--            los ya reclamados.
--
-- Estado en atributos del Player (DataService): Ach_<id>, AchProg_<id>,
-- VipDailyDay y Pass_VIP. El servidor (AchievementService) valida todo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local NativeUI = require(script.Parent.NativeUI)
local LobbyPanels = require(script.Parent.LobbyPanels)

local COLORS = NativeUI.COLORS
local label, button, frame, corner, stroke = NativeUI.label, NativeUI.button, NativeUI.frame, NativeUI.corner, NativeUI.stroke

local AchievementsPanel = {}

local player = Players.LocalPlayer
local DIAMOND = "💎"
local GOLD = Color3.fromRGB(255, 200, 60)

local window: Frame
local diamondsLabel: TextLabel
local vipTitle: TextLabel
local vipText: TextLabel
local vipButton: TextButton
local statusLabel: TextLabel
local cards: { [string]: Frame } = {}
local busy = false

----------------------------------------------------------------------
-- Estado
----------------------------------------------------------------------

local function today(): number
	return math.floor(Workspace:GetServerTimeNow() / 86400)
end

local function isVip(): boolean
	return player:GetAttribute("Pass_VIP") == true
end

local function vipDailyReady(): boolean
	return isVip() and (player:GetAttribute("VipDailyDay") or 0) < today()
end

local function stateOf(id: string): string
	local s = player:GetAttribute("Ach_" .. id)
	return if type(s) == "string" then s else "locked"
end

-- Hay algo que reclamar (logro o bono VIP): lo usa el "!" del boton LOGROS.
function AchievementsPanel.HasClaimable(): boolean
	if vipDailyReady() then
		return true
	end
	for _, id in Config.AchievementOrder do
		if stateOf(id) == "claimable" then
			return true
		end
	end
	return false
end

local function formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

local RARITY_BY_ORDER = {}
for _, rarity in Config.Rarities do
	RARITY_BY_ORDER[rarity.Order] = rarity
end

local function progressText(achievement, value: number): string
	if achievement.Stat == "BestRarity" then
		local best = RARITY_BY_ORDER[value]
		return "Tu mejor: " .. (if best then best.DisplayName else "—")
	end
	return formatNumber(math.min(value, achievement.Goal)) .. " / " .. formatNumber(achievement.Goal)
end

local function setStatus(text: string, good: boolean?)
	statusLabel.Text = text
	statusLabel.TextColor3 = if good == true then COLORS.Good elseif good == false then COLORS.Bad else COLORS.Dim
end

----------------------------------------------------------------------
-- Refresco
----------------------------------------------------------------------

local function refreshVip()
	if isVip() then
		vipTitle.Text = "👑 BONO DIARIO VIP"
		if vipDailyReady() then
			vipText.Text = string.format("Tus %d %s de hoy te esperan.", Config.VIP.DailyDiamonds, DIAMOND)
			vipButton.Text = string.format("Reclamar %d %s", Config.VIP.DailyDiamonds, DIAMOND)
			vipButton.BackgroundColor3 = COLORS.Buy
		else
			local secondsLeft = (today() + 1) * 86400 - Workspace:GetServerTimeNow()
			local hours = math.floor(secondsLeft / 3600)
			local minutes = math.floor((secondsLeft % 3600) / 60)
			vipText.Text = "Ya reclamaste el bono de hoy."
			vipButton.Text = string.format("Vuelve en %dh %02dm", hours, minutes)
			vipButton.BackgroundColor3 = COLORS.Off
		end
	else
		vipTitle.Text = "👑 VIP"
		vipText.Text = string.format(
			"%d %s gratis cada día, ruleta %d%% más barata, [VIP] en el chat y nombre dorado.",
			Config.VIP.DailyDiamonds,
			DIAMOND,
			math.floor(Config.VIP.SpinDiscount * 100 + 0.5)
		)
		vipButton.Text = "Hazte VIP"
		vipButton.BackgroundColor3 = GOLD
	end
end

local function refreshCards()
	-- Orden: reclamables, luego pendientes por avance, luego reclamados
	local list = {}
	for i, id in Config.AchievementOrder do
		local achievement = Config.Achievements[id]
		local state = stateOf(id)
		local value = player:GetAttribute("AchProg_" .. id) or 0
		local ratio = math.clamp(value / achievement.Goal, 0, 1)
		local rank = if state == "claimable" then 0 elseif state == "locked" then 1 else 2
		table.insert(list, { Id = id, State = state, Value = value, Ratio = ratio, Rank = rank, Index = i })
	end
	table.sort(list, function(a, b)
		if a.Rank ~= b.Rank then
			return a.Rank < b.Rank
		end
		if a.Rank == 1 and a.Ratio ~= b.Ratio then
			return a.Ratio > b.Ratio
		end
		return a.Index < b.Index
	end)

	for order, entry in list do
		local card = cards[entry.Id]
		local achievement = Config.Achievements[entry.Id]
		card.LayoutOrder = order
		local fill = card:FindFirstChild("Bar") and card.Bar:FindFirstChild("Fill") :: Frame
		fill.Size = UDim2.fromScale(entry.Ratio, 1)
		fill.BackgroundColor3 = if entry.State == "locked" then Color3.fromRGB(90, 120, 200) else COLORS.Good
		local progress = card:FindFirstChild("Progress") :: TextLabel
		progress.Text = progressText(achievement, entry.Value)
		local b = card:FindFirstChild("Claim") :: TextButton
		local s = card:FindFirstChildOfClass("UIStroke") :: UIStroke
		if entry.State == "claimable" then
			b.Text = string.format("Reclamar %d %s", achievement.Diamonds, DIAMOND)
			b.BackgroundColor3 = COLORS.Buy
			s.Color = COLORS.Good
			s.Transparency = 0.1
			card.BackgroundColor3 = COLORS.RowSelected
		elseif entry.State == "claimed" then
			b.Text = "✓ Reclamado"
			b.BackgroundColor3 = COLORS.Off
			s.Transparency = 1
			card.BackgroundColor3 = COLORS.Row
		else
			b.Text = string.format("%d %s", achievement.Diamonds, DIAMOND)
			b.BackgroundColor3 = Color3.fromRGB(45, 48, 70)
			s.Transparency = 1
			card.BackgroundColor3 = COLORS.Panel
		end
	end
end

local function refresh()
	if not window then
		return
	end
	diamondsLabel.Text = string.format("%s %d", DIAMOND, player:GetAttribute("Diamonds") or 0)
	refreshVip()
	refreshCards()
end

----------------------------------------------------------------------
-- Construccion
----------------------------------------------------------------------

local function claim(id: string)
	if busy or stateOf(id) ~= "claimable" then
		return
	end
	busy = true
	local ok, message = Remotes.func("RequestClaimAchievement"):InvokeServer(id)
	busy = false
	setStatus(message or "", ok == true)
end

local function build(gui: ScreenGui)
	local close, plus
	window, diamondsLabel, close, plus = NativeUI.window(gui, "LOGROS", GOLD)
	close.Activated:Connect(function()
		AchievementsPanel.Close()
	end)
	plus.Activated:Connect(function()
		LobbyPanels.open("Shop")
	end)

	local body = frame(window, "Body", UDim2.fromScale(1, 0.89), UDim2.fromScale(0, 0.11))

	-- Bono diario VIP
	local vip = frame(body, "Vip", UDim2.fromScale(1, 0.17), UDim2.fromScale(0, 0), Color3.fromRGB(48, 38, 14))
	corner(vip, 0.15)
	stroke(vip, GOLD, 0.3, 1.5)
	vipTitle = label(vip, "Title", UDim2.fromScale(0.6, 0.42), UDim2.fromScale(0.02, 0.08), 22, {
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	vipText = label(vip, "Text", UDim2.fromScale(0.66, 0.38), UDim2.fromScale(0.02, 0.54), 15, {
		Font = Enum.Font.Gotham,
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	})
	vipButton = button(vip, "Claim", UDim2.fromScale(0.26, 0.64), UDim2.fromScale(0.72, 0.18), COLORS.Buy, 20)
	vipButton.Activated:Connect(function()
		if not isVip() then
			LobbyPanels.open("Shop")
			return
		end
		if busy or not vipDailyReady() then
			return
		end
		busy = true
		local ok, message = Remotes.func("RequestClaimVipDaily"):InvokeServer()
		busy = false
		setStatus(message or "", ok == true)
	end)

	statusLabel = label(body, "Status", UDim2.fromScale(0.5, 0.05), UDim2.fromScale(0.5, 0.19), 15, {
		TextColor3 = COLORS.Dim,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	label(body, "Section", UDim2.fromScale(0.5, 0.05), UDim2.fromScale(0, 0.19), 16, {
		Text = "LOGROS  ·  reclama sus diamantes",
		TextColor3 = COLORS.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	-- Lista en dos columnas
	local grid = frame(body, "Grid", UDim2.fromScale(1, 0.75), UDim2.fromScale(0, 0.25))
	local layout = Instance.new("UIGridLayout")
	local rows = math.ceil(#Config.AchievementOrder / 2)
	layout.CellPadding = UDim2.fromScale(0.015, 0.012)
	layout.CellSize = UDim2.fromScale(0.4925, (1 - 0.012 * (rows - 1)) / rows)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for i, id in Config.AchievementOrder do
		local achievement = Config.Achievements[id]
		local card = frame(grid, id, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), COLORS.Panel)
		card.LayoutOrder = i
		corner(card, 0.14)
		stroke(card, COLORS.Good, 1, 1.5)
		label(card, "Name", UDim2.fromScale(0.62, 0.4), UDim2.fromScale(0.03, 0.06), 18, {
			Text = achievement.DisplayName,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		label(card, "Description", UDim2.fromScale(0.62, 0.26), UDim2.fromScale(0.03, 0.46), 13, {
			Text = achievement.Description,
			Font = Enum.Font.Gotham,
			TextColor3 = COLORS.Dim,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local bar = frame(card, "Bar", UDim2.fromScale(0.4, 0.12), UDim2.fromScale(0.03, 0.78), Color3.fromRGB(20, 22, 34))
		corner(bar, 0.5)
		local fill = frame(bar, "Fill", UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), COLORS.Good)
		corner(fill, 0.5)
		label(card, "Progress", UDim2.fromScale(0.2, 0.2), UDim2.fromScale(0.45, 0.74), 12, {
			TextColor3 = COLORS.Dim,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local b = button(card, "Claim", UDim2.fromScale(0.31, 0.6), UDim2.fromScale(0.66, 0.2), COLORS.Off, 16)
		b.Activated:Connect(function()
			task.spawn(claim, id)
		end)
		cards[id] = card
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function AchievementsPanel.Open()
	if not window then
		return
	end
	setStatus("")
	refresh()
	window.Visible = true
end

function AchievementsPanel.Close()
	if window then
		window.Visible = false
	end
end

function AchievementsPanel.IsOpen(): boolean
	return window ~= nil and window.Visible
end

-- Se llama cuando cambia algo que afecta a los logros o al bono VIP.
AchievementsPanel.Changed = Instance.new("BindableEvent")

function AchievementsPanel.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "AchievementsPanel"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 7
	gui.Parent = player:WaitForChild("PlayerGui")
	build(gui)

	local function onChange()
		if window.Visible then
			refresh()
		end
		AchievementsPanel.Changed:Fire()
	end
	player.AttributeChanged:Connect(function(name: string)
		if name == "Diamonds" or name == "Pass_VIP" or name == "VipDailyDay" or string.sub(name, 1, 3) == "Ach" then
			onChange()
		end
	end)
	-- Cuenta atras del bono VIP y cambio de dia
	task.spawn(function()
		while gui.Parent do
			task.wait(30)
			onChange()
		end
	end)
end

return AchievementsPanel
