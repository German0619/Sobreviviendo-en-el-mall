-- CosmeticsPanel (solo en el lobby): dos puestos separados en la plaza.
--
--   CAJA DE SKINS (puesto "SkinBox"): girar con diamantes (Config.Cosmetics.SpinCost) o
--              con Robux (producto CosmeticSpin). Probabilidades siempre visibles. El
--              resultado se revela al terminar la animacion (la coleccion no se
--              actualiza antes). Donde los objetos aleatorios pagados estan
--              restringidos (PaidRandomRestricted) no se ofrece el giro con Robux.
--   SKINS (puesto "Cosmetics"): la coleccion. Una fila por objeto (linterna y armas) y
--              una columna por skin. Las que tienes: "Usar" / "PUESTA". Las que no:
--              precio de compra directa (pide confirmar con un segundo toque).
--              "Normal" quita la skin.
--
-- El servidor (CosmeticsService) valida todo. Lee OwnedSkins y Skin_<objeto> del Player.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local NativeUI = require(script.Parent.NativeUI)

local COLORS = NativeUI.COLORS
local label, button, frame, corner, stroke = NativeUI.label, NativeUI.button, NativeUI.frame, NativeUI.corner, NativeUI.stroke

local CosmeticsPanel = {}

local player = Players.LocalPlayer
local DIAMOND = "💎"
local ACCENT = Color3.fromRGB(255, 90, 180)
local C = Config.Cosmetics

local boxWindow: Frame
local collectionWindow: Frame
local window: Frame -- (la que haya abierta; para refrescar)
local diamondsLabels: { TextLabel } = {}
local collectionStatus: TextLabel
local resultTitle: TextLabel
local resultSub: TextLabel
local spinButton: TextButton
local robuxButton: TextButton
local restrictedNote: TextLabel
local cells: { [string]: { [string]: TextButton } } = {} -- [objeto][skin | "None"]
local spinning = false
local confirmKey: string? = nil -- compra directa pendiente de confirmar

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
	local owned = ownedSet()
	for _, itemId in C.Items do
		local equipped = player:GetAttribute("Skin_" .. itemId)
		local row = cells[itemId]
		local none = row.None
		none.Text = if equipped == nil then "PUESTA" else "Normal"
		none.BackgroundColor3 = if equipped == nil then COLORS.Good else COLORS.Off
		for _, skinId in Config.SkinOrder do
			local cell = row[skinId]
			local key = itemId .. ":" .. skinId
			local style = Config.Skins[skinId].Body
			if equipped == skinId then
				cell.Text = "PUESTA"
				cell.BackgroundColor3 = COLORS.Good
			elseif owned[key] then
				cell.Text = "Usar"
				cell.BackgroundColor3 = style.Color:Lerp(COLORS.Row, 0.35)
			elseif confirmKey == key then
				cell.Text = "¿Comprar?"
				cell.BackgroundColor3 = COLORS.Buy
			else
				cell.Text = string.format("%d%s", C.DirectPrice[Config.Skins[skinId].Rarity] or 0, DIAMOND)
				cell.BackgroundColor3 = COLORS.Row
			end
		end
	end
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
	-- ...y se para en el resultado
	local rarity = rarityOf(skinId)
	resultTitle.Text = string.format("%s · %s", C.ItemNames[itemId], Config.Skins[skinId].DisplayName)
	resultTitle.TextColor3 = rarity.Color
	resultSub.Text = if duplicate
		then string.format("%s · ya la tenías: +%d %s", rarity.DisplayName, C.DuplicateRefund, DIAMOND)
		else string.format("%s · ¡nueva! Equípala en el puesto SKINS", rarity.DisplayName)
	resultSub.TextColor3 = if duplicate then COLORS.Dim else COLORS.Good
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
	-- Resultado
	local result = frame(box, "Result", UDim2.fromScale(0.9, 0.2), UDim2.fromScale(0.05, 0.1), COLORS.Window)
	corner(result, 0.1)
	resultTitle = label(result, "Name", UDim2.fromScale(0.94, 0.55), UDim2.fromScale(0.03, 0.08), 26, {
		Text = "Gira para conseguir una skin",
		Font = Enum.Font.GothamBlack,
	})
	resultSub = label(result, "Sub", UDim2.fromScale(0.94, 0.3), UDim2.fromScale(0.03, 0.64), 15, {
		Text = "",
		Font = Enum.Font.Gotham,
		TextColor3 = COLORS.Dim,
	})
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
	label(box, "OddsTitle", UDim2.fromScale(0.9, 0.05), UDim2.fromScale(0.05, 0.52), 15, {
		Text = "PROBABILIDADES",
		TextColor3 = COLORS.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local bySkin, byRarity = Config.getSkinOdds()
	local order = { "Common", "Rare", "Epic", "Legendary" }
	local y = 0.575
	for _, rarityId in order do
		if byRarity[rarityId] then
			local names = {}
			for _, skinId in Config.SkinOrder do
				if Config.Skins[skinId].Rarity == rarityId then
					table.insert(names, string.format("%s %.1f%%", Config.Skins[skinId].DisplayName, bySkin[skinId]))
				end
			end
			local rarity = Config.Rarities[rarityId]
			label(box, "Odds_" .. rarityId, UDim2.fromScale(0.9, 0.075), UDim2.fromScale(0.05, y), 14, {
				Text = string.format("%s  %d%%\n%s", rarity.DisplayName, math.floor(byRarity[rarityId] + 0.5), table.concat(names, "  ·  ")),
				TextColor3 = rarity.Color,
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.Gotham,
			})
			y += 0.085
		end
	end
	label(box, "Note", UDim2.fromScale(0.9, 0.07), UDim2.fromScale(0.05, 0.92), 13, {
		Text = string.format("Objeto al azar (linterna o arma). Si sale repetida: +%d %s", C.DuplicateRefund, DIAMOND),
		Font = Enum.Font.Gotham,
		TextColor3 = COLORS.Dim,
		TextWrapped = true,
	})
end

local function buildCollection(body: Frame)
	local panel = frame(body, "Collection", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), COLORS.Panel)
	corner(panel, 0.03)
	label(panel, "Title", UDim2.fromScale(0.9, 0.07), UDim2.fromScale(0.03, 0.02), 20, {
		Text = "COLECCIÓN  ·  toca para usar o comprar",
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local columns = 2 + #Config.SkinOrder -- nombre, Normal, skins
	local nameWidth = 0.16
	local cellWidth = (0.97 - nameWidth) / (columns - 1)
	local top = 0.11
	local rowHeight = (0.97 - top - 0.07) / #C.Items
	-- Cabecera: nombres de las skins (color de su rareza)
	label(panel, "HeadNone", UDim2.fromScale(cellWidth, 0.06), UDim2.fromScale(0.015 + nameWidth, top), 13, {
		Text = "Normal",
		TextColor3 = COLORS.Dim,
	})
	for k, skinId in Config.SkinOrder do
		label(panel, "Head_" .. skinId, UDim2.fromScale(cellWidth, 0.06), UDim2.fromScale(0.015 + nameWidth + cellWidth * k, top), 13, {
			Text = Config.Skins[skinId].DisplayName,
			TextColor3 = rarityOf(skinId).Color,
		})
	end
	for r, itemId in C.Items do
		local y = top + 0.07 + (r - 1) * rowHeight
		label(panel, "Item_" .. itemId, UDim2.fromScale(nameWidth, rowHeight * 0.8), UDim2.fromScale(0.015, y + rowHeight * 0.1), 16, {
			Text = C.ItemNames[itemId],
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local row = {}
		local none = button(panel, "None_" .. itemId, UDim2.fromScale(cellWidth * 0.92, rowHeight * 0.78), UDim2.fromScale(0.015 + nameWidth, y + rowHeight * 0.11), COLORS.Off, 14)
		none.Activated:Connect(function()
			confirmKey = nil
			Remotes.event("RequestEquipSkin"):FireServer(itemId, nil)
		end)
		row.None = none
		for k, skinId in Config.SkinOrder do
			local cell = button(panel, itemId .. "_" .. skinId, UDim2.fromScale(cellWidth * 0.92, rowHeight * 0.78), UDim2.fromScale(0.015 + nameWidth + cellWidth * k, y + rowHeight * 0.11), COLORS.Row, 14)
			stroke(cell, rarityOf(skinId).Color, 0.4, 1.5)
			local key = itemId .. ":" .. skinId
			cell.Activated:Connect(function()
				if spinning then
					return
				end
				if ownedSet()[key] then
					confirmKey = nil
					Remotes.event("RequestEquipSkin"):FireServer(itemId, skinId)
				elseif confirmKey == key then
					confirmKey = nil
					local ok, success, message = pcall(function()
						return Remotes.func("RequestBuySkin"):InvokeServer(itemId, skinId)
					end)
					collectionStatus.Text = if ok then tostring(message) else "Error, inténtalo de nuevo"
					collectionStatus.TextColor3 = if ok and success then COLORS.Good else COLORS.Bad
					refresh()
				else
					-- Primer toque: pedir confirmacion (3 s)
					confirmKey = key
					refresh()
					task.delay(3, function()
						if confirmKey == key then
							confirmKey = nil
							refresh()
						end
					end)
				end
			end)
			row[skinId] = cell
		end
		cells[itemId] = row
	end
	collectionStatus = label(panel, "Footer", UDim2.fromScale(0.94, 0.06), UDim2.fromScale(0.03, 0.93), 13, {
		Text = "Solo estética: se ven en tus manos en el mall (las armas al llevarlas). Compra directa: toca dos veces. Skins al azar: puesto CAJA.",
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
end

return CosmeticsPanel
