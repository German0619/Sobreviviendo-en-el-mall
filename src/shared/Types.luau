--!strict
-- Tipos compartidos entre servidor y cliente.

export type StatName = "Health" | "Stamina" | "Battery" | "WalkSpeed"

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type StatConfig = {
	DisplayName: string,
	Base: number,
	PerLevel: number,
	MaxLevel: number,
	BaseCost: number,
	CostGrowth: number,
}

export type ClassDef = {
	DisplayName: string,
	Rarity: Rarity,
	Description: string,
	-- Multiplicadores sobre las estadisticas finales (1.1 = +10%)
	Modifiers: { [string]: number },
	-- Habilidades pasivas que leen otros sistemas (MissionService, EnemyService, ...)
	Perks: { [string]: any },
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
	DiamondsEarned: number,
	RunsPlayed: number,
}

-- Datos PERMANENTES del jugador (DataStore).
export type PlayerData = {
	Version: number,
	Diamonds: number,
	PaidDiamonds: number,
	ClassSlots: { string },
	MaxSlots: number,
	EquippedSlot: number,
	ReviveTokens: number,
	SodaTokens: number,
	ProcessedReceipts: { string },
	BestNight: number,
	Achievements: { [string]: boolean },
	ClaimedAchievements: { [string]: boolean },
	VipDailyDay: number,
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
