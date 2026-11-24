--!strict
-- HUD del lobby: contador de diamantes (con "+" para comprar) en el lateral
-- derecho y botones TIENDA y LOGROS en el lateral izquierdo. (Las salas no
-- tienen boton: se entra subiendose a un cuadro de la plaza.) Tambien abre el panel de cada puesto de la plaza.
--
-- Todo se dimensiona en Scale con limites en pixeles (UISizeConstraint), y el
-- ScreenGui respeta las zonas seguras (notch, barra de Roblox), asi que se ve
-- igual de proporcionado en PC, telefono, tableta y consola.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local LobbyPanels = require(script.Parent.LobbyPanels)
-- Paneles que ya existian (se rehacen en formato nativo en sus fases)
local ClassPanel = require(script.Parent.ClassPanel)
local ShopPanel = require(script.Parent.ShopPanel)
local AchievementsPanel = require(script.Parent.AchievementsPanel)

local LobbyHUD = {}

local player = Players.LocalPlayer

local COLORS = {
	Panel = Color3.fromRGB(18, 20, 32),
	Stroke = Color3.fromRGB(255, 255, 255),
	Text = Color3.fromRGB(255, 255, 255),
	Diamond = Color3.fromRGB(120, 220, 255),
}

local function corner(parent: Instance, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = parent
end

local function stroke(parent: Instance, transparency: number)
	local s = Instance.new("UIStroke")
	s.Color = COLORS.Stroke
	s.Transparency = transparency
	s.Thickness = 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, maxTextSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Enum.Font.GothamBold
	l.Text = text
	l.TextColor3 = COLORS.Text
	l.TextScaled = true
	l.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxTextSize
	limit.MinTextSize = 8
	limit.Parent = l
	return l
end

local function formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

local function buildDiamondCounter(gui: ScreenGui)
	-- Lateral derecho, por encima del centro (lejos del boton de salto tactil)
	local frame = Instance.new("Frame")
	frame.Name = "Diamonds"
	frame.AnchorPoint = Vector2.new(1, 0.5)
	frame.Position = UDim2.new(1, -10, 0.36, 0)
	frame.Size = UDim2.fromScale(0.2, 0.08)
	frame.BackgroundColor3 = COLORS.Panel
	frame.BackgroundTransparency = 0.25
	frame.Parent = gui
	corner(frame, 0.5)
	stroke(frame, 0.7)

	local limits = Instance.new("UISizeConstraint")
	limits.MinSize = Vector2.new(130, 36)
	limits.MaxSize = Vector2.new(240, 54)
	limits.Parent = frame

	label(frame, "💎", UDim2.fromScale(0.22, 0.8), UDim2.fromScale(0.03, 0.1), 32)
	local amount = label(frame, "0", UDim2.fromScale(0.5, 0.7), UDim2.fromScale(0.26, 0.15), 30)
	amount.Name = "Amount"
	amount.TextXAlignment = Enum.TextXAlignment.Left
	amount.TextColor3 = COLORS.Diamond

	-- "+" abre la tienda (paquetes de diamantes)
	local plus = Instance.new("TextButton")
	plus.Name = "Buy"
	plus.AnchorPoint = Vector2.new(1, 0.5)
	plus.Position = UDim2.fromScale(0.97, 0.5)
	plus.Size = UDim2.fromScale(0.8, 0.8)
	plus.BackgroundColor3 = Color3.fromRGB(70, 190, 90)
	plus.Font = Enum.Font.GothamBlack
	plus.Text = "+"
	plus.TextColor3 = COLORS.Text
	plus.TextScaled = true
	plus.Parent = frame
	corner(plus, 0.3)
	local plusAspect = Instance.new("UIAspectRatioConstraint")
	plusAspect.AspectRatio = 1
	plusAspect.Parent = plus
	plus.Activated:Connect(function()
		LobbyPanels.open("Shop")
	end)

	local function refresh()
		amount.Text = formatNumber((player:GetAttribute("Diamonds") :: number?) or 0)
	end
	player:GetAttributeChangedSignal("Diamonds"):Connect(refresh)
	refresh()
end

local SIDE_BUTTONS = {
	{ Id = "Shop", Icon = "🛒", Text = "TIENDA" },
	{ Id = "Achievements", Icon = "🏆", Text = "LOGROS" },
	-- Sin boton de salas: se entra subiendose a un cuadro de la plaza (PadUI).
}

local function buildSideButtons(gui: ScreenGui)
	local rail = Instance.new("Frame")
	rail.Name = "SideButtons"
	rail.AnchorPoint = Vector2.new(0, 0.5)
	rail.Position = UDim2.new(0, 10, 0.5, 0)
	rail.Size = UDim2.fromScale(0.2, 0.5)
	rail.BackgroundTransparency = 1
	rail.Parent = gui

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0.03, 0)
	list.Parent = rail

	for i, def in SIDE_BUTTONS do
		local button = Instance.new("TextButton")
		button.Name = def.Id
		button.LayoutOrder = i
		button.Text = ""
		button.AutoButtonColor = true
		button.Size = UDim2.fromScale(1, 0.28)
		button.BackgroundColor3 = COLORS.Panel
		button.BackgroundTransparency = 0.25
		button.Parent = rail
		corner(button, 0.2)
		stroke(button, 0.7)

		-- Cuadrado, entre 48 px (minimo tactil) y 80 px
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.Parent = button
		local limits = Instance.new("UISizeConstraint")
		limits.MinSize = Vector2.new(48, 48)
		limits.MaxSize = Vector2.new(80, 80)
		limits.Parent = button

		label(button, def.Icon, UDim2.fromScale(0.8, 0.5), UDim2.fromScale(0.1, 0.08), 40)
		label(button, def.Text, UDim2.fromScale(0.9, 0.24), UDim2.fromScale(0.05, 0.66), 16)

		-- Aviso "!" (lo enciende la Fase 5 con el atributo HasClaimable del boton)
		local badge = Instance.new("TextLabel")
		badge.Name = "Badge"
		badge.Visible = false
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.fromScale(0.92, 0.08)
		badge.Size = UDim2.fromScale(0.3, 0.3)
		badge.BackgroundColor3 = Color3.fromRGB(230, 50, 60)
		badge.Font = Enum.Font.GothamBlack
		badge.Text = "!"
		badge.TextColor3 = COLORS.Text
		badge.TextScaled = true
		badge.Parent = button
		corner(badge, 0.5)

		button.Activated:Connect(function()
			LobbyPanels.open(def.Id)
		end)
	end
end

function LobbyHUD.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "LobbyHUD"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	buildDiamondCounter(gui)
	buildSideButtons(gui)

	-- Un panel a la vez
	local function closeAll()
		ClassPanel.Close()
		ShopPanel.Close()
		AchievementsPanel.Close()
	end
	LobbyPanels.register("Classes", function()
		closeAll()
		ClassPanel.Open()
	end)
	LobbyPanels.register("Shop", function()
		closeAll()
		ShopPanel.Open()
	end)
	LobbyPanels.register("Achievements", function()
		closeAll()
		AchievementsPanel.Open()
	end)

	-- "!" en LOGROS cuando hay un logro o el bono VIP por reclamar
	local rail = gui:FindFirstChild("SideButtons")
	local achievementsButton = rail and rail:FindFirstChild("Achievements")
	local badge = achievementsButton and achievementsButton:FindFirstChild("Badge") :: GuiObject?
	if badge then
		local function refreshBadge()
			badge.Visible = AchievementsPanel.HasClaimable()
		end
		AchievementsPanel.Changed.Event:Connect(refreshBadge)
		refreshBadge()
	end

	-- Puestos de la plaza (ProximityPrompt creado por PlazaService)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local stand = prompt:GetAttribute("Stand")
		if type(stand) == "string" then
			LobbyPanels.open(stand)
		end
	end)

	-- Pararse sobre el circulo de luz de un puesto tambien abre su panel
	-- (una vez por cada vez que entras al circulo).
	task.spawn(function()
		local inside: { [Instance]: boolean } = {}
		while gui.Parent do
			task.wait(0.2)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			for _, stand in CollectionService:GetTagged(Tags.LobbyStand) do
				local glow = stand:FindFirstChild("FloorGlow")
				local standId = stand:GetAttribute("Stand")
				if glow and glow:IsA("BasePart") and type(standId) == "string" then
					local onIt = false
					if root then
						local offset = root.Position - glow.Position
						local radius = math.max(glow.Size.Y, glow.Size.Z) / 2 -- cilindro tumbado: su eje es X
						onIt = Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius and math.abs(offset.Y) < 6
					end
					if onIt and not inside[stand] then
						LobbyPanels.open(standId)
					end
					inside[stand] = onIt
				end
			end
		end
	end)

	-- Avisos del servidor (TravelService, compras...) como notificacion nativa
	Remotes.event("Notify").OnClientEvent:Connect(function(text: string)
		LobbyPanels.notify("Plaza Luna", text, 5)
	end)
end

return LobbyHUD
