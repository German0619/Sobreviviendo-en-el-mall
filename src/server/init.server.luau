--!strict
-- Punto de entrada del servidor. Arranca los servicios en orden.
--
-- El mismo codigo corre en los dos places (ver shared/Place):
--   * Lobby: ruleta, slots, compras con Robux y salas (LobbyService).
--   * Mall:  la partida completa + RoomService (registro de la sala).
--
-- IMPORTANTE: DataService va al final. Los demas servicios se suscriben a
-- DataService.ProfileLoaded en su Start(), y tienen que estar conectados
-- antes de que se cargue el primer perfil.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Place = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Place"))

local services: { any }
if Place.IsLobby then
	require(script.LobbyMapBuilder).BuildIfNeeded()
	services = {
		require(script.RunState),
		require(script.PlayerStats),
		require(script.ClassService),
		require(script.PassService),
		require(script.MonetizationService),
		require(script.LobbyService),
		require(script.DataService),
	}
else
	require(script.MallBuilder).BuildIfNeeded()
	services = {
		require(script.RunState),
		require(script.LightService),
		require(script.FlashlightService),
		require(script.PlayerStats),
		require(script.ClassService),
		require(script.ReviveService),
		require(script.PassService),
		require(script.MonetizationService),
		require(script.DefenseService),
		require(script.ShopService),
		require(script.VendingService),
		require(script.MissionService),
		require(script.EnemyService),
		require(script.NightManager),
		require(script.RoomService),
		require(script.DataService),
	}
end

for _, service in services do
	(service :: any).Start()
end

print(string.format("[Server] Sobreviviendo en el Mall: servidor iniciado (%s)", Place.Role))
