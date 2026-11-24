-- Rooms: registro de salas compartido entre el lobby y el mall (MemoryStoreService).
-- No tiene Start: lo usan LobbyService (lobby) y RoomService (mall).
--
-- Dos SortedMaps:
--   Rooms_v1      clave = PrivateServerId del servidor reservado -> Room
--   RoomCodes_v1  clave = codigo de la sala (ABC123)             -> PrivateServerId
--
-- La sala se arma en el lobby (State "Open": entran y salen miembros). Al
-- iniciarla pasa a "Starting" y cada lobby envia a sus miembros al servidor
-- reservado; el mall la marca "Started" al llegar el primero.
-- El lobby crea la sala al reservar el servidor (es el unico que conoce el
-- AccessCode). El mall solo la renueva y actualiza fase/noche: la busca por
-- su propio game.PrivateServerId, asi nadie puede hacerse pasar por otra sala.
-- Todas las llamadas van en pcall: MemoryStore puede fallar y no debe romper nada.

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

export type Member = { UserId: number, Name: string, VIP: boolean? }

export type Room = {
	Id: string, -- PrivateServerId
	Code: string,
	Name: string,
	Public: boolean,
	AccessCode: string, -- SOLO servidor: nunca se envia al cliente
	HostName: string,
	HostUserId: number,
	Members: { Member }, -- en orden de llegada
	State: string, -- "Open" | "Starting" | "Started"
	Max: number,
	Phase: string,
	Night: number,
	CreatedAt: number,
	UpdatedAt: number,
}

local Rooms = {}

local roomsMap: MemoryStoreSortedMap? = nil
local codesMap: MemoryStoreSortedMap? = nil

local function maps(): (MemoryStoreSortedMap?, MemoryStoreSortedMap?)
	if not roomsMap then
		local ok, a, b = pcall(function()
			return MemoryStoreService:GetSortedMap("Rooms_v1"), MemoryStoreService:GetSortedMap("RoomCodes_v1")
		end)
		if ok then
			roomsMap, codesMap = a, b
		else
			warn("[Rooms] MemoryStore no disponible:", a)
		end
	end
	return roomsMap, codesMap
end

local function try<T>(label: string, fn: () -> T): (boolean, T?)
	local ok, result = pcall(fn)
	if not ok then
		warn("[Rooms] " .. label .. ":", result)
		return false, nil
	end
	return true, result
end

----------------------------------------------------------------------
-- Salas
----------------------------------------------------------------------

function Rooms.Get(id: string): Room?
	local _, room = Rooms.Fetch(id)
	return room
end

-- Como Get, pero distingue "no existe" (true, nil) de "fallo MemoryStore" (false, nil).
function Rooms.Fetch(id: string): (boolean, Room?)
	local rooms = maps()
	if not rooms then
		return false, nil
	end
	local ok, room = try("GetAsync", function()
		return rooms:GetAsync(id)
	end)
	return ok, room
end

function Rooms.FindMember(room: Room, userId: number): number?
	for i, member in room.Members do
		if member.UserId == userId then
			return i
		end
	end
	return nil
end

function Rooms.Set(room: Room, expiration: number): boolean
	local rooms = maps()
	if not rooms then
		return false
	end
	return (try("SetAsync", function()
		return rooms:SetAsync(room.Id, room, expiration)
	end))
end

-- fn(old) -> nuevo valor o nil para no cambiar nada. Devuelve el valor guardado.
function Rooms.Update(id: string, fn: (Room?) -> Room?, expiration: number): Room?
	local rooms = maps()
	if not rooms then
		return nil
	end
	local _, room = try("UpdateAsync", function()
		return rooms:UpdateAsync(id, fn, expiration)
	end)
	return room
end

function Rooms.Remove(id: string, code: string?)
	local rooms, codes = maps()
	if rooms then
		try("RemoveAsync", function()
			rooms:RemoveAsync(id)
		end)
	end
	if codes and code then
		try("RemoveAsync code", function()
			codes:RemoveAsync(code)
		end)
	end
end

-- Hasta `max` salas (sin filtrar).
function Rooms.List(max: number): { Room }
	local rooms = maps()
	local list = {}
	if not rooms then
		return list
	end
	local _, items = try("GetRangeAsync", function()
		return rooms:GetRangeAsync(Enum.SortDirection.Ascending, math.clamp(max, 1, 200))
	end)
	for _, item in items or {} do
		if type(item.value) == "table" then
			table.insert(list, item.value)
		end
	end
	return list
end

----------------------------------------------------------------------
-- Codigos
----------------------------------------------------------------------

-- "abc 123" -> "ABC123" (solo letras y numeros, con el largo de Config.Rooms.CodeLength)
function Rooms.NormalizeCode(input: any): string?
	if type(input) ~= "string" then
		return nil
	end
	local code = string.upper((string.gsub(input, "[^%w]", "")))
	if #code ~= Config.Rooms.CodeLength then
		return nil
	end
	return code
end

function Rooms.RandomCode(rng: Random): string
	local alphabet = Config.Rooms.CodeAlphabet
	local chars = table.create(Config.Rooms.CodeLength)
	for i = 1, Config.Rooms.CodeLength do
		local n = rng:NextInteger(1, #alphabet)
		chars[i] = string.sub(alphabet, n, n)
	end
	return table.concat(chars)
end

function Rooms.GetIdByCode(code: string): string?
	local _, codes = maps()
	if not codes then
		return nil
	end
	local _, id = try("GetAsync code", function()
		return codes:GetAsync(code)
	end)
	return if type(id) == "string" then id else nil
end

function Rooms.SetCode(code: string, id: string, expiration: number): boolean
	local _, codes = maps()
	if not codes then
		return false
	end
	return (try("SetAsync code", function()
		return codes:SetAsync(code, id, expiration)
	end))
end

----------------------------------------------------------------------
-- Teleports
----------------------------------------------------------------------

-- Teletransporta jugadores a un place (a un servidor reservado si hay accessCode).
-- Devuelve (ok, error). Los fallos posteriores llegan por TeleportService.TeleportInitFailed.
function Rooms.Teleport(players: { Player }, placeId: number, accessCode: string?, data: any?): (boolean, string?)
	local options = Instance.new("TeleportOptions")
	if accessCode then
		options.ReservedServerAccessCode = accessCode
	end
	if data ~= nil then
		options:SetTeleportData(data)
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(placeId, players, options)
	end)
	if not ok then
		warn("[Rooms] TeleportAsync:", err)
		return false, tostring(err)
	end
	return true, nil
end

-- Mensaje claro para un fallo de teleport.
function Rooms.DescribeTeleportFailure(result: Enum.TeleportResult, message: string?): string
	if result == Enum.TeleportResult.GameFull then
		return "La sala está llena."
	elseif result == Enum.TeleportResult.GameEnded or result == Enum.TeleportResult.GameNotFound then
		return "La sala ya no existe."
	elseif result == Enum.TeleportResult.Flooded then
		return "Demasiados intentos. Espera unos segundos."
	elseif result == Enum.TeleportResult.Unauthorized then
		return "No tienes permiso para entrar a esa sala."
	end
	return "No se pudo viajar" .. (if message and message ~= "" then ": " .. message else ".")
end

return Rooms
