-- PermanentUpgradeService: mejoras permanentes (Config.PermanentUpgrades).
--
-- * Lobby (puesto MEJORAS): se compran nivel a nivel. Se pagan primero con puntos de
--   mejora y lo que falte con diamantes. Sin azar.
-- * Reinicio (producto PermanentReset, Robux): quita todos los niveles y devuelve el
--   100% de lo gastado como puntos de mejora (solo sirven para volver a comprar mejoras).
--   Lo entrega MonetizationService, solo en el lobby.
-- * Mall: las de estadistica las aplica PlayerStats.Compute; los billetes extra y el
--   kit de inicio los entrega NightManager al empezar cada partida (GrantRunStart).
-- Datos: data.PermanentUpgrades[id] = nivel, data.UpgradePoints.
-- Atributos del Player (DataService): Perm_<id>, UpgradePoints.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local PlayerStats = require(script.Parent.PlayerStats)

local PermanentUpgradeService = {}

local lastRequest: { [Player]: number } = {}

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind or "info")
end

local function levelOf(data, upgradeId: string): number
	return (data.PermanentUpgrades or {})[upgradeId] or 0
end

-- Lo que devolveria un reinicio ahora (todo lo gastado en niveles).
function PermanentUpgradeService.GetSpent(player: Player): number
	local data = DataService.GetData(player)
	if not data then
		return 0
	end
	local total = 0
	for upgradeId, level in data.PermanentUpgrades or {} do
		total += Config.getPermanentSpent(upgradeId, level)
	end
	return total
end

-- Compra el siguiente nivel. Devuelve (exito, mensaje).
function PermanentUpgradeService.Buy(player: Player, upgradeId: any): (boolean, string)
	local data = DataService.GetData(player)
	if not data then
		return false, "Datos no cargados"
	end
	if type(upgradeId) ~= "string" or not Config.PermanentUpgrades[upgradeId] then
		return false, "Mejora inválida"
	end
	local upgrade = Config.PermanentUpgrades[upgradeId]
	local level = levelOf(data, upgradeId)
	local cost = Config.getPermanentCost(upgradeId, level)
	if not cost then
		return false, "Ya está al máximo"
	end

	-- Primero los puntos de mejora, lo que falte con diamantes
	local fromPoints = math.min(data.UpgradePoints or 0, cost)
	local fromDiamonds = cost - fromPoints
	if fromDiamonds > 0 and not DataService.TrySpendDiamonds(player, fromDiamonds, false) then
		return false, "Diamantes insuficientes"
	end
	DataService.Update(player, function(d)
		d.UpgradePoints = math.max(0, (d.UpgradePoints or 0) - fromPoints)
		d.PermanentUpgrades = d.PermanentUpgrades or {}
		d.PermanentUpgrades[upgradeId] = level + 1
	end)
	DataService.Save(player)
	PlayerStats.Apply(player)
	if RunService:IsStudio() then
		print(string.format("[Mejoras] %s compró %s nivel %d (%d puntos + %d 💎)", player.Name, upgradeId, level + 1, fromPoints, fromDiamonds))
	end
	return true, string.format("%s nivel %d: %s", upgrade.DisplayName, level + 1, Config.getPermanentEffectText(upgradeId, level + 1))
end

-- Reinicio pagado con Robux (lo llama MonetizationService). true = entregado.
function PermanentUpgradeService.Reset(player: Player): boolean
	if not DataService.GetData(player) then
		return false
	end
	local refund = PermanentUpgradeService.GetSpent(player)
	DataService.Update(player, function(d)
		d.PermanentUpgrades = {}
		d.UpgradePoints = (d.UpgradePoints or 0) + refund
	end)
	PlayerStats.Apply(player)
	notify(player, string.format("Mejoras reiniciadas: +%d puntos de mejora para repartir.", refund), "good")
	if RunService:IsStudio() then
		print(string.format("[Mejoras] %s reinició: +%d puntos", player.Name, refund))
	end
	return true
end

-- Al empezar una partida en el mall (NightManager, despues de RunState.ResetAll):
-- billetes extra y kit de inicio.
function PermanentUpgradeService.GrantRunStart(player: Player)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	local RunState = require(script.Parent.RunState) :: any
	local ShopService = require(script.Parent.ShopService) :: any -- (solo existe en el mall)
	local parts = {}

	local cashLevel = levelOf(data, "StartCash")
	if cashLevel > 0 then
		local cash = Config.PermanentUpgrades.StartCash.StartCash * cashLevel
		RunState.AddCash(player, cash)
		table.insert(parts, string.format("+%d billetes", cash))
	end

	local kitLevel = levelOf(data, "StarterKit")
	local kit = Config.PermanentUpgrades.StarterKit.Kit
	for n = 1, math.min(kitLevel, #kit) do
		if ShopService.GiveItem(player, kit[n], 1) > 0 then
			table.insert(parts, Config.ShopItems[kit[n]].DisplayName)
		end
	end

	if #parts > 0 then
		notify(player, "Mejoras permanentes: " .. table.concat(parts, ", "), "good")
		if RunService:IsStudio() then
			print("[Mejoras] Inicio de partida para " .. player.Name .. ": " .. table.concat(parts, ", "))
		end
	end
end

function PermanentUpgradeService.Start()
	Remotes.func("RequestBuyPermanent").OnServerInvoke = function(player: Player, upgradeId: any)
		local now = os.clock()
		if lastRequest[player] and now - lastRequest[player] < 0.3 then
			return false, "Demasiado rápido"
		end
		lastRequest[player] = now
		return PermanentUpgradeService.Buy(player, upgradeId)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return PermanentUpgradeService
