-- SpawnDirector: decide QUE enemigos aparecen cada noche, en que planta y cuando,
-- gastando un presupuesto de peligro (ver Config.SpawnDirector).
--
-- Plan(night, playersPerFloor, opts) es una funcion pura (sin efectos): devuelve la
-- lista de apariciones y EnemyService las ejecuta. Asi se puede probar sin jugar.
--
--   Cada enemigo tiene un nivel (Config.Enemies[x].Tier) con su coste (TierCost).
--   Se sortea el nivel con los % de la noche (Config.getTierOdds); entre los niveles
--   que aun se pueden pagar y tienen algun tipo disponible, se reparte el %.
--   Topes: Config.getTier3Max(noche) de nivel 3, MaxPerFloor de cada tipo por planta
--   y MaxTotal (opcional) de cada tipo en todo el mall.
--   Planta: con peso = jugadores en esa planta (o EmptyFloorWeight si no hay nadie).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local SpawnDirector = {}

export type Spawn = {
	Type: string,
	Tier: number,
	Floor: number,
	Delay: number, -- segundos desde el inicio de la noche
}

export type PlanOptions = {
	Rng: Random?,
	BudgetMultiplier: number?, -- noches de jefe: Config.SpawnDirector.BossBudgetMultiplier
	Allowed: { string }?, -- solo estos tipos (Config.Debug.OnlyEnemies)
	Floors: number?, -- plantas del mapa (2)
}

-- Tipos disponibles esta noche, agrupados por nivel.
local function typesByTier(night: number, allowed: { string }?): { [number]: { string } }
	local byTier = { {}, {}, {} }
	for enemyType, def in Config.Enemies do
		local tier = def.Tier
		if
			tier
			and byTier[tier]
			and night >= (def.UnlockNight or 1)
			and (allowed == nil or table.find(allowed, enemyType) ~= nil)
		then
			table.insert(byTier[tier], enemyType)
		end
	end
	for _, list in byTier do
		table.sort(list) -- orden estable (mismo resultado con la misma semilla)
	end
	return byTier
end

local function pickWeighted(weights: { number }, rng: Random): number?
	local total = 0
	for _, w in weights do
		total += w
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for i, w in weights do
		roll -= w
		if roll <= 0 and w > 0 then
			return i
		end
	end
	for i = #weights, 1, -1 do
		if weights[i] > 0 then
			return i
		end
	end
	return nil
end

function SpawnDirector.Plan(night: number, playersPerFloor: { number }, opts: PlanOptions?): ({ Spawn }, number)
	local options = opts or {}
	local rng = options.Rng or Random.new()
	local floors = options.Floors or 2
	local cfg = Config.SpawnDirector

	local players = 0
	for f = 1, floors do
		players += playersPerFloor[f] or 0
	end
	local budget = Config.getDangerBudget(night, math.max(players, 1), options.BudgetMultiplier)
	local totalBudget = budget

	local byTier = typesByTier(night, options.Allowed)
	local odds = Config.getTierOdds(night)
	local tier3Max = Config.getTier3Max(night)

	local count: { [string]: { [number]: number } } = {} -- [tipo][planta]
	local tierCount = { 0, 0, 0 }
	local picks: { { Type: string, Tier: number, Floor: number } } = {}

	local function hasRoom(enemyType: string, floor: number): boolean
		local def = Config.Enemies[enemyType]
		local perFloor = count[enemyType] or {}
		-- (los topes de los niveles 1 y 2 se multiplican por CapMultiplier; el nivel 3 no)
		local cap = def.MaxPerFloor or math.huge
		if (def.Tier or 1) < 3 then
			cap *= Config.SpawnDirector.CapMultiplier or 1
		end
		if (perFloor[floor] or 0) >= cap then
			return false
		end
		-- MaxTotal: tope entre las dos plantas (p. ej. solo hay una Estatua)
		if def.MaxTotal then
			local total = 0
			for _, n in perFloor do
				total += n
			end
			if total >= def.MaxTotal then
				return false
			end
		end
		return true
	end

	local function floorsWithRoom(enemyType: string): { number }
		local list = {}
		for f = 1, floors do
			if hasRoom(enemyType, f) then
				table.insert(list, f)
			end
		end
		return list
	end

	for _ = 1, 500 do -- tope de seguridad
		-- Niveles que se pueden elegir ahora mismo
		local weights = { 0, 0, 0 }
		for tier = 1, 3 do
			local affordable = cfg.TierCost[tier] <= budget
			local underCap = tier ~= 3 or tierCount[3] < tier3Max
			local anyType = false
			for _, enemyType in byTier[tier] do
				if #floorsWithRoom(enemyType) > 0 then
					anyType = true
					break
				end
			end
			if affordable and underCap and anyType then
				weights[tier] = odds[tier] or 0
			end
		end
		local tier = pickWeighted(weights, rng)
		if not tier then
			break -- nada mas que se pueda pagar o colocar
		end

		-- Tipo del nivel (con hueco en alguna planta)
		local candidates = {}
		for _, enemyType in byTier[tier] do
			if #floorsWithRoom(enemyType) > 0 then
				table.insert(candidates, enemyType)
			end
		end
		local enemyType = candidates[rng:NextInteger(1, #candidates)]

		-- Planta segun donde estan los jugadores
		local floorOptions = floorsWithRoom(enemyType)
		local floorWeights = {}
		for i, f in floorOptions do
			local n = playersPerFloor[f] or 0
			floorWeights[i] = if n > 0 then n else cfg.EmptyFloorWeight
		end
		local floor = floorOptions[pickWeighted(floorWeights, rng) or 1]

		count[enemyType] = count[enemyType] or {}
		count[enemyType][floor] = (count[enemyType][floor] or 0) + 1
		tierCount[tier] += 1
		budget -= cfg.TierCost[tier]
		table.insert(picks, { Type = enemyType, Tier = tier, Floor = floor })
	end

	-- Calendario: primero los de menor nivel. InitialShare del presupuesto al empezar
	-- (con 1 s entre cada uno), el resto escalonado. El nivel 3 nunca al principio.
	table.sort(picks, function(a, b)
		return a.Tier < b.Tier
	end)
	local plan: { Spawn } = {}
	local spentAtStart = 0
	local initialLimit = math.max(1, totalBudget * cfg.InitialShare)
	local startIndex, staggerIndex = 0, 0
	for _, pick in picks do
		local cost = cfg.TierCost[pick.Tier]
		local delay
		if pick.Tier < 3 and spentAtStart + cost <= initialLimit then
			spentAtStart += cost
			delay = startIndex
			startIndex += 1
		else
			staggerIndex += 1
			delay = staggerIndex * cfg.StaggerSeconds
		end
		table.insert(plan, { Type = pick.Type, Tier = pick.Tier, Floor = pick.Floor, Delay = delay })
	end
	return plan, totalBudget
end

-- Texto corto del plan (para la consola en Studio).
function SpawnDirector.Describe(plan: { Spawn }, budget: number): string
	local byType = {}
	local order = {}
	for _, s in plan do
		if not byType[s.Type] then
			byType[s.Type] = { 0, 0 }
			table.insert(order, s.Type)
		end
		byType[s.Type][s.Floor] = (byType[s.Type][s.Floor] or 0) + 1
	end
	local parts = {}
	for _, enemyType in order do
		local f = byType[enemyType]
		table.insert(parts, string.format("%s P1:%d P2:%d", enemyType, f[1] or 0, f[2] or 0))
	end
	return string.format("presupuesto %d, %d enemigos -> %s", budget, #plan, table.concat(parts, ", "))
end

return SpawnDirector
