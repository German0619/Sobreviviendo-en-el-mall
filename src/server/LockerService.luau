-- LockerService: Taquilla del conserje (Config.Locker).
--
-- * Lobby (puesto TAQUILLA): se compran consumibles con diamantes, de uno en uno, hasta
--   el maximo guardado de cada objeto. Sin azar.
-- * Mall: al empezar cada partida (NightManager, GrantRunStart) se entrega PerRun de cada
--   objeto guardado, si cabe en la mochila, y se descuenta de la taquilla.
-- Datos: data.Locker[objeto] = cantidad. Atributos del Player: Locker_<objeto>.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)

local LockerService = {}

local lastRequest: { [Player]: number } = {}

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind or "info")
end

local function itemName(itemId: string): string
	local item = Config.ShopItems[itemId]
	return if item then item.DisplayName else itemId
end

-- Compra uno. Devuelve (exito, mensaje).
function LockerService.Buy(player: Player, itemId: any): (boolean, string)
	local data = DataService.GetData(player)
	if not data then
		return false, "Datos no cargados"
	end
	local entry = type(itemId) == "string" and Config.Locker.Items[itemId] or nil
	if not entry then
		return false, "Objeto inválido"
	end
	local stored = (data.Locker or {})[itemId] or 0
	if stored >= entry.Max then
		return false, string.format("Tu taquilla ya tiene %d (el máximo)", entry.Max)
	end
	if not DataService.TrySpendDiamonds(player, entry.Price, false) then
		return false, "Diamantes insuficientes"
	end
	DataService.Update(player, function(d)
		d.Locker = d.Locker or {}
		d.Locker[itemId] = stored + 1
	end)
	DataService.Save(player)
	if RunService:IsStudio() then
		print(string.format("[Taquilla] %s compró %s (ahora %d)", player.Name, itemId, stored + 1))
	end
	return true, string.format("%s guardado en tu taquilla (%d).", itemName(itemId), stored + 1)
end

-- Al empezar una partida en el mall (NightManager, despues de RunState.ResetAll).
function LockerService.GrantRunStart(player: Player)
	local data = DataService.GetData(player)
	if not data or not data.Locker or next(data.Locker) == nil then
		return
	end
	local ShopService = require(script.Parent.ShopService) :: any -- (solo existe en el mall)
	local given: { [string]: number } = {}
	local parts = {}
	for _, itemId in Config.Locker.Order do
		local stored = data.Locker[itemId] or 0
		if stored > 0 then
			local count = ShopService.GiveItem(player, itemId, math.min(Config.Locker.PerRun, stored))
			if count > 0 then
				given[itemId] = count
				table.insert(parts, string.format("%s (quedan %d)", itemName(itemId), stored - count))
			end
		end
	end
	if #parts == 0 then
		return
	end
	DataService.Update(player, function(d)
		for itemId, count in given do
			local left = (d.Locker[itemId] or 0) - count
			d.Locker[itemId] = if left > 0 then left else nil
		end
	end)
	task.spawn(DataService.Save, player) -- que no se entreguen dos veces si se cae el servidor
	notify(player, "De tu taquilla: " .. table.concat(parts, ", "), "good")
	if RunService:IsStudio() then
		print("[Taquilla] Inicio de partida para " .. player.Name .. ": " .. table.concat(parts, ", "))
	end
end

function LockerService.Start()
	Remotes.func("RequestBuyLocker").OnServerInvoke = function(player: Player, itemId: any)
		local now = os.clock()
		if lastRequest[player] and now - lastRequest[player] < 0.25 then
			return false, "Demasiado rápido"
		end
		lastRequest[player] = now
		return LockerService.Buy(player, itemId)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return LockerService
