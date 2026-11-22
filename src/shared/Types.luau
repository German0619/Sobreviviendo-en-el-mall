--!strict
-- Tipos compartidos entre servidor y cliente.

export type StatName = "Health" | "Stamina" | "Battery" | "WalkSpeed"

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"

export type StatConfig = {
	DisplayName: string,
	Base: number,
	PerLevel: number,
	MaxLevel: number,
	BaseCost: number,
	CostGrowth: number,
}

export type ClassUnlock = {
	Type: "Default" | "Money" | "Achievement",
	Price: number?, -- si Type == "Money"
	Achievement: string?, -- si Type == "Achievement"
	Description: string?,
}

export type ClassDef = {
	DisplayName: string,
	Rarity: Rarity,
	Description: string,
	-- Multiplicadores sobre las estadisticas finales (1.1 = +10%)
	Modifiers: { [string]: number },
	-- Habilidades pasivas que leen otros sistemas (MissionService, EnemyService, ...)
	Perks: { [string]: any },
	Unlock: ClassUnlock,
}

export type SessionLock = {
	JobId: string,
	Time: number,
}

export type LifetimeStats = {
	NightsSurvived: number,
	MissionsCompleted: number,
	Deaths: number,
	MoneyEarned: number,
	RunsPlayed: number,
}

export type PlayerData = {
	Version: number,
	Money: number,
	Upgrades: { [string]: number },
	OwnedClasses: { [string]: boolean },
	EquippedClass: string,
	BestNight: number,
	Inventory: { [string]: number },
	Achievements: { [string]: boolean },
	Lifetime: LifetimeStats,
	SessionLock: SessionLock?,
}

export type ComputedStats = {
	Health: number,
	Stamina: number,
	Battery: number,
	WalkSpeed: number,
}

return nil
