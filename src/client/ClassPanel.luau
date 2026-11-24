-- ClassPanel (solo en el lobby): panel "CLASES Y RULETA" del puesto CLASES.
--
--   Arriba     slots: toca uno para equiparlo; los bloqueados se compran con Robux.
--   Izquierda  las clases con su rareza y su probabilidad (siempre visibles).
--   Centro     la ruleta: GIRAR (diamantes), "Girar hasta: <clase>" (giros
--              automaticos hasta que salga la clase elegida) y el tiro
--              afortunado (Robux, garantiza Epica o Legendaria; con sus %).
--   Derecha    detalle de la clase seleccionada y sus bonificaciones.
--
-- La clase que sale REEMPLAZA a la del slot equipado (si es Epica o Legendaria
-- se pide confirmar). El servidor (ClassService) valida y sortea; aqui solo se
-- anima el resultado. Tamanos en Scale con limites: se ve igual en todo dispositivo.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local ClassPanel = {}

local player = Players.LocalPlayer
local DIAMOND = "💎"

local COLORS = {
	Window = Color3.fromRGB(16, 17, 28),
	Panel = Color3.fromRGB(28, 30, 46),
	Row = Color3.fromRGB(34, 36, 54),
	RowSelected = Color3.fromRGB(58, 60, 92),
	Text = Color3.fromRGB(255, 255, 255),
	Dim = Color3.fromRGB(170, 174, 200),
	Good = Color3.fromRGB(110, 230, 140),
	Bad = Color3.fromRGB(255, 120, 120),
	Spin = Color3.fromRGB(60, 170, 90),
	Off = Color3.fromRGB(70, 72, 90),
	Auto = Color3.fromRGB(60, 110, 190),
	Lucky = Color3.fromRGB(230, 170, 30),
	Gold = Color3.fromRGB(255, 205, 80),
	Diamond = Color3.fromRGB(120, 220, 255),
}

----------------------------------------------------------------------
-- Datos
----------------------------------------------------------------------

local function oddsMap(lucky: boolean): { [string]: number }
	local map = {}
	for _, entry in Config.getRouletteOdds(lucky) do
		map[entry.Class] = entry.Percent
	end
	return map
end
local NORMAL_ODDS = oddsMap(false)
local LUCKY_ODDS = oddsMap(true)

-- string.upper no convierte las letras con tilde (COMúN): se hace a mano.
local ACCENTS = { ["á"] = "Á", ["é"] = "É", ["í"] = "Í", ["ó"] = "Ó", ["ú"] = "Ú", ["ñ"] = "Ñ" }
local function upper(s: string): string
	local out = string.upper(s)
	for lower, up in ACCENTS do
		out = string.gsub(out, lower, up)
	end
	return out
end

local function formatPercent(p: number): string
	local s = string.format("%.1f", p)
	s = string.gsub(s, "%.0$", "")
	return s .. "%"
end

local function classDef(className: string?)
	return Config.Classes[className or ""] or Config.Classes[Config.DefaultClass]
end

local function rarityOf(className: string?)
	return Config.Rarities[classDef(className).Rarity]
end

local MODIFIER_NAMES = {
	{ "Health", "vida" },
	{ "Stamina", "estamina" },
	{ "WalkSpeed", "velocidad al caminar" },
	{ "Battery", "batería de linterna" },
}

local function pct(x: number): number
	return math.floor(x * 100 + 0.5)
end

local PERK_TEXT = {
	RepairSpeed = function(v)
		return string.format("Repara %d%% más rápido", pct(v - 1))
	end,
	FlashCostMultiplier = function(v)
		return string.format("Destello: %d%% menos batería", pct(1 - v))
	end,
	FlashCooldownMultiplier = function(v)
		return string.format("Destello: %d%% menos de espera", pct(1 - v))
	end,
	Shove = function()
		return "[Q] Porrazo: empuja y aturde a los enemigos"
	end,
	PayBonus = function(v)
		return string.format("+%d%% de pago por noche", pct(v))
	end,
	NightVision = function()
		return "Ve en la oscuridad sin linterna"
	end,
	FreeRevive = function()
		return "Revive GRATIS a sus compañeros"
	end,
	ReviveSpeed = function(v)
		return string.format("Revive %gx más rápido", v)
	end,
	SeeGhostsThroughWalls = function()
		return "Ve a los fantasmas a través de las paredes"
	end,
	DetectionDelay = function(v)
		return string.format("Los enemigos tardan %gx en detectarte", v)
	end,
}

local function bonusesOf(className: string): { string }
	local def = classDef(className)
	local list = {}
	for _, pair in MODIFIER_NAMES do
		local mult = def.Modifiers[pair[1]]
		if mult and mult ~= 1 then
			local p = pct(mult - 1)
			table.insert(list, string.format("%s%d%% de %s", if p > 0 then "+" else "", p, pair[2]))
		end
	end
	local perkNames = {}
	for name in def.Perks do
		table.insert(perkNames, name)
	end
	table.sort(perkNames)
	for _, name in perkNames do
		local fn = PERK_TEXT[name]
		if fn then
			table.insert(list, fn(def.Perks[name]))
		end
	end
	if #list == 0 then
		table.insert(list, "Sin bonificaciones: equilibrado")
	end
	return list
end

local function equippedClass(): string
	local c = player:GetAttribute("EquippedClass")
	return if type(c) == "string" and Config.Classes[c] then c else Config.DefaultClass
end

local function isRestricted(): boolean
	return player:GetAttribute("PaidRandomRestricted") ~= false
end

-- Diamantes que se pueden gastar en la ruleta (en paises restringidos, solo los ganados)
local function spendableDiamonds(): number
	local total = player:GetAttribute("Diamonds") or 0
	if isRestricted() then
		return math.max(0, total - (player:GetAttribute("PaidDiamonds") or 0))
	end
	return total
end

----------------------------------------------------------------------
-- Piezas de interfaz
----------------------------------------------------------------------

local function corner(parent: Instance, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, transparency: number, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Transparency = transparency
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function label(parent: Instance, name: string, size: UDim2, position: UDim2, maxSize: number, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = COLORS.Text
	l.TextScaled = true
	l.Text = ""
	for k, v in props or {} do
		(l :: any)[k] = v
	end
	l.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = 8
	limit.Parent = l
	return l
end

local function button(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, maxSize: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = color
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBlack
	b.TextColor3 = COLORS.Text
	b.TextScaled = true
	b.Text = ""
	b.Parent = parent
	corner(b, 0.22)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = 8
	limit.Parent = b
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.16, 0)
	padding.PaddingBottom = UDim.new(0.16, 0)
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.Parent = b
	return b
end

local function frame(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color or COLORS.Panel
	f.BackgroundTransparency = if color then 0 else 1
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

----------------------------------------------------------------------
-- Estado
----------------------------------------------------------------------

local window: Frame
local diamondsLabel: TextLabel
local slotButtons: { TextButton } = {}
local rows: { [string]: TextButton } = {}
local reelCard: Frame
local reelStroke: UIStroke
local reelCaption: TextLabel
local reelName: TextLabel
local reelRarity: TextLabel
local spinButton: TextButton
local autoButton: TextButton
local luckyButton: TextButton
local luckyOdds: TextLabel
local statusLabel: TextLabel
local detail: { [string]: TextLabel } = {}

local selectedClass = Config.DefaultClass
local animating = false
local autoOn = false
local busy = false
local confirmUntil = 0
local luckyPriceText = "…"

local function setStatus(text: string, kind: string?)
	statusLabel.Text = text
	statusLabel.TextColor3 = if kind == "good" then COLORS.Good elseif kind == "bad" then COLORS.Bad else COLORS.Dim
end

local function showReel(className: string)
	local def = classDef(className)
	local rarity = rarityOf(className)
	reelName.Text = def.DisplayName
	reelName.TextColor3 = rarity.Color
	reelRarity.Text = upper(rarity.DisplayName)
	reelStroke.Color = rarity.Color
end

----------------------------------------------------------------------
-- Refrescos
----------------------------------------------------------------------

local function refreshSlots()
	local maxSlots = player:GetAttribute("MaxSlots") or 1
	local equipped = player:GetAttribute("EquippedSlot") or 1
	for i, b in slotButtons do
		local top = b:FindFirstChild("Top") :: TextLabel
		local bottom = b:FindFirstChild("Bottom") :: TextLabel
		local s = b:FindFirstChildOfClass("UIStroke") :: UIStroke
		if i <= maxSlots then
			local className = player:GetAttribute("Slot_" .. i)
			local def = classDef(if type(className) == "string" and className ~= "" then className else nil)
			top.Text = if i == equipped then string.format("SLOT %d · EQUIPADO", i) else string.format("SLOT %d", i)
			top.TextColor3 = if i == equipped then COLORS.Gold else COLORS.Dim
			bottom.Text = def.DisplayName
			bottom.TextColor3 = Config.Rarities[def.Rarity].Color
			s.Color = if i == equipped then COLORS.Gold else Color3.new(1, 1, 1)
			s.Transparency = if i == equipped then 0 else 0.8
			s.Thickness = if i == equipped then 2 else 1
		else
			top.Text = string.format("SLOT %d", i)
			top.TextColor3 = COLORS.Dim
			bottom.Text = "🔒 Comprar"
			bottom.TextColor3 = COLORS.Dim
			s.Color = Color3.new(1, 1, 1)
			s.Transparency = 0.85
			s.Thickness = 1
		end
	end
end

local function refreshList()
	for className, row in rows do
		row.BackgroundColor3 = if className == selectedClass then COLORS.RowSelected else COLORS.Row
		local s = row:FindFirstChildOfClass("UIStroke") :: UIStroke
		s.Transparency = if className == selectedClass then 0.2 else 1
	end
end

local function refreshDetail()
	local def = classDef(selectedClass)
	local rarity = rarityOf(selectedClass)
	detail.Name.Text = def.DisplayName
	detail.Name.TextColor3 = rarity.Color
	detail.Rarity.Text = upper(rarity.DisplayName)
	detail.Rarity.TextColor3 = rarity.Color
	local odds = "Probabilidad: " .. formatPercent(NORMAL_ODDS[selectedClass] or 0)
	if LUCKY_ODDS[selectedClass] then
		odds ..= "  ·  afortunado: " .. formatPercent(LUCKY_ODDS[selectedClass])
	end
	detail.Odds.Text = odds
	detail.Description.Text = def.Description
	detail.Bonuses.Text = "• " .. table.concat(bonusesOf(selectedClass), "\n• ")

	local owned = {}
	for i = 1, player:GetAttribute("MaxSlots") or 1 do
		if player:GetAttribute("Slot_" .. i) == selectedClass then
			table.insert(owned, tostring(i))
		end
	end
	detail.Owned.Text = if #owned > 0 then "La tienes en el slot " .. table.concat(owned, ", ") else "No la tienes en ningún slot"
end

local function refreshCenter()
	local equipped = equippedClass()
	local slot = player:GetAttribute("EquippedSlot") or 1
	if not animating then
		showReel(equipped)
	end
	reelCaption.Text = string.format("Slot %d equipado", slot)

	diamondsLabel.Text = string.format("%s %d", DIAMOND, player:GetAttribute("Diamonds") or 0)

	local canPay = spendableDiamonds() >= Config.Roulette.SpinCost
	if os.clock() < confirmUntil then
		spinButton.Text = string.format("¿Reemplazar a %s? Pulsa otra vez", classDef(equipped).DisplayName)
		spinButton.BackgroundColor3 = COLORS.Bad
	else
		spinButton.Text = string.format("GIRAR · %d %s", Config.Roulette.SpinCost, DIAMOND)
		spinButton.BackgroundColor3 = if canPay and not autoOn and not animating then COLORS.Spin else COLORS.Off
	end

	if autoOn then
		autoButton.Text = string.format("■ Detener  (buscando %s)", classDef(selectedClass).DisplayName)
		autoButton.BackgroundColor3 = COLORS.Bad
	else
		autoButton.Text = string.format("🔁 Girar hasta: %s", classDef(selectedClass).DisplayName)
		autoButton.BackgroundColor3 = if canPay and not animating then COLORS.Auto else COLORS.Off
	end

	-- Tiro afortunado: no se ofrece donde los objetos aleatorios pagados estan restringidos
	local showLucky = not isRestricted()
	luckyButton.Visible = showLucky
	luckyOdds.Visible = showLucky
	luckyButton.Text = "🍀 TIRO AFORTUNADO · " .. luckyPriceText
end

local function refreshAll()
	if not window then
		return
	end
	refreshSlots()
	refreshList()
	refreshDetail()
	refreshCenter()
end

----------------------------------------------------------------------
-- Ruleta
----------------------------------------------------------------------

-- Anima el carrete hasta `className`. fast = giros automaticos.
local function animateTo(className: string, fast: boolean)
	animating = true
	refreshCenter()
	local steps = if fast then 10 else 20
	local delay = if fast then 0.025 else 0.04
	local growth = if fast then 1.08 else 1.1
	for i = 1, steps do
		local shown = if i == steps then className else Config.ClassOrder[math.random(1, #Config.ClassOrder)]
		showReel(shown)
		task.wait(delay)
		delay *= growth
	end
	showReel(className)
	reelStroke.Thickness = 6
	TweenService:Create(reelStroke, TweenInfo.new(0.6), { Thickness = 2 }):Play()
	animating = false
	refreshAll()
end

-- Un giro con diamantes. Devuelve (ok, clase).
local function spinOnce(fast: boolean): (boolean, string?)
	local ok, message, className = Remotes.func("RequestSpin"):InvokeServer()
	if not ok or type(className) ~= "string" then
		setStatus(message or "No se pudo girar.", "bad")
		return false, nil
	end
	animateTo(className, fast)
	setStatus(message, "good")
	return true, className
end

local function onSpinPressed()
	if busy or animating or autoOn then
		return
	end
	if spendableDiamonds() < Config.Roulette.SpinCost then
		setStatus(
			if isRestricted() and (player:GetAttribute("Diamonds") or 0) >= Config.Roulette.SpinCost
				then "En tu país solo puedes girar con diamantes ganados jugando."
				else "No tienes diamantes suficientes.",
			"bad"
		)
		return
	end
	-- Proteger las clases Epicas y Legendarias: confirmar antes de reemplazarlas
	local equipped = equippedClass()
	if rarityOf(equipped).Order >= 3 and os.clock() > confirmUntil then
		confirmUntil = os.clock() + 3
		refreshCenter()
		task.delay(3.05, refreshCenter)
		return
	end
	confirmUntil = 0
	busy = true
	setStatus("Girando...")
	spinOnce(false)
	busy = false
end

local function onAutoPressed()
	if autoOn then
		autoOn = false
		refreshCenter()
		return
	end
	if busy or animating then
		return
	end
	local target = selectedClass
	if equippedClass() == target then
		setStatus("Ya tienes " .. classDef(target).DisplayName .. " en el slot equipado.", "info")
		return
	end
	if spendableDiamonds() < Config.Roulette.SpinCost then
		setStatus("No tienes diamantes suficientes.", "bad")
		return
	end
	autoOn = true
	busy = true
	refreshCenter()
	local spins = 0
	while autoOn and window.Visible do
		if spendableDiamonds() < Config.Roulette.SpinCost then
			setStatus(string.format("Sin diamantes tras %d giros. No salió %s.", spins, classDef(target).DisplayName), "bad")
			break
		end
		local ok, className = spinOnce(true)
		if not ok then
			break
		end
		spins += 1
		if className == target then
			setStatus(string.format("¡Conseguiste %s en %d giros!", classDef(target).DisplayName, spins), "good")
			break
		end
		task.wait(0.45) -- el servidor limita los giros seguidos
	end
	autoOn = false
	busy = false
	refreshAll()
end

----------------------------------------------------------------------
-- Construccion
----------------------------------------------------------------------

local function build(gui: ScreenGui)
	window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromScale(0.96, 0.92)
	window.BackgroundColor3 = COLORS.Window
	window.BackgroundTransparency = 0.05
	window.Visible = false
	window.Active = true
	window.Parent = gui
	corner(window, 0.03)
	stroke(window, Color3.fromRGB(170, 80, 255), 0.3, 2)
	local limits = Instance.new("UISizeConstraint")
	limits.MaxSize = Vector2.new(980, 600)
	limits.Parent = window
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.025, 0)
	padding.PaddingBottom = UDim.new(0.025, 0)
	padding.PaddingLeft = UDim.new(0.018, 0)
	padding.PaddingRight = UDim.new(0.018, 0)
	padding.Parent = window

	-- Cabecera
	local header = frame(window, "Header", UDim2.fromScale(1, 0.09), UDim2.fromScale(0, 0))
	label(header, "Title", UDim2.fromScale(0.5, 1), UDim2.fromScale(0, 0), 30, {
		Text = "CLASES Y RULETA",
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	diamondsLabel = label(header, "Diamonds", UDim2.fromScale(0.3, 0.8), UDim2.fromScale(0.58, 0.1), 26, {
		TextColor3 = COLORS.Diamond,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local close = button(header, "Close", UDim2.fromScale(0.07, 1), UDim2.fromScale(1, 0), COLORS.Off, 26)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Text = "X"
	local closeAspect = Instance.new("UIAspectRatioConstraint")
	closeAspect.AspectRatio = 1
	closeAspect.Parent = close
	close.Activated:Connect(function()
		ClassPanel.Close()
	end)

	-- Slots
	local slotsBar = frame(window, "Slots", UDim2.fromScale(1, 0.12), UDim2.fromScale(0, 0.105))
	local slotsList = Instance.new("UIListLayout")
	slotsList.FillDirection = Enum.FillDirection.Horizontal
	slotsList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	slotsList.Padding = UDim.new(0.012, 0)
	slotsList.SortOrder = Enum.SortOrder.LayoutOrder
	slotsList.Parent = slotsBar
	for i = 1, Config.Roulette.MaxSlots do
		local b = Instance.new("TextButton")
		b.Name = "Slot" .. i
		b.LayoutOrder = i
		b.Text = ""
		b.AutoButtonColor = true
		b.Size = UDim2.fromScale((1 - 0.012 * (Config.Roulette.MaxSlots - 1)) / Config.Roulette.MaxSlots, 1)
		b.BackgroundColor3 = COLORS.Panel
		b.Parent = slotsBar
		corner(b, 0.18)
		stroke(b, Color3.new(1, 1, 1), 0.8, 1)
		label(b, "Top", UDim2.fromScale(0.9, 0.36), UDim2.fromScale(0.05, 0.1), 14, { TextColor3 = COLORS.Dim })
		label(b, "Bottom", UDim2.fromScale(0.9, 0.42), UDim2.fromScale(0.05, 0.48), 20)
		b.Activated:Connect(function()
			if busy or animating or autoOn then
				return
			end
			if i > (player:GetAttribute("MaxSlots") or 1) then
				Remotes.event("RequestBuyProduct"):FireServer("ClassSlot")
				return
			end
			if i == player:GetAttribute("EquippedSlot") then
				return
			end
			busy = true
			local ok, message = Remotes.func("RequestEquipSlot"):InvokeServer(i)
			busy = false
			setStatus(message or "", if ok then "good" else "bad")
		end)
		slotButtons[i] = b
	end

	local body = frame(window, "Body", UDim2.fromScale(1, 0.755), UDim2.fromScale(0, 0.245))

	-- Izquierda: clases y probabilidades
	local left = frame(body, "Classes", UDim2.fromScale(0.31, 1), UDim2.fromScale(0, 0))
	label(left, "Title", UDim2.fromScale(1, 0.06), UDim2.fromScale(0, 0), 16, {
		Text = "PROBABILIDADES",
		TextColor3 = COLORS.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local list = frame(left, "List", UDim2.fromScale(1, 0.93), UDim2.fromScale(0, 0.07))
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0.006, 0)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list
	local count = #Config.ClassOrder
	for i, className in Config.ClassOrder do
		local def = classDef(className)
		local rarity = rarityOf(className)
		local row = Instance.new("TextButton")
		row.Name = className
		row.LayoutOrder = i
		row.Text = ""
		row.AutoButtonColor = true
		row.Size = UDim2.fromScale(1, (1 - 0.006 * (count - 1)) / count)
		row.BackgroundColor3 = COLORS.Row
		row.Parent = list
		corner(row, 0.2)
		stroke(row, rarity.Color, 1, 1.5)
		label(row, "Name", UDim2.fromScale(0.62, 0.56), UDim2.fromScale(0.04, 0.06), 18, {
			Text = def.DisplayName,
			TextColor3 = rarity.Color,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		label(row, "Rarity", UDim2.fromScale(0.62, 0.36), UDim2.fromScale(0.04, 0.6), 12, {
			Text = upper(rarity.DisplayName),
			TextColor3 = COLORS.Dim,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local badge = label(row, "Percent", UDim2.fromScale(0.28, 0.7), UDim2.fromScale(0.97, 0.5), 16, {
			Text = formatPercent(NORMAL_ODDS[className] or 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 0.25,
			BackgroundColor3 = rarity.Color:Lerp(Color3.new(0, 0, 0), 0.45),
		})
		corner(badge, 0.3)
		row.Activated:Connect(function()
			if autoOn then
				return -- no cambiar el objetivo a mitad de los giros automaticos
			end
			selectedClass = className
			refreshAll()
		end)
		rows[className] = row
	end

	-- Centro: ruleta
	local center = frame(body, "Roulette", UDim2.fromScale(0.36, 1), UDim2.fromScale(0.32, 0))
	reelCard = frame(center, "Reel", UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0), COLORS.Panel)
	corner(reelCard, 0.08)
	reelStroke = stroke(reelCard, Color3.new(1, 1, 1), 0, 2)
	reelCaption = label(reelCard, "Caption", UDim2.fromScale(0.9, 0.16), UDim2.fromScale(0.05, 0.07), 15, { TextColor3 = COLORS.Dim })
	reelName = label(reelCard, "ClassName", UDim2.fromScale(0.9, 0.38), UDim2.fromScale(0.05, 0.27), 44, { Font = Enum.Font.GothamBlack })
	reelRarity = label(reelCard, "Rarity", UDim2.fromScale(0.9, 0.17), UDim2.fromScale(0.05, 0.69), 18)

	spinButton = button(center, "Spin", UDim2.fromScale(1, 0.13), UDim2.fromScale(0, 0.43), COLORS.Spin, 26)
	spinButton.Activated:Connect(function()
		task.spawn(onSpinPressed)
	end)
	autoButton = button(center, "Auto", UDim2.fromScale(1, 0.1), UDim2.fromScale(0, 0.58), COLORS.Auto, 18)
	autoButton.Activated:Connect(function()
		task.spawn(onAutoPressed)
	end)
	luckyButton = button(center, "Lucky", UDim2.fromScale(1, 0.11), UDim2.fromScale(0, 0.71), COLORS.Lucky, 20)
	luckyButton.Activated:Connect(function()
		if busy or animating or autoOn then
			return
		end
		Remotes.event("RequestBuyProduct"):FireServer("LuckySpin")
	end)
	local luckyParts = {}
	for _, entry in Config.getRouletteOdds(true) do
		table.insert(luckyParts, classDef(entry.Class).DisplayName .. " " .. formatPercent(entry.Percent))
	end
	luckyOdds = label(center, "LuckyOdds", UDim2.fromScale(1, 0.075), UDim2.fromScale(0, 0.83), 13, {
		Text = "Solo Épica o Legendaria: " .. table.concat(luckyParts, " · "),
		TextColor3 = COLORS.Dim,
		TextWrapped = true,
	})
	statusLabel = label(center, "Status", UDim2.fromScale(1, 0.085), UDim2.fromScale(0, 0.915), 15, {
		TextColor3 = COLORS.Dim,
		TextWrapped = true,
	})

	-- Derecha: detalle
	local right = frame(body, "Detail", UDim2.fromScale(0.3, 1), UDim2.fromScale(0.7, 0), COLORS.Panel)
	right.BackgroundTransparency = 0
	corner(right, 0.05)
	local rightPadding = Instance.new("UIPadding")
	rightPadding.PaddingTop = UDim.new(0.04, 0)
	rightPadding.PaddingBottom = UDim.new(0.04, 0)
	rightPadding.PaddingLeft = UDim.new(0.06, 0)
	rightPadding.PaddingRight = UDim.new(0.06, 0)
	rightPadding.Parent = right
	detail.Name = label(right, "Name", UDim2.fromScale(1, 0.12), UDim2.fromScale(0, 0), 32, { Font = Enum.Font.GothamBlack })
	detail.Rarity = label(right, "Rarity", UDim2.fromScale(1, 0.07), UDim2.fromScale(0, 0.12), 18)
	detail.Odds = label(right, "Odds", UDim2.fromScale(1, 0.06), UDim2.fromScale(0, 0.2), 14, { TextColor3 = COLORS.Dim })
	detail.Description = label(right, "Description", UDim2.fromScale(1, 0.2), UDim2.fromScale(0, 0.29), 17, {
		Font = Enum.Font.Gotham,
		TextWrapped = true,
	})
	label(right, "BonusTitle", UDim2.fromScale(1, 0.06), UDim2.fromScale(0, 0.52), 16, {
		Text = "BONIFICACIONES",
		TextColor3 = COLORS.Gold,
	})
	detail.Bonuses = label(right, "Bonuses", UDim2.fromScale(1, 0.26), UDim2.fromScale(0, 0.6), 16, {
		TextColor3 = COLORS.Good,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	detail.Owned = label(right, "Owned", UDim2.fromScale(1, 0.07), UDim2.fromScale(0, 0.91), 13, { TextColor3 = COLORS.Dim })
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function ClassPanel.Open()
	if not window then
		return
	end
	selectedClass = if autoOn then selectedClass else equippedClass()
	setStatus("La clase que sale reemplaza a la del slot equipado.")
	window.Visible = true
	refreshAll()
end

function ClassPanel.Close()
	if window then
		window.Visible = false
		autoOn = false -- los giros automaticos se detienen al cerrar
	end
end

function ClassPanel.IsOpen(): boolean
	return window ~= nil and window.Visible
end

function ClassPanel.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ClassPanel"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")
	build(gui)

	for _, attr in { "Diamonds", "PaidDiamonds", "MaxSlots", "EquippedSlot", "EquippedClass", "PaidRandomRestricted" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			if window.Visible and not animating then
				refreshAll()
			end
		end)
	end
	for i = 1, Config.Roulette.MaxSlots do
		player:GetAttributeChangedSignal("Slot_" .. i):Connect(function()
			if window.Visible and not animating then
				refreshAll()
			end
		end)
	end

	-- Tiro afortunado comprado: se abre el panel y se anima el resultado
	Remotes.event("SpinResult").OnClientEvent:Connect(function(className: string, message: string)
		ClassPanel.Open()
		task.spawn(function()
			while animating do
				task.wait(0.1)
			end
			busy = true
			animateTo(className, false)
			setStatus(message, "good")
			busy = false
		end)
	end)

	-- Precio real del tiro afortunado
	task.spawn(function()
		local id = Config.DevProducts.LuckySpin
		if id == 0 then
			luckyPriceText = "Sin configurar"
		else
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)
			end)
			luckyPriceText = if ok and info and info.PriceInRobux then "R$ " .. info.PriceInRobux else "R$ ?"
		end
		if window.Visible then
			refreshCenter()
		end
	end)
end

return ClassPanel
