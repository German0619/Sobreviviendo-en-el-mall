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
		-- Armas: un solo hueco (en la mochila); la misma se recarga, otra la reemplaza
		if item.Weapon then
			local def = Config.Weapons[itemId]
			local equipped = player:GetAttribute("Weapon") == itemId
			local uses = player:GetAttribute("WeaponUses") or 0
			local full = equipped and (def.Uses == nil or uses >= def.Uses)
			if equipped then
				row.Owned.Text = if def.Uses then string.format("Equipada · %d/%d usos", uses, def.Uses) else "Equipada"
			else
				row.Owned.Text = "Arma · reemplaza a la que llevas"
			end
			if full then
				row.Button.Text = "EQUIPADA"
				row.Button.BackgroundColor3 = C.ButtonOff
			else
				row.Button.Text = Util.formatMoney(item.Price)
				row.Button.BackgroundColor3 = if money >= item.Price then C.Button else C.ButtonOff
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
	-- Alto segun el numero de objetos (70 px por fila), con tope: el resto con scroll
	local height = math.min(130 + #Config.ShopOrder * 70, 560)
	window, content = UIKit.window(gui, "TIENDA DEL MALL", Vector2.new(480, height), ShopUI.Close)

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
		CanvasSize = UDim2.fromOffset(0, #Config.ShopOrder * 70),
		ZIndex = 22,
		Parent = content,
	})

	for i, itemId in Config.ShopOrder do
		local item = Config.ShopItems[itemId]
		local row = UIKit.make("Frame", {
			Position = UDim2.fromOffset(0, (i - 1) * 70),
			Size = UDim2.new(1, -10, 0, 62),
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
		UIKit.text({
			Position = UDim2.fromOffset(12, 28),
			Size = UDim2.new(1, -140, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 13,
			Font = UIKit.FONT_LIGHT,
			TextColor3 = C.Dim,
			Text = item.Description,
			ZIndex = 23,
			Parent = row,
		})
		local owned = UIKit.text({
			Position = UDim2.fromOffset(12, 44),
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
		rows[itemId] = { Owned = owned, Button = button }
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
	player:GetAttributeChangedSignal("Weapon"):Connect(refresh)
	player:GetAttributeChangedSignal("WeaponUses"):Connect(refresh)

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
