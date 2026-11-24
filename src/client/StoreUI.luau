-- StoreUI (solo en el lobby): tienda con Robux.
--   * Diamantes (para la ruleta). No se venden donde la politica de Roblox
--     restringe los objetos aleatorios pagados (atributo PaidRandomRestricted).
--   * Slot de clase extra.
--   * Game Passes (permanentes).
-- Los precios se leen de Roblox (GetProductInfo); el servidor abre la compra.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer
local C = UIKit.COLORS

local StoreUI = {}

local DIAMOND = "◆"
local DIAMOND_COLOR = Color3.fromRGB(110, 220, 255)
local GOLD = Color3.fromRGB(255, 200, 60)

local window
local built = false
local priceCache: { [string]: number | false } = {}
local diamondCards = {} -- { { Button, Blocked } }
local slotInfo, slotButton
local passRows = {} -- [passName] = { Button, Price }

----------------------------------------------------------------------
-- Precios
----------------------------------------------------------------------

-- Escribe el precio en Robux en `label` (lo pide a Roblox una vez y lo guarda).
local function showPrice(label: TextLabel, id: number, isPass: boolean)
	if id == 0 then
		label.Text = "Sin configurar"
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
		label.Text = if price then "R$ " .. tostring(price) else "R$ ?"
	end)
end

----------------------------------------------------------------------
-- Estado
----------------------------------------------------------------------

local function refresh()
	if not built then
		return
	end
	-- Diamantes
	local restricted = player:GetAttribute("PaidRandomRestricted") ~= false
	for _, card in diamondCards do
		card.Blocked.Visible = restricted
		card.Button.Visible = not restricted
	end

	-- Slots
	local maxSlots = player:GetAttribute("MaxSlots") or Config.Roulette.DefaultSlots
	slotInfo.Text = string.format("Tienes %d de %d slots", maxSlots, Config.Roulette.MaxSlots)
	local full = maxSlots >= Config.Roulette.MaxSlots
	slotButton.Text = if full then "Máximo" else "Comprar"
	slotButton.BackgroundColor3 = if full then C.ButtonOff else C.Button

	-- Pases
	for passName, row in passRows do
		local has = player:GetAttribute("Pass_" .. passName) == true
		row.Button.Text = if has then "Lo tienes" else "Comprar"
		row.Button.BackgroundColor3 = if has then C.ButtonOff else C.Button
	end
end

function StoreUI.Open()
	if not built then
		return
	end
	refresh()
	window.Visible = true
end

function StoreUI.Close()
	if window then
		window.Visible = false
	end
end

function StoreUI.IsOpen(): boolean
	return window ~= nil and window.Visible
end

----------------------------------------------------------------------
-- Construccion
----------------------------------------------------------------------

local function sectionTitle(parent: Instance, y: number, title: string)
	UIKit.text({
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		TextColor3 = C.Dim,
		Text = title,
		ZIndex = 22,
		Parent = parent,
	})
end

local function priceLabel(parent: Instance, props)
	local base = {
		TextSize = 15,
		TextColor3 = C.Accent,
		Text = "...",
		ZIndex = 24,
		Parent = parent,
	}
	for k, v in props do
		base[k] = v
	end
	return UIKit.text(base)
end

local function build()
	local gui = UIKit.make("ScreenGui", {
		Name = "StoreUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 6,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local content
	window, content = UIKit.window(gui, "TIENDA", Vector2.new(640, 520), StoreUI.Close)

	-- Diamantes
	sectionTitle(content, 0, "DIAMANTES  (se usan en la ruleta de clases)")
	local packs = Config.DevProducts.DiamondPacks
	for i, pack in packs do
		local card = UIKit.make("Frame", {
			Position = UDim2.new((i - 1) / #packs, if i > 1 then 6 else 0, 0, 22),
			Size = UDim2.new(1 / #packs, -8, 0, 92),
			BackgroundColor3 = C.Row,
			ZIndex = 23,
			Parent = content,
		}, { UIKit.corner(8) })
		UIKit.text({
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 26),
			TextSize = 22,
			TextColor3 = DIAMOND_COLOR,
			Text = string.format("%s %d", DIAMOND, pack.Amount),
			ZIndex = 24,
			Parent = card,
		})
		local price = priceLabel(card, { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 18) })
		showPrice(price, pack.Id, false)
		local button = UIKit.button({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -20, 0, 28),
			Text = "Comprar",
			ZIndex = 24,
			Parent = card,
		}, function()
			Remotes.event("RequestBuyProduct"):FireServer("Diamonds", i)
		end)
		local blocked = UIKit.text({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -12, 0, 28),
			TextSize = 11,
			Font = UIKit.FONT_LIGHT,
			TextColor3 = C.Dim,
			TextWrapped = true,
			Text = "No disponible en tu país",
			Visible = false,
			ZIndex = 24,
			Parent = card,
		})
		table.insert(diamondCards, { Button = button, Blocked = blocked })
	end

	-- Slot de clase
	sectionTitle(content, 124, "SLOT DE CLASE EXTRA  (cada slot guarda una clase; empieza con Conserje)")
	local slotRow = UIKit.make("Frame", {
		Position = UDim2.fromOffset(0, 146),
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = C.Row,
		ZIndex = 23,
		Parent = content,
	}, { UIKit.corner(8) })
	slotInfo = UIKit.text({
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -260, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 16,
		Text = "",
		ZIndex = 24,
		Parent = slotRow,
	})
	local slotPrice = priceLabel(slotRow, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -130, 0.5, 0),
		Size = UDim2.fromOffset(100, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	showPrice(slotPrice, Config.DevProducts.ClassSlot, false)
	slotButton = UIKit.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(110, 32),
		Text = "Comprar",
		ZIndex = 24,
		Parent = slotRow,
	}, function()
		Remotes.event("RequestBuyProduct"):FireServer("ClassSlot")
	end)

	-- Pases
	sectionTitle(content, 206, "PASES  (para siempre)")
	for i, passName in Config.GamePassOrder do
		local info = Config.GamePassInfo[passName]
		local row = UIKit.make("Frame", {
			Position = UDim2.fromOffset(0, 228 + (i - 1) * 58),
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundColor3 = C.Row,
			ZIndex = 23,
			Parent = content,
		}, { UIKit.corner(8) })
		UIKit.text({
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -260, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 16,
			TextColor3 = GOLD,
			Text = info.DisplayName,
			ZIndex = 24,
			Parent = row,
		})
		UIKit.text({
			Position = UDim2.fromOffset(12, 26),
			Size = UDim2.new(1, -260, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 13,
			Font = UIKit.FONT_LIGHT,
			TextColor3 = C.Dim,
			Text = info.Description,
			ZIndex = 24,
			Parent = row,
		})
		local price = priceLabel(row, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -130, 0.5, 0),
			Size = UDim2.fromOffset(100, 20),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		showPrice(price, Config.GamePasses[passName], true)
		local button = UIKit.button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(110, 32),
			Text = "Comprar",
			ZIndex = 24,
			Parent = row,
		}, function()
			if player:GetAttribute("Pass_" .. passName) ~= true then
				Remotes.event("RequestBuyPass"):FireServer(passName)
			end
		end)
		passRows[passName] = { Button = button, Price = price }
	end

	UIKit.text({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 12,
		Font = UIKit.FONT_LIGHT,
		TextColor3 = C.Dim,
		TextWrapped = true,
		Text = "Las probabilidades de la ruleta están siempre visibles en CLASES Y RULETA.",
		ZIndex = 22,
		Parent = content,
	})
	built = true
end

function StoreUI.Start()
	build()
	local watched = { "PaidRandomRestricted", "MaxSlots" }
	for passName in Config.GamePasses do
		table.insert(watched, "Pass_" .. passName)
	end
	for _, attr in watched do
		player:GetAttributeChangedSignal(attr):Connect(refresh)
	end
	refresh()
end

return StoreUI
