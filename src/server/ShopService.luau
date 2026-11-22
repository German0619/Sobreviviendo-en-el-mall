-- ShopService: tienda del mall (dinero del juego) e inventario de objetos.
--
-- * El mostrador (tag ShopCounter) tiene un ProximityPrompt que abre la tienda.
-- * Comprar exige estar cerca de un mostrador (lo valida el servidor).
-- * Los consumibles se guardan en data.Inventory y se usan con su tecla.
-- * El cliente ve su inventario en los atributos Item_<id>.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local FlashlightService = require(script.Parent.FlashlightService)

local ShopService = {}

local lastAction = {} -- [Player] = os.clock() (anti-spam)

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
	local data = DataService.GetData(player)
	return if data then data.Inventory[itemId] or 0 else 0
end

function ShopService.Purchase(player: Player, itemId: any): (boolean, string)
	if type(itemId) ~= "string" then
		return false, "Objeto inválido"
	end
	local item = Config.ShopItems[itemId]
	if not item then
		return false, "Objeto inválido"
	end
	if not DataService.GetData(player) then
		return false, "Datos no cargados"
	end
	if not nearCounter(player) then
		return false, "Acércate al mostrador"
	end

	local owned = ShopService.GetCount(player, itemId)
	if item.Permanent and owned >= 1 then
		return false, "Ya lo tienes"
	end
	if item.MaxStack and owned >= item.MaxStack then
		return false, string.format("Solo puedes llevar %d", item.MaxStack)
	end
	if not DataService.TrySpend(player, item.Price) then
		return false, "Dinero insuficiente"
	end

	DataService.Update(player, function(d)
		d.Inventory[itemId] = owned + 1
	end)
	if itemId == "FlashlightPro" then
		FlashlightService.Refresh(player)
	end
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
	else
		return
	end

	DataService.Update(player, function(d)
		d.Inventory[itemId] = math.max(0, (d.Inventory[itemId] or 0) - 1)
	end)
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

	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return ShopService
