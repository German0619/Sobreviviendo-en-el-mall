--!strict
-- Punto de entrada del servidor. Arranca los servicios en orden.
--
-- IMPORTANTE: DataService va al final. Los demas servicios se suscriben a
-- DataService.ProfileLoaded en su Start(), y tienen que estar conectados
-- antes de que se cargue el primer perfil.

require(script.TestMapBuilder).BuildIfNeeded()

local services = {
	require(script.LightService),
	require(script.FlashlightService),
	require(script.PlayerStats),
	require(script.ShopService),
	require(script.VendingService),
	require(script.MissionService),
	require(script.EnemyService),
	require(script.NightManager),
	require(script.DataService),
}

for _, service in services do
	(service :: any).Start()
end

print("[Server] Sobreviviendo en el Mall: servidor iniciado")
