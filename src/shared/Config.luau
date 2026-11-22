--!strict
-- Configuracion central del juego. Todo el balance vive aqui.

local Types = require(script.Parent.Types)

local Config = {}

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
	Common = { DisplayName = "Comun", Order = 1, Color = Color3.fromRGB(190, 190, 190) },
	Rare = { DisplayName = "Rara", Order = 2, Color = Color3.fromRGB(70, 140, 255) },
	Epic = { DisplayName = "Epica", Order = 3, Color = Color3.fromRGB(170, 80, 255) },
	Legendary = { DisplayName = "Legendaria", Order = 4, Color = Color3.fromRGB(255, 180, 40) },
}

Config.DefaultClass = "Conserje"

Config.Classes = {
	-- Comun
	Conserje = {
		DisplayName = "Conserje",
		Rarity = "Common",
		Description = "Equilibrado. Un poco de todo.",
		Modifiers = {},
		Perks = {},
		Unlock = { Type = "Default" },
	},
	Corredor = {
		DisplayName = "Corredor",
		Rarity = "Common",
		Description = "+10% de velocidad al caminar.",
		Modifiers = { WalkSpeed = 1.10 },
		Perks = {},
		Unlock = { Type = "Money", Price = 1500 },
	},
	Atleta = {
		DisplayName = "Atleta",
		Rarity = "Common",
		Description = "+30% de estamina.",
		Modifiers = { Stamina = 1.30 },
		Perks = {},
		Unlock = { Type = "Money", Price = 1500 },
	},

	-- Rara
	Electricista = {
		DisplayName = "Electricista",
		Rarity = "Rare",
		Description = "Repara luces y generadores un 50% mas rapido.",
		Modifiers = {},
		Perks = { RepairSpeed = 1.5 },
		Unlock = { Type = "Money", Price = 5000 },
	},
	Guardia = {
		DisplayName = "Guardia",
		Rarity = "Rare",
		Description = "+30% de vida.",
		Modifiers = { Health = 1.30 },
		Perks = {},
		Unlock = { Type = "Money", Price = 5000 },
	},
	Ahorrador = {
		DisplayName = "Ahorrador",
		Rarity = "Rare",
		Description = "+15% de pago por noche.",
		Modifiers = {},
		Perks = { PayBonus = 0.15 },
		Unlock = { Type = "Money", Price = 6000 },
	},

	-- Epica
	VisionNocturna = {
		DisplayName = "Vision nocturna",
		Rarity = "Epic",
		Description = "Ve en la oscuridad sin linterna.",
		Modifiers = {},
		Perks = { NightVision = true },
		Unlock = {
			Type = "Achievement",
			Achievement = "ReachNight5",
			Description = "Sobrevive hasta la noche 5.",
		},
	},
	Medico = {
		DisplayName = "Medico",
		Rarity = "Epic",
		Description = "Revive a sus companeros el doble de rapido.",
		Modifiers = {},
		Perks = { ReviveSpeed = 2.0 },
		Unlock = { Type = "Money", Price = 15000 },
	},

	-- Legendaria
	Medium = {
		DisplayName = "Medium",
		Rarity = "Legendary",
		Description = "Ve a los fantasmas a traves de las paredes.",
		Modifiers = {},
		Perks = { SeeGhostsThroughWalls = true },
		Unlock = {
			Type = "Achievement",
			Achievement = "ReachNight10",
			Description = "Sobrevive hasta la noche 10.",
		},
	},
	Sombra = {
		DisplayName = "Sombra",
		Rarity = "Legendary",
		Description = "Los enemigos tardan el doble en detectarte.",
		Modifiers = {},
		Perks = { DetectionDelay = 2.0 },
		Unlock = { Type = "Money", Price = 50000 },
	},
} :: { [string]: Types.ClassDef }

-- Logros que desbloquean clases (los comprueba ClassService)
Config.Achievements = {
	ReachNight5 = { DisplayName = "Turno largo", Description = "Llega a la noche 5." },
	ReachNight10 = { DisplayName = "Veterano del turno noche", Description = "Llega a la noche 10." },
}

----------------------------------------------------------------------
-- Tienda del mall (dinero del juego)
----------------------------------------------------------------------
Config.ShopItems = {
	Battery = { DisplayName = "Bateria", Price = 75, Description = "Recarga la linterna al 100%." },
	Medkit = { DisplayName = "Botiquin", Price = 150, Description = "Cura 50 de vida." },
	FlashlightPro = {
		DisplayName = "Linterna Pro",
		Price = 1200,
		Description = "Haz mas amplio y 25% menos consumo.",
		Permanent = true,
	},
}

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

-- Las probabilidades se muestran en la UI (politica de Roblox para objetos aleatorios).
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

----------------------------------------------------------------------
-- Enemigos
----------------------------------------------------------------------
Config.Enemies = {
	Mannequin = { DisplayName = "Maniqui", UnlockNight = 1, BaseCount = 2, Speed = 22, Damage = 35 },
	Blackout = { DisplayName = "Apagon", UnlockNight = 2, BaseCount = 1, Speed = 12, Damage = 25 },
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

Config.DevProducts = {
	Revive = 0,
	PremiumSoda = 0,
	-- Desbloqueo directo de clases: { ClassName = productId }
	ClassUnlocks = {} :: { [string]: number },
}

----------------------------------------------------------------------
-- Datos guardados
----------------------------------------------------------------------
Config.Data = {
	StoreName = "PlayerData_v1",
	AutosaveSeconds = 120,
}

Config.DefaultData = {
	Version = 1,
	Money = 0,
	Upgrades = { Health = 0, Stamina = 0, Battery = 0, WalkSpeed = 0 },
	OwnedClasses = { [Config.DefaultClass] = true },
	EquippedClass = Config.DefaultClass,
	BestNight = 0,
	Inventory = {},
	Achievements = {},
	Lifetime = {
		NightsSurvived = 0,
		MissionsCompleted = 0,
		Deaths = 0,
		MoneyEarned = 0,
		RunsPlayed = 0,
	},
} :: Types.PlayerData

return Config
