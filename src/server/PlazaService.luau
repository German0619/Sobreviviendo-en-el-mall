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
local EntityModels = require(Shared.EntityModels)

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

-- Imagenes del agua (assets/lobby/generate.py)
local WATER_STREAK = "rbxassetid://102168890675191"
local WATER_SPLASH = "rbxassetid://86916911366925"
local WATER_RING = "rbxassetid://101709116609242"
local POUR_REACH = 3.3 -- a que distancia del centro cae el agua en el plato

local function seq(a: number, b: number, c: number?, d: number?): NumberSequence
	local keys = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(if c then 0.85 else 1, b) }
	if c and d then
		keys[3] = NumberSequenceKeypoint.new(1, d)
	end
	return NumberSequence.new(keys)
end

-- La estatua vierte agua desde las manos: un caño (Beam con textura de agua que corre)
-- que cae en arco al plato, con salpicadura y ondas donde cae. El plato y su agua estan
-- modelados en el place (Fountain: Bowl es el pedestal de la estatua; Water.BowlSurface).
local function pourFromHands(fountain: Instance, feet: Vector3, forward: Vector3)
	local flat = Vector3.new(forward.X, 0, forward.Z)
	forward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	local surface = fountain:FindFirstChild("BowlSurface", true)
	local waterY = if surface and surface:IsA("BasePart") then surface.Position.Y else feet.Y - 0.9
	local hands = feet + Vector3.new(0, EntityModels.STATUE_HANDS_Y + 0.1, 0) + forward * 1.15
	local land = Vector3.new(feet.X, waterY, feet.Z) + forward * POUR_REACH

	local holder = Instance.new("Part")
	holder.Name = "FountainJet"
	holder.Size = Vector3.new(0.3, 0.1, 0.3)
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Position = land
	local function attachment(pos: Vector3, axis: Vector3): Attachment
		local a = Instance.new("Attachment")
		a.Parent = holder -- (antes de WorldCFrame: si no, la posicion queda relativa a nada)
		local right = axis:Cross(Vector3.yAxis)
		a.WorldCFrame = CFrame.fromMatrix(pos, axis.Unit, if right.Magnitude > 0.01 then right.Unit:Cross(axis.Unit) else Vector3.zAxis)
		return a
	end
	-- dos hilos que se cruzan un poco: un chorro con cuerpo, no una linea
	for i, offset in { -0.12, 0.12 } do
		local side = forward:Cross(Vector3.yAxis) * offset
		local beam = Instance.new("Beam")
		beam.Name = "Pour" .. i
		beam.Attachment0 = attachment(hands + side, forward + Vector3.new(0, 0.35, 0))
		beam.Attachment1 = attachment(land - side * 2, Vector3.new(0, -1, 0) + forward * 0.25)
		beam.CurveSize0 = 1.6
		beam.CurveSize1 = 2.4
		beam.Width0 = 0.32
		beam.Width1 = 0.5
		beam.FaceCamera = true
		beam.Segments = 24
		beam.Texture = WATER_STREAK
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = 2.2
		beam.TextureSpeed = 3.6 + i * 0.4
		beam.LightEmission = 0.25
		beam.LightInfluence = 0.6
		beam.Color = ColorSequence.new(Color3.fromRGB(225, 242, 255))
		beam.Transparency = seq(0.15, 0.3, 0.3, 0.7)
		beam.Parent = holder
	end
	local splash = Instance.new("ParticleEmitter")
	splash.Name = "Splash"
	splash.Texture = WATER_SPLASH
	splash.Rate = 45
	splash.Lifetime = NumberRange.new(0.25, 0.45)
	splash.Speed = NumberRange.new(2, 3.5)
	splash.SpreadAngle = Vector2.new(40, 40)
	splash.Acceleration = Vector3.new(0, -30, 0)
	splash.Size = seq(0.22, 0.08)
	splash.Transparency = seq(0.2, 1)
	splash.LightEmission = 0.2
	splash.EmissionDirection = Enum.NormalId.Top
	splash.Parent = holder
	local ripple = Instance.new("ParticleEmitter")
	ripple.Name = "Ripple"
	ripple.Texture = WATER_RING
	ripple.Rate = 3
	ripple.Lifetime = NumberRange.new(1, 1.3)
	ripple.Speed = NumberRange.new(0.01)
	ripple.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	ripple.EmissionDirection = Enum.NormalId.Top
	ripple.Size = seq(0.3, 2.4)
	ripple.Transparency = seq(0.3, 1)
	ripple.LightEmission = 0.3
	ripple.Parent = holder
	holder.Parent = fountain
end

-- La Estatua de la fuente (la misma que despierta en el mall) sobre el plato de la
-- fuente de la plaza, con la luna flotando sobre su casco y vertiendo agua.
local function placeFountainStatue()
	local lobby = workspace:FindFirstChild("Lobby")
	local fountain = lobby and lobby:FindFirstChild("Fountain", true)
	local bowl = fountain and fountain:FindFirstChild("Bowl")
	if not fountain or not bowl or not bowl:IsA("BasePart") or fountain:FindFirstChild("FountainStatue") then
		return
	end
	-- Cara superior del plato (cilindro tumbado: su grosor es el eje X)
	local thickness = if bowl.Shape == Enum.PartType.Cylinder then bowl.Size.X else bowl.Size.Y
	local feet = Vector3.new(bowl.Position.X, bowl.Position.Y + thickness / 2, bowl.Position.Z)
	local statue = EntityModels.statue()
	statue.Name = "FountainStatue"
	-- Mirando hacia el centro de la plaza (o hacia +Z si no hay referencia)
	local spawnPart = lobby:FindFirstChildWhichIsA("SpawnLocation", true)
	local lookAt = if spawnPart then Vector3.new(spawnPart.Position.X, feet.Y, spawnPart.Position.Z) else feet + Vector3.new(0, 0, 1)
	if (lookAt - feet).Magnitude < 0.5 then
		lookAt = feet + Vector3.new(0, 0, 1)
	end
	-- El frente del modelo es -Z: CFrame.lookAt ya mira hacia -Z
	EntityModels.placeAt(statue, CFrame.lookAt(feet, lookAt), fountain)
	CollectionService:AddTag(statue, Tags.FountainStatue)

	-- La luna (y su sombra) flota sobre el casco de la estatua
	local moon = fountain:FindFirstChild("Moon")
	if moon and moon:IsA("BasePart") then
		local target = feet + Vector3.new(0, EntityModels.STATUE_TOP_Y + moon.Size.Y * 0.5, 0)
		local delta = target - moon.Position
		for _, name in { "Moon", "MoonShade" } do
			local p = fountain:FindFirstChild(name)
			if p and p:IsA("BasePart") then
				p.CFrame += delta
			end
		end
	end

	pourFromHands(fountain, feet, (lookAt - feet).Unit)
end

function PlazaService.Start()
	placeFountainStatue()
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
