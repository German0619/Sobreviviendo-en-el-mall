-- ShopPanel (solo en el lobby): TIENDA con Robux (boton TIENDA y "+" de diamantes).
--
--   Diamantes  3 paquetes (Config.DevProducts.DiamondPacks). No se venden donde
--              la politica de Roblox restringe los objetos aleatorios pagados
--              (atributo PaidRandomRestricted): los diamantes sirven para la ruleta.
--   Slot       +1 slot de clase (Config.DevProducts.ClassSlot), hasta MaxSlots.
--   Pases      permanentes (Config.GamePasses / GamePassInfo / GamePassOrder).
--
-- Muestra el precio REAL en Robux (GetProductInfo). El servidor abre la compra
-- (RequestBuyProduct / RequestBuyPass) y entrega lo comprado. Revivir y la
-- soda a eleccion se compran en el mall, no aqui.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local NativeUI = require(script.Parent.NativeUI)

local COLORS = NativeUI.COLORS
local label, button, frame, corner, stroke = NativeUI.label, NativeUI.button, NativeUI.frame, NativeUI.corner, NativeUI.stroke

local ShopPanel = {}

local player = Players.LocalPlayer
local DIAMOND = "💎"
local ACCENT = Color3.fromRGB(230, 170, 30)

local window: Frame
local diamondsLabel: TextLabel
local diamondCards: { Frame } = {}
local restrictedNote: TextLabel
local slotInfo: TextLabel
local slotButton: TextButton
local passButtons: { [string]: TextButton } = {}

----------------------------------------------------------------------
-- Precios reales
----------------------------------------------------------------------

local priceCache: { [string]: number | false } = {}

-- Escribe el precio en `target` (lo pide a Roblox una vez y lo guarda).
local function showPrice(target: TextLabel, id: number, isPass: boolean)
	if id == 0 then
		target.Text = "Sin configurar"
		return
	end
	local key = (if isPass then "Pass_" else "Product_") .. id
	task.spawn(function()
		if priceCache[key] == nil then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, if isPass then Enum.InfoType.GamePass else Enum.InfoType.Product)
			end)
			priceCache[key] = if ok and info and type(info.PriceInRobux) == "number" then info.PriceInRobux else false
		end
		local price = priceCache[key]
		target.Text = if price then "R$ " .. tostring(price) else "R$ ?"
	end)
end

----------------------------------------------------------------------
-- Estado
----------------------------------------------------------------------

local function refresh()
	if not window then
		return
	end
	diamondsLabel.Text = string.format("%s %d", DIAMOND, player:GetAttribute("Diamonds") or 0)

	local restricted = player:GetAttribute("PaidRandomRestricted") ~= false
	for _, card in diamondCards do
		card.Visible = not restricted
	end
	restrictedNote.Visible = restricted

	local maxSlots = player:GetAttribute("MaxSlots") or Config.Roulette.DefaultSlots
	local full = maxSlots >= Config.Roulette.MaxSlots
	slotInfo.Text = string.format("Tienes %d de %d. Cada slot guarda una clase; el nuevo empieza con Conserje.", maxSlots, Config.Roulette.MaxSlots)
	slotButton.Text = if full then "Máximo" else "Comprar"
	slotButton.BackgroundColor3 = if full then COLORS.Off else COLORS.Buy

	for passName, b in passButtons do
		local has = player:GetAttribute("Pass_" .. passName) == true
		b.Text = if has then "Lo tienes" else "Comprar"
		b.BackgroundColor3 = if has then COLORS.Off else COLORS.Buy
	end
end

----------------------------------------------------------------------
-- Construccion
----------------------------------------------------------------------

local function sectionTitle(parent: Instance, y: number, text: string)
	label(parent, "Section", UDim2.fromScale(1, 0.045), UDim2.fromScale(0, y), 16, {
		Text = text,
		TextColor3 = COLORS.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

-- Fila: titulo + descripcion a la izquierda, precio y boton a la derecha.
-- x / width (opcionales): para poner dos filas lado a lado (pases).
local function row(parent: Instance, name: string, y: number, height: number, title: string, description: string, titleColor: Color3?, x: number?, width: number?)
	local r = frame(parent, name, UDim2.fromScale(width or 1, height), UDim2.fromScale(x or 0, y), COLORS.Panel)
	corner(r, 0.18)
	label(r, "Title", UDim2.fromScale(0.6, 0.48), UDim2.fromScale(0.02, 0.06), 20, {
		Text = title,
		TextColor3 = titleColor or COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	label(r, "Description", UDim2.fromScale(0.6, 0.36), UDim2.fromScale(0.02, 0.56), 14, {
		Text = description,
		Font = Enum.Font.Gotham,
		TextColor3 = COLORS.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local price = label(r, "Price", UDim2.fromScale(0.15, 0.5), UDim2.fromScale(0.64, 0.25), 18, {
		TextColor3 = COLORS.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local b = button(r, "Buy", UDim2.fromScale(0.17, 0.7), UDim2.fromScale(0.81, 0.15), COLORS.Buy, 18)
	return price, b
end

local function build(gui: ScreenGui)
	local close, plus
	window, diamondsLabel, close, plus = NativeUI.window(gui, "TIENDA", ACCENT)
	close.Activated:Connect(function()
		ShopPanel.Close()
	end)
	plus.Visible = false -- ya estas en la tienda

	local body = frame(window, "Body", UDim2.fromScale(1, 0.89), UDim2.fromScale(0, 0.11))

	-- Diamantes
	sectionTitle(body, 0, "DIAMANTES  ·  para la ruleta de clases")
	local packs = frame(body, "Packs", UDim2.fromScale(1, 0.27), UDim2.fromScale(0, 0.05))
	local count = #Config.DevProducts.DiamondPacks
	local gap = 0.02
	local width = (1 - gap * (count - 1)) / count
	for i, pack in Config.DevProducts.DiamondPacks do
		local card = frame(packs, "Pack" .. i, UDim2.fromScale(width, 1), UDim2.fromScale((width + gap) * (i - 1), 0), COLORS.Panel)
		corner(card, 0.1)
		stroke(card, COLORS.Diamond, 0.6, 1.5)
		label(card, "Amount", UDim2.fromScale(0.9, 0.34), UDim2.fromScale(0.05, 0.06), 34, {
			Text = string.format("%s %d", DIAMOND, pack.Amount),
			Font = Enum.Font.GothamBlack,
			TextColor3 = COLORS.Diamond,
		})
		local price = label(card, "Price", UDim2.fromScale(0.9, 0.18), UDim2.fromScale(0.05, 0.42), 18, { TextColor3 = COLORS.Gold })
		showPrice(price, pack.Id, false)
		local b = button(card, "Buy", UDim2.fromScale(0.8, 0.3), UDim2.fromScale(0.1, 0.64), COLORS.Buy, 20)
		b.Text = "Comprar"
		b.Activated:Connect(function()
			Remotes.event("RequestBuyProduct"):FireServer("Diamonds", i)
		end)
		table.insert(diamondCards, card)
	end
	restrictedNote = label(packs, "Restricted", UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0.25), 18, {
		Text = "En tu país los diamantes no están a la venta: se ganan jugando (cada 5 noches y con logros).",
		TextColor3 = COLORS.Dim,
		TextWrapped = true,
		Visible = false,
	})

	-- Slot de clase
	sectionTitle(body, 0.345, "SLOTS DE CLASE")
	local slotPrice
	slotPrice, slotButton = row(body, "Slot", 0.395, 0.13, "+1 slot de clase", "")
	-- La descripcion dice cuantos slots tienes (refresh)
	slotInfo = (slotPrice.Parent :: Instance):FindFirstChild("Description") :: TextLabel
	showPrice(slotPrice, Config.DevProducts.ClassSlot, false)
	slotButton.Activated:Connect(function()
		Remotes.event("RequestBuyProduct"):FireServer("ClassSlot")
	end)

	-- Pases: en dos columnas (caben 6 en el hueco que queda)
	sectionTitle(body, 0.545, "PASES  ·  para siempre")
	local rowsCount = math.ceil(#Config.GamePassOrder / 2)
	local rowStep = math.min(0.135, 0.4 / math.max(rowsCount, 1))
	for i, passName in Config.GamePassOrder do
		local info = Config.GamePassInfo[passName]
		local column = (i - 1) % 2
		local y = 0.595 + math.floor((i - 1) / 2) * rowStep
		local price, b = row(body, "Pass_" .. passName, y, rowStep - 0.01, info.DisplayName, info.Description, COLORS.Gold, column * 0.505, 0.495)
		showPrice(price, Config.GamePasses[passName] or 0, true)
		b.Activated:Connect(function()
			if player:GetAttribute("Pass_" .. passName) ~= true then
				Remotes.event("RequestBuyPass"):FireServer(passName)
			end
		end)
		passButtons[passName] = b
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function ShopPanel.Open()
	if not window then
		return
	end
	refresh()
	window.Visible = true
end

function ShopPanel.Close()
	if window then
		window.Visible = false
	end
end

function ShopPanel.IsOpen(): boolean
	return window ~= nil and window.Visible
end

function ShopPanel.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopPanel"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 7
	gui.Parent = player:WaitForChild("PlayerGui")
	build(gui)

	local attrs = { "Diamonds", "MaxSlots", "PaidRandomRestricted" }
	for _, passName in Config.GamePassOrder do
		table.insert(attrs, "Pass_" .. passName)
	end
	for _, attr in attrs do
		player:GetAttributeChangedSignal(attr):Connect(function()
			if window.Visible then
				refresh()
			end
		end)
	end
end

return ShopPanel
