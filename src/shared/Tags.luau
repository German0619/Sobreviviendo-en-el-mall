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
	-- Caja registradora de una tienda (mision ResetRegisters). Atributo Wing = zona de la galeria.
	CashRegister = "CashRegister",
	-- Pantalla del escaparate de una tienda (mision TurnOffDisplays). Atributo Wing. Tiene un
	-- SurfaceGui "Screen" que se apaga.
	StoreDisplay = "StoreDisplay",
	-- Reloj de control de la ronda de seguridad (mision SecurityRound). Atributo Zone.
	PatrolClock = "PatrolClock",
	-- Mostrador de una tienda donde se entrega un paquete (mision Delivery). Atributo Zone.
	StoreCounter = "StoreCounter",
	-- Bandeja de albaranes en Administracion: se firma la entrega (mision Delivery).
	DeliveryDesk = "DeliveryDesk",
	-- Mesa del patio de comidas donde puede quedar una bandeja (mision ClearTrays).
	TraySpot = "TraySpot",
	-- Cubo donde se tiran las bandejas (mision ClearTrays).
	TrayBin = "TrayBin",
	-- Plaza del estacionamiento donde puede quedar un carrito abandonado (mision CollectCarts).
	CartSpot = "CartSpot",
	-- Corral de carritos del estacionamiento (mision CollectCarts).
	CartCorral = "CartCorral",
	-- Caño de un grifo de los baños (mision CloseFaucets). Atributo Zone ("Baños" / "Baños P2").
	Faucet = "Faucet",
	-- Recreativa de la zona de juegos (mision ResetArcade). Atributo Zone.
	ArcadeMachine = "ArcadeMachine",
	-- Proyector de una sala de cine (mision TurnOffProjector). Atributo Zone = sala.
	Projector = "Projector",
	-- Extintor de pared (mision CheckExtinguishers). Atributo Floor ("Planta baja" / "Planta alta").
	Extinguisher = "Extinguisher",
	-- Telefono publico (mision PayPhone). Atributo Zone.
	PayPhone = "PayPhone",
	-- Papelera (mision EmptyBins). Atributo Zone = ala de la galeria.
	Wastebasket = "Wastebasket",
	-- Estanteria del fondo de una tienda (mision Inventory). Atributo Zone = tienda.
	InventoryShelf = "InventoryShelf",
	-- Valvula de la caldera (mision PurgeBoiler). Atributo Zone. Hijo "Wheel" (la rueda).
	BoilerValve = "BoilerValve",
	-- Panel de la caldera (mision PurgeBoiler: se reinicia al final).
	BoilerControl = "BoilerControl",
	-- Herramienta de la obra del Ala Sur (mision UnplugTools). Atributo Zone = "Ala Sur" / "Ala Sur P2".
	PowerTool = "PowerTool",
	-- Peana de un maniqui destapado de los grandes almacenes (mision CoverMannequins).
	-- Atributo Zone. El maniqui es un Model hijo de la peana; HomeCFrame = su sitio.
	SheetMannequin = "SheetMannequin",
	-- Luz de emergencia sin bateria del pasillo de servicio (mision RestoreEmergencyLights).
	-- Atributo Zone = "Pasillo de servicio" / "Pasillo de servicio P2". Hijo "Lens".
	EmergencyBox = "EmergencyBox",

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
	-- Puesto de la plaza. Atributos: Stand ("Classes" | "Upgrades" | "Cosmetics" (SKINS) |
	-- "SkinBox" (CAJA) | "Locker" (TAQUILLA)), ActionText, ObjectText.
	-- Debe tener una parte hija llamada "PromptPart" donde aparece el ProximityPrompt.
	LobbyStand = "LobbyStand",
	-- Pantalla de clasificacion. Atributo: Board ("BestNight" | "BossesDefeated").
	-- Debe tener una parte hija llamada "Screen" con un SurfaceGui.
	LobbyLeaderboard = "LobbyLeaderboard",
}
