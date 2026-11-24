-- AchievementService: logros y bono diario VIP.
--
-- * Los logros (Config.Achievements) se DESBLOQUEAN solos al llegar a su meta
--   (Check: al cargar el perfil, al terminar una noche, tras un giro de ruleta).
-- * Sus diamantes se dan al RECLAMARLOS en el panel LOGROS del lobby
--   (RequestClaimAchievement). Cuentan como diamantes ganados jugando.
-- * VIP: Config.VIP.DailyDiamonds una vez por dia UTC (RequestClaimVipDaily).
--   Vienen de un pase pagado, asi que cuentan como diamantes COMPRADOS (politica
--   de objetos aleatorios pagados: en paises restringidos no sirven en la ruleta).
--
-- El cliente lee el estado en atributos del Player (DataService): Ach_<id>
-- ("locked" | "claimable" | "claimed"), AchProg_<id> y VipDailyDay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Place = require(Shared.Place)

local DataService = require(script.Parent.DataService)
local PassService = require(script.Parent.PassService)

local AchievementService = {}

local lastRequest: { [Player]: number } = {}

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind or "info")
end

local function today(): number
	return os.time() // 86400
end

-- Desbloquea los logros cuya meta ya se cumple (sin dar diamantes todavia).
function AchievementService.Check(player: Player)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	local unlocked = {}
	for _, achievementId in Config.AchievementOrder do
		local achievement = Config.Achievements[achievementId]
		if
			achievement
			and not data.Achievements[achievementId]
			and Config.getAchievementProgress(data, achievement) >= achievement.Goal
		then
			table.insert(unlocked, achievementId)
		end
	end
	-- Update vuelve a publicar los atributos (tambien el progreso), haya o no logros nuevos
	DataService.Update(player, function(d)
		for _, achievementId in unlocked do
			d.Achievements[achievementId] = true
		end
	end)
	for _, achievementId in unlocked do
		local where = if Place.IsLobby then "en LOGROS" else "en el lobby (LOGROS)"
		notify(player, string.format("¡Logro: %s! Reclama tus diamantes %s.", Config.Achievements[achievementId].DisplayName, where), "good")
	end
end

function AchievementService.Claim(player: Player, achievementId: any): (boolean, string)
	local data = DataService.GetData(player)
	local achievement = if type(achievementId) == "string" then Config.Achievements[achievementId] else nil
	if not data or not achievement then
		return false, "Logro inválido."
	end
	if data.ClaimedAchievements[achievementId] then
		return false, "Ya lo reclamaste."
	end
	if not data.Achievements[achievementId] then
		return false, "Aún no lo consigues."
	end
	DataService.Update(player, function(d)
		d.ClaimedAchievements[achievementId] = true
	end)
	DataService.AddDiamonds(player, achievement.Diamonds, false)
	DataService.Save(player)
	return true, string.format("+%d diamantes: %s", achievement.Diamonds, achievement.DisplayName)
end

function AchievementService.ClaimVipDaily(player: Player): (boolean, string)
	local data = DataService.GetData(player)
	if not data then
		return false, "Tus datos aún se están cargando."
	end
	if not PassService.Owns(player, "VIP") then
		return false, "El bono diario es para jugadores VIP."
	end
	if data.VipDailyDay >= today() then
		return false, "Ya lo reclamaste hoy. Vuelve mañana."
	end
	DataService.Update(player, function(d)
		d.VipDailyDay = today()
	end)
	DataService.AddDiamonds(player, Config.VIP.DailyDiamonds, true)
	DataService.Save(player)
	return true, string.format("Bono VIP: +%d diamantes", Config.VIP.DailyDiamonds)
end

local function throttled(player: Player): boolean
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < 0.5 then
		return true
	end
	lastRequest[player] = now
	return false
end

function AchievementService.Start()
	Remotes.func("RequestClaimAchievement").OnServerInvoke = function(player: Player, achievementId: any)
		if throttled(player) then
			return false, "Espera un momento."
		end
		return AchievementService.Claim(player, achievementId)
	end
	Remotes.func("RequestClaimVipDaily").OnServerInvoke = function(player: Player)
		if throttled(player) then
			return false, "Espera un momento."
		end
		return AchievementService.ClaimVipDaily(player)
	end
	-- (Check al cargar el perfil lo conecta ClassService, que corre en los dos places)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return AchievementService
