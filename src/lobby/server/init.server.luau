--!strict
-- Punto de entrada del servidor del LOBBY. Arranca los servicios en orden.
--
-- Los servicios compartidos con el mall (DataService, ClassService,
-- MonetizationService, TravelService) viven en src/server y lobby.project.json
-- los coloca junto a este script, asi que se requieren igual que en el mall.
--
-- IMPORTANTE: DataService va al final (los demas se suscriben a ProfileLoaded).

local services = {
	require(script.PlazaService),
	require(script.TravelService),
	require(script.ClassService),
	require(script.MonetizationService),
	require(script.DataService),
}

for _, service in services do
	(service :: any).Start()
end

print("[Lobby] Sobreviviendo en el Mall: servidor del lobby iniciado")
