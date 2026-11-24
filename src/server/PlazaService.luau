--!strict
-- PlazaService: prepara la plaza del lobby (Workspace.Lobby, modelada en Studio).
--
-- * Pone un ProximityPrompt en cada puesto (tag LobbyStand). El prompt es nativo
--   de Roblox: se adapta solo a teclado, tactil y mando. El cliente escucha
--   ProximityPromptService.PromptTriggered y abre el panel del puesto.
-- * El lobby es una zona segura: sin dano y sin caidas fuera del mapa.
-- * Sobre cada jugador: su clase equipada (color de su rareza), su nombre y
--   un trofeo con su noche record. Reemplaza al nombre por defecto de Roblox.
--
-- Los cuadros de sala (LobbyRoomPad) los gestiona RoomService (Fase 2) y las
-- pantallas (LobbyLeaderboard) LeaderboardService (Fase 6).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)

local PlazaService = {}

local PROMPT_DISTANCE = 10
local FALL_LIMIT_Y = -50 -- por debajo de esto se devuelve al jugador al spawn

local function setupStand(stand: Instance)
	local promptPart = stand:FindFirstChild("PromptPart")
	if not promptPart or not promptPart:IsA("BasePart") then
		warn("[PlazaService] El puesto", stand:GetFullName(), "no tiene una parte 'PromptPart'")
		return
	end
	if promptPart:FindFirstChild("StandPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StandPrompt"
	prompt.ActionText = (stand:GetAttribute("ActionText") :: string?) or "Abrir"
	prompt.ObjectText = (stand:GetAttribute("ObjectText") :: string?) or ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Stand", stand:GetAttribute("Stand"))
	prompt.Parent = promptPart
end

local function overheadLabel(parent: Instance, name: string, height: number, y: number, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, height)
	l.Position = UDim2.fromScale(0, y)
	l.Font = font
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.4
	l.Parent = parent
	return l
end

-- Placa sobre la cabeza: clase, nombre y noche record.
local function buildOverhead(player: Player, character: Model, humanoid: Humanoid)
	local head = character:WaitForChild("Head", 10)
	if not head then
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local bb = Instance.new("BillboardGui")
	bb.Name = "Overhead"
	bb.Size = UDim2.fromScale(5, 1.9) -- en studs: se ve proporcionado en cualquier pantalla
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	bb.MaxDistance = 70
	bb.LightInfluence = 0
	bb.Adornee = head

	local classLabel = overheadLabel(bb, "Class", 0.26, 0, Enum.Font.GothamBold)
	local nameLabel = overheadLabel(bb, "PlayerName", 0.42, 0.26, Enum.Font.GothamBlack)
	nameLabel.Text = player.DisplayName
	local recordLabel = overheadLabel(bb, "Record", 0.26, 0.7, Enum.Font.GothamBold)
	recordLabel.TextColor3 = Color3.fromRGB(255, 210, 90)

	local function refresh()
		-- Tras un giro, no revelar la clase antes de que acabe la animacion del cliente
		local revealAt = player:GetAttribute("SpinRevealAt")
		if type(revealAt) == "number" then
			local wait = revealAt - workspace:GetServerTimeNow()
			if wait > 0 then
				task.delay(wait, function()
					if bb.Parent then
						refresh()
					end
				end)
				return
			end
		end
		local className = player:GetAttribute("EquippedClass")
		local class = if type(className) == "string" then Config.Classes[className] else nil
		local rarity = class and Config.Rarities[class.Rarity]
		classLabel.Text = if class then class.DisplayName else ""
		classLabel.TextColor3 = if rarity then rarity.Color else Color3.new(1, 1, 1)
		local best = player:GetAttribute("BestNight")
		recordLabel.Text = if type(best) == "number" and best > 0 then "🏆 Noche " .. best else "🏆 --"
		-- Pase VIP: etiqueta y nombre dorado
		local vip = player:GetAttribute("Pass_VIP") == true
		nameLabel.Text = if vip then "VIP · " .. player.DisplayName else player.DisplayName
		nameLabel.TextColor3 = if vip then Color3.fromRGB(255, 200, 60) else Color3.new(1, 1, 1)
	end
	refresh()

	local connections = {
		player:GetAttributeChangedSignal("EquippedClass"):Connect(refresh),
		player:GetAttributeChangedSignal("BestNight"):Connect(refresh),
		player:GetAttributeChangedSignal("Pass_VIP"):Connect(refresh),
	}
	bb.Destroying:Connect(function()
		for _, c in connections do
			c:Disconnect()
		end
	end)
	bb.Parent = character
end

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	-- Zona segura: nada hace dano en el lobby.
	local forceField = Instance.new("ForceField")
	forceField.Visible = false
	forceField.Parent = character
	humanoid.BreakJointsOnDeath = false

	buildOverhead(player, character, humanoid)
end

function PlazaService.Start()
	for _, stand in CollectionService:GetTagged(Tags.LobbyStand) do
		setupStand(stand)
	end
	CollectionService:GetInstanceAddedSignal(Tags.LobbyStand):Connect(setupStand)

	if not workspace:FindFirstChild("Lobby") then
		warn("[PlazaService] No hay Workspace.Lobby: la plaza se modela en Studio (place del lobby).")
	end

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			setupCharacter(player, character)
		end)
		if player.Character then
			task.spawn(setupCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	-- Si alguien cae fuera de la plaza, vuelve al spawn.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and root.Position.Y < FALL_LIMIT_Y then
					player:LoadCharacter()
				end
			end
		end
	end)
end

return PlazaService
