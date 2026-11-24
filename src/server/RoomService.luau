-- RoomService (solo en el place del Mall): la sala vista desde la partida.
--
-- * Servidor reservado: la partida ya se inicio en el lobby. Marca la sala
--   como "Started" (deja de salir en la lista y no entra nadie mas), la
--   renueva en MemoryStore, sabe que miembros tienen que llegar y la borra al
--   cerrarse. Publica nombre/codigo en GameState para el HUD.
-- * Al terminar la partida, todos vuelven al lobby (SendAllToLobby).
-- * Limite de jugadores: si entra uno de mas, vuelve al lobby.
--   (Pon tambien "Max Players" = Config.MaxPlayersPerRoom en el place del mall.)
-- * Servidor normal del mall (alguien entro directo al place, no desde el
--   lobby): fuera de Studio, se manda a los jugadores al lobby. En Studio se
--   juega aqui y el anfitrion inicia con [P] (para probar).
-- * [L] Volver al lobby (RequestReturnToLobby).
-- * Anfitrion: el de la sala; si no esta, el que lleva mas tiempo dentro.
--
-- Atributos de GameState: RoomName, RoomCode, RoomPublic, ExpectedPlayers
-- (solo en salas reservadas) y HostUserId (siempre).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local GameState = require(Shared.GameState)

local Rooms = require(script.Parent.Rooms)

local RoomService = {}

local roomId: string? = nil
local roomCode: string? = nil
local refreshQueued = false
local lastReturn: { [Player]: number } = {}
local joinOrder: { Player } = {} -- orden de llegada (para elegir anfitrion)
local creatorUserId: number? = nil -- anfitrion de la sala en el lobby
local expected: { number } = {} -- UserIds de los miembros que viajan al mall
local fetchedRoom = false -- ya se leyo la sala al menos una vez

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind or "info")
end

local function isReservedServer(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

-- true en las partidas creadas desde el lobby (servidor reservado).
function RoomService.IsReserved(): boolean
	return isReservedServer()
end

-- true cuando ya estan aqui todos los miembros de la sala que se inicio en el lobby.
function RoomService.AllMembersArrived(): boolean
	if not fetchedRoom or #expected == 0 then
		return false
	end
	for _, userId in expected do
		if not Players:GetPlayerByUserId(userId) then
			return false
		end
	end
	return true
end

local function canReachLobby(): boolean
	return Config.Places.LobbyPlaceId ~= 0 and not RunService:IsStudio()
end

function RoomService.SendToLobby(player: Player, message: string?)
	if not canReachLobby() then
		return false
	end
	if message then
		notify(player, message)
	end
	return Rooms.Teleport({ player }, Config.Places.LobbyPlaceId)
end

-- Fin de la partida: todos al lobby. Devuelve false si no se puede (Studio / sin ID).
function RoomService.SendAllToLobby(message: string?): boolean
	if not canReachLobby() then
		return false
	end
	local list = Players:GetPlayers()
	if #list == 0 then
		return true
	end
	for _, player in list do
		if message then
			notify(player, message)
		end
	end
	return (Rooms.Teleport(list, Config.Places.LobbyPlaceId))
end

----------------------------------------------------------------------
-- Anfitrion
----------------------------------------------------------------------

function RoomService.GetHost(): Player?
	if creatorUserId then
		local creator = Players:GetPlayerByUserId(creatorUserId)
		if creator then
			return creator
		end
	end
	for _, player in joinOrder do
		if player.Parent then
			return player
		end
	end
	return nil
end

local function updateHost()
	local host = RoomService.GetHost()
	GameState.Folder:SetAttribute("HostUserId", if host then host.UserId else nil)
end

----------------------------------------------------------------------
-- Registro de la sala
----------------------------------------------------------------------

local function refresh()
	local id = roomId
	if not id then
		return
	end
	local phase = GameState.Folder:GetAttribute("Phase") or "Waiting"
	local night = GameState.Folder:GetAttribute("Night") or 1
	local room = Rooms.Update(id, function(old)
		if not old then
			return nil -- caducada: no se puede recrear (solo el lobby conoce el AccessCode)
		end
		old.State = "Started" -- ya no se lista ni se puede entrar desde el lobby
		old.Phase = phase
		old.Night = night
		old.UpdatedAt = os.time()
		return old
	end, Config.Rooms.RefreshExpiration)

	if room then
		roomCode = room.Code
		fetchedRoom = true
		expected = {}
		for _, member in room.Members or {} do
			table.insert(expected, member.UserId)
		end
		GameState.Folder:SetAttribute("ExpectedPlayers", #expected)
		if creatorUserId ~= room.HostUserId then
			creatorUserId = room.HostUserId
			updateHost()
		end
		Rooms.SetCode(room.Code, id, Config.Rooms.RefreshExpiration)
		GameState.Folder:SetAttribute("RoomName", room.Name)
		GameState.Folder:SetAttribute("RoomCode", room.Code)
		GameState.Folder:SetAttribute("RoomPublic", room.Public)
	end
end

-- Agrupa varios cambios seguidos (entradas/salidas) en una sola escritura.
local function requestRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.delay(1, function()
		refreshQueued = false
		refresh()
	end)
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

function RoomService.Start()
	Remotes.event("RequestReturnToLobby").OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if lastReturn[player] and now - lastReturn[player] < 3 then
			return
		end
		lastReturn[player] = now
		if not canReachLobby() then
			notify(player, if RunService:IsStudio()
				then "Los teleports no funcionan en Studio."
				else "Falta el ID del place del lobby (Config.Places.LobbyPlaceId).", "bad")
			return
		end
		RoomService.SendToLobby(player, "Volviendo al lobby...")
	end)

	TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
		notify(player, Rooms.DescribeTeleportFailure(result, message), "bad")
	end)

	-- Orden de llegada y anfitrion (tambien en Studio / servidores normales)
	local function track(player: Player)
		if not table.find(joinOrder, player) then
			table.insert(joinOrder, player)
		end
		updateHost()
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastReturn[player] = nil
		local i = table.find(joinOrder, player)
		if i then
			table.remove(joinOrder, i)
		end
		-- Esperar a que salga de verdad antes de elegir otro anfitrion
		task.delay(0.5, updateHost)
	end)

	if not isReservedServer() then
		-- Servidor publico del mall: las partidas se crean desde el lobby
		if canReachLobby() then
			local function redirect(player: Player)
				task.wait(2)
				if player.Parent then
					RoomService.SendToLobby(player, "Las partidas se crean desde el lobby. Llevándote allí...")
				end
			end
			Players.PlayerAdded:Connect(redirect)
			for _, player in Players:GetPlayers() do
				task.spawn(redirect, player)
			end
		end
		return
	end

	roomId = game.PrivateServerId

	local function onPlayerAdded(player: Player)
		if #Players:GetPlayers() > Config.MaxPlayersPerRoom then
			task.wait(1)
			if player.Parent then
				RoomService.SendToLobby(player, "La sala está llena. Volviendo al lobby...")
			end
		end
		requestRefresh()
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(requestRefresh)
	GameState.Folder:GetAttributeChangedSignal("Phase"):Connect(requestRefresh)

	task.spawn(function()
		while true do
			refresh()
			task.wait(Config.Rooms.RefreshSeconds)
		end
	end)

	-- Al cerrarse el servidor (se fue el ultimo jugador), la sala desaparece de la lista
	game:BindToClose(function()
		if roomId then
			Rooms.Remove(roomId, roomCode)
		end
	end)
end

return RoomService
