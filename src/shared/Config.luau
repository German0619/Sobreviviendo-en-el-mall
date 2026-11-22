--!strict
-- Configuracion central del juego. Todo el balance vive aqui.

local Types = require(script.Parent.Types)

local Config = {}

----------------------------------------------------------------------
-- Pruebas (cambiar para probar mas rapido; dejar en los valores por defecto al publicar)
----------------------------------------------------------------------
Config.Debug = {
	BuildTestMap = true, -- construye un mall de prueba si no hay un mapa con tags
	StartNight = 1, -- pon 2 para que aparezca el Apagon desde el inicio
	NightSecondsOverride = nil :: number?, -- ej. 120 para noches de 2 minutos
	PreparationSecondsOverride = nil :: number?,
	-- SOLO en Studio:
	StudioStartCash = 0, -- billetes al empezar cada partida (ej. 5000 para probar la tienda)
	-- Diamantes que se suman al entrar (ej. 1000 para probar la ruleta).
	-- Ojo: con API Services activado se guardan en tus datos de verdad.
	StudioBonusDiamonds = 0,
}

----------------------------------------------------------------------
-- Partida
----------------------------------------------------------------------
Config.MaxPlayersPerRoom = 5

Config.Night = {
	StartHour = 0, -- 12 AM
	EndHour = 6, -- 6 AM
	RealSeconds = 540, -- duracion real de una noche (9 min)
	PreparationSeconds = 30,
	ResultsSeconds = 10,
	UpgradeSeconds = 30,
}

-- Pago al final de cada noche = Base + PerNight * (noche - 1) + misiones + supervivencia
Config.Pay = {
	Base = 100,
	PerNight = 25,
	SurvivalBonus = 75, -- solo si el jugador sigue vivo a las 6 AM
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
	Angle = 55, -- angulo del SpotLight (visual)
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
		Description = "Repara luces y generadores un 50% más rápido.",
		Modifiers = {},
		Perks = { RepairSpeed = 1.5 },
	},
	Guardia = {
		DisplayName = "Guardia",
		Rarity = "Rare",
		Description = "+30% de vida.",
		Modifiers = { Health = 1.30 },
		Perks = {},
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
	Medico = {
		DisplayName = "Médico",
		Rarity = "Epic",
		Description = "Revive GRATIS a sus compañeros (los demás necesitan Robux).",
		Modifiers = {},
		Perks = { FreeRevive = true, ReviveSpeed = 2.0 },
	},

	-- Legendaria
	Medium = {
		DisplayName = "Médium",
		Rarity = "Legendary",
		Description = "Ve a los fantasmas a través de las paredes.",
		Modifiers = {},
		Perks = { SeeGhostsThroughWalls = true },
	},
	Sombra = {
		DisplayName = "Sombra",
		Rarity = "Legendary",
		Description = "Los enemigos tardan el doble en detectarte.",
		Modifiers = {},
		Perks = { DetectionDelay = 2.0 },
	},
} :: { [string]: Types.ClassDef }

-- Orden en la ventana de clases / probabilidades
Config.ClassOrder = {
	"Conserje",
	"Corredor",
	"Atleta",
	"Electricista",
	"Guardia",
	"Ahorrador",
	"VisionNocturna",
	"Medico",
	"Medium",
	"Sombra",
}

-- Ruleta de clases (en el lobby, antes de crear partida). Cada giro cuesta diamantes.
-- Los pesos se convierten en porcentajes y SIEMPRE se muestran al jugador.
-- El Medico es la mas dificil de conseguir (revive gratis).
Config.Roulette = {
	SpinCost = 100, -- diamantes por giro
	DefaultSlots = 1, -- slots gratis
	MaxSlots = 5, -- maximo comprando slots con Robux
	Weights = {
		Conserje = 22.5,
		Corredor = 20,
		Atleta = 20,
		Electricista = 9,
		Guardia = 9,
		Ahorrador = 9,
		VisionNocturna = 4.5,
		Medium = 2.5,
		Sombra = 2.5,
		Medico = 1,
	},
}

-- Diamantes: moneda permanente (ruleta). Tambien se compran con Robux.
Config.Diamonds = {
	MilestoneNights = 5, -- cada 5 noches sobrevividas (contando todas tus partidas)...
	MilestoneReward = 100, -- ...ganas 100 diamantes
}

-- Logros: dan diamantes. Los comprueba ClassService al terminar cada noche.
-- BestNight: se consigue al sobrevivir esa noche.
Config.Achievements = {
	FirstNight = { DisplayName = "Primer turno", Description = "Sobrevive tu primera noche.", BestNight = 1, Diamonds = 50 },
	ReachNight5 = { DisplayName = "Turno largo", Description = "Sobrevive la noche 5.", BestNight = 5, Diamonds = 150 },
	ReachNight10 = {
		DisplayName = "Veterano del turno noche",
		Description = "Sobrevive la noche 10.",
		BestNight = 10,
		Diamonds = 300,
	},
}

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
	FlashlightPro = {
		DisplayName = "Linterna Pro",
		Price = 1200,
		Description = "Haz más amplio y 25% menos consumo.",
		Unique = true,
	},
}

Config.ShopOrder = { "Battery", "Medkit", "FlashlightPro" }

Config.FlashlightPro = {
	ExtraAngle = 15, -- grados extra del haz visible
	ExtraDetectAngle = 8, -- grados extra del cono que afecta a enemigos
	DrainMultiplier = 0.75,
}

Config.ShopRange = 14 -- distancia maxima al mostrador para comprar

----------------------------------------------------------------------
-- Maquinas expendedoras
----------------------------------------------------------------------
-- Effects: { Stat = multiplicador } o banderas especiales; Duration en segundos.
Config.SodaEffects = {
	-- Positivos
	Speed = { DisplayName = "Turbo", Positive = true, Duration = 30, Modifiers = { WalkSpeed = 1.25 } },
	Vision = { DisplayName = "Ojos de gato", Positive = true, Duration = 45, Flags = { NightVision = true } },
	Regen = { DisplayName = "Regeneracion", Positive = true, Duration = 20, Flags = { RegenPerSecond = 4 } },
	InfiniteStamina = {
		DisplayName = "Estamina infinita",
		Positive = true,
		Duration = 20,
		Flags = { InfiniteStamina = true },
	},
	-- Negativos
	Slow = { DisplayName = "Pesadez", Positive = false, Duration = 20, Modifiers = { WalkSpeed = 0.75 } },
	Blurry = { DisplayName = "Vision borrosa", Positive = false, Duration = 20, Flags = { BlurryVision = true } },
	Tired = { DisplayName = "Cansancio", Positive = false, Duration = 25, Modifiers = { Stamina = 0.6 } },
}

-- Las probabilidades se muestran en la maquina (politica de Roblox para objetos aleatorios).
-- Solo hay una soda activa a la vez: tomar otra reemplaza el efecto anterior.
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
Config.Missions = {
	FixLights = { DisplayName = "Reparar luces", Weight = 30, TimeLimit = 90, Reward = 40, Duration = 4 },
	CleanSpill = { DisplayName = "Limpiar derrame", Weight = 30, TimeLimit = 75, Reward = 30, Duration = 3 },
	RestartGenerator = { DisplayName = "Reiniciar generador", Weight = 15, TimeLimit = 120, Reward = 70, Duration = 6 },
	TakeOutTrash = { DisplayName = "Sacar la basura", Weight = 20, TimeLimit = 90, Reward = 35, Duration = 3 },
	LockDoors = { DisplayName = "Cerrar puertas", Weight = 15, TimeLimit = 60, Reward = 45, Duration = 2 },
	RestockStore = { DisplayName = "Reponer tienda", Weight = 15, TimeLimit = 100, Reward = 50, Duration = 5 },
}

-- Misiones simultaneas maximas segun la noche
function Config.getMaxConcurrentMissions(night: number): number
	return math.min(2 + math.floor(night / 2), 6)
end

Config.MissionSpawn = {
	FirstDelay = 8, -- segundos tras empezar la noche
	BaseInterval = 30, -- segundos entre misiones nuevas en la noche 1
	IntervalPerNight = -2, -- cada noche salen antes
	MinInterval = 12,
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
Config.Enemies = {
	Mannequin = {
		DisplayName = "Maniqui",
		UnlockNight = 1,
		BaseCount = 2,
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
		BaseCount = 1,
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
	Echo = { DisplayName = "Eco", UnlockNight = 3, BaseCount = 1, Speed = 14, Damage = 30 },
	Tracker = { DisplayName = "Rastro", UnlockNight = 5, BaseCount = 1, Speed = 16, Damage = 30 },
	Watcher = { DisplayName = "Vigilante", UnlockNight = 7, BaseCount = 1, Speed = 13, Damage = 40 },
}

-- Multiplicador de dificultad por noche (velocidad, deteccion, cantidad)
function Config.getDifficulty(night: number)
	local n = math.max(night - 1, 0)
	return {
		SpeedMultiplier = 1 + 0.06 * n,
		DetectionMultiplier = 1 + 0.10 * n,
		ExtraCount = math.floor(n / 2),
	}
end

----------------------------------------------------------------------
-- Monetizacion (IDs de la web de Roblox; 0 = aun no creado)
----------------------------------------------------------------------
Config.GamePasses = {
	DoubleMoney = 0,
	PremiumFlashlight = 0,
	VIP = 0,
}

-- Developer Products (se crean en create.roblox.com -> tu experiencia -> Monetization).
-- El precio en Robux se define alli; aqui solo va el ID.
Config.DevProducts = {
	Revive = 0, -- revivir (a ti mismo o a un companero)
	ClassSlot = 0, -- +1 slot de clase (hasta Config.Roulette.MaxSlots)
	PremiumSoda = 0, -- (Fase 8)
	DiamondPacks = {
		{ Id = 0, Amount = 100 },
		{ Id = 0, Amount = 550 },
		{ Id = 0, Amount = 1200 },
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
	Version = 2,
	Diamonds = 0, -- total de diamantes
	PaidDiamonds = 0, -- cuantos de ellos se compraron con Robux (politica de objetos aleatorios)
	ClassSlots = { Config.DefaultClass }, -- clase en cada slot
	MaxSlots = Config.Roulette.DefaultSlots,
	EquippedSlot = 1,
	ReviveTokens = 0, -- revivires comprados que no se pudieron usar
	ProcessedReceipts = {}, -- compras de Robux ya entregadas (evita entregarlas dos veces)
	BestNight = 0,
	Achievements = {},
	Lifetime = {
		NightsSurvived = 0,
		MissionsCompleted = 0,
		Deaths = 0,
		MoneyEarned = 0,
		DiamondsEarned = 0,
		RunsPlayed = 0,
	},
} :: Types.PlayerData

return Config
