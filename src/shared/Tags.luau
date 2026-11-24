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
	-- Atributos: MissionType (una clave de Config.Missions), Zone (opcional).
	-- FixLights: tablero electrico · CleanSpill / TakeOutTrash / LostItem: punto del suelo
	-- RestockStore: estante de la tienda · SilenceAlarm: panel de alarma
	-- RestartGenerator: panel del generador (atributo PowersZones = "Servicio,Bodega")
	-- CheckCameras: monitores · UnclogToilet: inodoro (su cara Front mira a la puerta)
	-- WaterPlants / LockDoors: solo marcan la zona (los puntos son Planter / ShutterControl)
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
	-- Escondite (casillero, probador, armario). Parte solida del tamano del escondite;
	-- su cara frontal (Front) mira hacia donde sale el jugador. Atributo opcional: DisplayName
	HidingSpot = "HidingSpot",
	-- Camara de seguridad (la usa el Vigilante). Parte pequena en lo alto de una pared;
	-- su cara frontal (Front) apunta hacia donde mira.
	SecurityCamera = "SecurityCamera",
	-- Vidrio de escaparate o espejo donde puede aparecer el Reflejo. Parte plana: su eje
	-- mas fino (normalmente Z) es el grosor; el Reflejo aparece del lado donde estas.
	ReflectiveSurface = "ReflectiveSurface",
	-- Rejilla de ventilacion del techo (la usa el Ducto). Parte plana pegada al techo.
	CeilingVent = "CeilingVent",
	-- Estatua de la fuente (Model de shared/EntityModels.statue). Cuando sale la entidad
	-- Estatua es ESTE modelo el que se mueve; al terminar la noche vuelve (atributo HomeCFrame).
	FountainStatue = "FountainStatue",
	-- Maniqui de escaparate (Model de EntityModels.mannequin). El enemigo Maniqui es uno
	-- de ellos que cobra vida y vuelve a su sitio al terminar la noche (HomeCFrame).
	DisplayMannequin = "DisplayMannequin",

	-- Misiones de varios puntos / de llevar objetos (ademas del MissionSpot de la mision):
	-- Control de la persiana de una tienda (mision LockDoors). Atributo Wing = zona de la galeria
	-- donde esta. La persiana es una parte hija llamada "Shutter".
	ShutterControl = "ShutterControl",
	-- Macetero (mision WaterPlants). Atributo Zone.
	Planter = "Planter",
	-- Donde se recogen las cajas para reponer (mision RestockStore), en la bodega.
	StockPickup = "StockPickup",
	-- Mostrador de objetos perdidos (mision LostItem), en informacion.
	LostAndFound = "LostAndFound",

	-- Escalera mecanica (Model). La rampa transporta a los jugadores (AssemblyLinearVelocity);
	-- el cliente anima los escalones de su carpeta "Steps".
	-- Atributos: Surface (CFrame del centro de la rampa, LookVector = hacia arriba),
	-- Length (studs a lo largo de la rampa), Spacing (entre escalones), Speed (+ sube, - baja).
	Escalator = "Escalator",

	-- Escalera entre plantas (mecanica o de servicio): la bloquea el evento Piso aislado.
	-- Atributos: Low y High (Vector3: centro de cada extremo, a ras de suelo) y Width (studs).
	FloorConnector = "FloorConnector",

	-- Agua de las fuentes (solo visual, la anima el cliente): laminas de agua que giran
	-- despacio (atributo Spin, rad/s) y focos sumergidos que titilan (atributo Shimmer).
	FountainWater = "FountainWater",

	-- LOBBY (place del lobby, Workspace.Lobby)
	-- Cuadro blanco del suelo donde se crea / reune una sala. Atributo: PadId (number)
	LobbyRoomPad = "LobbyRoomPad",
	-- Puesto de la plaza. Atributos: Stand ("Classes" | "Upgrades"), ActionText, ObjectText.
	-- Debe tener una parte hija llamada "PromptPart" donde aparece el ProximityPrompt.
	LobbyStand = "LobbyStand",
	-- Pantalla de clasificacion. Atributo: Board ("BestNight" | "BossesDefeated").
	-- Debe tener una parte hija llamada "Screen" con un SurfaceGui.
	LobbyLeaderboard = "LobbyLeaderboard",
}
