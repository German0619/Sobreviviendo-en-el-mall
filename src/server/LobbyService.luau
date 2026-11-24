-- LobbyService (solo en el place del Lobby): salas que se arman EN EL LOBBY.
--
--   Crear sala -> los demas entran (lista publica o codigo) -> el anfitrion pulsa
--   INICIAR PARTIDA (o la sala se llena) -> TODOS viajan juntos al mall.
--
-- Nadie va al mall antes de que la partida empiece. Mientras tanto todos se
-- quedan en el lobby (pueden cambiar de clase, girar la ruleta...).
--
-- Los miembros pueden estar en servidores de lobby distintos: la sala vive en
-- MemoryStore (Rooms) y cada lobby revisa cada Config.Rooms.PollSeconds las
-- salas de SUS jugadores. Cuando una pasa a "Starting", cada lobby envia a sus
-- miembros al mismo servidor reservado del mall.
--
-- * El nombre de la sala lo escribe un jugador: se filtra con TextService.
-- * En Studio no hay ReserveServer ni teleports: se pueden crear salas y entrar
--   en ellas (para probar la interfaz), pero al iniciar se avisa.
-- * El cliente recibe el estado de su sala por el evento PartyState
--   (sin el AccessCode) y el atributo PartyId del Player.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local Rooms = require(script.Parent.Rooms)
local PassService = require(script.Parent.PassService)

type Room = Rooms.Room

local LobbyService = {}

local RoomsConfig = Config.Rooms
local TELEPORT_TIMEOUT = 20 -- si el viaje no ocurre en este tiempo, se reintenta

local rng = Random.new()
local partyOf: { [Player]: string } = {} -- sala de cada jugador de ESTE servidor
local teleporting: { [Player]: number } = {} -- os.clock() del ultimo intento de viaje
local attempts: { [Player]: number } = {}
local lastPushed: { [Player]: string } = {} -- ultimo estado enviado (para no repetir)
local lastRequest: { [Player]: { [string]: number } } = {}
local cachedList: { any } = {}
local cachedAt = -math.huge

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind or "info")
end

-- Anti-spam por accion (la lista se refresca sola y no debe bloquear "Crear sala").
local function throttled(player: Player, action: string, seconds: number): boolean
	local now = os.clock()
	local times = lastRequest[player] or {}
	lastRequest[player] = times
	if times[action] and now - times[action] < seconds then
		return true
	end
	times[action] = now
	return false
end

----------------------------------------------------------------------
-- Estado local y envio al cliente
----------------------------------------------------------------------

-- Lo que ve el cliente de su sala (nunca el AccessCode).
local function snapshot(room: Room)
	local members = {}
	for _, member in room.Members do
		table.insert(members, { UserId = member.UserId, Name = member.Name, VIP = member.VIP == true })
	end
	return {
		Id = room.Id,
		Name = room.Name,
		Code = room.Code,
		Public = room.Public,
		HostUserId = room.HostUserId,
		HostName = room.HostName,
		Members = members,
		Max = room.Max,
		State = room.State,
	}
end

local function push(player: Player, room: Room?)
	local data = if room then snapshot(room) else nil
	local key = if data then HttpService:JSONEncode(data) else ""
	if lastPushed[player] == key then
		return
	end
	lastPushed[player] = key
	Remotes.event("PartyState"):FireClient(player, data)
end

local function setParty(player: Player, id: string?)
	partyOf[player] = id
	player:SetAttribute("PartyId", id)
	if not id then
		attempts[player] = nil
		push(player, nil)
	end
end

-- Jugadores de este servidor que estan en la sala `id`.
local function localMembers(id: string): { Player }
	local list = {}
	for player, partyId in partyOf do
		if partyId == id and player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

-- Envia el estado a los miembros locales y quita a los que ya no figuran en la sala.
local function syncLocal(id: string, room: Room?)
	for _, player in localMembers(id) do
		if not room then
			setParty(player, nil)
			notify(player, "La sala se cerró.", "bad")
		elseif not Rooms.FindMember(room, player.UserId) then
			setParty(player, nil)
		else
			push(player, room)
		end
	end
end

----------------------------------------------------------------------
-- Viaje al mall
----------------------------------------------------------------------

-- Envia al mall a los miembros locales de una sala que ya empezo.
local function dispatch(room: Room)
	if RunService:IsStudio() then
		return
	end
	local group = {}
	local now = os.clock()
	for _, player in localMembers(room.Id) do
		if Rooms.FindMember(room, player.UserId) then
			local since = teleporting[player]
			if not since or now - since > TELEPORT_TIMEOUT then
				if (attempts[player] or 0) >= RoomsConfig.MaxTeleportAttempts then
					setParty(player, nil)
					notify(player, "No pudiste viajar al mall. Vuelve a entrar a una sala.", "bad")
				else
					table.insert(group, player)
				end
			end
		end
	end
	if #group == 0 then
		return
	end
	for _, player in group do
		teleporting[player] = now
		attempts[player] = (attempts[player] or 0) + 1
		push(player, room)
	end
	local ok, err = Rooms.Teleport(group, Config.Places.MallPlaceId, room.AccessCode)
	if not ok then
		for _, player in group do
			teleporting[player] = nil
			notify(player, "No se pudo viajar al mall: " .. tostring(err), "bad")
		end
	end
end

----------------------------------------------------------------------
-- Nombre de la sala
----------------------------------------------------------------------

-- Nombre filtrado (o uno por defecto si esta vacio o el filtro falla).
local function filterRoomName(player: Player, raw: any): string
	local default = "Sala de " .. player.DisplayName
	if type(raw) ~= "string" or utf8.len(raw) == nil then
		return default
	end
	local name = string.gsub(raw, "%c", "")
	name = string.match(name, "^%s*(.-)%s*$") or ""
	local cut = utf8.offset(name, RoomsConfig.NameMaxLength + 1)
	if cut then
		name = string.sub(name, 1, cut - 1)
	end
	if name == "" then
		return default
	end
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(name, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(result) ~= "string" or result == "" then
		return default
	end
	return result
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function LobbyService.LeaveRoom(player: Player): (boolean, string)
	local id = partyOf[player]
	if not id then
		return false, "No estás en ninguna sala."
	end
	setParty(player, nil)

	local room = Rooms.Update(id, function(old)
		if not old or old.State ~= "Open" then
			return nil -- ya empezo (o no existe): no se toca
		end
		local i = Rooms.FindMember(old, player.UserId)
		if not i then
			return nil
		end
		table.remove(old.Members, i)
		-- Si se va el anfitrion, lo es el siguiente que llego
		if old.HostUserId == player.UserId and old.Members[1] then
			old.HostUserId = old.Members[1].UserId
			old.HostName = old.Members[1].Name
		end
		old.UpdatedAt = os.time()
		return old
	end, RoomsConfig.InitialExpiration)

	if room then
		if #room.Members == 0 then
			Rooms.Remove(room.Id, room.Code)
		else
			syncLocal(id, room)
		end
	end
	cachedAt = -math.huge
	return true, "Saliste de la sala."
end

function LobbyService.CreateRoom(player: Player, isPublic: any, rawName: any): (boolean, string)
	if not DataService.GetData(player) then
		return false, "Tus datos aún se están cargando."
	end
	if Config.Places.MallPlaceId == 0 and not RunService:IsStudio() then
		return false, "Falta el ID del place del mall (Config.Places.MallPlaceId)."
	end
	if partyOf[player] then
		LobbyService.LeaveRoom(player)
	end

	-- Servidor reservado del mall (en Studio no existe: sala solo para probar la interfaz)
	local accessCode, privateServerId
	if RunService:IsStudio() then
		accessCode, privateServerId = "", "studio-" .. HttpService:GenerateGUID(false)
	else
		local ok, a, b = pcall(function()
			return TeleportService:ReserveServer(Config.Places.MallPlaceId)
		end)
		if not ok or type(a) ~= "string" or type(b) ~= "string" then
			warn("[LobbyService] ReserveServer:", a)
			return false, "No se pudo crear la sala. Inténtalo de nuevo."
		end
		accessCode, privateServerId = a, b
	end

	local code = nil
	for _ = 1, 5 do
		local candidate = Rooms.RandomCode(rng)
		if not Rooms.GetIdByCode(candidate) then
			code = candidate
			break
		end
	end
	if not code then
		return false, "No se pudo generar un código. Inténtalo de nuevo."
	end

	local now = os.time()
	local room: Room = {
		Id = privateServerId,
		Code = code,
		Name = filterRoomName(player, rawName),
		Public = isPublic == true,
		AccessCode = accessCode,
		HostName = player.DisplayName,
		HostUserId = player.UserId,
		Members = { { UserId = player.UserId, Name = player.DisplayName, VIP = PassService.Owns(player, "VIP") } },
		State = "Open",
		Max = Config.MaxPlayersPerRoom,
		Phase = "Waiting",
		Night = 1,
		CreatedAt = now,
		UpdatedAt = now,
	}
	if not Rooms.Set(room, RoomsConfig.InitialExpiration) or not Rooms.SetCode(code, room.Id, RoomsConfig.InitialExpiration) then
		return false, "El servicio de salas no responde. Inténtalo en un momento."
	end
	setParty(player, room.Id)
	push(player, room)
	cachedAt = -math.huge
	return true, "Sala creada. Código: " .. code
end

-- Empieza la partida: la sala pasa a "Starting" y todos viajan.
-- byPlayer = nil cuando se inicia sola por estar llena.
local function startRoom(id: string, byPlayer: Player?): (boolean, string)
	if RunService:IsStudio() then
		return false, "Los teleports no funcionan en Studio. Publica el juego y pruébalo desde Roblox."
	end
	if Config.Places.MallPlaceId == 0 then
		return false, "Falta el ID del place del mall (Config.Places.MallPlaceId)."
	end
	local reason: string? = nil
	local room = Rooms.Update(id, function(old)
		reason = nil
		if not old then
			reason = "La sala ya no existe."
			return nil
		end
		if old.State ~= "Open" then
			reason = "La partida ya está empezando."
			return nil
		end
		if byPlayer and old.HostUserId ~= byPlayer.UserId then
			reason = "Solo el anfitrión puede iniciar la partida."
			return nil
		end
		old.State = "Starting"
		old.UpdatedAt = os.time()
		return old
	end, RoomsConfig.InitialExpiration)
	if not room then
		return false, reason or "No se pudo iniciar. Inténtalo de nuevo."
	end
	cachedAt = -math.huge
	dispatch(room) -- los de este servidor salen ya; los demas lobbies lo ven en su revision
	return true, "¡Empieza la partida! Viajando al mall..."
end

function LobbyService.StartRoom(player: Player): (boolean, string)
	local id = partyOf[player]
	if not id then
		return false, "No estás en ninguna sala."
	end
	return startRoom(id, player)
end

local function joinRoom(player: Player, id: string, requirePublic: boolean): (boolean, string)
	if not DataService.GetData(player) then
		return false, "Tus datos aún se están cargando."
	end
	if partyOf[player] == id then
		return false, "Ya estás en esta sala."
	end
	if partyOf[player] then
		LobbyService.LeaveRoom(player)
	end

	local reason: string? = nil
	local vip = PassService.Owns(player, "VIP")
	local room = Rooms.Update(id, function(old)
		reason = nil
		if not old or (requirePublic and not old.Public) then
			reason = "La sala ya no existe."
			return nil
		end
		if old.State ~= "Open" then
			reason = "La partida de esa sala ya empezó."
			return nil
		end
		if Rooms.FindMember(old, player.UserId) then
			return old -- ya estaba (p. ej. desde otro servidor)
		end
		if #old.Members >= old.Max then
			reason = "La sala está llena."
			return nil
		end
		table.insert(old.Members, { UserId = player.UserId, Name = player.DisplayName, VIP = vip })
		old.UpdatedAt = os.time()
		return old
	end, RoomsConfig.InitialExpiration)
	if not room then
		return false, reason or "No se pudo entrar a la sala."
	end

	setParty(player, id)
	syncLocal(id, room)
	cachedAt = -math.huge

	-- Sala llena: empieza sola
	if #room.Members >= room.Max and not RunService:IsStudio() then
		startRoom(id, nil)
	end
	return true, "Entraste a " .. room.Name .. "."
end

function LobbyService.JoinRoom(player: Player, roomId: any): (boolean, string)
	if type(roomId) ~= "string" or #roomId > 128 then
		return false, "Sala inválida."
	end
	-- Por id solo se entra a salas publicas (las privadas, con su codigo)
	return joinRoom(player, roomId, true)
end

-- Para PadService (servidor, de confianza): entra por id aunque la sala sea
-- "solo amigos" (PadService ya comprobo la amistad con el anfitrion).
function LobbyService.JoinRoomById(player: Player, roomId: string): (boolean, string)
	return joinRoom(player, roomId, false)
end

-- Sala en la que esta el jugador (id = PrivateServerId), o nil.
function LobbyService.GetPartyId(player: Player): string?
	return partyOf[player]
end

-- Inicio automatico (cuenta atras del cuadro): no exige anfitrion.
function LobbyService.StartById(roomId: string): (boolean, string)
	return startRoom(roomId, nil)
end

function LobbyService.JoinByCode(player: Player, rawCode: any): (boolean, string)
	local code = Rooms.NormalizeCode(rawCode)
	if not code then
		return false, string.format("El código tiene %d letras o números.", RoomsConfig.CodeLength)
	end
	local roomId = Rooms.GetIdByCode(code)
	if not roomId then
		return false, "No hay ninguna sala con ese código."
	end
	return joinRoom(player, roomId, false)
end

-- Salas publicas abiertas y con hueco, sin datos privados.
function LobbyService.GetPublicRooms(): { any }
	if os.clock() - cachedAt < RoomsConfig.ListRefreshSeconds then
		return cachedList
	end
	cachedAt = os.clock()
	local list = {}
	for _, room in Rooms.List(RoomsConfig.ListMax) do
		local members = room.Members or {}
		if room.Public and room.State == "Open" and #members < room.Max then
			table.insert(list, {
				Id = room.Id,
				Name = room.Name,
				HostName = room.HostName,
				Players = #members,
				Max = room.Max,
			})
		end
	end
	-- Primero las que tienen mas gente (pero no llenas)
	table.sort(list, function(a, b)
		return a.Players > b.Players
	end)
	cachedList = list
	return list
end

----------------------------------------------------------------------
-- Revision periodica de las salas de los jugadores de este servidor
----------------------------------------------------------------------

local function pollRoom(id: string, renew: boolean)
	local ok, room = Rooms.Fetch(id)
	if not ok then
		return -- fallo de MemoryStore: se reintenta en la siguiente vuelta
	end
	if room and renew then
		-- Mantenerla viva mientras haya miembros en algun lobby
		Rooms.Update(id, function(old)
			if not old then
				return nil
			end
			old.UpdatedAt = os.time()
			return old
		end, RoomsConfig.RefreshExpiration)
		Rooms.SetCode(room.Code, id, RoomsConfig.RefreshExpiration)
	end
	syncLocal(id, room)
	if room and room.State ~= "Open" then
		dispatch(room)
	end
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

function LobbyService.Start()
	-- Crear, unirse, salir e iniciar se hace SOLO con los cuadros de la plaza
	-- (PadService llama a esta API). No hay remotes de salas aqui.

	TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
		teleporting[player] = nil -- la siguiente revision lo reintenta
		notify(player, Rooms.DescribeTeleportFailure(result, message), "bad")
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- Si se va de verdad (no viajando al mall), deja su sala
		if partyOf[player] and not teleporting[player] then
			LobbyService.LeaveRoom(player)
		end
		partyOf[player] = nil
		teleporting[player] = nil
		attempts[player] = nil
		lastPushed[player] = nil
		lastRequest[player] = nil
	end)

	task.spawn(function()
		local lastRenew = os.clock()
		while true do
			task.wait(RoomsConfig.PollSeconds)
			local renew = os.clock() - lastRenew >= RoomsConfig.RefreshSeconds
			if renew then
				lastRenew = os.clock()
			end
			local ids = {}
			for _, id in partyOf do
				ids[id] = true
			end
			for id in ids do
				task.spawn(pollRoom, id, renew)
			end
		end
	end)
end

return LobbyService
