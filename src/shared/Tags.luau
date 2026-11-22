--!strict
-- Tags de CollectionService que usa el mapa del mall.
-- En Studio: selecciona una parte -> Properties -> Tags -> "+" y escribe el nombre.
-- Los atributos se agregan en Properties -> Attributes -> "+".

return {
	-- Volumen invisible que define una zona. Atributo: Zone (string)
	Zone = "MallZone",
	-- Parte con una luz (PointLight/SpotLight/SurfaceLight) dentro. Atributo: Zone
	Light = "MallLight",
	-- Lugar donde puede aparecer una mision.
	-- Atributos: MissionType ("FixLights" | "CleanSpill" | "TakeOutTrash"), Zone (opcional)
	MissionSpot = "MissionSpot",
	-- Contenedor de basura donde se entregan las bolsas
	TrashDropoff = "TrashDropoff",
	-- Puntos de aparicion de enemigos (parte en el suelo). Atributo opcional: EnemyType
	EnemySpawn = "EnemySpawn",
	-- Puntos de aparicion de jugadores (parte en el suelo)
	PlayerSpawn = "PlayerSpawn",
	-- Lo pone el juego en los derrames sin limpiar (lo usara el Rastro)
	DirtyArea = "DirtyArea",
	-- Mostrador de la tienda del mall (abre la tienda al acercarse)
	ShopCounter = "ShopCounter",
	-- Maquina expendedora. Atributo: MachineType ("Cheap" | "Premium").
	-- Su cara frontal (Front) muestra las probabilidades.
	VendingMachine = "VendingMachine",
}
