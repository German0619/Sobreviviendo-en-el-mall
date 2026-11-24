-- TravelService: viajes entre el lobby y el mall (lo usan los dos places).
--
-- * ToLobby(players): devuelve jugadores al lobby (al terminar la partida).
-- * ToMall(players, data): crea un servidor reservado del mall y manda a todo
--   el grupo junto (lo usara RoomService en la Fase 2).
-- El teletransporte no funciona en Studio: CanTravel() devuelve false y quien
-- llame debe seguir con el comportamiento local.
-- No hace falta guardar antes de viajar: DataService guarda al salir y el
-- servidor de destino espera a que termine (bloqueo de sesion).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local TravelService = {}

local ATTEMPTS = 3
local RETRY_SECONDS = 3

-- [Player] = { PlaceId, Options, Tries } de cada viaje en curso, para reintentar si falla
local inFlight: { [Player]: { PlaceId: number, Options: TeleportOptions?, Tries: number } } = {}

function TravelService.CanTravel(): boolean
	return not RunService:IsStudio() and Config.Places.Lobby ~= 0 and Config.Places.Mall ~= 0
end

local function teleport(placeId: number, players: { Player }, options: TeleportOptions?): boolean
	for attempt = 1, ATTEMPTS do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(placeId, players, options)
		end)
		if ok then
			return true
		end
		warn(string.format("[TravelService] Error al viajar a %d (intento %d): %s", placeId, attempt, tostring(err)))
		task.wait(RETRY_SECONDS)
	end
	return false
end

local function send(placeId: number, players: { Player }, options: TeleportOptions?): boolean
	local valid = {}
	for _, player in players do
		if player.Parent then
			table.insert(valid, player)
			inFlight[player] = { PlaceId = placeId, Options = options, Tries = 0 }
		end
	end
	if #valid == 0 then
		return false
	end
	local ok = teleport(placeId, valid, options)
	if not ok then
		for _, player in valid do
			inFlight[player] = nil
		end
	end
	return ok
end

function TravelService.ToLobby(players: { Player }): boolean
	if not TravelService.CanTravel() then
		return false
	end
	return send(Config.Places.Lobby, players, nil)
end

-- data: tabla que el mall lee con player:GetJoinData().TeleportData
function TravelService.ToMall(players: { Player }, data: { [string]: any }?): boolean
	if not TravelService.CanTravel() then
		return false
	end
	local ok, code = pcall(function()
		return TeleportService:ReserveServer(Config.Places.Mall)
	end)
	if not ok then
		warn("[TravelService] No se pudo reservar un servidor del mall:", code)
		return false
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code :: string
	if data then
		options:SetTeleportData(data)
	end
	return send(Config.Places.Mall, players, options)
end

function TravelService.Start()
	-- Si el viaje de un jugador falla despues de empezar, se reintenta solo con el.
	TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
		local trip = inFlight[player]
		if not trip or not player.Parent then
			return
		end
		trip.Tries += 1
		warn(string.format("[TravelService] Viaje fallido de %s (%s): %s", player.Name, result.Name, message))
		if trip.Tries >= ATTEMPTS then
			inFlight[player] = nil
			Remotes.event("Notify"):FireClient(player, "No pudimos llevarte. Vuelve a entrar al juego.", "bad")
			return
		end
		task.wait(RETRY_SECONDS)
		if player.Parent then
			teleport(trip.PlaceId, { player }, trip.Options)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		inFlight[player] = nil
	end)
end

return TravelService
