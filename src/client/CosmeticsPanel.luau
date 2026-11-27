-- CosmeticsPanel (solo en el lobby): dos puestos separados en la plaza.
--
--   CAJA DE SKINS (puesto "SkinBox"): girar con diamantes (Config.Cosmetics.SpinCost) o
--              con Robux (producto CosmeticSpin). Probabilidades siempre visibles. El
--              resultado se revela al terminar la animacion (con su vista previa 3D y un
--              destello del color de su rareza). Donde los objetos aleatorios pagados estan
--              restringidos (PaidRandomRestricted) no se ofrece el giro con Robux.
--   SKINS (puesto "Cosmetics"): la coleccion. Pestañas por objeto (linterna y armas) y,
--              para el elegido, una tarjeta por skin con su vista previa 3D girando,
--              agrupadas por rareza (una fila por rareza). Cuanto mas rara, mas vistosa la
--              tarjeta: borde de su color; las legendarias con brillo dorado que gira y
--              destellos; las miticas con borde arcoiris. Las que tienes: "Usar" /
--              "PUESTA". Las que no: precio de compra directa (pide confirmar con un
--              segundo toque). "Sin skin" quita la skin.
--
-- El servidor (CosmeticsService) valida todo. Lee OwnedSkins y Skin_<objeto> del Player.
-- Los brillos animados de las skins en las vistas previas los pone client/SkinFX.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local HeldModels = require(Shared.HeldModels)
local NativeUI = require(script.Parent.NativeUI)

local COLORS = NativeUI.COLORS
local label, button, frame, corner, stroke = NativeUI.label, NativeUI.button, NativeUI.frame, NativeUI.corner, NativeUI.stroke

local CosmeticsPanel = {}

local player = Players.LocalPlayer
local DIAMOND = "💎"
local ACCENT = Color3.fromRGB(255, 90, 180)
local C = Config.Cosmetics
local RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary", "Mythic" }
local ROW_ASPECT = 4.3 -- ancho / alto de cada fila de tarjetas de la coleccion

local boxWindow: Frame
local collectionWindow: Frame
local window: Frame -- (la que haya abierta; para refrescar)
local diamondsLabels: { TextLabel } = {}
local collectionStatus: TextLabel
local resultTitle: TextLabel
local resultSub: TextLabel
local resultViewport: ViewportFrame
local resultStroke: UIStroke
local spinButton: TextButton
local robuxButton: TextButton
local restrictedNote: TextLabel
local noneButton: TextButton
local tabButtons: { [string]: TextButton } = {}
local cards: { [string]: { Button: TextButton, Viewport: ViewportFrame } } = {} -- [skin]
local selectedItem = C.Items[1]
local previewsBuilt = false
local spinning = false
local confirmKey: string? = nil -- compra directa pendiente de confirmar

-- Vistas previas que giran: { Model, Center }
type Preview = { Model: Model, Center: Vector3 }
local previews: { [ViewportFrame]: Preview } = {}
-- Tarjetas animadas (legendarias y miticas): gradiente del borde y destellos
local shiny: { { Gradient: UIGradient, Sparkles: { TextLabel }, Speed: number } } = {}

local function ownedSet(): { [string]: boolean }
	local set = {}
	local raw = player:GetAttribute("OwnedSkins")
	if type(raw) == "string" then
		for key in string.gmatch(raw, "[^,]+") do
			set[key] = true
		end
	end
	return set
end

local function rarityOf(skinId: string)
	return Config.Rarities[Config.Skins[skinId].Rarity]
end

-- Mayusculas con tildes (string.upper solo cambia las letras ASCII)
local function UIupper(s: string): string
	s = string.upper(s)
	for lower, upperChar in { ["á"] = "Á", ["é"] = "É", ["í"] = "Í", ["ó"] = "Ó", ["ú"] = "Ú", ["ñ"] = "Ñ" } do
		s = string.gsub(s, lower, upperChar)
	end
	return s
end

----------------------------------------------------------------------
-- Vista previa 3D
----------------------------------------------------------------------

-- Pone en el ViewportFrame el objeto con la skin (nil = sin skin), encuadrado.
local function setPreview(viewport: ViewportFrame, itemId: string, skinId: string?)
	previews[viewport] = nil
	viewport:ClearAllChildren()
	local model = HeldModels.build(itemId, skinId)
	if not model then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CastShadow = false
		end
	end
	model:PivotTo(CFrame.identity)
	local cf, size = model:GetBoundingBox()
	local radius = math.max(size.Magnitude / 2, 0.5)
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local distance = radius / math.tan(math.rad(15)) * 0.78
	camera.CFrame = CFrame.lookAt(Vector3.new(0, radius * 0.45, distance), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	previews[viewport] = { Model = model, Center = cf.Position }
end

local function newViewport(parent: Instance, size: UDim2, position: UDim2): ViewportFrame
	local v = Instance.new("ViewportFrame")
	v.Name = "Preview"
	v.Size = size
	v.Position = position
	v.BackgroundTransparency = 1
	v.Ambient = Color3.fromRGB(170, 170, 185)
	v.LightColor = Color3.fromRGB(255, 250, 240)
	v.LightDirection = Vector3.new(-0.6, -1, -0.5)
	v.Parent = parent
	return v
end

----------------------------------------------------------------------
-- Estado
----------------------------------------------------------------------

local function refresh()
	if not window then
		return
	end
	for _, l in diamondsLabels do
		l.Text = string.format("%s %d", DIAMOND, player:GetAttribute("Diamonds") or 0)
	end
	local restricted = player:GetAttribute("PaidRandomRestricted") ~= false
	robuxButton.Visible = not restricted and Config.DevProducts.CosmeticSpin ~= 0
	restrictedNote.Visible = restricted
	spinButton.Text = string.format("Girar · %d %s", C.SpinCost, DIAMOND)
	spinButton.BackgroundColor3 = if (player:GetAttribute("Diamonds") or 0) >= C.SpinCost then COLORS.Buy else COLORS.Off

	if spinning then
		return -- la coleccion se actualiza al revelar el resultado
	end
	for itemId, tab in tabButtons do
		local hasSkin = player:GetAttribute("Skin_" .. itemId) ~= nil
		tab.BackgroundColor3 = if itemId == selectedItem then COLORS.RowSelected else COLORS.Row
		tab.TextColor3 = if itemId == selectedItem then COLORS.Text else COLORS.Dim
		tab.Text = C.ItemNames[itemId] .. (if hasSkin then "  •" else "")
	end
	local owned = ownedSet()
	local equipped = player:GetAttribute("Skin_" .. selectedItem)
	noneButton.Text = if equipped == nil then "SIN SKIN · PUESTA" else "Quitar skin"
	noneButton.BackgroundColor3 = if equipped == nil then COLORS.Good else COLORS.Off
	for skinId, card in cards do
		local cell = card.Button
		local key = selectedItem .. ":" .. skinId
		if equipped == skinId then
			cell.Text = "PUESTA"
			cell.BackgroundColor3 = COLORS.Good
		elseif owned[key] then
			cell.Text = "Usar"
			cell.BackgroundColor3 = rarityOf(skinId).Color:Lerp(COLORS.Row, 0.45)
		elseif confirmKey == key then
			cell.Text = "¿Comprar?"
			cell.BackgroundColor3 = COLORS.Buy
		else
			cell.Text = string.format("%d %s", C.DirectPrice[Config.Skins[skinId].Rarity] or 0, DIAMOND)
			cell.BackgroundColor3 = COLORS.Off
		end
	end
end

-- Cambia de objeto en la coleccion: rehace las vistas previas
local function selectItem(itemId: string)
	selectedItem = itemId
	confirmKey = nil
	for skinId, card in cards do
		setPreview(card.Viewport, itemId, skinId)
	end
	refresh()
end

----------------------------------------------------------------------
-- Giro (animacion y resultado)
----------------------------------------------------------------------

local function reveal(itemId: string, skinId: string, duplicate: boolean)
	spinning = true
	resultSub.Text = ""
	-- Pasan nombres al azar cada vez mas despacio...
	local delay = 0.05
	for _ = 1, 16 do
		local s = Config.SkinOrder[math.random(1, #Config.SkinOrder)]
		local i = C.Items[math.random(1, #C.Items)]
		resultTitle.Text = string.format("%s · %s", C.ItemNames[i], Config.Skins[s].DisplayName)
		resultTitle.TextColor3 = rarityOf(s).Color
		task.wait(delay)
		delay *= 1.15
	end
	-- ...y se para en el resultado, con su vista previa y un destello de su rareza
	local rarity = rarityOf(skinId)
	resultTitle.Text = string.format("%s · %s", C.ItemNames[itemId], Config.Skins[skinId].DisplayName)
	resultTitle.TextColor3 = rarity.Color
	resultSub.Text = if duplicate
		then string.format("%s · ya la tenías: +%d %s", rarity.DisplayName, C.DuplicateRefund, DIAMOND)
		else string.format("%s · ¡nueva! Equípala en el puesto SKINS", rarity.DisplayName)
	resultSub.TextColor3 = if duplicate then COLORS.Dim else COLORS.Good
	setPreview(resultViewport, itemId, skinId)
	resultStroke.Color = rarity.Color
	resultStroke.Thickness = 2 + rarity.Order
	resultStroke.Transparency = 0
	task.spawn(function()
		for i = 1, 12 do
			resultStroke.Transparency = if i % 2 == 0 then 0 else 0.6
			task.wait(0.08)
		end
		resultStroke.Transparency = 0.2
	end)
	spinning = false
	refresh()
end

local function spinWithDiamonds()
	if spinning then
		return
	end
	spinning = true
	local ok, success, message, itemId, skinId, duplicate = pcall(function()
		return Remotes.func("RequestCosmeticSpin"):InvokeServer()
	end)
	if not ok or not success then
		spinning = false
		resultSub.Text = if ok then tostring(message) else "Error, inténtalo de nuevo"
		resultSub.TextColor3 = COLORS.Bad
		refresh()
		return
	end
	task.spawn(reveal, itemId, skinId, duplicate == true)
end

----------------------------------------------------------------------
-- Construccion
----------------------------------------------------------------------

local function buildBox(body: Frame)
	local box = frame(body, "Box", UDim2.fromScale(0.5, 1), UDim2.fromScale(0.25, 0), COLORS.Panel)
	corner(box, 0.04)
	stroke(box, ACCENT, 0.5, 1.5)
	label(box, "Title", UDim2.fromScale(0.9, 0.07), UDim2.fromScale(0.05, 0.02), 20, {
		Text = "CAJA DE COSMÉTICOS",
		Font = Enum.Font.GothamBlack,
		TextColor3 = ACCENT,
	})
	-- Resultado: nombre a la izquierda y la skin en 3D a la derecha
	local result = frame(box, "Result", UDim2.fromScale(0.9, 0.2), UDim2.fromScale(0.05, 0.1), COLORS.Window)
	corner(result, 0.1)
	resultStroke = stroke(result, COLORS.Off, 0.5, 2)
	resultTitle = label(result, "Name", UDim2.fromScale(0.7, 0.55), UDim2.fromScale(0.03, 0.08), 24, {
		Text = "Gira para conseguir una skin",
		Font = Enum.Font.GothamBlack,
	})
	resultSub = label(result, "Sub", UDim2.fromScale(0.7, 0.3), UDim2.fromScale(0.03, 0.64), 15, {
		Text = "",
		Font = Enum.Font.Gotham,
		TextColor3 = COLORS.Dim,
	})
	resultViewport = newViewport(result, UDim2.fromScale(0.26, 0.96), UDim2.fromScale(0.73, 0.02))
	-- Botones
	spinButton = button(box, "Spin", UDim2.fromScale(0.9, 0.09), UDim2.fromScale(0.05, 0.32), COLORS.Buy, 22)
	spinButton.Activated:Connect(spinWithDiamonds)
	robuxButton = button(box, "SpinRobux", UDim2.fromScale(0.9, 0.08), UDim2.fromScale(0.05, 0.42), Color3.fromRGB(200, 150, 30), 20)
	robuxButton.Text = "Girar con Robux"
	robuxButton.Activated:Connect(function()
		if not spinning then
			Remotes.event("RequestBuyProduct"):FireServer("CosmeticSpin")
		end
	end)
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(Config.DevProducts.CosmeticSpin, Enum.InfoType.Product)
		end)
		if ok and info and type(info.PriceInRobux) == "number" then
			robuxButton.Text = "Girar · R$ " .. info.PriceInRobux
		end
	end)
	restrictedNote = label(box, "Restricted", UDim2.fromScale(0.9, 0.08), UDim2.fromScale(0.05, 0.42), 13, {
		Text = "En tu país solo se puede girar con diamantes ganados jugando.",
		Font = Enum.Font.Gotham,
		TextColor3 = COLORS.Dim,
		TextWrapped = true,
		Visible = false,
	})
	-- Probabilidades (siempre visibles)
	label(box, "OddsTitle", UDim2.fromScale(0.9, 0.045), UDim2.fromScale(0.05, 0.515), 15, {
		Text = "PROBABILIDADES",
		TextColor3 = COLORS.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local bySkin, byRarity = Config.getSkinOdds()
	local y = 0.565
	for _, rarityId in RARITY_ORDER do
		if byRarity[rarityId] then
			local names, each = {}, 0
			for _, skinId in Config.SkinOrder do
				if Config.Skins[skinId].Rarity == rarityId then
					table.insert(names, Config.Skins[skinId].DisplayName)
					each = bySkin[skinId]
				end
			end
			local rarity = Config.Rarities[rarityId]
			label(box, "Odds_" .. rarityId, UDim2.fromScale(0.9, 0.065), UDim2.fromScale(0.05, y), 14, {
				Text = string.format("%s  %g%%  (%.1f%% c/u)\n%s", rarity.DisplayName, byRarity[rarityId], each, table.concat(names, "  ·  ")),
				TextColor3 = rarity.Color,
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.Gotham,
			})
			y += 0.07
		end
	end
	label(box, "Note", UDim2.fromScale(0.9, 0.06), UDim2.fromScale(0.05, 0.925), 13, {
		Text = string.format("Objeto al azar (linterna o arma). Si sale repetida: +%d %s", C.DuplicateRefund, DIAMOND),
		Font = Enum.Font.Gotham,
		TextColor3 = COLORS.Dim,
		TextWrapped = true,
	})
end

-- Tarjeta de una skin: vista previa, nombre, rareza y boton.
local function buildCard(parent: Frame, skinId: string, position: UDim2, size: UDim2)
	local skin = Config.Skins[skinId]
	local rarityId = skin.Rarity
	local rarity = Config.Rarities[rarityId]
	local order = rarity.Order

	local card = frame(parent, "Card_" .. skinId, size, position, COLORS.Window)
	corner(card, 0.08)
	-- Fondo: del color de la rareza abajo, cada vez mas intenso
	local bg = Instance.new("UIGradient")
	bg.Rotation = 90
	bg.Color = ColorSequence.new(COLORS.Window, rarity.Color:Lerp(COLORS.Window, 0.75 - order * 0.08))
	bg.Parent = card
	local border = stroke(card, rarity.Color, if order >= 4 then 0 else 0.35, 1 + order * 0.5)
	-- Legendaria: brillo dorado que da vueltas por el borde. Mitica: arcoiris.
	if order >= 4 then
		border.Color = Color3.new(1, 1, 1)
		local g = Instance.new("UIGradient")
		if rarityId == "Mythic" then
			local keys = {}
			for i = 0, 6 do
				table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.75, 1)))
			end
			g.Color = ColorSequence.new(keys)
		else
			g.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, rarity.Color),
				ColorSequenceKeypoint.new(0.45, rarity.Color),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 250, 220)),
				ColorSequenceKeypoint.new(0.55, rarity.Color),
				ColorSequenceKeypoint.new(1, rarity.Color),
			})
		end
		g.Parent = border
		-- Destellos que titilan sobre la tarjeta (estrella de 4 puntas: dos barras cruzadas)
		local sparkles = {}
		for i = 1, (if rarityId == "Mythic" then 5 else 3) do
			local color = if rarityId == "Mythic" then Color3.fromHSV((i * 0.21) % 1, 0.45, 1) else Color3.fromRGB(255, 235, 170)
			local s = frame(card, "Sparkle" .. i, UDim2.fromScale(0.09, 0.09), UDim2.fromScale(0.05 + (i * 0.37) % 0.85, 0.05 + (i * 0.29) % 0.45))
			s.ZIndex = 3
			local aspect = Instance.new("UIAspectRatioConstraint")
			aspect.Parent = s
			for _, bar in { UDim2.fromScale(1, 0.16), UDim2.fromScale(0.16, 1) } do
				local b = frame(s, "Bar", bar, UDim2.fromScale(0.5, 0.5), color)
				b.AnchorPoint = Vector2.new(0.5, 0.5)
				b.ZIndex = 3
				corner(b, 0.5)
			end
			table.insert(sparkles, s)
		end
		table.insert(shiny, { Gradient = g, Sparkles = sparkles, Speed = if rarityId == "Mythic" then 90 else 60 })
	end

	local viewport = newViewport(card, UDim2.fromScale(1, 0.56), UDim2.fromScale(0, 0.02))
	label(card, "Name", UDim2.fromScale(0.92, 0.15), UDim2.fromScale(0.04, 0.57), 16, {
		Text = UIupper(skin.DisplayName),
		Font = Enum.Font.GothamBlack,
		TextColor3 = rarity.Color,
		ZIndex = 2,
	})
	local cell = button(card, "Action", UDim2.fromScale(0.86, 0.22), UDim2.fromScale(0.07, 0.75), COLORS.Off, 15)
	local key = function()
		return selectedItem .. ":" .. skinId
	end
	cell.Activated:Connect(function()
		if spinning then
			return
		end
		local k = key()
		if ownedSet()[k] then
			confirmKey = nil
			Remotes.event("RequestEquipSkin"):FireServer(selectedItem, skinId)
		elseif confirmKey == k then
			confirmKey = nil
			local ok, success, message = pcall(function()
				return Remotes.func("RequestBuySkin"):InvokeServer(selectedItem, skinId)
			end)
			collectionStatus.Text = if ok then tostring(message) else "Error, inténtalo de nuevo"
			collectionStatus.TextColor3 = if ok and success then COLORS.Good else COLORS.Bad
			refresh()
		else
			-- Primer toque: pedir confirmacion (3 s)
			confirmKey = k
			refresh()
			task.delay(3, function()
				if confirmKey == k then
					confirmKey = nil
					refresh()
				end
			end)
		end
	end)
	cards[skinId] = { Button = cell, Viewport = viewport }
end

local function buildCollection(body: Frame)
	local panel = frame(body, "Collection", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), COLORS.Panel)
	corner(panel, 0.03)

	-- Pestañas: un objeto cada una
	local tabs = frame(panel, "Tabs", UDim2.fromScale(0.17, 0.86), UDim2.fromScale(0.012, 0.02))
	label(tabs, "TabsTitle", UDim2.fromScale(1, 0.07), UDim2.fromScale(0, 0), 14, {
		Text = "OBJETO",
		TextColor3 = COLORS.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local tabHeight = 0.9 / #C.Items
	for i, itemId in C.Items do
		local tab = button(tabs, "Tab_" .. itemId, UDim2.fromScale(1, tabHeight * 0.86), UDim2.fromScale(0, 0.08 + (i - 1) * tabHeight), COLORS.Row, 16)
		tab.Text = C.ItemNames[itemId]
		tab.Activated:Connect(function()
			if itemId ~= selectedItem then
				selectItem(itemId)
			end
		end)
		tabButtons[itemId] = tab
	end

	-- Cabecera de la derecha: quitar skin
	local right = frame(panel, "Right", UDim2.fromScale(0.795, 0.9), UDim2.fromScale(0.195, 0.02))
	label(right, "Hint", UDim2.fromScale(0.68, 0.07), UDim2.fromScale(0, 0), 15, {
		Text = "Cuanto más rara, más espectacular · toca para usar o comprar",
		TextColor3 = COLORS.Dim,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	noneButton = button(right, "None", UDim2.fromScale(0.3, 0.07), UDim2.fromScale(0.7, 0), COLORS.Off, 15)
	noneButton.Activated:Connect(function()
		confirmKey = nil
		Remotes.event("RequestEquipSkin"):FireServer(selectedItem, nil)
	end)

	-- Una fila por rareza (nombre de la rareza a la izquierda y sus skins)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.Size = UDim2.fromScale(1, 0.91)
	scroll.Position = UDim2.fromScale(0, 0.09)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = ACCENT
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = right
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll
	-- Alto de cada fila segun el ancho (en un ScrollingFrame no vale la escala en Y)
	local rows: { Frame } = {}
	local function fitRows()
		local height = math.floor((scroll.AbsoluteSize.X - 10) / ROW_ASPECT)
		for _, row in rows do
			row.Size = UDim2.new(1, -10, 0, height)
		end
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitRows)
	task.defer(fitRows)

	for r, rarityId in RARITY_ORDER do
		local skins = {}
		for _, skinId in Config.SkinOrder do
			if Config.Skins[skinId].Rarity == rarityId then
				table.insert(skins, skinId)
			end
		end
		if #skins > 0 then
			local rarity = Config.Rarities[rarityId]
			local row = frame(scroll, "Row_" .. rarityId, UDim2.new(1, -10, 0, 120), UDim2.new())
			row.LayoutOrder = r
			table.insert(rows, row)
			label(row, "Rarity", UDim2.fromScale(0.13, 0.5), UDim2.fromScale(0, 0.25), 16, {
				Text = UIupper(rarity.DisplayName) .. "\n" .. string.format("%d %s", C.DirectPrice[rarityId] or 0, DIAMOND),
				Font = Enum.Font.GothamBlack,
				TextColor3 = rarity.Color,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			local cardWidth = 0.86 / 3
			for k, skinId in skins do
				buildCard(row, skinId, UDim2.fromScale(0.14 + (k - 1) * cardWidth, 0), UDim2.fromScale(cardWidth * 0.95, 1))
			end
		end
	end

	collectionStatus = label(panel, "Footer", UDim2.fromScale(0.94, 0.06), UDim2.fromScale(0.03, 0.93), 13, {
		Text = "Solo estética: se ven en tus manos en el mall, con su brillo y sus partículas. Compra directa: toca dos veces. Skins al azar: ruleta de skins.",
		Font = Enum.Font.Gotham,
		TextColor3 = COLORS.Dim,
		TextWrapped = true,
	})
end

-- Una ventana con cabecera (titulo, diamantes, + y X) y su cuerpo.
local function makeWindow(gui: ScreenGui, title: string, color: Color3): (Frame, Frame)
	local w, diamonds, close, plus = NativeUI.window(gui, title, color)
	table.insert(diamondsLabels, diamonds)
	close.Activated:Connect(function()
		CosmeticsPanel.Close()
	end)
	plus.Activated:Connect(function()
		CosmeticsPanel.Close()
		local LobbyPanels = require(script.Parent.LobbyPanels) :: any
		LobbyPanels.open("Shop")
	end)
	local body = frame(w, "Body", UDim2.fromScale(1, 0.89), UDim2.fromScale(0, 0.11))
	return w, body
end

local function build(gui: ScreenGui)
	local boxBody, collectionBody
	boxWindow, boxBody = makeWindow(gui, "CAJA DE SKINS", Color3.fromRGB(60, 220, 255))
	buildBox(boxBody)
	collectionWindow, collectionBody = makeWindow(gui, "SKINS", ACCENT)
	buildCollection(collectionBody)
	window = collectionWindow
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

-- mode: "Box" (puesto CAJA) o "Collection" (puesto SKINS).
function CosmeticsPanel.Open(mode: string?)
	if not boxWindow then
		return
	end
	CosmeticsPanel.Close()
	window = if mode == "Box" then boxWindow else collectionWindow
	confirmKey = nil
	if window == collectionWindow and not previewsBuilt then
		previewsBuilt = true
		selectItem(selectedItem) -- primera vez: construir las vistas previas
	end
	refresh()
	window.Visible = true
end

function CosmeticsPanel.Close()
	if boxWindow then
		boxWindow.Visible = false
		collectionWindow.Visible = false
	end
end

function CosmeticsPanel.IsOpen(): boolean
	return boxWindow ~= nil and (boxWindow.Visible or collectionWindow.Visible)
end

function CosmeticsPanel.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CosmeticsPanel"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 7
	gui.Parent = player:WaitForChild("PlayerGui")
	build(gui)

	local attrs = { "Diamonds", "OwnedSkins", "PaidRandomRestricted" }
	for _, itemId in C.Items do
		table.insert(attrs, "Skin_" .. itemId)
	end
	for _, attr in attrs do
		player:GetAttributeChangedSignal(attr):Connect(function()
			if CosmeticsPanel.IsOpen() then
				refresh()
			end
		end)
	end
	-- Giro pagado con Robux: el servidor manda el resultado
	Remotes.event("CosmeticResult").OnClientEvent:Connect(function(itemId: string, skinId: string, duplicate: boolean)
		if not boxWindow.Visible then
			CosmeticsPanel.Open("Box")
		end
		task.spawn(reveal, itemId, skinId, duplicate)
	end)

	-- Vistas previas girando y bordes brillantes (solo con la ventana abierta)
	RunService.RenderStepped:Connect(function()
		if not CosmeticsPanel.IsOpen() then
			return
		end
		local t = os.clock()
		for _, p in previews do
			p.Model:PivotTo(CFrame.Angles(0, t * 0.8, 0) * CFrame.Angles(math.rad(-12), 0, 0) * CFrame.new(-p.Center))
		end
		for _, s in shiny do
			s.Gradient.Rotation = (t * s.Speed) % 360
			for i, sparkle in s.Sparkles do
				local a = 0.5 + 0.5 * math.sin(t * 3 + i * 1.7)
				for _, bar in sparkle:GetChildren() do
					if bar:IsA("Frame") then
						bar.BackgroundTransparency = 1 - a
					end
				end
				sparkle.Rotation = (t * 40 + i * 30) % 360
			end
		end
	end)
end

return CosmeticsPanel
