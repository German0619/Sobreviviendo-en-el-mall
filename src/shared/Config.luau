--!strict
-- Configuracion central del juego. Todo el balance vive aqui.

local Types = require(script.Parent.Types)

local Config = {}

----------------------------------------------------------------------
-- Pruebas (cambiar para probar mas rapido; dejar en los valores por defecto al publicar)
----------------------------------------------------------------------
Config.Debug = {
	-- Que place simular en Studio cuando el place no esta publicado ni tiene el
	-- atributo PlaceRole en Workspace: "Mall" (la partida) o "Lobby".
	PlaceRole = "Mall",
	-- La ruleta y los slots solo existen en el lobby. (true = permitirlos tambien en el
	-- mall dentro de Studio; desactivado: en el mall no se cambia de clase)
	ClassesInMallInStudio = false,
	BuildTestMap = true, -- construye el mall (MallBuilder) o el lobby si el place no tiene uno propio
	-- true = la partida empieza sola en cuanto hay alguien (sin esperar a que el anfitrion pulse Iniciar)
	AutoStart = false,
	StartNight = 1, -- pon 2 (Apagon), 3 (Eco), 5 (Rastro) o 7 (Vigilante) para probarlos desde el inicio
	OnlyEnemies = nil :: { string }?, -- ej. { "Echo" }: solo salen esos tipos (para probar uno)
	Tier3MaxOverride = nil :: number?, -- ej. 3: permite varios de nivel 3 a la vez (para probarlos)
	MissionGoalOverride = nil :: number?, -- ej. 2: tareas necesarias para pasar la noche (para probar)
	OnlyEvents = nil :: { string }?, -- ej. { "Fog" }: solo salen esos eventos (para probarlos)
	EventDelayOverride = nil :: number?, -- ej. 10: segundos hasta el primer evento y entre eventos
	PreparationSecondsOverride = nil :: number?,
	-- SOLO en Studio:
	StudioStartCash = 0, -- billetes al empezar cada partida (ej. 5000 para probar la tienda)
	-- Diamantes que se suman al entrar (ej. 1000 para probar la ruleta).
	-- Ojo: con API Services activado se guardan en tus datos de verdad.
	StudioBonusDiamonds = 0,
	-- Pases que se simulan como comprados en Studio (ej. { "DoubleMoney", "VIP" })
	StudioOwnedPasses = {} :: { string },
}

----------------------------------------------------------------------
-- Places y salas (Fase 6)
----------------------------------------------------------------------
-- IDs de los dos places de la experiencia (create.roblox.com -> tu experiencia -> Places).
-- 0 = aun no publicado. El mismo codigo de Rojo se sincroniza en ambos places;
-- cada uno sabe quien es por estos IDs o por el atributo PlaceRole de Workspace.
Config.Places = {
	LobbyPlaceId = 94961138619437, -- place de inicio
	MallPlaceId = 94971350910183, -- la partida (servidores reservados)
}

Config.MaxPlayersPerRoom = 5 -- poner tambien "Max Players" = 5 en la configuracion del place del mall

-- Salas (grupos) en MemoryStoreService. Se arman EN EL LOBBY: nadie viaja al mall
-- hasta que el anfitrion pulsa INICIAR PARTIDA o la sala se llena.
Config.Rooms = {
	NameMaxLength = 24,
	CodeLength = 6, -- codigo para salas privadas (y publicas)
	CodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789", -- sin 0/O ni 1/I
	InitialExpiration = 600, -- caducidad al crear/modificar la sala
	RefreshExpiration = 120, -- los servidores con miembros la renuevan cada RefreshSeconds con esta caducidad
	RefreshSeconds = 20,
	PollSeconds = 2, -- cada cuanto cada lobby revisa las salas de sus jugadores (inicio, miembros)
	ListRefreshSeconds = 5, -- cache de la lista de salas publicas en el lobby
	ListMax = 100,
	MaxTeleportAttempts = 3, -- reintentos de viaje al mall antes de sacar al jugador de la sala
	ArrivalTimeout = 25, -- en el mall: segundos maximos esperando a que lleguen todos los miembros
	-- Cuadros de sala de la plaza (PadService)
	PadStartSeconds = 40, -- la partida empieza sola este tiempo despues de abrir la sala
	PadChooseSeconds = 15, -- tiempo para elegir publica / solo amigos (si no, queda publica)
}

----------------------------------------------------------------------
-- Partida
----------------------------------------------------------------------

-- La noche se gana completando la cuota de tareas del equipo (Config.getMissionGoal):
-- el reloj avanza con cada tarea y marca las 6 AM al completarla. Se pierde si
-- cae todo el equipo. Pasado OvertimeSeconds, los enemigos se aceleran cada minuto.
Config.Night = {
	StartHour = 0, -- 12 AM
	EndHour = 6, -- 6 AM
	OvertimeSeconds = 480, -- a partir de aqui los enemigos se impacientan
	OvertimeSpeedPerMinute = 0.05, -- +5% de velocidad por minuto extra
	MaxOvertimeBonus = 0.5,
	PreparationSeconds = 30,
	ResultsSeconds = 10,
	UpgradeSeconds = 30,
}

-- Cuota de tareas por noche: Base + PerNight * (noche - 1) + PerExtraPlayer * (jugadores - 1)
Config.NightGoal = {
	Base = 4,
	PerNight = 1,
	PerExtraPlayer = 1.5,
	Max = 20,
}

function Config.getMissionGoal(night: number, players: number): number
	if Config.Debug.MissionGoalOverride then
		return Config.Debug.MissionGoalOverride
	end
	local g = Config.NightGoal
	local goal = g.Base + g.PerNight * (night - 1) + g.PerExtraPlayer * (math.max(players, 1) - 1)
	return math.clamp(math.floor(goal + 0.5), 1, g.Max)
end

-- Pago al completar cada noche (por jugador del equipo, vivo o caido):
--   Base + PerNight * (noche - 1) + (tareas del equipo / jugadores) + NightCompleteBonus
-- Lo de las tareas va a un fondo comun que se reparte a partes iguales.
Config.Pay = {
	Base = 100,
	PerNight = 25,
	NightCompleteBonus = 75,
}

----------------------------------------------------------------------
-- Estadisticas y mejoras
----------------------------------------------------------------------
Config.Stats = {
	Health = {
		DisplayName = "Vida",
		Base = 100,
		PerLevel = 10,
		MaxLevel = 10,
		BaseCost = 150,
		CostGrowth = 1.35,
	},
	Stamina = {
		DisplayName = "Estamina",
		Base = 100,
		PerLevel = 12,
		MaxLevel = 10,
		BaseCost = 120,
		CostGrowth = 1.3,
	},
	Battery = {
		DisplayName = "Bateria de linterna",
		Base = 120, -- segundos de luz
		PerLevel = 15,
		MaxLevel = 10,
		BaseCost = 100,
		CostGrowth = 1.3,
	},
	WalkSpeed = {
		DisplayName = "Velocidad",
		Base = 14,
		PerLevel = 0.5,
		MaxLevel = 8,
		BaseCost = 200,
		CostGrowth = 1.45,
	},
} :: { [string]: Types.StatConfig }

Config.StatOrder = { "Health", "Stamina", "Battery", "WalkSpeed" }

Config.Movement = {
	SprintMultiplier = 1.6,
	StaminaDrainPerSecond = 20,
	StaminaRegenPerSecond = 12,
	StaminaRegenDelay = 1.2,
}

Config.Flashlight = {
	DrainPerSecond = 1, -- segundos de bateria por segundo encendida
	Range = 45,
	Angle = 38, -- angulo del SpotLight (visual): cono estrecho, haz recto de linterna
	Brightness = 3,
	DetectHalfAngle = 22, -- cono (grados) en el que la linterna "alumbra" a un enemigo
}

function Config.getUpgradeCost(statName: string, currentLevel: number): number?
	local stat = Config.Stats[statName]
	if not stat or currentLevel >= stat.MaxLevel then
		return nil
	end
	return math.floor(stat.BaseCost * stat.CostGrowth ^ currentLevel)
end

----------------------------------------------------------------------
-- Clases
----------------------------------------------------------------------
Config.Rarities = {
	Common = { DisplayName = "Común", Order = 1, Color = Color3.fromRGB(190, 190, 190) },
	Rare = { DisplayName = "Rara", Order = 2, Color = Color3.fromRGB(70, 140, 255) },
	Epic = { DisplayName = "Épica", Order = 3, Color = Color3.fromRGB(170, 80, 255) },
	Legendary = { DisplayName = "Legendaria", Order = 4, Color = Color3.fromRGB(255, 180, 40) },
	Mythic = { DisplayName = "Mítica", Order = 5, Color = Color3.fromRGB(255, 70, 120) },
}

Config.DefaultClass = "Conserje"

-- Las clases se obtienen con la ruleta (Config.Roulette) y se guardan en slots.
-- Modifiers: multiplicadores de estadisticas. Perks: habilidades que leen otros sistemas.
Config.Classes = {
	-- Comun
	Conserje = {
		DisplayName = "Conserje",
		Rarity = "Common",
		Description = "Equilibrado. Un poco de todo.",
		Modifiers = {},
		Perks = {},
	},
	Corredor = {
		DisplayName = "Corredor",
		Rarity = "Common",
		Description = "+10% de velocidad al caminar.",
		Modifiers = { WalkSpeed = 1.10 },
		Perks = {},
	},
	Atleta = {
		DisplayName = "Atleta",
		Rarity = "Common",
		Description = "+30% de estamina.",
		Modifiers = { Stamina = 1.30 },
		Perks = {},
	},

	-- Rara
	Electricista = {
		DisplayName = "Electricista",
		Rarity = "Rare",
		Description = "Repara un 50% más rápido. Sus destellos gastan la mitad de batería.",
		Modifiers = {},
		Perks = { RepairSpeed = 1.5, FlashCostMultiplier = 0.5, FlashCooldownMultiplier = 0.7 },
	},
	Guardia = {
		DisplayName = "Guardia",
		Rarity = "Rare",
		Description = "+30% de vida. Porrazo: empuja y aturde a los enemigos cercanos.",
		Modifiers = { Health = 1.30 },
		Perks = { Shove = true },
	},
	Ahorrador = {
		DisplayName = "Ahorrador",
		Rarity = "Rare",
		Description = "+15% de pago por noche.",
		Modifiers = {},
		Perks = { PayBonus = 0.15 },
	},

	-- Epica
	VisionNocturna = {
		DisplayName = "Visión nocturna",
		Rarity = "Epic",
		Description = "Ve en la oscuridad sin linterna.",
		Modifiers = {},
		Perks = { NightVision = true },
	},
	Medium = {
		DisplayName = "Médium",
		Rarity = "Epic",
		Description = "Ve a los fantasmas a través de las paredes.",
		Modifiers = {},
		Perks = { SeeGhostsThroughWalls = true },
	},

	-- Legendaria
	Sombra = {
		DisplayName = "Sombra",
		Rarity = "Legendary",
		Description = "Los enemigos tardan el doble en detectarte.",
		Modifiers = {},
		Perks = { DetectionDelay = 2.0 },
	},
	Medico = {
		DisplayName = "Médico",
		Rarity = "Legendary",
		Description = "Revive GRATIS a sus compañeros (los demás necesitan Robux).",
		Modifiers = {},
		Perks = { FreeRevive = true, ReviveSpeed = 2.0 },
	},

	-- Mitica
	GuardianLunar = {
		DisplayName = "Guardián lunar",
		Rarity = "Mythic",
		Description = "Protector de Plaza Luna: más resistente, ve en la oscuridad y a los fantasmas.",
		Modifiers = { Health = 1.5, Stamina = 1.5, WalkSpeed = 1.15 },
		Perks = { NightVision = true, SeeGhostsThroughWalls = true },
	},
	ConserjeExperimentado = {
		DisplayName = "Conserje experimentado",
		Rarity = "Mythic",
		Description = "Lo ha visto todo: tiene las habilidades de todas las demás clases.",
		Modifiers = {}, -- se rellenan abajo con lo mejor de cada clase
		Perks = {},
	},
} :: { [string]: Types.ClassDef }

-- El Conserje experimentado reune lo mejor de TODAS las clases no miticas
-- (se calcula, asi hereda tambien las clases que se agreguen despues):
--   Modifiers: el mayor de cada estadistica.
--   Perks: true si alguna lo tiene; numeros: el menor si es un "...Multiplier"
--   (menos coste/espera es mejor), si no el mayor.
do
	local veteran = Config.Classes.ConserjeExperimentado
	for _, class in Config.Classes do
		if class.Rarity ~= "Mythic" then
			for stat, mult in class.Modifiers do
				veteran.Modifiers[stat] = math.max(veteran.Modifiers[stat] or 1, mult)
			end
			for perk, value in class.Perks do
				local current = veteran.Perks[perk]
				if type(value) == "number" then
					if current == nil then
						veteran.Perks[perk] = value
					elseif string.sub(perk, -10) == "Multiplier" then
						veteran.Perks[perk] = math.min(current, value)
					else
						veteran.Perks[perk] = math.max(current, value)
					end
				elseif value then
					veteran.Perks[perk] = value
				end
			end
		end
	end
end

-- Orden en la ventana de clases / probabilidades
Config.ClassOrder = {
	"Conserje",
	"Corredor",
	"Atleta",
	"Electricista",
	"Guardia",
	"Ahorrador",
	"VisionNocturna",
	"Medium",
	"Sombra",
	"Medico",
	"GuardianLunar",
	"ConserjeExperimentado",
}

-- Ruleta de clases (en el lobby, antes de crear partida). Cada giro cuesta diamantes.
-- Los pesos se convierten en porcentajes y SIEMPRE se muestran al jugador.
-- El Medico es la mas dificil de conseguir (revive gratis).
Config.Roulette = {
	SpinCost = 100, -- diamantes por giro
	DefaultSlots = 1, -- slots gratis
	MaxSlots = 5, -- maximo comprando slots con Robux
	Weights = {
		-- Los pesos suman 100, asi que cada uno es su % (el Conserje cede lo de las miticas)
		Conserje = 22.4499,
		Corredor = 20,
		Atleta = 20,
		Electricista = 9,
		Guardia = 9,
		Ahorrador = 9,
		VisionNocturna = 4.5, -- Epica
		Medium = 2.5, -- Epica
		Sombra = 2.5, -- Legendaria
		Medico = 1, -- Legendaria
		GuardianLunar = 0.05, -- Mitica
		ConserjeExperimentado = 0.0001, -- Mitica: 1 entre un millon
	},
	-- Tiro afortunado (Robux, Config.DevProducts.LuckySpin): solo sale una clase de
	-- estas rarezas, con los mismos pesos relativos. Sus % tambien se muestran siempre.
	LuckyRarities = { Epic = true, Legendary = true, Mythic = true },
	-- Segundos que dura la animacion del giro (la placa sobre la cabeza espera a que termine)
	RevealSeconds = 3,
}

-- Probabilidades en % de la ruleta (lucky = tiro afortunado), en el orden de Config.ClassOrder.
-- Las usan el servidor (para sortear) y el cliente (para mostrarlas).
function Config.getRouletteWeights(lucky: boolean?): { [string]: number }
	local weights = {}
	for className, weight in Config.Roulette.Weights do
		local class = Config.Classes[className]
		if class and (not lucky or Config.Roulette.LuckyRarities[class.Rarity]) then
			weights[className] = weight
		end
	end
	return weights
end

function Config.getRouletteOdds(lucky: boolean?): { { Class: string, Percent: number } }
	local weights = Config.getRouletteWeights(lucky)
	local total = 0
	for _, w in weights do
		total += w
	end
	local list = {}
	for _, className in Config.ClassOrder do
		local w = weights[className]
		if w and total > 0 then
			table.insert(list, { Class = className, Percent = w / total * 100 })
		end
	end
	return list
end

-- Diamantes: moneda permanente (ruleta). Tambien se compran con Robux.
Config.Diamonds = {
	MilestoneNights = 5, -- cada 5 noches sobrevividas (contando todas tus partidas)...
	MilestoneReward = 100, -- ...ganas 100 diamantes
}

-- Logros: dan diamantes. Los comprueba ClassService al terminar cada noche.
-- BestNight: se consigue al sobrevivir esa noche.
-- Se DESBLOQUEAN solos al llegar a la meta y los diamantes se dan al RECLAMARLOS
-- en el panel LOGROS del lobby (AchievementService). Los jefes sumaran los suyos.
-- Stat: que se mide (ver Config.getAchievementProgress). Goal: la meta.
Config.Achievements = {
	FirstRun = { DisplayName = "Primer día", Description = "Juega tu primera partida.", Stat = "RunsPlayed", Goal = 1, Diamonds = 25 },
	FirstNight = { DisplayName = "Primer turno", Description = "Sobrevive tu primera noche.", Stat = "BestNight", Goal = 1, Diamonds = 50 },
	ReachNight5 = { DisplayName = "Turno largo", Description = "Sobrevive la noche 5.", Stat = "BestNight", Goal = 5, Diamonds = 150 },
	ReachNight10 = {
		DisplayName = "Veterano del turno noche",
		Description = "Sobrevive la noche 10.",
		Stat = "BestNight",
		Goal = 10,
		Diamonds = 300,
	},
	ReachNight20 = {
		DisplayName = "Leyenda de Plaza Luna",
		Description = "Sobrevive la noche 20.",
		Stat = "BestNight",
		Goal = 20,
		Diamonds = 600,
	},
	Survive25 = { DisplayName = "Insomne", Description = "Sobrevive 25 noches en total.", Stat = "NightsSurvived", Goal = 25, Diamonds = 150 },
	Missions10 = { DisplayName = "Manos a la obra", Description = "Completa 10 tareas.", Stat = "MissionsCompleted", Goal = 10, Diamonds = 50 },
	Missions100 = { DisplayName = "Empleado del mes", Description = "Completa 100 tareas.", Stat = "MissionsCompleted", Goal = 100, Diamonds = 200 },
	Money10k = { DisplayName = "Buen sueldo", Description = "Gana 10,000 billetes en total.", Stat = "MoneyEarned", Goal = 10000, Diamonds = 100 },
	EpicClass = { DisplayName = "Suerte épica", Description = "Consigue una clase Épica o mejor.", Stat = "BestRarity", Goal = 3, Diamonds = 75 },
	LegendaryClass = {
		DisplayName = "Leyenda en la ruleta",
		Description = "Consigue una clase Legendaria o mejor.",
		Stat = "BestRarity",
		Goal = 4,
		Diamonds = 200,
	},
	MythicClass = { DisplayName = "Mito viviente", Description = "Consigue una clase Mítica.", Stat = "BestRarity", Goal = 5, Diamonds = 1000 },
}

Config.AchievementOrder = {
	"FirstRun",
	"FirstNight",
	"ReachNight5",
	"ReachNight10",
	"ReachNight20",
	"Survive25",
	"Missions10",
	"Missions100",
	"Money10k",
	"EpicClass",
	"LegendaryClass",
	"MythicClass",
}

-- Progreso actual de un logro segun los datos guardados del jugador.
function Config.getAchievementProgress(data: any, achievement: any): number
	local stat = achievement.Stat
	if stat == "BestNight" then
		return data.BestNight or 0
	elseif stat == "BestRarity" then
		-- La mejor rareza que tienes en tus slots (1 Comun ... 5 Mitica)
		local best = 0
		for _, className in data.ClassSlots or {} do
			local class = Config.Classes[className]
			local rarity = class and Config.Rarities[class.Rarity]
			if rarity then
				best = math.max(best, rarity.Order)
			end
		end
		return best
	end
	return (data.Lifetime and data.Lifetime[stat]) or 0
end

----------------------------------------------------------------------
-- VIP (Game Pass Config.GamePasses.VIP)
----------------------------------------------------------------------
Config.VIP = {
	DailyDiamonds = 50, -- se reclaman una vez por dia (UTC) en el panel LOGROS
	SpinDiscount = 0.2, -- la ruleta cuesta un 20% menos
}

-- Diamantes que cuesta un giro de la ruleta (VIP con descuento).
function Config.getSpinCost(isVip: boolean?): number
	local discount = if isVip then Config.VIP.SpinDiscount else 0
	return math.floor(Config.Roulette.SpinCost * (1 - discount) + 0.5)
end

----------------------------------------------------------------------
-- Revivir y deteccion
----------------------------------------------------------------------
-- Revivir cuesta Robux (producto Config.DevProducts.Revive), salvo con el Medico.
Config.Revive = {
	HoldSeconds = 8, -- lo que mantiene E el Medico (dividido por su ReviveSpeed)
	HealthFraction = 0.5, -- vida con la que vuelves
	WipeGraceSeconds = 12, -- si caen todos: segundos para revivir con Robux antes de perder
}

-- Los enemigos tienen que "notarte" antes de perseguirte.
Config.Detection = {
	BaseTime = 0.6, -- segundos viendote para detectarte (x DetectionDelay de la clase Sombra)
	Memory = 6, -- segundos que te siguen buscando tras perderte de vista
	SenseRange = 90, -- distancia maxima de vision
	CloseRange = 8, -- a esta distancia te sienten aunque no te vean
}

----------------------------------------------------------------------
-- Tienda del mall (dinero del juego)
----------------------------------------------------------------------
-- Los objetos son POR VIDA: se pierden al morir o salir de la partida.
-- Use: que hace al usarlo (tecla Hotkey). Unique: solo puedes llevar uno (no se gasta).
Config.ShopItems = {
	Battery = {
		DisplayName = "Batería",
		Price = 75,
		Description = "Recarga la linterna al 100%.",
		MaxStack = 5,
		Use = "RechargeBattery",
		Hotkey = 1,
	},
	Medkit = {
		DisplayName = "Botiquín",
		Price = 150,
		Description = "Cura 50 de vida.",
		MaxStack = 3,
		Use = "Heal",
		Amount = 50,
		Hotkey = 2,
	},
	Flare = {
		DisplayName = "Bengala",
		Price = 120,
		Description = "Ilumina una zona 20 s. El Apagón no puede entrar.",
		MaxStack = 3,
		Use = "ThrowFlare",
		Hotkey = 3,
	},
	Firecracker = {
		DisplayName = "Petardo",
		Price = 90,
		Description = "Lánzalo: atrae a los enemigos cercanos unos segundos.",
		MaxStack = 3,
		Use = "ThrowFirecracker",
		Hotkey = 4,
	},
	FlashlightPro = {
		DisplayName = "Linterna Pro",
		Price = 1200,
		Description = "Haz más amplio y 25% menos consumo.",
		Unique = true,
	},

	-- Armas (Weapon = true): una equipada a la vez, se usa con [R]. Comprar otra
	-- reemplaza a la que llevas. Se pierden al morir. Datos en Config.Weapons.
	Taser = {
		DisplayName = "Taser",
		Price = 250,
		Description = "Aturde 10 s al enemigo de enfrente (nivel 3: 1 s). 10 usos.",
		Weapon = true,
	},
	Extinguisher = {
		DisplayName = "Extintor",
		Price = 200,
		Description = "Nube que ciega a los enemigos 5 s. Útil contra el Rastro. 6 usos.",
		Weapon = true,
	},
	WetFloorSign = {
		DisplayName = "Cartel de piso mojado",
		Price = 150,
		Description = "Trampa: los enemigos que pasan van a mitad de velocidad. 3 usos.",
		Weapon = true,
	},
	UVFlashlight = {
		DisplayName = "Linterna UV",
		Price = 300,
		Description = "Enciende la luz UV: revela al Eco de lejos. Gasta más batería.",
		Weapon = true,
	},
	Mop = {
		DisplayName = "Trapeador",
		Price = 100,
		Description = "Empujón corto que aturde 1.5 s. Sin límite de usos.",
		Weapon = true,
	},
}

Config.ShopOrder = {
	"Battery",
	"Medkit",
	"Flare",
	"Firecracker",
	"FlashlightPro",
	"Taser",
	"Extinguisher",
	"WetFloorSign",
	"UVFlashlight",
	"Mop",
}

-- Armas (WeaponService). Uses = usos (nil = infinitos). Cooldown en segundos.
-- Son defensas temporales: aturden o apartan, no matan (sigue siendo un juego de terror).
Config.Weapons = {
	Taser = {
		Uses = 10,
		Cooldown = 8,
		Range = 14, -- alcance del disparo (el enemigo mas cercano delante de ti)
		HalfAngle = 25, -- grados del cono de apuntado
		StunSeconds = 10,
		Tier3StunSeconds = 1, -- contra enemigos de nivel 3 apenas sirve
	},
	Extinguisher = {
		Uses = 6,
		Cooldown = 6,
		Range = 10, -- a que distancia delante de ti se forma la nube
		Radius = 9,
		Duration = 5, -- los enemigos no ven a quien este dentro ni ven desde dentro
	},
	WetFloorSign = {
		Uses = 3,
		Cooldown = 4,
		Radius = 7,
		SpeedMultiplier = 0.5, -- los enemigos dentro van a mitad de velocidad
		Duration = 45,
	},
	UVFlashlight = {
		Cooldown = 0.5, -- [R] enciende / apaga la luz UV
		Range = 60, -- revela a esta distancia (la linterna normal llega a Config.Flashlight.Range)
		RevealSeconds = 3, -- cuanto dura marcado el enemigo revelado
		DrainMultiplier = 1.8, -- la bateria baja mas rapido con la UV encendida
	},
	Mop = {
		Cooldown = 10,
		Range = 7,
		StunSeconds = 1.5, -- menos que el Porrazo del Guardia
		Distance = 7, -- studs que retroceden
	},
}

Config.FlashlightPro = {
	ExtraAngle = 15, -- grados extra del haz visible
	ExtraDetectAngle = 8, -- grados extra del cono que afecta a enemigos
	DrainMultiplier = 0.75,
}

Config.ShopRange = 14 -- distancia maxima al mostrador para comprar

----------------------------------------------------------------------
-- Defensa contra las entidades (DefenseService)
----------------------------------------------------------------------
-- Defenderse cuesta recursos y es temporal: el juego sigue siendo de terror.
Config.Defense = {
	-- [G] Destello de linterna: gasta bateria de golpe y aturde a los enemigos del cono.
	-- El Apagon huye al instante; el Maniqui queda congelado aunque nadie lo mire.
	Flash = {
		BatteryCost = 25, -- segundos de bateria (x FlashCostMultiplier del Electricista)
		Cooldown = 10, -- (x FlashCooldownMultiplier)
		StunSeconds = 4,
		RangeMultiplier = 1.15, -- alcance respecto a Config.Flashlight.Range
		ExtraHalfAngle = 10, -- grados extra sobre el cono normal de la linterna
	},
	-- [Q] Porrazo del Guardia (Perk Shove): empuja y aturde a los enemigos de enfrente.
	Shove = {
		Range = 9,
		Distance = 12, -- studs que retroceden
		StunSeconds = 2.5,
		Cooldown = 25,
	},
	-- Bengala: zona iluminada. El Apagon no entra y no siente a quien este dentro;
	-- el Maniqui se ve dentro aunque la zona este a oscuras.
	Flare = {
		Duration = 20,
		Radius = 18,
		ThrowRange = 18,
	},
	-- Petardo: tras la mecha, atrae a los enemigos cercanos que no esten encima de alguien.
	Firecracker = {
		Fuse = 1.5,
		Duration = 7,
		Radius = 70,
		ThrowRange = 30,
		IgnoreIfTargetWithin = 12, -- si el enemigo ya esta a esta distancia de su presa, no se distrae
	},
	-- Escondites (tag HidingSpot): rompen la persecucion si el enemigo no te vio entrar.
	Hiding = {
		MaxSeconds = 30, -- luego sales solo (te falta el aire)
		Cooldown = 4,
		PromptDistance = 6,
		SeenEnteringWindow = 0.5, -- si un enemigo que te perseguia te vio en este margen, sabe donde estas
	},
}

----------------------------------------------------------------------
-- Maquinas expendedoras
----------------------------------------------------------------------
-- Effects: { Stat = multiplicador } o banderas especiales; Duration en segundos.
Config.SodaEffects = {
	-- Positivos
	Speed = {
		DisplayName = "Turbo",
		Description = "+25% de velocidad.",
		Positive = true,
		Duration = 30,
		Modifiers = { WalkSpeed = 1.25 },
	},
	Vision = {
		DisplayName = "Ojos de gato",
		Description = "Ves en la oscuridad.",
		Positive = true,
		Duration = 45,
		Flags = { NightVision = true },
	},
	Regen = {
		DisplayName = "Regeneracion",
		Description = "+4 de vida por segundo.",
		Positive = true,
		Duration = 20,
		Flags = { RegenPerSecond = 4 },
	},
	InfiniteStamina = {
		DisplayName = "Estamina infinita",
		Description = "Corres sin cansarte.",
		Positive = true,
		Duration = 20,
		Flags = { InfiniteStamina = true },
	},
	-- Negativos
	Slow = { DisplayName = "Pesadez", Positive = false, Duration = 20, Modifiers = { WalkSpeed = 0.75 } },
	Blurry = { DisplayName = "Vision borrosa", Positive = false, Duration = 20, Flags = { BlurryVision = true } },
	Tired = { DisplayName = "Cansancio", Positive = false, Duration = 25, Modifiers = { Stamina = 0.6 } },
}

-- Soda a eleccion (Robux, producto Config.DevProducts.PremiumSoda) en las maquinas "Premium":
-- el jugador ELIGE el efecto antes de pagar, asi que no es un objeto aleatorio de pago.
Config.ChoiceSoda = {
	DisplayName = "Soda a elección",
	Effects = { "Speed", "Vision", "Regen", "InfiniteStamina" },
	DurationMultiplier = 1.5,
}

-- Las probabilidades se muestran en la maquina (politica de Roblox para objetos aleatorios).
-- Positivas: una a la vez (otra positiva reemplaza a la anterior).
-- Negativas: se acumulan, cada una con su tiempo; repetir la misma SUMA su duracion.
Config.VendingMachines = {
	Cheap = {
		DisplayName = "Soda misteriosa",
		Price = 50,
		Weights = { Speed = 15, Vision = 15, Regen = 10, InfiniteStamina = 10, Slow = 20, Blurry = 15, Tired = 15 },
	},
	Premium = {
		DisplayName = "Soda premium",
		Price = 250,
		Weights = { Speed = 30, Vision = 25, Regen = 25, InfiniteStamina = 20 },
	},
}

----------------------------------------------------------------------
-- Misiones
----------------------------------------------------------------------
-- Reward va al fondo del equipo. Duration = segundos manteniendo E (por paso en las de varios pasos).
-- Count = pasos en las misiones de varios puntos. Las que caducan (TimeLimit) fallan y potencian enemigos.
Config.Missions = {
	FixLights = { DisplayName = "Reparar luces", Weight = 25, TimeLimit = 120, Reward = 40, Duration = 4 },
	CleanSpill = { DisplayName = "Limpiar derrame", Weight = 25, TimeLimit = 110, Reward = 30, Duration = 3 },
	TakeOutTrash = { DisplayName = "Sacar la basura", Weight = 18, TimeLimit = 150, Reward = 40, Duration = 2 },
	RestartGenerator = {
		DisplayName = "Reiniciar generador",
		Weight = 8,
		TimeLimit = 150,
		Reward = 70,
		Duration = 6,
	},
	LockDoors = { DisplayName = "Bajar persianas", Weight = 12, TimeLimit = 150, Reward = 55, Duration = 2, Count = 3 },
	RestockStore = { DisplayName = "Reponer tienda", Weight = 14, TimeLimit = 160, Reward = 50, Duration = 2 },
	CheckCameras = { DisplayName = "Revisar cámaras", Weight = 8, TimeLimit = 120, Reward = 45, Duration = 4 },
	UnclogToilet = { DisplayName = "Desatascar baño", Weight = 10, TimeLimit = 120, Reward = 40, Duration = 5 },
	SilenceAlarm = { DisplayName = "Apagar alarma", Weight = 10, TimeLimit = 75, Reward = 45, Duration = 3 },
	LostItem = { DisplayName = "Objeto perdido", Weight = 10, TimeLimit = 160, Reward = 45, Duration = 1 },
	WaterPlants = { DisplayName = "Regar plantas", Weight = 10, TimeLimit = 150, Reward = 40, Duration = 2, Count = 3 },
}

-- Detalles de algunas misiones
Config.MissionDetails = {
	SilenceAlarm = { LureRadius = 75 }, -- la alarma atrae a los enemigos mientras suena
	CheckCameras = { RevealSeconds = 6 }, -- al completarla, el equipo ve a todos los enemigos
	UnclogToilet = { PuddleSize = 6 }, -- el agua del baño es un derrame (la huele el Rastro)
}

-- Brillo de todas las luces del mall (multiplica el Brightness de cada luz al construir
-- el mapa). 1 = como estaba diseñado; 0.4 = penumbra de mall cerrado (mas miedo).
Config.MallLightScale = 0.4

-- Zonas sin luz de ambiente (bodega, servicio, almacen y oficinas): siempre a oscuras,
-- solo luces de emergencia. Ahi se juega con la linterna. LightService las marca como
-- oscuras al empezar (no tienen misiones de "Reparar luces").
Config.DarkZones = {
	"Bodega",
	"Servicio",
	"Almacén alto",
	"Oficinas",
	"Escalera de servicio",
	"Administración",
	"Sala de descanso",
	"Baños P2",
	"Archivo",
	"Sala de máquinas",
}

-- Tamano del mapa: el mall tiene 2 plantas (~1.8x de superficie). Multiplica (redondeando
-- hacia abajo) las misiones simultaneas y la cantidad de enemigos para que la densidad
-- sea parecida a la del mapa de una planta. 1 = sin escalar.
Config.MapScale = 1.5

-- Misiones simultaneas maximas segun la noche y el tamano del equipo
function Config.getMaxConcurrentMissions(night: number, players: number?): number
	local base = 2 + math.floor(night / 2) + math.floor((players or 1) / 2)
	return math.min(math.floor(base * Config.MapScale), 12)
end

Config.MissionSpawn = {
	FirstDelay = 8, -- segundos tras empezar la noche
	BaseInterval = 30, -- segundos entre misiones nuevas en la noche 1
	IntervalPerNight = -2, -- cada noche salen antes
	MinInterval = 10,
	PerExtraPlayer = 0.2, -- cada jugador extra acorta el intervalo un 20%
	MinActive = 2, -- si hay menos tareas activas que esto, sale otra a los RefillInterval segundos
	RefillInterval = 4,
	RewardPerNight = 0.10, -- +10% de recompensa por noche
}

-- Cuanto se potencian los enemigos por cada mision fallada
Config.Threat = {
	SpeedPerFailedMission = 0.04, -- +4% velocidad a todos por mision fallada
	BlackoutPerFailedLights = 0.15, -- +15% velocidad/resistencia del Apagon por luces sin reparar
}

----------------------------------------------------------------------
-- Enemigos
----------------------------------------------------------------------
-- Cuantos y cuales aparecen lo decide el director por presupuesto (Config.SpawnDirector).
-- UnlockNight: primera noche en que puede salir. Tier: nivel de peligro (1-3, ver su coste).
-- MaxPerFloor: tope de ese tipo en cada planta.
-- Hint: aviso con su contramedida la primera vez que aparece en la partida.
Config.Enemies = {
	Mannequin = {
		DisplayName = "Maniqui",
		UnlockNight = 1,
		Tier = 1,
		MaxPerFloor = 3,
		Speed = 20,
		Damage = 35,
		AttackRange = 3.5,
		AttackCooldown = 1.5,
		ViewHalfAngle = 50, -- grados: cono de vision del jugador que lo congela
		ViewRange = 150,
	},
	Blackout = {
		DisplayName = "Apagon",
		UnlockNight = 2,
		Tier = 1,
		MaxPerFloor = 2,
		Hint = "Nuevo: el Apagón deja zonas a oscuras. Alúmbralo con la linterna o usa el destello para que huya.",
		Speed = 11,
		Damage = 25,
		AttackRange = 4,
		AttackCooldown = 1.5,
		HoverHeight = 4.5,
		DarkenDelay = 2.5, -- parpadeo antes de apagar la zona
		ExposureToFlee = 2.5, -- segundos de linterna para hacerlo huir
		FleeCooldown = 12,
		ZoneLinger = 15, -- segundos sin victimas antes de cambiar de zona
	},
	-- Carrito: si te ve en linea recta tiembla y embiste. Apartate; si choca con una pared queda aturdido.
	Cart = {
		DisplayName = "Carrito",
		UnlockNight = 2,
		Tier = 1,
		MaxPerFloor = 2,
		Speed = 9, -- buscando / patrullando (x0.6)
		ChargeRange = 40, -- distancia maxima para lanzarse
		WindupSeconds = 0.9, -- tiembla antes de embestir (aviso para apartarse)
		ChargeSpeed = 42,
		ChargeDistance = 55, -- recorrido maximo de una embestida
		HitRadius = 3.2,
		Damage = 30,
		WallStunSeconds = 4,
		RecoverSeconds = 2, -- pausa tras una embestida sin chocar
		Hint = "Nuevo: el Carrito embiste en línea recta. Cuando tiemble, apártate: si choca con una pared, queda aturdido.",
	},
	-- Globo: flota quieto. Si lo miras fijamente se hincha, revienta y atrae a los enemigos.
	-- Reventarlo de lejos (taser, destello, porrazo, trapeador) no hace ruido.
	Balloon = {
		DisplayName = "Globo",
		UnlockNight = 3,
		Tier = 1,
		MaxPerFloor = 2,
		HoverHeight = 6,
		LookRange = 70,
		LookHalfAngle = 15, -- grados: hay que mirarlo casi de frente
		PopSeconds = 3, -- segundos mirandolo hasta que revienta
		DeflatePerSecond = 0.25, -- lo que se deshincha por segundo si nadie lo mira (0..1)
		LureSeconds = 10,
		LureRadius = 90,
		SafeDistance = 15, -- reventarlo desde mas lejos que esto no hace ruido
		RespawnSeconds = 45,
		RespawnMinDistance = 35,
		Hint = "Nuevo: el Globo revienta si lo miras fijamente y el estallido atrae a los enemigos. No lo mires, o reviéntalo de lejos.",
	},
	-- Polillas de luz: persiguen las linternas encendidas y les chupan la bateria (no hacen dano).
	-- Apagar la linterna las despista; una bengala o un petardo las atrae; el destello las dispersa.
	Moth = {
		DisplayName = "Polillas",
		UnlockNight = 4,
		Tier = 1,
		MaxPerFloor = 2,
		Speed = 6, -- revoloteando
		ChaseSpeed = 13,
		HoverHeight = 5,
		SenseRange = 70, -- ven una linterna encendida a esta distancia
		DrainRange = 6,
		DrainPerSecond = 5, -- segundos de bateria por segundo (aparte del consumo normal)
		LingerSeconds = 3, -- siguen a donde estaba la luz tras apagarla
		ScatterSeconds = 15, -- dispersas tras un destello
		Hint = "Nuevo: las Polillas siguen tu linterna y le chupan la batería. Apágala o lánzales una bengala.",
	},
	-- Eco: se hace pasar por un companero (nombre, linterna y pasos). Alumbrarlo lo revela y lo hace
	-- desaparecer; el destello lo hace al instante. Si te alcanza, golpea y se esfuma.
	Echo = {
		DisplayName = "Eco",
		UnlockNight = 3,
		Tier = 2,
		MaxPerFloor = 2,
		Speed = 8, -- acechando
		LungeSpeed = 17, -- al acercarse sin que lo alumbren
		LungeDistance = 14,
		Damage = 30,
		AttackRange = 4,
		AttackCooldown = 2,
		SenseRange = 80, -- te "oye" a esta distancia, aunque haya paredes
		ExposureToVanish = 1, -- segundos alumbrado para desaparecer
		VanishSeconds = 10, -- tiempo desaparecido antes de volver
		ReappearMinDistance = 35, -- vuelve lejos de los jugadores
		Hint = "Nuevo: el Eco imita a tus compañeros. Si un \"compañero\" se te acerca, alúmbralo con la linterna.",
	},
	-- Reflejo: acecha dentro de los vidrios y espejos (tag ReflectiveSurface). Si lo miras fijamente,
	-- sale y te persigue un rato. La linterna UV lo marca; el destello lo devuelve al cristal.
	Reflection = {
		DisplayName = "Reflejo",
		UnlockNight = 4,
		Tier = 2,
		MaxPerFloor = 1,
		LurkRange = 45, -- elige vidrios a esta distancia de algun jugador
		RelocateSeconds = 12, -- cambia de vidrio cada tanto si nadie lo mira
		LookRange = 50,
		LookHalfAngle = 20, -- grados: hay que mirarlo casi de frente
		EmergeSeconds = 1.5, -- segundos mirandolo hasta que sale
		EmergeWindup = 0.7, -- aviso (sale del cristal) antes de perseguir
		ChaseSpeed = 16,
		ChaseSeconds = 12,
		Damage = 30,
		AttackRange = 4,
		VanishSeconds = 10, -- tras golpear o un destello, tarda esto en volver a un vidrio
		ReappearMinDistance = 30,
		Hint = "Nuevo: el Reflejo vive en los vidrios y espejos. Si ves una silueta en un cristal, no la mires fijamente.",
	},
	-- Ducto: se arrastra por las rejillas del techo (tag CeilingVent) y se le oye. Si corres cerca
	-- de una rejilla, la hace temblar y cae sobre ti. Caminar sin correr cerca de las rejillas lo evita.
	Duct = {
		DisplayName = "Ducto",
		UnlockNight = 5,
		Tier = 2,
		MaxPerFloor = 1,
		CrawlSpeed = 14, -- por dentro del techo
		HearRange = 55, -- oye a quien corre a esta distancia
		DropRange = 14, -- distancia horizontal a la rejilla para dejarse caer
		RattleSeconds = 1.3, -- la rejilla tiembla antes de caer (aviso)
		LandSeconds = 0.8, -- al caer se queda agazapado mirandote antes de perseguirte
		HuntSpeed = 17,
		HuntSeconds = 7,
		Damage = 35,
		AttackRange = 3.5,
		AttackCooldown = 1.5,
		ClimbCooldown = 6, -- tras volver a subir no baja enseguida
		Hint = "Nuevo: el Ducto anda por las rejillas del techo. Si oyes ruido arriba, camina: correr cerca lo hace caer.",
	},
	-- Cajero: no hace dano, persigue al que lleva billetes y le roba una parte. Si lo aturdes
	-- (destello, porrazo, taser, trapeador) antes de que escape, recuperas el dinero.
	Cashier = {
		DisplayName = "Cajero",
		UnlockNight = 4,
		Tier = 2,
		MaxPerFloor = 1,
		Speed = 10, -- patrullando
		ChaseSpeed = 15,
		FleeSpeed = 19,
		MinCash = 10, -- ignora a quien lleva menos
		StealFraction = 0.3,
		StealMin = 10,
		AttackRange = 3.5,
		FleeSeconds = 14, -- si no lo aturdes en este tiempo, se queda el dinero
		StealCooldown = 20,
		Hint = "Nuevo: el Cajero roba billetes. Si te roba, atúrdelo antes de que escape para recuperarlos.",
	},
	-- Megafonia: no tiene cuerpo. Anuncia tareas falsas con su marca "!"; al acercarte, salta
	-- una alarma que atrae a los enemigos. Las falsas NO salen en tu lista de tareas.
	Intercom = {
		DisplayName = "Megafonía",
		UnlockNight = 6,
		Tier = 2,
		MaxPerFloor = 1,
		FirstDelay = 20, -- segundos hasta el primer anuncio
		Interval = { 45, 70 }, -- segundos entre anuncios
		FakeLifetime = 60, -- la tarea falsa desaparece sola
		MinDistance = 40, -- la pone a esta distancia de los jugadores (o mas)
		MaxDistance = 120,
		TriggerRange = 7,
		LureSeconds = 12,
		LureRadius = 110,
		Hint = "Nuevo: la Megafonía anuncia tareas falsas. Si una tarea no aparece en tu lista, ¡no vayas!",
	},
	-- Rastro: si pisas un derrame te marca y te sigue a donde vayas (incluso a un escondite).
	-- Limpiar los derrames lo mantiene a raya. Cada derrame sin limpiar lo hace mas rapido.
	Tracker = {
		DisplayName = "Rastro",
		UnlockNight = 5,
		Tier = 2,
		MaxPerFloor = 1,
		Speed = 10, -- patrullando
		ChaseSpeed = 15, -- si te ve sin olor
		TrackSpeed = 18, -- siguiendo tu olor
		Damage = 30,
		AttackRange = 3.5,
		AttackCooldown = 1.5,
		MarkSeconds = 20, -- lo que dura el olor tras pisar un derrame
		SpeedPerDirtySpill = 0.08, -- +8% por cada derrame fallado esta noche
		Hint = "Nuevo: el Rastro huele los derrames. Si pisas uno, te seguirá a donde vayas. ¡Límpialos!",
	},
	-- Estatua de la fuente: la estatua de la fuente central (tag FountainStatue) despierta y
	-- te sigue sin descanso; te siente a traves de las paredes. No le afectan el destello,
	-- el porrazo, el taser ni los petardos: SOLO la frena la luz de una bengala.
	Statue = {
		DisplayName = "Estatua",
		UnlockNight = 6,
		Tier = 3,
		MaxPerFloor = 1,
		MaxTotal = 1, -- solo hay una estatua
		TaserImmune = true,
		Speed = 9.5, -- mas lenta que caminar: se la deja atras, pero no para nunca
		SenseRange = 110, -- te siente (pasos) a esta distancia aunque haya paredes
		Damage = 50,
		AttackRange = 4.5,
		AttackCooldown = 2,
		WakeSeconds = 2.5, -- tiembla en la fuente antes de bajar
		FlareMargin = 3, -- se detiene a esta distancia del borde de la luz de una bengala
		Hint = "Nuevo: la Estatua de la fuente ha despertado. Nada la detiene, salvo la luz de una bengala.",
	},
	-- Mimico: una de las maquinas expendedoras del mall (tag VendingMachine) esta viva.
	-- No se mueve. Muerde a quien intenta comprar en ella o se queda delante. Pistas: sus
	-- luces parpadean y gotea; la linterna UV la delata y el destello la hace enseñar los dientes.
	Mimic = {
		DisplayName = "Mímico",
		UnlockNight = 8,
		Tier = 3,
		MaxPerFloor = 1,
		MaxTotal = 2,
		Damage = 60,
		BiteRange = 5, -- delante de la maquina
		LingerSeconds = 2.5, -- quedarse delante tanto tiempo tambien lo hace morder
		RelocateSeconds = 40, -- tras morder cambia de maquina (lejos de los jugadores)
		TellInterval = { 5, 10 }, -- segundos entre pistas (parpadeo / goteo) si hay alguien cerca
		TellRange = 30,
		RevealSeconds = 4, -- UV o destello: se le ven los dientes
		Hint = "Nuevo: una máquina expendedora es un Mímico. Si sus luces parpadean o gotea, no compres en ella.",
	},
	-- Cazador: marca al jugador mas solo y lo persigue sabiendo siempre donde esta.
	-- Ignora a los demas. Reunirte con otro jugador (o esconderte lejos de el) rompe la marca.
	Hunter = {
		DisplayName = "Cazador",
		UnlockNight = 9,
		Tier = 3,
		MaxPerFloor = 1,
		MaxTotal = 1,
		Speed = 9, -- buscando presa
		ChaseSpeed = 15.5, -- algo mas rapido que caminar: hay que correr
		Damage = 45,
		AttackRange = 4,
		AttackCooldown = 2,
		LonelyDistance = 35, -- marca al que este a mas de esto del resto (o jugando solo)
		GroupDistance = 15, -- a esta distancia de otro jugador...
		GroupSeconds = 3, -- ...durante este tiempo, la marca se rompe
		HideEscapeDistance = 25, -- esconderse con el Cazador mas lejos que esto rompe la marca
		MarkSeconds = 35, -- la marca dura como mucho esto
		MarkCooldown = 15, -- pausa antes de marcar a otro
		RetreatSeconds = 20, -- tras golpear desaparece y vuelve lejos
		Hint = "Nuevo: el Cazador marca al que está más solo. Si te marca, ¡reúnete con tu equipo o escóndete lejos de él!",
	},
	-- Vigilante: patrulla y ve a traves de las camaras de seguridad (tag SecurityCamera).
	-- Esquiva sus haces rojos o ciega las camaras con el destello.
	Watcher = {
		DisplayName = "Vigilante",
		UnlockNight = 7,
		Tier = 3,
		MaxPerFloor = 1,
		Speed = 11,
		ChaseSpeed = 17,
		Damage = 40,
		AttackRange = 4,
		AttackCooldown = 1.8,
		AlertMemory = 10, -- segundos que va hacia donde una camara te vio
		Hint = "Nuevo: el Vigilante ve por las cámaras. Evita sus haces rojos o ciégalas con el destello.",
	},
}

----------------------------------------------------------------------
-- Eventos de la noche (EventDirector, un modulo por evento en server/Events)
----------------------------------------------------------------------
-- Uno cada 2-3 minutos, como mucho 1 activo, y un numero maximo por noche (PerNight).
-- Cada evento tiene su enfriamiento (Cooldown, en segundos de juego).
-- Weight: probabilidad relativa. Los mas fuertes (Apagon general, Oleada, Megafonia hackeada,
-- Hora de oro, Suministros, Camaras amigas) tienen menos peso que los normales (8-10).
-- Kind: "Bad" | "Good" | "Mixed" (color del aviso). Floor: true = ocurre en una planta
-- (la de mas jugadores, con algo de azar); false = en todo el mall.
-- Las "misiones de evento" no cuentan para la cuota, no pagan y no avanzan el reloj;
-- si caducan, el evento sigue (se prolonga).
Config.EventDirector = {
	FirstDelay = 60, -- segundos desde el inicio de la noche hasta el primer evento
	Interval = { 120, 180 }, -- segundos entre el inicio de un evento y el siguiente
	GapAfterEnd = 20, -- y al menos esto tras terminar el anterior
	-- Eventos por noche. Cada noche se decide al empezar cuantos habra: hay Max huecos y
	-- cada uno sale con probabilidad Chance (asi no esta asegurado que salgan todos).
	-- GuaranteedBad: cuantos de ellos seran negativos seguro.
	PerNight = {
		{ UpToNight = 4, Max = 1, Chance = 0.65 }, -- noches 1-4: como mucho 1
		{ UpToNight = 10, Max = 2, Chance = 0.7 }, -- noches 5-10: como mucho 2
		{ UpToNight = math.huge, Max = 3, Chance = 1, GuaranteedBad = 2 }, -- 11+: 3, 2 negativos
	},
	-- Los negativos salen algo mas que los positivos, y los positivos cada vez menos:
	-- peso de un positivo x max(GoodMin, 1 - GoodFadePerNight * (noche - 1)).
	BadWeightMultiplier = 1.25,
	GoodFadePerNight = 0.06,
	GoodMin = 0.35,
}

Config.Events = {
	GeneralBlackout = {
		DisplayName = "Apagón general",
		Kind = "Bad",
		Description = "Todo el mall se queda a oscuras. Reinicien los generadores principales.",
		MinNight = 4,
		Weight = 5, -- de los mas fuertes: sale menos
		Cooldown = 600,
		Floor = false,
		MaxSeconds = 240, -- si nadie arregla nada, vuelve la luz a los 4 minutos
		MissionSeconds = 90, -- tiempo de cada mision de generador (al caducar se renueva)
		HoldSeconds = 6,
	},
	Fog = {
		DisplayName = "Neblina",
		Kind = "Bad",
		Description = "Una niebla densa entra en el mall. Ni tú ni ellos verán lejos.",
		MinNight = 3,
		Weight = 10,
		Cooldown = 420,
		Floor = false,
		Duration = 90,
		FadeSeconds = 10,
		SenseMultiplier = 0.6, -- los enemigos ven a menos distancia
	},
	WeakBatteries = {
		DisplayName = "Baterías débiles",
		Kind = "Bad",
		Description = "Las linternas gastan el doble de batería durante 2 minutos.",
		MinNight = 2,
		Weight = 10,
		Cooldown = 420,
		Floor = false,
		Duration = 120,
		DrainMultiplier = 2,
	},
	Wave = {
		DisplayName = "Oleada",
		Kind = "Bad",
		Description = "Una horda de entidades aparece en tu planta durante 60 segundos.",
		MinNight = 3,
		Weight = 5, -- de los mas fuertes: sale menos
		Cooldown = 480,
		Floor = true,
		Duration = 60,
		BaseCount = 3,
		PerNights = 3, -- +1 enemigo cada 3 noches
		MaxCount = 8,
	},
	MarkedPlayer = {
		DisplayName = "Jugador marcado",
		Kind = "Bad",
		Description = "Un jugador atrae a los enemigos. Se anula acercándose a un compañero.",
		MinNight = 2,
		Weight = 8,
		Cooldown = 420,
		Floor = false,
		Duration = 45,
		LureRadius = 80,
		ClearDistance = 10, -- junto a un companero a esta distancia...
		ClearSeconds = 1.5, -- ...durante este tiempo
	},
	HackedIntercom = {
		DisplayName = "Megafonía hackeada",
		Kind = "Bad",
		Description = "La megafonía anuncia tareas falsas. Fíate solo de tu lista.",
		MinNight = 5,
		Weight = 4, -- de los mas fuertes: sale menos
		Cooldown = 600,
		Floor = true,
		Duration = 120,
		Interval = { 20, 30 }, -- anuncia mucho mas seguido que la Megafonia normal
	},
	FireAlarm = {
		DisplayName = "Alarma de incendio",
		Kind = "Bad",
		Description = "Los rociadores mojan una zona: allí vas más lento y las bengalas se apagan. Apaguen la alarma.",
		MinNight = 4,
		Weight = 8,
		Cooldown = 480,
		Floor = true,
		Duration = 90,
		Radius = 40, -- zona mojada alrededor de donde salta (junto a un jugador de la planta)
		WalkMultiplier = 0.6, -- suelo mojado (tambien al correr)
		HoldSeconds = 3,
	},
	GoldenHour = {
		DisplayName = "Hora de oro",
		Kind = "Good",
		Description = "Las tareas pagan el doble 2 minutos... pero los enemigos van más rápido.",
		MinNight = 1,
		Weight = 6, -- de los mas fuertes: sale menos
		Cooldown = 480,
		Floor = false,
		Duration = 120,
		RewardMultiplier = 2,
		EnemySpeedMultiplier = 1.15,
	},
	Supplies = {
		DisplayName = "Suministros",
		Kind = "Good",
		Description = "Ha caído una caja de suministros. Ábrela antes de que se la lleven.",
		MinNight = 1,
		Weight = 6, -- de los mas fuertes: sale menos
		Cooldown = 360,
		Floor = true,
		MissionSeconds = 90,
		HoldSeconds = 1.5,
		Items = { Flare = 1, Battery = 1, Medkit = 1 }, -- para quien la abre
	},
	FriendlyCameras = {
		DisplayName = "Cámaras amigas",
		Kind = "Good",
		Description = "Las cámaras de seguridad funcionan: úsalas para ver a todas las entidades.",
		MinNight = 2,
		Weight = 6, -- de los mas fuertes: sale menos
		Cooldown = 420,
		Floor = false,
		MissionSeconds = 75,
		HoldSeconds = 2,
		RevealSeconds = 10,
	},
}

-- Camaras de seguridad (las usa el Vigilante; solo funcionan las noches en que hay Vigilante)
Config.SecurityCameras = {
	Range = 50,
	HalfAngle = 20, -- grados del cono de vision
	SweepDegrees = 80, -- barrido total de lado a lado
	SweepSeconds = 7,
	DetectSeconds = 0.8, -- tiempo viendote para avisar al Vigilante (x DetectionDelay de la Sombra)
	DisabledSeconds = 20, -- cegada por un destello
}

-- Plantas del mall: por debajo de SplitY es la planta baja (1), por encima la alta (2).
-- (La planta alta esta a 18 studs; sirve para spawns y para la posicion de los jugadores.)
Config.Floors = {
	SplitY = 10,
}

function Config.getFloor(y: number): number
	return if y >= Config.Floors.SplitY then 2 else 1
end

-- Director de aparicion por presupuesto (SpawnDirector). Cada noche:
--   1. Presupuesto = (Base + PerNight * (noche - 1)) x (1 + PerExtraPlayer por jugador extra) x MapScale.
--   2. Se sortea el nivel de cada enemigo con TierOdds (la fila de la noche) y se paga su TierCost.
--      Si un nivel no tiene enemigos disponibles (por UnlockNight o topes) se reparte entre los demas.
--   3. Topes: Tier3Max(noche) de nivel 3 y MaxPerFloor de cada tipo por planta.
--   4. Cada enemigo va a una planta segun cuantos jugadores hay en cada una.
--   5. InitialShare del presupuesto aparece al empezar; el resto, uno cada StaggerSeconds.
--      Los de nivel 3 nunca aparecen al principio.
-- Valores de partida para ajustar jugando.
Config.SpawnDirector = {
	TierCost = { 1, 3, 6 },
	Budget = {
		Base = 2,
		PerNight = 1.5,
		PerExtraPlayer = 0.35,
		Max = 60,
	},
	-- { desde la noche, { % nivel 1, % nivel 2, % nivel 3 } } (tabla del documento de diseno)
	TierOdds = {
		{ 1, { 85, 15, 0 } },
		{ 3, { 60, 35, 5 } },
		{ 5, { 40, 40, 20 } },
		{ 8, { 25, 45, 30 } },
		{ 11, { 15, 40, 45 } },
	},
	InitialShare = 0.5,
	StaggerSeconds = 25,
	EmptyFloorWeight = 0.5, -- peso de una planta sin jugadores al repartir (para que no quede vacia)
	BossBudgetMultiplier = 0.5, -- las noches de jefe (Fase 9) usan la mitad
}

-- Maximo de enemigos de nivel 3 a la vez.
function Config.getTier3Max(night: number): number
	if Config.Debug.Tier3MaxOverride then
		return Config.Debug.Tier3MaxOverride
	end
	return if night >= 11 then 2 else 1
end

-- Presupuesto de peligro de la noche.
function Config.getDangerBudget(night: number, players: number, multiplier: number?): number
	local b = Config.SpawnDirector.Budget
	local base = b.Base + b.PerNight * math.max(night - 1, 0)
	local playerFactor = 1 + b.PerExtraPlayer * math.max(players - 1, 0)
	local budget = math.floor(base * playerFactor * Config.MapScale * (multiplier or 1))
	return math.clamp(budget, 1, b.Max)
end

-- % de cada nivel en esta noche ({ n1, n2, n3 }).
function Config.getTierOdds(night: number): { number }
	local odds = Config.SpawnDirector.TierOdds[1][2]
	for _, row in Config.SpawnDirector.TierOdds do
		if night >= row[1] then
			odds = row[2]
		end
	end
	return odds
end

-- Multiplicador de dificultad por noche (velocidad y deteccion; la cantidad la decide el director)
function Config.getDifficulty(night: number)
	local n = math.max(night - 1, 0)
	return {
		SpeedMultiplier = math.min(1 + 0.05 * n, 1.6),
		DetectionMultiplier = math.min(1 + 0.10 * n, 2.5),
	}
end

----------------------------------------------------------------------
-- Monetizacion (IDs de la web de Roblox; 0 = aun no creado)
----------------------------------------------------------------------
-- Creados el 2026-11-23 (precio inicial: 199 / 149 / 249 R$; se cambia en el Creator Dashboard)
Config.GamePasses = {
	DoubleMoney = 2098534334,
	PremiumFlashlight = 2100340312,
	VIP = 2100244294,
}

-- Lo que se muestra en la tienda del lobby para cada pase (orden = Config.GamePassOrder)
Config.GamePassInfo = {
	DoubleMoney = {
		DisplayName = "x2 Billetes",
		Description = "Cobras el doble cada noche, en todas tus partidas.",
	},
	PremiumFlashlight = {
		DisplayName = "Linterna Premium",
		Description = "Empiezas cada vida con la Linterna Pro, con un haz dorado.",
	},
	VIP = {
		DisplayName = "VIP",
		Description = "50 💎 gratis cada día, ruleta 20% más barata, [VIP] en el chat y nombre dorado.",
	},
}
Config.GamePassOrder = { "DoubleMoney", "PremiumFlashlight", "VIP" }

-- Developer Products (se crean en create.roblox.com -> tu experiencia -> Monetization).
-- El precio en Robux se define alli; aqui solo va el ID.
-- Creados el 2026-11-23 (precio inicial en R$ entre parentesis)
Config.DevProducts = {
	Revive = 3735454697, -- (25) revivir (a ti mismo o a un companero)
	ClassSlot = 3735454585, -- (99) +1 slot de clase (hasta Config.Roulette.MaxSlots)
	PremiumSoda = 3735454715, -- (15) soda a eleccion (Config.ChoiceSoda)
	LuckySpin = 3735454677, -- (49) tiro afortunado: garantiza clase Epica o superior (lobby)
	DiamondPacks = {
		{ Id = 3735454464, Amount = 100 }, -- (49)
		{ Id = 3735454548, Amount = 550 }, -- (199)
		{ Id = 3735454564, Amount = 1200 }, -- (399)
	},
}

----------------------------------------------------------------------
-- Datos guardados
----------------------------------------------------------------------
Config.Data = {
	StoreName = "PlayerData_v1",
	AutosaveSeconds = 120,
}

-- Solo lo PERMANENTE. Billetes, mejoras y objetos son por partida (RunState / ShopService).
Config.DefaultData = {
	Version = 3,
	Diamonds = 0, -- total de diamantes
	PaidDiamonds = 0, -- cuantos de ellos se compraron con Robux (politica de objetos aleatorios)
	ClassSlots = { Config.DefaultClass }, -- clase en cada slot
	MaxSlots = Config.Roulette.DefaultSlots,
	EquippedSlot = 1,
	ReviveTokens = 0, -- revivires comprados que no se pudieron usar
	SodaTokens = 0, -- sodas a eleccion compradas que no se pudieron usar
	ProcessedReceipts = {}, -- compras de Robux ya entregadas (evita entregarlas dos veces)
	BestNight = 0,
	Achievements = {}, -- [id] = true: desbloqueado
	ClaimedAchievements = {}, -- [id] = true: ya se cobraron sus diamantes
	VipDailyDay = 0, -- dia (UTC, os.time() // 86400) del ultimo bono diario VIP
	Lifetime = {
		NightsSurvived = 0,
		MissionsCompleted = 0,
		Deaths = 0,
		MoneyEarned = 0,
		DiamondsEarned = 0,
		RunsPlayed = 0,
		BossesDefeated = 0, -- lo suma el sistema de jefes (tabla "Jefes vencidos")
	},
} :: Types.PlayerData

----------------------------------------------------------------------
-- Tablas de clasificacion (pantallas del fondo de la plaza; LeaderboardService)
----------------------------------------------------------------------
-- Cada tabla es un OrderedDataStore global. Stat = atributo del Player que se sube.
Config.Leaderboards = {
	Top = 5, -- jugadores por pantalla (mas filas no se leen bien desde la plaza)
	RefreshSeconds = 60, -- cada cuanto se releen en el lobby
	Boards = {
		BestNight = {
			Title = "NOCHE RÉCORD",
			Store = "Leaderboard_BestNight_v1",
			Stat = "BestNight",
			Format = "Noche %d",
			Empty = "¡Sé el primero en sobrevivir una noche!",
		},
		BossesDefeated = {
			Title = "JEFES VENCIDOS",
			Store = "Leaderboard_BossesDefeated_v1",
			Stat = "BossesDefeated",
			Format = "%d jefes",
			Empty = "Aún nadie ha vencido a un jefe.",
		},
	},
}

return Config
