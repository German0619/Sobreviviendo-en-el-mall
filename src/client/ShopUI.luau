-- ShopUI: ventana de la tienda del mall. La abre el servidor al usar el
-- mostrador y se cierra sola si te alejas.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer
local C = UIKit.COLORS

local ShopUI = {}

local window, statusLabel, moneyLabel
local rows = {}
local counterPosition: Vector3? = nil
local busy = false

local function setStatus(message: string, good: boolean?)
	statusLabel.Text = message
	statusLabel.TextColor3 = if good then C.Good else C.Bad
end

-- Icono de cada objeto (los que no estan, un "+")
local ICONS = {
	Battery = { "🔋", Color3.fromRGB(120, 190, 255) },
	Medkit = { "✚", Color3.fromRGB(230, 80, 80) },
	Flare = { "🔥", Color3.fromRGB(255, 120, 60) },
	Firecracker = { "🧨", Color3.fromRGB(255, 90, 90) },
	FlashlightPro = { "🔦", Color3.fromRGB(255, 220, 120) },
	Taser = { "⚡", Color3.fromRGB(110, 200, 255) },
	Extinguisher = { "🧯", Color3.fromRGB(230, 70, 70) },
	WetFloorSign = { "⚠", Color3.fromRGB(255, 210, 60) },
	UVFlashlight = { "🔦", Color3.fromRGB(180, 110, 255) },
	Mop = { "🧹", Color3.fromRGB(120, 200, 160) },
	Machete = { "🔪", Color3.fromRGB(200, 200, 210) },
	Pistol = { "🔫", Color3.fromRGB(200, 200, 210) },
}

local function priceCaption(money: number, price: number): string
	return if money >= price then "COMPRAR" else "TE FALTA " .. Util.formatMoney(price - money)
end

-- Boton de compra: precio grande y leyenda pequena debajo
local function setButton(row, priceText: string, caption: string, affordable: boolean, owned: boolean)
	row.Price.Text = priceText
	row.Caption.Text = caption
	row.Caption.Visible = caption ~= ""
	row.Price.Position = UDim2.new(0, 0, 0, if caption ~= "" then 5 else 0)
	row.Price.Size = UDim2.new(1, 0, if caption ~= "" then 0 else 1, if caption ~= "" then 24 else 0)
	row.Button.BackgroundColor3 = if affordable then C.Button else C.ButtonOff
	row.Price.TextColor3 = if owned then C.Good elseif affordable then C.Text else C.Dim
	row.Stroke.Transparency = if affordable then 0.4 else 0.8
end

local function refresh()
	if not window then
		return
	end
	local money = player:GetAttribute("Money") or 0
	moneyLabel.Text = Util.formatMoney(money)
	for itemId, row in rows do
		local item = Config.ShopItems[itemId]
		-- Armas: cada una en su casilla de la mochila; la misma se recarga. El taser no se
		-- recarga aqui: se vuelve a comprar cuando se acaba, cada vez mas caro.
		if item.Weapon then
			local def = Config.Weapons[itemId]
			local usesAttr = player:GetAttribute("WeaponUses_" .. itemId)
			local carried = type(usesAttr) == "number"
			local uses = if carried then usesAttr else 0
			local infinite = carried and uses < 0
			local full = carried and (def.Uses == nil or infinite or uses >= def.Uses or itemId == "Taser")
			local price = Config.getShopPrice(itemId, player:GetAttribute(itemId .. "Buys") or 0)
			if infinite and def.Uses then
				row.Owned.Text = "La llevas · usos infinitos (pase)"
			elseif carried then
				row.Owned.Text = if def.Uses then string.format("La llevas · %d/%d usos", uses, def.Uses) else "La llevas"
			elseif price > item.Price then
				row.Owned.Text = "Arma · vuelve a comprarla (más cara cada vez)"
			else
				row.Owned.Text = "Arma · va a su casilla de la mochila"
			end
			-- Recarga de taser con Robux (+10 usos): solo con un taser que se gasta
			if row.Recharge then
				row.Recharge.Visible = carried and not infinite
			end
			if full then
				setButton(row, "LA LLEVAS", "", false, true)
			else
				setButton(row, Util.formatMoney(price), priceCaption(money, price), money >= price, false)
			end
			continue
		end
		local owned = player:GetAttribute("Item_" .. itemId) or 0
		local byPass = itemId == "FlashlightPro" and player:GetAttribute("Pass_PremiumFlashlight") == true
		if byPass then
			owned = 1
		end
		local full = (item.Unique and owned >= 1) or (item.MaxStack ~= nil and owned >= item.MaxStack)
		if byPass then
			row.Owned.Text = "Incluida en tu pase Linterna Premium"
		elseif item.Unique then
			row.Owned.Text = if owned >= 1 then "Equipada" else "No se gasta"
		else
			row.Owned.Text = string.format("Tienes %d / %d", owned, item.MaxStack or 99)
		end
		if full then
			setButton(row, if item.Unique then "TUYA" else "LLENO", "", false, true)
		else
			setButton(row, Util.formatMoney(item.Price), priceCaption(money, item.Price), money >= item.Price, false)
		end
	end
end

local function buy(itemId: string)
	if busy then
		return
	end
	busy = true
	local ok, result, message = pcall(function()
		return Remotes.func("RequestPurchase"):InvokeServer(itemId)
	end)
	busy = false
	if not ok then
		warn("[ShopUI] RequestPurchase fallo:", result)
		setStatus("Error: " .. tostring(result))
	else
		setStatus((if result == true then "✓ " else "") .. (message or ""), result == true)
		local row = rows[itemId]
		if result == true and row then
			-- Destello de la fila comprada
			local icon = ICONS[itemId] or { "+", C.Accent }
			row.Frame.BackgroundColor3 = UIKit.shade(icon[2], -0.5)
			UIKit.tween(row.Frame, 0.6, { BackgroundColor3 = C.Row })
		end
	end
	refresh()
end

function ShopUI.Open(position: Vector3)
	counterPosition = position
	statusLabel.Text = "Los objetos se pierden si mueres."
	statusLabel.TextColor3 = C.Dim
	refresh()
	window.Visible = true
end

function ShopUI.Close()
	window.Visible = false
	counterPosition = nil
end

local ROW = 94 -- alto de cada fila de la lista (con su separacion)

local function build()
	local gui = UIKit.make("ScreenGui", {
		Name = "ShopUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
		Parent = player:WaitForChild("PlayerGui"),
	})
	UIKit.adapt(gui) -- escala segun la pantalla y respeta el notch
	local content
	-- (Precio de las armas: Config.getShopPrice, el taser sube al volver a comprarlo)
	-- Alto segun el numero de objetos (ROW px por fila), con tope: el resto con scroll
	local height = math.min(130 + #Config.ShopOrder * ROW, 560)
	-- (scroll = true: en pantallas bajas la ventana baja de alto y la lista hace scroll)
	window, content = UIKit.window(gui, "TIENDA DEL MALL", Vector2.new(540, height), ShopUI.Close, true)

	-- Billetes en una pastilla dorada
	local moneyPill = UIKit.make("Frame", {
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = UIKit.shade(C.Accent, -0.8),
		ZIndex = 22,
		Parent = content,
	}, {
		UIKit.corner(14),
		UIKit.make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
	})
	UIKit.stroke(moneyPill, C.Accent, 1, 0.4)
	moneyLabel = UIKit.text({
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 17,
		Font = UIKit.FONT_BLACK,
		TextColor3 = C.Accent,
		ZIndex = 23,
		Parent = moneyPill,
	})

	-- Lista con scroll entre el dinero y la linea de estado
	local list = UIKit.make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -64),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.fromOffset(0, #Config.ShopOrder * ROW),
		ZIndex = 22,
		Parent = content,
	})

	for i, itemId in Config.ShopOrder do
		local item = Config.ShopItems[itemId]
		local icon = ICONS[itemId] or { "+", C.Accent }
		local row = UIKit.make("Frame", {
			Position = UDim2.fromOffset(0, (i - 1) * ROW),
			Size = UDim2.new(1, -10, 0, ROW - 8),
			BackgroundColor3 = C.Row,
			ZIndex = 22,
			Parent = list,
		}, { UIKit.corner(10) })
		local rowStroke = UIKit.stroke(row, icon[2], 1, 0.8)
		UIKit.iconBox({
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(54, 54),
			Radius = 10,
			ZIndex = 23,
			Parent = row,
		}, icon[1], icon[2])
		local name = item.DisplayName
		UIKit.text({
			Position = UDim2.fromOffset(76, 8),
			Size = UDim2.new(1, -220, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 17,
			Font = UIKit.FONT_BLACK,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = name,
			ZIndex = 23,
			Parent = row,
		})
		-- Descripcion en hasta dos lineas
		UIKit.text({
			Position = UDim2.fromOffset(76, 30),
			Size = UDim2.new(1, -220, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			TextSize = 13,
			Font = UIKit.FONT_LIGHT,
			TextColor3 = Color3.fromRGB(185, 185, 195),
			Text = item.Description,
			ZIndex = 23,
			Parent = row,
		})
		local owned = UIKit.text({
			Position = UDim2.fromOffset(76, 64),
			Size = UDim2.new(1, -220, 0, 14),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 12,
			Font = UIKit.FONT,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = C.Accent,
			ZIndex = 23,
			Parent = row,
		})
		local button = UIKit.button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(124, 52),
			Text = "",
			ZIndex = 23,
			Parent = row,
		}, function()
			buy(itemId)
		end)
		UIKit.gloss(button, 0.3)
		local price = UIKit.text({
			Position = UDim2.fromOffset(0, 5),
			Size = UDim2.new(1, 0, 0, 24),
			TextSize = 18,
			Font = UIKit.FONT_BLACK,
			ZIndex = 24,
			Parent = button,
		})
		local caption = UIKit.text({
			Position = UDim2.fromOffset(0, 29),
			Size = UDim2.new(1, 0, 0, 16),
			TextSize = 11,
			Font = UIKit.FONT,
			TextColor3 = Color3.fromRGB(215, 235, 215),
			ZIndex = 24,
			Parent = button,
		})
		-- Taser: boton de recarga con Robux (producto TaserRecharge)
		local recharge = nil
		if itemId == "Taser" and Config.DevProducts.TaserRecharge ~= 0 then
			recharge = UIKit.button({
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -140, 1, -8),
				Size = UDim2.fromOffset(96, 26),
				Text = string.format("+%d usos R$", Config.DevProducts.TaserRechargeUses),
				TextSize = 13,
				BackgroundColor3 = Color3.fromRGB(40, 130, 70),
				Visible = false,
				ZIndex = 23,
				Parent = row,
			}, function()
				Remotes.event("RequestBuyProduct"):FireServer("TaserRecharge")
			end)
		end
		rows[itemId] = {
			Frame = row,
			Owned = owned,
			Button = button,
			Price = price,
			Caption = caption,
			Stroke = rowStroke,
			Recharge = recharge,
		}
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

function ShopUI.Start()
	build()

	Remotes.event("OpenShop").OnClientEvent:Connect(ShopUI.Open)
	player:GetAttributeChangedSignal("Money"):Connect(refresh)
	for itemId in Config.ShopItems do
		player:GetAttributeChangedSignal("Item_" .. itemId):Connect(refresh)
	end
	for weaponId in Config.Weapons do
		player:GetAttributeChangedSignal("WeaponUses_" .. weaponId):Connect(refresh)
		player:GetAttributeChangedSignal(weaponId .. "Buys"):Connect(refresh)
	end

	-- Cerrar si te alejas del mostrador o mueres
	RunService.Heartbeat:Connect(function()
		if not window.Visible or not counterPosition then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0
			or (root.Position - counterPosition).Magnitude > Config.ShopRange + 2 then
			ShopUI.Close()
		end
	end)
end

return ShopUI
