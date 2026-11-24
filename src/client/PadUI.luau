--!strict
-- PadUI (solo en el lobby): paneles de los cuadros de sala de la plaza.
--
--   * Cuadro libre: al subirte, "Crear sala" con Publica / Solo amigos
--     (el servidor la crea publica si no eliges a tiempo).
--   * Dentro de una sala: anfitrion, jugadores, cuenta atras, INICIAR PARTIDA
--     (solo el anfitrion) y el recordatorio "Salta para salir".
--
-- Todo el estado viene del servidor (PadService): el atributo PadId del jugador
-- y los atributos del modelo del cuadro (State, Count, Max, Public, HostName,
-- HostUserId, StartsAt). Tamanos en Scale con limites en pixeles.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)

local PadUI = {}

local player = Players.LocalPlayer

local COLORS = {
	Panel = Color3.fromRGB(18, 20, 32),
	Text = Color3.fromRGB(255, 255, 255),
	Dim = Color3.fromRGB(185, 188, 210),
	Public = Color3.fromRGB(50, 120, 200),
	Friends = Color3.fromRGB(130, 70, 190),
	Start = Color3.fromRGB(60, 170, 90),
}

local function corner(parent: Instance, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = parent
end

local function textLabel(parent: Instance, name: string, size: UDim2, position: UDim2, maxSize: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color or COLORS.Text
	l.TextScaled = true
	l.Text = ""
	l.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = 9
	limit.Parent = l
	return l
end

local function button(parent: Instance, name: string, text: string, color: Color3, size: UDim2, position: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = color
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBlack
	b.Text = text
	b.TextColor3 = COLORS.Text
	b.TextScaled = true
	b.Parent = parent
	corner(b, 0.25)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 22
	limit.MinTextSize = 10
	limit.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.18, 0)
	pad.PaddingBottom = UDim.new(0.18, 0)
	pad.Parent = b
	return b
end

-- Panel abajo al centro, del mismo tamano en todos los dispositivos (proporcional).
local function panel(gui: ScreenGui, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 1)
	f.Position = UDim2.new(0.5, 0, 1, -14)
	f.Size = UDim2.fromScale(0.42, 0.24)
	f.BackgroundColor3 = COLORS.Panel
	f.BackgroundTransparency = 0.15
	f.Visible = false
	f.Parent = gui
	corner(f, 0.12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.7
	stroke.Thickness = 1.5
	stroke.Parent = f
	local limits = Instance.new("UISizeConstraint")
	limits.MinSize = Vector2.new(260, 118)
	limits.MaxSize = Vector2.new(440, 170)
	limits.Parent = f
	return f
end

local function findPad(id: number): Model?
	for _, model in CollectionService:GetTagged(Tags.LobbyRoomPad) do
		if model:GetAttribute("PadId") == id and model:IsA("Model") then
			return model
		end
	end
	return nil
end

function PadUI.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PadUI"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 3
	gui.Parent = player:WaitForChild("PlayerGui")

	------------------------------------------------------------------
	-- Elegir tipo de sala
	------------------------------------------------------------------
	local choose = panel(gui, "Choose")
	textLabel(choose, "Title", UDim2.fromScale(0.9, 0.2), UDim2.fromScale(0.05, 0.07), 24).Text = "Crear sala"
	local choosing = false
	local chooseEndsAt = 0
	local publicButton = button(choose, "Public", "🌐 Pública", COLORS.Public, UDim2.fromScale(0.43, 0.36), UDim2.fromScale(0.05, 0.32))
	local friendsButton = button(choose, "Friends", "🔒 Solo amigos", COLORS.Friends, UDim2.fromScale(0.43, 0.36), UDim2.fromScale(0.52, 0.32))
	local chooseHint = textLabel(choose, "Hint", UDim2.fromScale(0.9, 0.16), UDim2.fromScale(0.05, 0.76), 15, COLORS.Dim)

	local function pick(isPublic: boolean)
		if not choosing then
			return
		end
		choosing = false
		choose.Visible = false
		task.spawn(function()
			Remotes.func("RequestPadCreate"):InvokeServer(isPublic)
		end)
	end
	publicButton.Activated:Connect(function()
		pick(true)
	end)
	friendsButton.Activated:Connect(function()
		pick(false)
	end)

	Remotes.event("PadPrompt").OnClientEvent:Connect(function(padId: number?)
		choosing = padId ~= nil
		chooseEndsAt = os.clock() + Config.Rooms.PadChooseSeconds
		choose.Visible = choosing
	end)

	------------------------------------------------------------------
	-- Tu sala
	------------------------------------------------------------------
	local room = panel(gui, "Room")
	local roomTitle = textLabel(room, "Title", UDim2.fromScale(0.9, 0.2), UDim2.fromScale(0.05, 0.06), 22)
	local roomInfo = textLabel(room, "Info", UDim2.fromScale(0.9, 0.16), UDim2.fromScale(0.05, 0.28), 17, COLORS.Dim)
	local startButton = button(room, "Start", "INICIAR PARTIDA", COLORS.Start, UDim2.fromScale(0.6, 0.3), UDim2.fromScale(0.2, 0.47))
	local roomHint = textLabel(room, "Hint", UDim2.fromScale(0.9, 0.14), UDim2.fromScale(0.05, 0.81), 14, COLORS.Dim)
	roomHint.Text = "Salta para salir de la sala"

	local starting = false
	startButton.Activated:Connect(function()
		if starting then
			return
		end
		starting = true
		task.spawn(function()
			Remotes.func("RequestStartRoom"):InvokeServer()
			starting = false
		end)
	end)

	------------------------------------------------------------------
	-- Actualizacion
	------------------------------------------------------------------
	task.spawn(function()
		while gui.Parent do
			-- Panel de eleccion: cuenta atras hasta que se crea publica sola
			if choosing then
				local left = math.max(0, math.ceil(chooseEndsAt - os.clock()))
				chooseHint.Text = string.format("Salta para salir · pública en %d s", left)
			end

			local padId = player:GetAttribute("PadId")
			local model = if type(padId) == "number" and not choosing then findPad(padId) else nil
			local state = model and model:GetAttribute("State")
			if model and (state == "Open" or state == "Starting") then
				local isPublic = model:GetAttribute("Public") == true
				local count = model:GetAttribute("Count") or 0
				local max = model:GetAttribute("Max") or Config.MaxPlayersPerRoom
				roomTitle.Text = string.format("Sala de %s  %s", tostring(model:GetAttribute("HostName") or "?"), if isPublic then "🌐" else "🔒")
				if state == "Starting" then
					roomInfo.Text = string.format("%d/%d jugadores · ¡viajando al mall!", count, max)
				else
					local startsAt = model:GetAttribute("StartsAt") or 0
					local left = math.max(0, math.ceil(startsAt - Workspace:GetServerTimeNow()))
					roomInfo.Text = string.format("%d/%d jugadores · empieza en %d s", count, max, left)
				end
				local isHost = model:GetAttribute("HostUserId") == player.UserId
				startButton.Visible = isHost and state == "Open"
				roomHint.Position = if startButton.Visible then UDim2.fromScale(0.05, 0.81) else UDim2.fromScale(0.05, 0.6)
				room.Visible = true
			else
				room.Visible = false
			end
			task.wait(0.2)
		end
	end)
end

return PadUI
