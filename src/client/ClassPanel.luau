-- ClassPanel (solo en el lobby): panel "CLASES Y RULETA" del puesto CLASES.
--
--   Arriba     slots: toca uno para equiparlo; los bloqueados se compran con Robux.
--   Izquierda  las clases con su rareza y su probabilidad (siempre visibles).
--   Centro     la RUEDA: un sector por clase (color de su rareza y su nombre), la
--              flecha arriba y GIRAR en el centro (diamantes). Gira varias vueltas
--              y frena con la clase que salio bajo la flecha (un clic por sector).
--              Tocar un sector (o una fila de la lista) lo selecciona.
--   Derecha    detalle de la clase seleccionada: su maestria (nivel y noches,
--              Config.ClassMastery) y sus bonificaciones con tu nivel de maestria;
--              debajo "Girar hasta: <clase>" (giros automaticos hasta que salga) y el
--              tiro afortunado (Robux, garantiza Epica o superior; con sus %).
--
-- La clase que sale REEMPLAZA a la del slot equipado (si es Epica o superior
-- se pide confirmar). El servidor (ClassService) valida y sortea; aqui solo se
-- anima el resultado. Tamanos en Scale con limites: se ve igual en todo dispositivo.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

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
	Rim = Color3.fromRGB(28, 44, 92),
	RimEdge = Color3.fromRGB(14, 22, 48),
	Bolt = Color3.fromRGB(150, 170, 210),
	Pointer = Color3.fromRGB(235, 45, 45),
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

-- 22.45% · 4.5% · 0.05% · 0.0001% (los muy bajos con 2 cifras significativas)
local function formatPercent(p: number): string
	local decimals = 2
	if p > 0 and p < 1 then
		decimals = math.max(2, -math.floor(math.log10(p)) + 1)
	end
	local s = string.format("%." .. decimals .. "f", p)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s .. "%"
end

local function classDef(className: string?)
	return Config.Classes[className or ""] or Config.Classes[Config.DefaultClass]
end

local function rarityOf(className: string?)
	return Config.Rarities[classDef(className).Rarity]
end

-- Textos cortos: con muchas bonificaciones (Conserje experimentado) van en dos columnas.
local MODIFIER_NAMES = {
	{ "Health", "vida" },
	{ "Stamina", "estamina" },
	{ "WalkSpeed", "velocidad" },
	{ "Battery", "batería" },
}

local function pct(x: number): number
	return math.floor(x * 100 + 0.5)
end

local PERK_TEXT = {
	RepairSpeed = function(v)
		return string.format("Repara +%d%% rápido", pct(v - 1))
	end,
	FlashCostMultiplier = function(v)
		return string.format("Destello -%d%% batería", pct(1 - v))
	end,
	FlashCooldownMultiplier = function(v)
		return string.format("Destello -%d%% espera", pct(1 - v))
	end,
	Shove = function()
		return "Porrazo que aturde"
	end,
	PayBonus = function(v)
		return string.format("+%d%% de pago", pct(v))
	end,
	NightVision = function()
		return "Ve en la oscuridad"
	end,
	FreeRevive = function()
		return "Revive GRATIS"
	end,
	ReviveSpeed = function(v)
		return string.format("Revive %gx más rápido", v)
	end,
	SeeGhostsThroughWalls = function()
		return "Ve fantasmas tras paredes"
	end,
	DetectionDelay = function(v)
		return string.format("Te detectan %gx más lento", v)
	end,
}

-- Noches con la clase y nivel de maestria (Config.ClassMastery)
local function masteryOf(className: string): (number, number, number?)
	local nights = player:GetAttribute("Mastery_" .. className)
	nights = if type(nights) == "number" then nights else 0
	local level, nextNights = Config.getMasteryLevel(nights)
	return nights, level, nextNights
end

-- Bonificaciones de la clase con TU nivel de maestria.
local function bonusesOf(className: string): { string }
	local _, level = masteryOf(className)
	local def = Config.getMasteredClass(className, level)
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

-- Lo que se MUESTRA en los slots y el carrete. El servidor cambia la clase del slot en
-- cuanto gira; aqui se sigue mostrando la anterior hasta que la ruleta se pare:
--   * spinPending: giro pedido, esperando respuesta;
--   * animating: la ruleta gira;
--   * SpinRevealAt (lo pone el servidor, tambien en el tiro afortunado con Robux): hasta
--     esa hora, salvo que este giro ya se haya revelado aqui (handledRevealAt).
local spinPending = false
local handledRevealAt: number? = nil
local shownSlots: { [number]: any } = {}
local shownEquipped: string? = nil

local function revealing(animatingNow: boolean): boolean
	if spinPending or animatingNow then
		return true
	end
	local revealAt = player:GetAttribute("SpinRevealAt")
	return type(revealAt) == "number" and revealAt ~= handledRevealAt and Workspace:GetServerTimeNow() < revealAt
end

-- Toma la foto de lo que se muestra (solo fuera de un giro).
local function snapshotSlots(animatingNow: boolean)
	if revealing(animatingNow) then
		return
	end
	for i = 1, Config.Roulette.MaxSlots do
		shownSlots[i] = player:GetAttribute("Slot_" .. i)
	end
	shownEquipped = equippedClass()
end

local function shownSlot(i: number): any
	return shownSlots[i]
end

local function shownEquippedClass(): string
	return shownEquipped or equippedClass()
end

local function isRestricted(): boolean
	return player:GetAttribute("PaidRandomRestricted") ~= false
end

-- Costo de un giro (VIP: con descuento, Config.VIP.SpinDiscount)
local function spinCost(): number
	return Config.getSpinCost(player:GetAttribute("Pass_VIP") == true)
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

local NativeUI = require(script.Parent.NativeUI)
local corner, stroke, label, button, frame = NativeUI.corner, NativeUI.stroke, NativeUI.label, NativeUI.button, NativeUI.frame

----------------------------------------------------------------------
-- Estado
----------------------------------------------------------------------

local window: Frame
local diamondsLabel: TextLabel
local slotButtons: { TextButton } = {}
local wheelDisk: Frame -- lo que gira (sectores, iconos, %)
local wheelPointer: TextLabel
local sectorNames: { [string]: TextLabel } = {} -- nombre de cada sector (dorado = seleccionado)
local rows: { [string]: TextButton } = {} -- lista de probabilidades (izquierda)
local spinCostLabel: TextLabel
local equippedLabel: TextLabel
local spinButton: TextButton
local autoButton: TextButton
local luckyButton: TextButton
local luckyOdds: TextLabel
local statusLabel: TextLabel
local detail: { [string]: TextLabel } = {}
local bonusGrid: Frame
local masteryFill: Frame

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

----------------------------------------------------------------------
-- Rueda: geometria
----------------------------------------------------------------------
-- Un sector por clase (Config.ClassOrder), todos iguales; el 1 arriba y en el sentido de
-- las agujas del reloj. La rueda (wheelDisk) gira: el sector de angulo a queda arriba
-- (bajo la flecha) cuando wheelDisk.Rotation = -a (mod 360).

local SECTORS = #Config.ClassOrder
local SECTOR_ANGLE = 360 / SECTORS
local SECTOR_INDEX: { [string]: number } = {}
for i, className in Config.ClassOrder do
	SECTOR_INDEX[className] = i
end

local function sectorAngle(className: string): number
	return ((SECTOR_INDEX[className] or 1) - 1) * SECTOR_ANGLE
end

-- Pieza que gira con la rueda: un "radio" del diametro entero girado `angle` grados
-- (las GuiObject giran sobre su centro, que es el de la rueda). Lo que se pone dentro,
-- en la mitad de arriba, queda en ese angulo.
local function spoke(parent: Instance, name: string, angle: number, width: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(width, 1)
	f.BackgroundTransparency = 1
	f.Rotation = angle
	f.Parent = parent
	return f
end

-- Sector de la clase que hay bajo la flecha con la rueda girada `rotation` grados.
local function sectorUnderPointer(rotation: number): number
	local a = (-rotation) % 360
	return math.floor((a + SECTOR_ANGLE / 2) / SECTOR_ANGLE) % SECTORS + 1
end

local tickSound: Sound? = nil
local winSound: Sound? = nil

local function playTick()
	if tickSound then
		tickSound.TimePosition = 0
		tickSound:Play()
	end
	if wheelPointer then
		wheelPointer.Rotation = 14
		TweenService:Create(wheelPointer, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Rotation = 0 }):Play()
	end
end

local SELECTED_NAME = Color3.fromRGB(255, 215, 80)

-- Destello del sector que salio: su nombre parpadea en blanco y dorado
local function flashSector(className: string)
	local name = sectorNames[className]
	if not name then
		return
	end
	task.spawn(function()
		for i = 1, 6 do
			name.TextColor3 = if i % 2 == 1 then Color3.new(1, 1, 1) else SELECTED_NAME
			name.TextStrokeColor3 = if i % 2 == 1 then SELECTED_NAME else Color3.new(0, 0, 0)
			task.wait(0.15)
		end
		name.TextStrokeColor3 = Color3.new(0, 0, 0)
		name.TextColor3 = if className == selectedClass then SELECTED_NAME else Color3.new(1, 1, 1)
	end)
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
			local className = shownSlot(i) -- (la anterior hasta que la ruleta se pare)
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

-- Clase seleccionada: su fila de la lista resaltada y su nombre en la rueda en dorado
local function refreshList()
	for className, row in rows do
		row.BackgroundColor3 = if className == selectedClass then COLORS.RowSelected else COLORS.Row
		local s = row:FindFirstChildOfClass("UIStroke") :: UIStroke
		s.Transparency = if className == selectedClass then 0.2 else 1
	end
	for className, name in sectorNames do
		name.TextColor3 = if className == selectedClass then SELECTED_NAME else Color3.new(1, 1, 1)
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
	-- Maestria
	local nights, level, nextNights = masteryOf(selectedClass)
	local maxLevel = #Config.ClassMastery.Nights
	local previousNights = if level > 0 then Config.ClassMastery.Nights[level] else 0
	if nextNights then
		detail.Mastery.Text = string.format("MAESTRÍA %d/%d  ·  %d/%d noches", level, maxLevel, nights, nextNights)
		masteryFill.Size = UDim2.fromScale(math.clamp((nights - previousNights) / (nextNights - previousNights), 0, 1), 1)
	else
		detail.Mastery.Text = string.format("MAESTRÍA %d/%d  ·  ¡máxima!", level, maxLevel)
		masteryFill.Size = UDim2.fromScale(1, 1)
	end
	-- Bonificaciones: una columna (hasta 5) o dos columnas (mas de 5)
	for _, child in bonusGrid:GetChildren() do
		child:Destroy()
	end
	local bonuses = bonusesOf(selectedClass)
	local columns = if #bonuses > 5 then 2 else 1
	local rowsCount = math.ceil(#bonuses / columns)
	local cellHeight = 1 / math.max(rowsCount, 5)
	for i, text in bonuses do
		local col = (i - 1) % columns
		local row = math.floor((i - 1) / columns)
		label(bonusGrid, "Bonus" .. i, UDim2.fromScale(1 / columns - 0.02, cellHeight * 0.9), UDim2.fromScale(col / columns, row * cellHeight), 16, {
			Text = "• " .. text,
			TextColor3 = COLORS.Good,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end

	local owned = {}
	for i = 1, player:GetAttribute("MaxSlots") or 1 do
		if shownSlot(i) == selectedClass then
			table.insert(owned, tostring(i))
		end
	end
	detail.Owned.Text = if #owned > 0 then "La tienes en el slot " .. table.concat(owned, ", ") else "No la tienes en ningún slot"
end

local function refreshCenter()
	local equipped = shownEquippedClass() -- (la anterior hasta que la ruleta se pare)
	local slot = player:GetAttribute("EquippedSlot") or 1
	local equippedDef = classDef(equipped)
	equippedLabel.Text = string.format("Slot %d: %s", slot, equippedDef.DisplayName)
	equippedLabel.TextColor3 = rarityOf(equipped).Color

	diamondsLabel.Text = string.format("%s %d", DIAMOND, player:GetAttribute("Diamonds") or 0)

	-- Boton GIRAR del centro de la rueda (con su precio debajo)
	local canPay = spendableDiamonds() >= spinCost()
	if os.clock() < confirmUntil then
		spinButton.Text = "¿SEGURO?"
		spinButton.BackgroundColor3 = COLORS.Bad
		spinCostLabel.Text = "Pulsa otra vez"
		setStatus(string.format("La clase que salga reemplazará a %s. Pulsa GIRAR otra vez.", equippedDef.DisplayName), "bad")
	else
		spinButton.Text = "GIRAR"
		spinButton.BackgroundColor3 = if canPay and not autoOn and not animating then COLORS.Spin else COLORS.Off
		spinCostLabel.Text = string.format("%d %s%s", spinCost(), DIAMOND, if player:GetAttribute("Pass_VIP") == true then " VIP" else "")
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
	snapshotSlots(animating)
	refreshSlots()
	refreshList()
	refreshDetail()
	refreshCenter()
end

----------------------------------------------------------------------
-- Ruleta
----------------------------------------------------------------------

-- Gira la rueda hasta dejar `className` bajo la flecha. fast = giros automaticos.
local function animateTo(className: string, fast: boolean)
	animating = true
	spinPending = false
	refreshCenter()
	local start = wheelDisk.Rotation
	-- Varias vueltas y frena en el sector (no siempre en su centro: parece mas real)
	local jitter = (math.random() - 0.5) * SECTOR_ANGLE * 0.6
	local landing = (-sectorAngle(className) + jitter - start) % 360
	local turns = if fast then 2 else 5
	local goal = start + turns * 360 + landing
	local duration = if fast then 1.3 else 4.2
	local tween = TweenService:Create(wheelDisk, TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Rotation = goal,
	})
	-- Un clic cada vez que pasa un sector por la flecha
	local lastSector = sectorUnderPointer(start)
	local conn = RunService.RenderStepped:Connect(function()
		local current = sectorUnderPointer(wheelDisk.Rotation)
		if current ~= lastSector then
			lastSector = current
			playTick()
		end
	end)
	tween:Play()
	tween.Completed:Wait()
	conn:Disconnect()
	-- (que no crezca sin limite)
	wheelDisk.Rotation = goal % 360
	if winSound then
		winSound.PlaybackSpeed = 0.9 + rarityOf(className).Order * 0.1
		winSound:Play()
	end
	flashSector(className)
	if not autoOn then
		selectedClass = className -- se ve su detalle
	end
	animating = false
	-- Este giro ya se revelo: los slots muestran ya el resultado
	handledRevealAt = player:GetAttribute("SpinRevealAt")
	refreshAll()
end

-- Un giro con diamantes. Devuelve (ok, clase).
local function spinOnce(fast: boolean): (boolean, string?)
	-- Los slots no cambian hasta que la ruleta se pare (el servidor los cambia ya)
	spinPending = true
	local ok, message, className = Remotes.func("RequestSpin"):InvokeServer()
	if not ok or type(className) ~= "string" then
		spinPending = false
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
	if spendableDiamonds() < spinCost() then
		setStatus(
			if isRestricted() and (player:GetAttribute("Diamonds") or 0) >= spinCost()
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
	if spendableDiamonds() < spinCost() then
		setStatus("No tienes diamantes suficientes.", "bad")
		return
	end
	autoOn = true
	busy = true
	refreshCenter()
	local spins = 0
	while autoOn and window.Visible do
		if spendableDiamonds() < spinCost() then
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

	-- Izquierda: clases y probabilidades (tocar una la selecciona)
	local listColumn = frame(body, "Classes", UDim2.fromScale(0.25, 1), UDim2.fromScale(0, 0))
	label(listColumn, "Title", UDim2.fromScale(1, 0.06), UDim2.fromScale(0, 0), 16, {
		Text = "PROBABILIDADES",
		TextColor3 = COLORS.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local list = frame(listColumn, "List", UDim2.fromScale(1, 0.93), UDim2.fromScale(0, 0.07))
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
		local badge = label(row, "Percent", UDim2.fromScale(0.3, 0.7), UDim2.fromScale(0.97, 0.5), 16, {
			Text = formatPercent(NORMAL_ODDS[className] or 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 0.25,
			BackgroundColor3 = rarity.Color:Lerp(Color3.new(0, 0, 0), 0.45),
		})
		corner(badge, 0.3)
		row.Activated:Connect(function()
			if autoOn or animating then
				return -- no cambiar el objetivo a mitad de los giros automaticos
			end
			selectedClass = className
			refreshAll()
		end)
		rows[className] = row
	end

	-- Centro: la rueda (cuadrada, centrada en su columna)
	local left = frame(body, "WheelArea", UDim2.fromScale(0.36, 1), UDim2.fromScale(0.26, 0))
	local wheel = frame(left, "Wheel", UDim2.fromScale(1, 0.93), UDim2.fromScale(0.5, 0.475))
	wheel.AnchorPoint = Vector2.new(0.5, 0.5)
	local wheelAspect = Instance.new("UIAspectRatioConstraint")
	wheelAspect.AspectRatio = 1
	wheelAspect.Parent = wheel
	local wheelLimit = Instance.new("UISizeConstraint")
	wheelLimit.MaxSize = Vector2.new(440, 440)
	wheelLimit.Parent = wheel

	-- Aro metalico (no gira)
	local rim = frame(wheel, "Rim", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), COLORS.Rim)
	corner(rim, 0.5)
	stroke(rim, COLORS.RimEdge, 0, 4)

	-- Disco que gira: sectores de colores, divisores y nombres.
	-- Cada sector se rellena con barras finas por ANILLOS (cuanto mas al centro, mas
	-- estrechas): una barra rectangular del centro al borde invadia el sector vecino cerca
	-- del centro (colores mezclados). Cada anillo: { radio interior, radio exterior }.
	wheelDisk = frame(wheel, "Disk", UDim2.fromScale(0.88, 0.88), UDim2.fromScale(0.5, 0.5))
	wheelDisk.AnchorPoint = Vector2.new(0.5, 0.5)
	local RINGS = { { 0.12, 0.18 }, { 0.18, 0.26 }, { 0.26, 0.37 }, { 0.37, 0.5 } }
	local BARS = 8 -- por sector
	local barAngle = SECTOR_ANGLE / BARS
	local outerWidth = 2 * 0.5 * math.sin(math.rad(barAngle / 2)) * 1.08 -- (sin huecos)
	for i, className in Config.ClassOrder do
		local rarity = rarityOf(className)
		local center = (i - 1) * SECTOR_ANGLE
		local shade = if i % 2 == 0 then 0.42 else 0.25
		local color = rarity.Color:Lerp(Color3.new(0, 0, 0), shade)
		for k = 0, BARS - 1 do
			local s = spoke(wheelDisk, "Fill", center - SECTOR_ANGLE / 2 + (k + 0.5) * barAngle, outerWidth)
			for _, ring in RINGS do
				-- (ancho de la barra en este anillo, relativo al del anillo exterior)
				local width = ring[2] / 0.5
				local piece = frame(s, "Ring", UDim2.fromScale(width, ring[2] - ring[1]), UDim2.fromScale((1 - width) / 2, 0.5 - ring[2]), color)
				piece.ZIndex = 1
			end
		end
		-- Divisor (a la izquierda del sector)
		local d = spoke(wheelDisk, "Divider", center - SECTOR_ANGLE / 2, 0.008)
		local line = frame(d, "Line", UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0), Color3.fromRGB(235, 240, 255))
		line.BackgroundTransparency = 0.35
		line.ZIndex = 3
	end
	for i, className in Config.ClassOrder do
		local def = classDef(className)
		local content = spoke(wheelDisk, "Sector_" .. className, (i - 1) * SECTOR_ANGLE, 0.3)
		-- Nombre a lo largo del radio, del boton GIRAR al borde (radio 0.165 a 0.465 del
		-- disco; el "content" mide 0.3 de ancho y el disco entero de alto). El de la clase
		-- seleccionada, en dorado.
		local nameLabel = label(content, "Name", UDim2.fromScale(1, 0.075), UDim2.fromScale(0.5, 0.185), 20, {
			Text = def.DisplayName,
			Font = Enum.Font.GothamBlack,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.2,
			TextWrapped = true,
			ZIndex = 5,
		})
		nameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		nameLabel.Rotation = -90
		sectorNames[className] = nameLabel
		-- Tocar el sector lo selecciona
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromScale(0.9, 0.32)
		hit.Position = UDim2.fromScale(0.05, 0.03)
		hit.ZIndex = 6
		hit.Parent = content
		hit.Activated:Connect(function()
			if autoOn or animating then
				return -- no cambiar el objetivo a mitad de los giros automaticos
			end
			selectedClass = className
			refreshAll()
		end)
	end

	-- Remaches del aro (no giran), uno en cada divisor
	for i = 1, SECTORS do
		local s = spoke(wheel, "Bolt", (i - 0.5) * SECTOR_ANGLE, 0.04)
		local bolt = frame(s, "Bolt", UDim2.fromScale(1, 0.04), UDim2.fromScale(0, 0.012), COLORS.Bolt)
		corner(bolt, 0.5)
		bolt.ZIndex = 7
	end

	-- Boton GIRAR en el centro (dorado por fuera), con su precio debajo
	spinButton = button(wheel, "Spin", UDim2.fromScale(0.26, 0.26), UDim2.fromScale(0.5, 0.5), COLORS.Spin, 28)
	spinButton.AnchorPoint = Vector2.new(0.5, 0.5)
	spinButton.ZIndex = 8
	local spinCorner = spinButton:FindFirstChildOfClass("UICorner") :: UICorner
	spinCorner.CornerRadius = UDim.new(0.5, 0)
	stroke(spinButton, COLORS.Gold, 0, 5)
	local spinPadding = spinButton:FindFirstChildOfClass("UIPadding") :: UIPadding
	spinPadding.PaddingTop = UDim.new(0.3, 0)
	spinPadding.PaddingBottom = UDim.new(0.38, 0)
	spinButton.Activated:Connect(function()
		task.spawn(onSpinPressed)
	end)
	spinCostLabel = label(spinButton, "Cost", UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 1.1), 14, {
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 9,
	})

	-- Flecha arriba (no gira): se mueve un poco con cada clic
	wheelPointer = label(wheel, "Pointer", UDim2.fromScale(0.14, 0.12), UDim2.fromScale(0.5, -0.03), 60, {
		Text = "▼",
		Font = Enum.Font.GothamBlack,
		TextColor3 = COLORS.Pointer,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.fromRGB(60, 0, 0),
		ZIndex = 9,
	})
	wheelPointer.AnchorPoint = Vector2.new(0.5, 0)

	-- Clase equipada, debajo de la rueda
	equippedLabel = label(left, "Equipped", UDim2.fromScale(1, 0.06), UDim2.fromScale(0, 0.945), 16, {
		TextColor3 = COLORS.Dim,
	})

	-- Sonidos de la rueda (clic por sector y el del resultado)
	tickSound = Instance.new("Sound")
	tickSound.SoundId = "rbxasset://sounds/clickfast.wav"
	tickSound.Volume = 0.5
	tickSound.Parent = SoundService
	winSound = Instance.new("Sound")
	winSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	winSound.Volume = 0.7
	winSound.Parent = SoundService

	-- Derecha: detalle arriba y, debajo, giros automaticos, tiro afortunado y estado
	local column = frame(body, "Side", UDim2.fromScale(0.36, 1), UDim2.fromScale(0.64, 0))
	local center = frame(column, "Buttons", UDim2.fromScale(1, 0.33), UDim2.fromScale(0, 0.67))
	autoButton = button(center, "Auto", UDim2.fromScale(1, 0.27), UDim2.fromScale(0, 0.02), COLORS.Auto, 18)
	autoButton.Activated:Connect(function()
		task.spawn(onAutoPressed)
	end)
	luckyButton = button(center, "Lucky", UDim2.fromScale(1, 0.27), UDim2.fromScale(0, 0.33), COLORS.Lucky, 20)
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
	luckyOdds = label(center, "LuckyOdds", UDim2.fromScale(1, 0.17), UDim2.fromScale(0, 0.61), 12, {
		Text = "Épica o superior: " .. table.concat(luckyParts, " · "),
		TextColor3 = COLORS.Dim,
		TextWrapped = true,
	})
	statusLabel = label(center, "Status", UDim2.fromScale(1, 0.2), UDim2.fromScale(0, 0.8), 15, {
		TextColor3 = COLORS.Dim,
		TextWrapped = true,
	})

	local right = frame(column, "Detail", UDim2.fromScale(1, 0.65), UDim2.fromScale(0, 0), COLORS.Panel)
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
	detail.Description = label(right, "Description", UDim2.fromScale(1, 0.14), UDim2.fromScale(0, 0.28), 17, {
		Font = Enum.Font.Gotham,
		TextWrapped = true,
	})
	-- Maestria: nivel y barra hasta el siguiente nivel (noches con esta clase equipada)
	detail.Mastery = label(right, "Mastery", UDim2.fromScale(1, 0.055), UDim2.fromScale(0, 0.44), 14, {
		TextColor3 = Color3.fromRGB(120, 200, 255),
	})
	local masteryBar = frame(right, "MasteryBar", UDim2.fromScale(1, 0.025), UDim2.fromScale(0, 0.505), Color3.fromRGB(20, 22, 34))
	corner(masteryBar, 0.5)
	masteryFill = frame(masteryBar, "Fill", UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), Color3.fromRGB(120, 200, 255))
	corner(masteryFill, 0.5)
	label(right, "BonusTitle", UDim2.fromScale(1, 0.055), UDim2.fromScale(0, 0.545), 16, {
		Text = "BONIFICACIONES",
		TextColor3 = COLORS.Gold,
	})
	bonusGrid = frame(right, "Bonuses", UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0.605))
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
	snapshotSlots(false)

	for _, attr in { "Diamonds", "PaidDiamonds", "MaxSlots", "EquippedSlot", "EquippedClass", "PaidRandomRestricted", "Pass_VIP" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			snapshotSlots(animating) -- (con el panel cerrado tambien: fuera de un giro)
			if window.Visible and not animating then
				refreshAll()
			end
		end)
	end
	for i = 1, Config.Roulette.MaxSlots do
		player:GetAttributeChangedSignal("Slot_" .. i):Connect(function()
			snapshotSlots(animating)
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
