-- CosmeticsService (lobby): skins de las armas y la linterna (Config.Skins, Config.Cosmetics).
--
-- * Caja de cosmeticos: SpinCost diamantes por giro (o el producto CosmeticSpin con
--   Robux). Se sortea la rareza (RarityOdds) y luego un objeto y una skin de esa rareza.
--   Si ya la tenias, devuelve DuplicateRefund diamantes.
--   Es un objeto ALEATORIO: igual que la ruleta, donde la politica de Roblox restringe
--   los objetos aleatorios pagados (PaidRandomRestricted), solo se puede girar con
--   diamantes ganados jugando, y el giro con Robux no se vende.
-- * Compra directa: cada skin tiene precio fijo segun su rareza (DirectPrice). Sin azar.
-- * Equipar: una skin por objeto (o ninguna). El mall la lee de Skin_<objeto>.
-- Datos: data.Skins["<objeto>:<skin>"] = true, data.EquippedSkins[objeto] = skin.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local DataService = require(script.Parent.DataService)
local ClassService = require(script.Parent.ClassService)

local CosmeticsService = {}

local C = Config.Cosmetics
local rng = Random.new()
local lastRequest: { [Player]: number } = {}

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind or "info")
end

local function throttled(player: Player): boolean
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < 0.4 then
		return true
	end
	lastRequest[player] = now
	return false
end

local function key(itemId: string, skinId: string): string
	return itemId .. ":" .. skinId
end

local function isValid(itemId: any, skinId: any): boolean
	return type(itemId) == "string"
		and type(skinId) == "string"
		and table.find(C.Items, itemId) ~= nil
		and Config.Skins[skinId] ~= nil
end

local function owns(data, itemId: string, skinId: string): boolean
	return data.Skins ~= nil and data.Skins[key(itemId, skinId)] == true
end

local function nameOf(itemId: string, skinId: string): string
	return string.format("%s · %s", C.ItemNames[itemId] or itemId, Config.Skins[skinId].DisplayName)
end

-- Sorteo: rareza y luego objeto + skin de esa rareza.
local function roll(): (string, string)
	local rarity = Util.weightedRandom(C.RarityOdds, rng) or "Common"
	local skins = {}
	for _, skinId in Config.SkinOrder do
		if Config.Skins[skinId].Rarity == rarity then
			table.insert(skins, skinId)
		end
	end
	if #skins == 0 then
		skins = table.clone(Config.SkinOrder)
	end
	local skinId = skins[rng:NextInteger(1, #skins)]
	local itemId = C.Items[rng:NextInteger(1, #C.Items)]
	return itemId, skinId
end

-- Entrega el resultado de un giro. Devuelve (objeto, skin, repetida, mensaje).
local function grantRoll(player: Player): (string, string, boolean, string)
	local itemId, skinId = roll()
	local data = DataService.GetData(player)
	local duplicate = data ~= nil and owns(data, itemId, skinId)
	local message
	if duplicate then
		DataService.AddDiamonds(player, C.DuplicateRefund, false)
		message = string.format("%s (ya la tenías): +%d 💎", nameOf(itemId, skinId), C.DuplicateRefund)
	else
		DataService.Update(player, function(d)
			d.Skins = d.Skins or {}
			d.Skins[key(itemId, skinId)] = true
		end)
		message = string.format("¡Nueva skin! %s", nameOf(itemId, skinId))
	end
	DataService.Save(player) -- que no se pierda el giro si se cae el servidor
	return itemId, skinId, duplicate, message
end

-- Giro con diamantes.
function CosmeticsService.Spin(player: Player): (boolean, string, string?, string?, boolean?)
	local data = DataService.GetData(player)
	if not data then
		return false, "Datos no cargados"
	end
	local restricted = ClassService.IsRestricted(player)
	if not DataService.TrySpendDiamonds(player, C.SpinCost, restricted) then
		if restricted and data.Diamonds >= C.SpinCost then
			return false, "En tu país solo puedes girar con diamantes ganados jugando"
		end
		return false, "Diamantes insuficientes"
	end
	local itemId, skinId, duplicate, message = grantRoll(player)
	return true, message, itemId, skinId, duplicate
end

-- Giro con Robux (producto CosmeticSpin). Lo llama MonetizationService.
function CosmeticsService.RobuxSpin(player: Player): boolean
	if not DataService.GetData(player) then
		return false
	end
	local itemId, skinId, duplicate, message = grantRoll(player)
	Remotes.event("CosmeticResult"):FireClient(player, itemId, skinId, duplicate)
	notify(player, message, "good")
	return true
end

-- Compra directa (sin azar).
function CosmeticsService.Buy(player: Player, itemId: any, skinId: any): (boolean, string)
	local data = DataService.GetData(player)
	if not data then
		return false, "Datos no cargados"
	end
	if not isValid(itemId, skinId) then
		return false, "Skin inválida"
	end
	if owns(data, itemId, skinId) then
		return false, "Ya la tienes"
	end
	local price = C.DirectPrice[Config.Skins[skinId].Rarity] or 0
	if not DataService.TrySpendDiamonds(player, price, false) then
		return false, "Diamantes insuficientes"
	end
	DataService.Update(player, function(d)
		d.Skins = d.Skins or {}
		d.Skins[key(itemId, skinId)] = true
		d.EquippedSkins = d.EquippedSkins or {}
		d.EquippedSkins[itemId] = skinId -- la compras para usarla: queda equipada
	end)
	DataService.Save(player)
	return true, string.format("Compraste %s (equipada).", nameOf(itemId, skinId))
end

-- Equipar (skinId) o quitar (nil) la skin de un objeto.
function CosmeticsService.Equip(player: Player, itemId: any, skinId: any)
	local data = DataService.GetData(player)
	if not data or type(itemId) ~= "string" or not table.find(C.Items, itemId) then
		return
	end
	if skinId ~= nil and (not isValid(itemId, skinId) or not owns(data, itemId, skinId)) then
		return
	end
	DataService.Update(player, function(d)
		d.EquippedSkins = d.EquippedSkins or {}
		d.EquippedSkins[itemId] = skinId
	end)
end

function CosmeticsService.Start()
	Remotes.func("RequestCosmeticSpin").OnServerInvoke = function(player: Player)
		if throttled(player) then
			return false, "Demasiado rápido"
		end
		return CosmeticsService.Spin(player)
	end
	Remotes.func("RequestBuySkin").OnServerInvoke = function(player: Player, itemId: any, skinId: any)
		if throttled(player) then
			return false, "Demasiado rápido"
		end
		return CosmeticsService.Buy(player, itemId, skinId)
	end
	Remotes.event("RequestEquipSkin").OnServerEvent:Connect(CosmeticsService.Equip)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return CosmeticsService
