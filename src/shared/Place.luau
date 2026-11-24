--!strict
-- Place: dice si este place es el Lobby o el Mall (la partida).
--
-- Los dos places usan el MISMO codigo (un solo proyecto de Rojo). Cada uno
-- sabe quien es, en este orden:
--   1. Atributo PlaceRole de Workspace ("Lobby" o "Mall"). Recomendado:
--      ponlo una vez en Studio en cada place (Workspace -> Attributes -> "+").
--   2. game.PlaceId comparado con Config.Places.
--   3. Config.Debug.PlaceRole (para probar en Studio sin publicar).
-- Funciona igual en el servidor y en el cliente.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

export type Role = "Lobby" | "Mall"

local function detect(): Role
	local attr = Workspace:GetAttribute("PlaceRole")
	if attr == "Lobby" or attr == "Mall" then
		return attr
	end
	if Config.Places.LobbyPlaceId ~= 0 and game.PlaceId == Config.Places.LobbyPlaceId then
		return "Lobby"
	end
	if Config.Places.MallPlaceId ~= 0 and game.PlaceId == Config.Places.MallPlaceId then
		return "Mall"
	end
	return if Config.Debug.PlaceRole == "Lobby" then "Lobby" else "Mall"
end

local role = detect()

-- La ruleta y los slots se usan en el lobby (y en el mall solo para probar en Studio).
local function classesEnabledHere(): boolean
	return role == "Lobby" or (RunService:IsStudio() and Config.Debug.ClassesInMallInStudio == true)
end

return {
	Role = role,
	IsLobby = role == "Lobby",
	IsMall = role == "Mall",
	ClassesEnabledHere = classesEnabledHere,
}
