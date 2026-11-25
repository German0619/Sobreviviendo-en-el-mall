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

local function refresh()
	if not window then
		return
	end
	local money = player:GetAttribute("Money") or 0
	moneyLabel.Text = "Billetes: " .. Util.formatMoney(money)
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
				row.Button.Text = "LA LLEVAS"
				row.Button.BackgroundColor3 = C.ButtonOff
			else
				row.Button.Text = Util.formatMoney(price)
				row.Button.BackgroundColor3 = if money >= price then C.Button else C.ButtonOff
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
			row.Button.Text = if item.Unique then "TUYA" else "LLENO"
			row.Button.BackgroundColor3 = C.ButtonOff
		else
			row.Button.Text = Util.formatMoney(item.Price)
			row.Button.BackgroundColor3 = if money >= item.Price then C.Button else C.ButtonOff
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
		setStatus(message or "", result == true)
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

local ROW = 84 -- alto de cada fila de la lista (con su separacion)

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
	window, content = UIKit.window(gui, "TIENDA DEL MALL", Vector2.new(480, height), ShopUI.Close, true)

	moneyLabel = UIKit.text({
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Accent,
		ZIndex = 22,
		Parent = content,
	})

	-- Lista con scroll entre el dinero y la linea de estado
	local list = UIKit.make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -60),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.fromOffset(0, #Config.ShopOrder * ROW),
		ZIndex = 22,
		Parent = content,
	})

	for i, itemId in Config.ShopOrder do
		local item = Config.ShopItems[itemId]
		local row = UIKit.make("Frame", {
			Position = UDim2.fromOffset(0, (i - 1) * ROW),
			Size = UDim2.new(1, -10, 0, ROW - 8),
			BackgroundColor3 = C.Row,
			ZIndex = 22,
			Parent = list,
		}, { UIKit.corner(8) })
		local name = item.DisplayName
		UIKit.text({
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -140, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = name,
			ZIndex = 23,
			Parent = row,
		})
		-- Descripcion en hasta dos lineas
		UIKit.text({
			Position = UDim2.fromOffset(12, 28),
			Size = UDim2.new(1, -140, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			TextSize = 13,
			Font = UIKit.FONT_LIGHT,
			TextColor3 = C.Dim,
			Text = item.Description,
			ZIndex = 23,
			Parent = row,
		})
		local owned = UIKit.text({
			Position = UDim2.fromOffset(12, 58),
			Size = UDim2.new(1, -140, 0, 14),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 12,
			Font = UIKit.FONT_LIGHT,
			TextColor3 = C.Accent,
			ZIndex = 23,
			Parent = row,
		})
		local button = UIKit.button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(110, 36),
			ZIndex = 23,
			Parent = row,
		}, function()
			buy(itemId)
		end)
		-- Taser: boton de recarga con Robux (producto TaserRecharge)
		local recharge = nil
		if itemId == "Taser" and Config.DevProducts.TaserRecharge ~= 0 then
			recharge = UIKit.button({
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -126, 0.5, 0),
				Size = UDim2.fromOffset(96, 36),
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
		rows[itemId] = { Owned = owned, Button = button, Recharge = recharge }
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
