-- ShopService: tienda del mall (dinero del juego) e inventario de objetos.
--
-- * El mostrador (tag ShopCounter) tiene un ProximityPrompt que abre la tienda.
-- * Comprar exige estar cerca de un mostrador (lo valida el servidor).
-- * El inventario es POR VIDA: no se guarda, y se pierde al morir o salir.
--   (El dinero gastado si se descuenta de los datos guardados.)
-- * Los consumibles se usan con su tecla.
-- * El cliente ve su inventario en los atributos Item_<id>.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local RunState = require(script.Parent.RunState)
local FlashlightService = require(script.Parent.FlashlightService)
local DefenseService = require(script.Parent.DefenseService)
local WeaponService = require(script.Parent.WeaponService)
local VendingService = require(script.Parent.VendingService)
local SfxService = require(script.Parent.SfxService)
local Workspace = game:GetService("Workspace")

local ShopService = {}

-- Sonido al usar cada tipo de objeto (Config.Sounds.Sfx)
local USE_SOUNDS = {
	RechargeBattery = "Battery",
	LithiumBattery = "Battery",
	Heal = "Heal",
	MysterySoda = "Soda",
}

local lastAction = {} -- [Player] = os.clock() (anti-spam)
local inventories = {} -- [Player] = { [itemId] = cantidad }

local function setCount(player: Player, itemId: string, count: number)
	local inv = inventories[player] or {}
	inventories[player] = inv
	inv[itemId] = if count > 0 then count else nil
	player:SetAttribute("Item_" .. itemId, count)
end

-- Lo que llevaba al morir: [Player] = { Items = { [id] = n }, Weapons = WeaponService.Snapshot }
local stash: { [Player]: { Items: { [string]: number }, Weapons: { any } } } = {}

-- Revivir pagando (Robux o ficha): recupera los objetos y armas que tenia al caer.
function ShopService.RestoreAfterRevive(player: Player)
	local saved = stash[player]
	stash[player] = nil
	if not saved then
		return
	end
	for itemId, count in saved.Items do
		setCount(player, itemId, count)
	end
	WeaponService.Restore(player, saved.Weapons)
	FlashlightService.Refresh(player)
	-- (notify se define mas abajo)
	Remotes.event("Notify"):FireClient(player, "Recuperaste tus objetos.", "good")
end

-- Revivir gratis (Medico) o empezar otra partida: lo que llevaba se pierde.
function ShopService.DropStash(player: Player)
	stash[player] = nil
end

-- Vacia el inventario (al morir, al salir, al empezar otra partida).
function ShopService.ClearInventory(player: Player)
	inventories[player] = nil
	for itemId, item in Config.ShopItems do
		if not item.Weapon then
			player:SetAttribute("Item_" .. itemId, 0)
		end
	end
	WeaponService.Clear(player) -- el arma tambien es por vida
	FlashlightService.Refresh(player)
end

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind or "info")
end

local function throttled(player: Player): boolean
	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < 0.25 then
		return true
	end
	lastAction[player] = now
	return false
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function nearCounter(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	for _, counter in CollectionService:GetTagged(Tags.ShopCounter) do
		if counter:IsA("BasePart") and (counter.Position - root.Position).Magnitude <= Config.ShopRange then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function ShopService.GetCount(player: Player, itemId: string): number
	local inv = inventories[player]
	return if inv then inv[itemId] or 0 else 0
end

-- Da objetos gratis (caja de Suministros), respetando el maximo que se puede llevar.
-- Devuelve cuantos se dieron.
function ShopService.GiveItem(player: Player, itemId: string, amount: number): number
	local item = Config.ShopItems[itemId]
	if not item or item.Weapon or amount <= 0 then
		return 0
	end
	local owned = ShopService.GetCount(player, itemId)
	local max = item.MaxStack or (if item.Unique then 1 else math.huge)
	local given = math.max(0, math.min(amount, max - owned))
	if given > 0 then
		setCount(player, itemId, owned + given)
	end
	return given
end

function ShopService.Purchase(player: Player, itemId: any): (boolean, string)
	if type(itemId) ~= "string" then
		return false, "Objeto inválido"
	end
	local item = Config.ShopItems[itemId]
	if not item or item.MerchantOnly or item.PassOnly then
		return false, "Objeto inválido"
	end
	if not DataService.GetData(player) then
		return false, "Datos no cargados"
	end
	if not nearCounter(player) then
		return false, "Acércate al mostrador"
	end
	local humanoid = getHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then
		return false, "Estás muerto"
	end

	-- Armas: cada una en su casilla de la mochila (la misma se recarga). El taser sube
	-- de precio cada vez que se vuelve a comprar en la partida (TaserBuys).
	if item.Weapon then
		local canEquip, reason = WeaponService.CanEquip(player, itemId)
		if not canEquip then
			return false, reason or "No puedes comprarla"
		end
		local buysAttr = itemId .. "Buys"
		local buys = player:GetAttribute(buysAttr) or 0
		local price = Config.getShopPrice(itemId, buys)
		if not RunState.TrySpend(player, price) then
			return false, "Billetes insuficientes"
		end
		if item.RebuyGrowth then
			player:SetAttribute(buysAttr, buys + 1)
		end
		WeaponService.Equip(player, itemId)
		SfxService.PlayFor(player, "Buy")
		return true, "Compraste: " .. item.DisplayName .. " (en tu mochila)"
	end

	local owned = ShopService.GetCount(player, itemId)
	if itemId == "FlashlightPro" and player:GetAttribute("Pass_PremiumFlashlight") == true then
		return false, "Ya la tienes con el pase Linterna Premium"
	end
	if item.Unique and owned >= 1 then
		return false, "Ya lo tienes"
	end
	if item.MaxStack and owned >= item.MaxStack then
		return false, string.format("Solo puedes llevar %d", item.MaxStack)
	end
	if not RunState.TrySpend(player, item.Price) then
		return false, "Billetes insuficientes"
	end

	setCount(player, itemId, owned + 1)
	if itemId == "FlashlightPro" then
		FlashlightService.Refresh(player)
	end
	SfxService.PlayFor(player, "Buy")
	return true, "Compraste: " .. item.DisplayName
end

function ShopService.UseItem(player: Player, itemId: any)
	if type(itemId) ~= "string" then
		return
	end
	local item = Config.ShopItems[itemId]
	if not item or not item.Use then
		return
	end
	local humanoid = getHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if ShopService.GetCount(player, itemId) <= 0 then
		notify(player, "No tienes " .. item.DisplayName .. ". Cómprala en la tienda del mall.")
		return
	end

	if item.Use == "RechargeBattery" then
		local max = player:GetAttribute("MaxBattery") or Config.Stats.Battery.Base
		if (player:GetAttribute("Battery") or 0) >= max - 0.5 then
			notify(player, "La batería ya está llena.")
			return
		end
		FlashlightService.Recharge(player)
		notify(player, "Linterna recargada.", "good")
	elseif item.Use == "Heal" then
		if humanoid.Health >= humanoid.MaxHealth then
			notify(player, "Ya tienes la vida completa.")
			return
		end
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + (item.Amount or 0))
		notify(player, string.format("+%d de vida.", item.Amount or 0), "good")
	elseif item.Use == "ThrowFlare" then
		-- item.Flare: { Duration, Radius } (la Bengala de magnesio del mercader)
		if not DefenseService.ThrowFlare(player, item.Flare) then
			return
		end
	elseif item.Use == "ThrowFirecracker" then
		-- item.Firecracker: { Duration, Radius, ThrowRange } (el Petardo gordo del mercader)
		if not DefenseService.ThrowFirecracker(player, item.Firecracker) then
			return
		end
	elseif item.Use == "LithiumBattery" then
		-- Bateria de litio: recarga y un rato sin gastar
		FlashlightService.Recharge(player)
		player:SetAttribute("FreeBatteryUntil", Workspace:GetServerTimeNow() + (item.FreeSeconds or 60))
		notify(player, string.format("Linterna recargada: %d s sin gastar batería.", item.FreeSeconds or 60), "good")
	elseif item.Use == "SmokeBomb" then
		if not DefenseService.SmokeBomb(player, item.Radius or 14, item.Duration or 8) then
			return
		end
		notify(player, "¡Bomba de humo! Los enemigos no te ven unos segundos.", "good")
	elseif item.Use == "MysterySoda" then
		local effects = Config.ChoiceSoda.Effects
		VendingService.ApplyEffect(player, effects[math.random(1, #effects)], item.DurationMultiplier or 1)
	else
		return
	end

	-- Sonido del objeto (la bengala, el petardo y el humo suenan donde caen: DefenseService)
	local useSound = USE_SOUNDS[item.Use]
	if useSound then
		SfxService.PlayFor(player, useSound)
	end
	setCount(player, itemId, ShopService.GetCount(player, itemId) - 1)
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

local function setupCounter(counter: Instance)
	if not counter:IsA("BasePart") or counter:FindFirstChild("ShopPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Abrir tienda"
	prompt.ObjectText = "Tienda del mall"
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = counter
	prompt.Triggered:Connect(function(player)
		Remotes.event("OpenShop"):FireClient(player, counter.Position)
	end)
end

function ShopService.Start()
	for _, counter in CollectionService:GetTagged(Tags.ShopCounter) do
		setupCounter(counter)
	end
	CollectionService:GetInstanceAddedSignal(Tags.ShopCounter):Connect(setupCounter)

	Remotes.func("RequestPurchase").OnServerInvoke = function(player: Player, itemId: any)
		if throttled(player) then
			return false, "Demasiado rápido"
		end
		return ShopService.Purchase(player, itemId)
	end

	Remotes.event("UseItem").OnServerEvent:Connect(function(player: Player, itemId: any)
		if not throttled(player) then
			ShopService.UseItem(player, itemId)
		end
	end)

	-- Morir = perder todos los objetos y armas. Se guarda una copia por si te reviven
	-- pagando (Robux o ficha): entonces se devuelven (RestoreAfterRevive).
	local function setup(player: Player)
		ShopService.ClearInventory(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid then
				humanoid.Died:Connect(function()
					local items = table.clone(inventories[player] or {})
					local weapons = WeaponService.Snapshot(player)
					if next(items) ~= nil or #weapons > 0 then
						stash[player] = { Items = items, Weapons = weapons }
						notify(player, "Perdiste tus objetos. Si te reviven pagando, los recuperas.", "bad")
					else
						stash[player] = nil
					end
					ShopService.ClearInventory(player)
				end)
			end
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		inventories[player] = nil
		stash[player] = nil
	end)
end

return ShopService
