-- PadService (solo en el lobby): las salas se arman SUBIENDOSE a los cuadros
-- de la plaza (tag LobbyRoomPad). No hay otra forma de crear o unirse a una sala.
--
--   Cuadro libre  -> el primero que se sube elige "Publica" o "Solo amigos"
--                    (Config.Rooms.PadChooseSeconds; si no elige, queda publica).
--   Sala abierta  -> los demas se unen al subirse. Si es solo amigos y no eres
--                    amigo del anfitrion, o esta llena, el cuadro te deja afuera.
--   Dentro        -> los bordes luminosos (Glow) son una barrera SOLO para los
--                    miembros: no se sale caminando, solo saltando. Salir del
--                    cuadro = salir de la sala.
--   Inicio        -> el anfitrion pulsa INICIAR PARTIDA, la sala se llena, o
--                    pasan Config.Rooms.PadStartSeconds. Todos viajan juntos al mall.
--
-- Por debajo usa LobbyService (servidor reservado, MemoryStore y teleports),
-- asi que en el mall la sala llega igual que siempre (RoomService).
-- El estado de cada cuadro se publica en atributos del modelo (State, Count,
-- Max, Public, HostName, StartsAt) y en su cartel flotante.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)

local LobbyService = require(script.Parent.LobbyService)

local PadService = {}

local TICK = 0.25
local INSIDE = 7.4 -- media anchura util del cuadro de 16 studs (las paredes estan en +-7.85)
local HEIGHT = 10 -- altura del volumen del cuadro (saltar dentro no te saca)
local EJECT_DISTANCE = 11 -- a cuanto del centro se deja a quien no puede entrar
local WALL_GROUP = "LobbyPadWall"
local MEMBER_GROUP = "LobbyRoomMember"
local MAX = Config.MaxPlayersPerRoom

local COLORS = {
	Free = Color3.fromRGB(235, 240, 255),
	Public = Color3.fromRGB(120, 200, 255),
	Friends = Color3.fromRGB(190, 120, 255),
	Starting = Color3.fromRGB(255, 210, 90),
}

type Pad = {
	Id: number,
	Model: Model,
	Base: BasePart,
	State: string, -- "Free" | "Choosing" | "Creating" | "Open" | "Starting"
	Chooser: Player?,
	ChooseEndsAt: number,
	RoomId: string?,
	Public: boolean,
	Host: Player?,
	Members: { Player },
	StartsAt: number,
	Starting: boolean, -- hay un intento de inicio en curso
}

local pads: { Pad } = {}
local padOf: { [Player]: Pad } = {} -- cuadro del que es miembro (o en el que esta eligiendo)
local busy: { [Player]: boolean } = {} -- uniendose (hay llamadas que esperan)
local lastWarn: { [Player]: number } = {}
local friendCache: { [string]: boolean } = {}
local collisionConn: { [Player]: RBXScriptConnection } = {}

----------------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------------

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind or "info")
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function isInside(pad: Pad, position: Vector3): boolean
	local p = pad.Base.CFrame:PointToObjectSpace(position)
	return math.abs(p.X) <= INSIDE and math.abs(p.Z) <= INSIDE and p.Y > -2 and p.Y < HEIGHT
end

local function isOnPad(pad: Pad, player: Player): boolean
	local root = rootOf(player)
	return root ~= nil and isInside(pad, root.Position)
end

local function isFriend(player: Player, hostUserId: number): boolean
	if player.UserId == hostUserId then
		return true
	end
	local key = player.UserId .. ":" .. hostUserId
	if friendCache[key] == nil then
		local ok, result = pcall(function()
			return player:IsFriendsWith(hostUserId)
		end)
		if not ok then
			return false -- sin cache: se vuelve a preguntar la proxima vez
		end
		friendCache[key] = result == true
	end
	return friendCache[key]
end

-- Los miembros chocan con los bordes del cuadro; el resto los atraviesa.
local function setBlocked(player: Player, blocked: boolean)
	local conn = collisionConn[player]
	if conn then
		conn:Disconnect()
		collisionConn[player] = nil
	end
	local character = player.Character
	if not character then
		return
	end
	local group = if blocked then MEMBER_GROUP else "Default"
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
	if blocked then
		collisionConn[player] = character.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				d.CollisionGroup = MEMBER_GROUP
			end
		end)
	end
end

-- Deja al jugador justo fuera del cuadro, por el lado mas cercano.
local function eject(pad: Pad, player: Player, message: string)
	local root = rootOf(player)
	if root then
		local rel = pad.Base.CFrame:PointToObjectSpace(root.Position)
		local offset = if math.abs(rel.X) > math.abs(rel.Z)
			then Vector3.new(math.sign(rel.X) * EJECT_DISTANCE, 3, 0)
			else Vector3.new(0, 3, (if rel.Z == 0 then 1 else math.sign(rel.Z)) * EJECT_DISTANCE)
		local target = pad.Base.CFrame:PointToWorldSpace(offset)
		root.CFrame = CFrame.new(target) * root.CFrame.Rotation
	end
	local last = lastWarn[player]
	if not last or os.clock() - last > 3 then
		lastWarn[player] = os.clock()
		notify(player, message, "bad")
	end
end

----------------------------------------------------------------------
-- Miembros
----------------------------------------------------------------------

local function claim(pad: Pad, player: Player)
	padOf[player] = pad
	player:SetAttribute("PadId", pad.Id)
	setBlocked(player, true)
end

local function release(player: Player)
	padOf[player] = nil
	busy[player] = nil
	if player.Parent then
		player:SetAttribute("PadId", nil)
		setBlocked(player, false)
	end
end

local function removeMember(pad: Pad, player: Player)
	local i = table.find(pad.Members, player)
	if i then
		table.remove(pad.Members, i)
	end
	if padOf[player] == pad then
		release(player)
	end
	-- Si se va el anfitrion, lo es el siguiente que llego (igual que LobbyService)
	if pad.Host == player then
		pad.Host = pad.Members[1]
	end
end

local function resetPad(pad: Pad)
	if pad.Chooser then
		Remotes.event("PadPrompt"):FireClient(pad.Chooser, nil)
		if padOf[pad.Chooser] == pad then
			release(pad.Chooser)
		end
	end
	for _, member in table.clone(pad.Members) do
		removeMember(pad, member)
	end
	pad.State = "Free"
	pad.Chooser = nil
	pad.RoomId = nil
	pad.Public = true
	pad.Host = nil
	pad.Members = {}
	pad.StartsAt = math.huge
	pad.Starting = false
end

----------------------------------------------------------------------
-- Crear, unirse, iniciar
----------------------------------------------------------------------

local function createRoom(pad: Pad, isPublic: boolean): (boolean, string)
	local host = pad.Chooser
	if pad.State ~= "Choosing" or not host then
		return false, "Ya no puedes crear la sala en este cuadro."
	end
	pad.State = "Creating"
	pad.Public = isPublic
	Remotes.event("PadPrompt"):FireClient(host, nil)

	local ok, message = LobbyService.CreateRoom(host, isPublic, nil)
	local roomId = if ok then LobbyService.GetPartyId(host) else nil

	if not ok or not roomId or pad.Chooser ~= host or not host.Parent then
		if ok and roomId and host.Parent then
			LobbyService.LeaveRoom(host)
		end
		if host.Parent then
			notify(host, if ok then "Saliste del cuadro antes de crear la sala." else message, "bad")
		end
		pad.Chooser = nil
		release(host)
		resetPad(pad)
		return false, message
	end

	pad.Chooser = nil
	pad.RoomId = roomId
	pad.Host = host
	pad.Members = { host }
	pad.State = "Open"
	pad.StartsAt = now() + Config.Rooms.PadStartSeconds
	notify(
		host,
		(if isPublic then "Sala pública creada." else "Sala solo para amigos creada.") .. " Salta para salir.",
		"good"
	)
	return true, "Sala creada."
end

local function startPad(pad: Pad): (boolean, string)
	local roomId = pad.RoomId
	if pad.State ~= "Open" or not roomId or pad.Starting then
		return false, "La sala no se puede iniciar ahora."
	end
	pad.Starting = true
	local ok, message = LobbyService.StartById(roomId)
	pad.Starting = false
	if pad.RoomId ~= roomId then
		return false, "La sala ya no existe."
	end
	if ok then
		pad.State = "Starting"
	else
		-- En Studio no hay teleports: se avisa y la cuenta atras vuelve a empezar
		pad.StartsAt = now() + Config.Rooms.PadStartSeconds
	end
	for _, member in pad.Members do
		notify(member, message, if ok then "good" else "bad")
	end
	return ok, message
end

local function tryJoin(pad: Pad, player: Player)
	local roomId = pad.RoomId
	local host = pad.Host
	if not roomId or not host then
		return
	end
	busy[player] = true
	task.spawn(function()
		if not pad.Public and not isFriend(player, host.UserId) then
			busy[player] = nil
			eject(pad, player, "Esta sala es solo para amigos de " .. host.DisplayName .. ".")
			return
		end
		-- Puede haber cambiado algo mientras se esperaba
		if pad.RoomId ~= roomId or pad.State ~= "Open" or padOf[player] or not isOnPad(pad, player) then
			busy[player] = nil
			return
		end
		if #pad.Members >= MAX then
			busy[player] = nil
			eject(pad, player, "La sala está llena.")
			return
		end
		local ok, message = LobbyService.JoinRoomById(player, roomId)
		busy[player] = nil
		if not ok then
			eject(pad, player, message)
			return
		end
		if pad.RoomId ~= roomId then
			LobbyService.LeaveRoom(player) -- el cuadro cambio de sala mientras entraba
			return
		end
		table.insert(pad.Members, player)
		claim(pad, player)
		notify(player, "Entraste a la sala de " .. (if pad.Host then pad.Host.DisplayName else "?") .. ". Salta para salir.", "good")
		-- Llena: LobbyService la inicia sola (fuera de Studio)
		if #pad.Members >= MAX and not RunService:IsStudio() then
			pad.State = "Starting"
		end
	end)
end

local function onNewcomer(pad: Pad, player: Player)
	if pad.State == "Free" then
		pad.State = "Choosing"
		pad.Chooser = player
		pad.ChooseEndsAt = now() + Config.Rooms.PadChooseSeconds
		claim(pad, player)
		Remotes.event("PadPrompt"):FireClient(player, pad.Id)
	elseif pad.State == "Open" then
		if #pad.Members >= MAX then
			eject(pad, player, "La sala está llena.")
		else
			tryJoin(pad, player)
		end
	elseif pad.State == "Starting" then
		eject(pad, player, "Esta sala ya va hacia el mall.")
	end
	-- "Choosing" / "Creating": espera dentro; entra en cuanto la sala exista
end

----------------------------------------------------------------------
-- Cartel y atributos
----------------------------------------------------------------------

local function setText(label: Instance?, text: string)
	if label and label:IsA("TextLabel") and label.Text ~= text then
		label.Text = text
	end
end

local function updateDisplay(pad: Pad)
	local model = pad.Model
	local count = #pad.Members + (if pad.State == "Choosing" or pad.State == "Creating" then 1 else 0)
	local hostName = if pad.Host then pad.Host.DisplayName elseif pad.Chooser then pad.Chooser.DisplayName else ""

	local countText, hint
	if pad.State == "Free" then
		countText, hint = "–/" .. MAX, "Toca para crear un grupo"
	elseif pad.State == "Choosing" or pad.State == "Creating" then
		countText, hint = count .. "/" .. MAX, hostName .. " está creando una sala..."
	elseif pad.State == "Open" then
		local seconds = math.max(0, math.ceil(pad.StartsAt - now()))
		countText = count .. "/" .. MAX .. (if pad.Public then "" else " 🔒")
		hint = string.format("Sala de %s · empieza en %d s", hostName, seconds)
	else
		countText, hint = count .. "/" .. MAX, "¡Viajando al mall!"
	end

	local status = model:FindFirstChild("SignAnchor") and model.SignAnchor:FindFirstChild("Status")
	if status then
		setText(status:FindFirstChild("Count"), countText)
		setText(status:FindFirstChild("Hint"), hint)
	end

	local color = if pad.State == "Starting"
		then COLORS.Starting
		elseif pad.State == "Free" then COLORS.Free
		elseif pad.Public then COLORS.Public
		else COLORS.Friends
	local glow = model:FindFirstChild("Glow")
	if glow then
		for _, wall in glow:GetChildren() do
			if wall:IsA("BasePart") and wall.Color ~= color then
				wall.Color = color
			end
		end
	end

	model:SetAttribute("State", pad.State)
	model:SetAttribute("Count", count)
	model:SetAttribute("Max", MAX)
	model:SetAttribute("Public", pad.Public)
	model:SetAttribute("HostName", hostName)
	model:SetAttribute("HostUserId", if pad.Host then pad.Host.UserId else 0)
	model:SetAttribute("StartsAt", if pad.State == "Open" then pad.StartsAt else 0)
end

----------------------------------------------------------------------
-- Revision de cada cuadro
----------------------------------------------------------------------

local function tickPad(pad: Pad)
	-- 1. Miembros que salieron del cuadro (saltando) o que LobbyService ya saco
	for i = #pad.Members, 1, -1 do
		local member = pad.Members[i]
		if not member.Parent then
			removeMember(pad, member) -- se fue del juego: LobbyService ya lo saca de la sala
		elseif LobbyService.GetPartyId(member) ~= pad.RoomId then
			removeMember(pad, member) -- p. ej. no pudo viajar al mall tras varios intentos
		elseif not isOnPad(pad, member) then
			removeMember(pad, member)
			task.spawn(LobbyService.LeaveRoom, member)
			notify(member, "Saliste de la sala.", "info")
		end
	end

	-- 2. Quien esta eligiendo el tipo de sala
	if pad.State == "Choosing" then
		local chooser = pad.Chooser
		if not chooser or not chooser.Parent or not isOnPad(pad, chooser) then
			resetPad(pad)
		elseif now() >= pad.ChooseEndsAt then
			task.spawn(createRoom, pad, true)
		end
	end

	-- 3. Sala sin nadie: el cuadro queda libre
	if (pad.State == "Open" or pad.State == "Starting") and #pad.Members == 0 then
		resetPad(pad)
	end

	-- 4. Recien llegados
	for _, player in Players:GetPlayers() do
		if not padOf[player] and not busy[player] and isOnPad(pad, player) then
			onNewcomer(pad, player)
		end
	end

	-- 5. Cuenta atras
	if pad.State == "Open" and not pad.Starting and now() >= pad.StartsAt then
		task.spawn(startPad, pad)
	end

	updateDisplay(pad)
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

local function setupCollisionGroups()
	for _, group in { WALL_GROUP, MEMBER_GROUP } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(group)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable(WALL_GROUP, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(WALL_GROUP, MEMBER_GROUP, true)
end

local function addPad(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local base = model:FindFirstChild("Base")
	local id = model:GetAttribute("PadId")
	if not base or not base:IsA("BasePart") or type(id) ~= "number" then
		warn("[PadService] Cuadro sin Base o sin atributo PadId:", model:GetFullName())
		return
	end
	local glow = model:FindFirstChild("Glow")
	if glow then
		for _, wall in glow:GetChildren() do
			if wall:IsA("BasePart") then
				wall.CanCollide = true
				wall.CollisionGroup = WALL_GROUP
			end
		end
	end
	local pad: Pad = {
		Id = id,
		Model = model,
		Base = base,
		State = "Free",
		Chooser = nil,
		ChooseEndsAt = 0,
		RoomId = nil,
		Public = true,
		Host = nil,
		Members = {},
		StartsAt = math.huge,
		Starting = false,
	}
	table.insert(pads, pad)
	updateDisplay(pad)
end

function PadService.Start()
	setupCollisionGroups()
	for _, model in CollectionService:GetTagged(Tags.LobbyRoomPad) do
		addPad(model)
	end
	table.sort(pads, function(a, b)
		return a.Id < b.Id
	end)
	if #pads == 0 then
		warn("[PadService] No hay cuadros de sala (tag LobbyRoomPad) en la plaza.")
	end

	Remotes.func("RequestPadCreate").OnServerInvoke = function(player: Player, isPublic: any)
		local pad = padOf[player]
		if not pad or pad.Chooser ~= player then
			return false, "Súbete a un cuadro libre para crear una sala."
		end
		return createRoom(pad, isPublic == true)
	end

	Remotes.func("RequestStartRoom").OnServerInvoke = function(player: Player)
		local pad = padOf[player]
		if not pad or pad.Host ~= player then
			return false, "Solo el anfitrión puede iniciar la partida."
		end
		return startPad(pad)
	end

	-- Personaje nuevo (reset) mientras es miembro: deja de estar en el cuadro y el
	-- tick lo saca. Al reaparecer siempre vuelve a chocar normal.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			if not padOf[player] then
				setBlocked(player, false)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local pad = padOf[player]
		if pad then
			if pad.Chooser == player then
				pad.Chooser = nil
				resetPad(pad)
			else
				removeMember(pad, player)
			end
		end
		padOf[player] = nil
		busy[player] = nil
		lastWarn[player] = nil
		local conn = collisionConn[player]
		if conn then
			conn:Disconnect()
			collisionConn[player] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(TICK)
			for _, pad in pads do
				local ok, err = pcall(tickPad, pad)
				if not ok then
					warn("[PadService] Error en el cuadro", pad.Id, err)
				end
			end
		end
	end)
end

return PadService
