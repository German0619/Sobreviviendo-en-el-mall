--!strict
-- Punto de entrada del servidor. Arranca los servicios en orden.
--
-- IMPORTANTE: DataService va al final. Los demas servicios se suscriben a
-- DataService.ProfileLoaded en su Start(), y tienen que estar conectados
-- antes de que se cargue el primer perfil.

local services = {
	require(script.PlayerStats),
	-- Fase 2+: NightManager, MissionService, EnemyService, ...
	require(script.DataService),
}

for _, service in services do
	(service :: any).Start()
end

print("[Server] Sobreviviendo en el Mall: servidor iniciado")
