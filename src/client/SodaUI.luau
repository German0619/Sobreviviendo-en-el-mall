-- SodaUI (solo en el mall): selector de la soda a eleccion (maquina premium, tecla R).
-- Eliges el efecto ANTES de pagar (no es aleatorio). Si tienes fichas de soda
-- se usa una; si no, se compra con Robux. Se cierra si te alejas o mueres.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer
local C = UIKit.COLORS

local SodaUI = {}

local ROW = 58
local MAX_DISTANCE = 12

local window, footer
local buttons = {}
local machinePosition: Vector3? = nil
local priceText = "Robux"

local function refresh()
	local tokens = player:GetAttribute("SodaTokens") or 0
	for _, button in buttons do
		button.Text = if tokens > 0 then "Usar ficha" else priceText
	end
	footer.Text = if tokens > 0
		then string.format("Tienes %d ficha(s) de soda: se usa una en vez de pagar.", tokens)
		else string.format("Dura %.1fx más que una soda normal.", Config.ChoiceSoda.DurationMultiplier)
end

function SodaUI.Open(position: Vector3)
	machinePosition = position
	refresh()
	window.Visible = true
end

function SodaUI.Close()
	window.Visible = false
	machinePosition = nil
end

local function build()
	local gui = UIKit.make("ScreenGui", {
		Name = "SodaUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
		Parent = player:WaitForChild("PlayerGui"),
	})
	UIKit.adapt(gui) -- escala segun la pantalla y respeta el notch
	local effects = Config.ChoiceSoda.Effects
	local content
	window, content = UIKit.window(
		gui,
		string.upper(Config.ChoiceSoda.DisplayName),
		Vector2.new(460, 150 + #effects * ROW),
		SodaUI.Close
	)

	UIKit.text({
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		Font = UIKit.FONT_LIGHT,
		TextColor3 = C.Dim,
		Text = "Elige el efecto que quieres. No es aleatoria: recibes el que eliges.",
		ZIndex = 22,
		Parent = content,
	})

	for i, effectId in effects do
		local effect = Config.SodaEffects[effectId]
		local row = UIKit.make("Frame", {
			Position = UDim2.fromOffset(0, 28 + (i - 1) * ROW),
			Size = UDim2.new(1, 0, 0, ROW - 6),
			BackgroundColor3 = C.Row,
			ZIndex = 22,
			Parent = content,
		}, { UIKit.corner(8) })
		UIKit.text({
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -150, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 16,
			TextColor3 = C.Good,
			Text = effect.DisplayName,
			ZIndex = 23,
			Parent = row,
		})
		UIKit.text({
			Position = UDim2.fromOffset(12, 26),
			Size = UDim2.new(1, -150, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 13,
			Font = UIKit.FONT_LIGHT,
			TextColor3 = C.Dim,
			Text = string.format(
				"%s  ·  %d s",
				effect.Description or "",
				math.floor(effect.Duration * Config.ChoiceSoda.DurationMultiplier)
			),
			ZIndex = 23,
			Parent = row,
		})
		local button = UIKit.button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(120, 34),
			Text = priceText,
			ZIndex = 23,
			Parent = row,
		}, function()
			Remotes.event("RequestChoiceSoda"):FireServer(effectId)
			SodaUI.Close()
		end)
		table.insert(buttons, button)
	end

	footer = UIKit.text({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 13,
		Font = UIKit.FONT_LIGHT,
		TextColor3 = C.Accent,
		Text = "",
		ZIndex = 22,
		Parent = content,
	})
end

function SodaUI.Start()
	build()

	-- Precio real del producto (si ya esta configurado)
	local productId = Config.DevProducts.PremiumSoda
	if productId ~= 0 then
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
			end)
			if ok and info and type(info.PriceInRobux) == "number" then
				priceText = "R$ " .. tostring(info.PriceInRobux)
				refresh()
			end
		end)
	end

	Remotes.event("OpenSodaPicker").OnClientEvent:Connect(SodaUI.Open)
	player:GetAttributeChangedSignal("SodaTokens"):Connect(refresh)

	-- Cerrar si te alejas de la maquina o mueres
	RunService.Heartbeat:Connect(function()
		if not window.Visible or not machinePosition then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 or (root.Position - machinePosition).Magnitude > MAX_DISTANCE then
			SodaUI.Close()
		end
	end)
end

return SodaUI
