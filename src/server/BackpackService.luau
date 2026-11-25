-- BackpackService (mall): el inventario se muestra en la MOCHILA NATIVA de Roblox
-- (la barra de casillas de abajo). Funciona igual en PC (teclas 1-9 y clic),
-- telefono (tocar la casilla y tocar para usar) y consola (mando).
--
-- * Cada objeto usable de la tienda (Config.ShopItems con Use) que tengas es una
--   herramienta (Tool) llamada "Batería x2". El arma equipada es otra: "Taser (9)".
-- * Usar la herramienta (Tool.Activated) gasta el objeto (ShopService.UseItem) o
--   usa el arma (WeaponService.Use).
-- * La fuente de verdad siguen siendo los atributos Item_<id> / Weapon / WeaponUses:
--   la mochila se rehace al cambiar y al reaparecer (Roblox la vacia al reaparecer).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local HeldModels = require(Shared.HeldModels)

local ShopService = require(script.Parent.ShopService)
local WeaponService = require(script.Parent.WeaponService)
local FumigatorService = require(script.Parent.FumigatorService)

local BackpackService = {}

local syncing: { [Player]: boolean } = {}

-- Herramienta de un objeto o arma (en la mochila o en la mano).
local function findTool(player: Player, key: string): Tool?
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("InventoryKey") == key then
					return child
				end
			end
		end
	end
	return nil
end

-- modelId: que modelo lleva en la mano (HeldModels). Lo ven los demas; tu lo ves con el
-- ViewModel del cliente (atributo ModelId de la Tool). skinId: skin del arma (Fase 11).
local function newTool(player: Player, key: string, name: string, tip: string, modelId: string, skinId: string?, onUse: () -> ()): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return nil
	end
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.ToolTip = tip
	tool.CanBeDropped = false
	tool:SetAttribute("InventoryKey", key)
	tool:SetAttribute("ModelId", modelId)
	tool:SetAttribute("Skin", skinId)
	local model = HeldModels.build(modelId, skinId)
	if model then
		HeldModels.intoTool(model, tool)
		tool.RequiresHandle = true
	else
		tool.RequiresHandle = false
	end
	tool.Activated:Connect(onUse)
	tool.Parent = backpack
	return tool
end

-- Pone la mochila al dia con los atributos del jugador.
function BackpackService.Sync(player: Player)
	if syncing[player] or not player.Parent then
		return
	end
	syncing[player] = true

	-- Objetos usables, en el orden de la tienda (y luego los exclusivos del mercader)
	local order = table.clone(Config.ShopOrder)
	for _, itemId in Config.MerchantOrder or {} do
		table.insert(order, itemId)
	end
	for _, itemId in order do
		local item = Config.ShopItems[itemId]
		if item and item.Use then
			local count = player:GetAttribute("Item_" .. itemId) or 0
			local key = "Item_" .. itemId
			local tool = findTool(player, key)
			if count > 0 then
				local name = string.format("%s x%d", item.DisplayName, count)
				if tool then
					tool.Name = name
				else
					newTool(player, key, name, item.Description, itemId, nil, function()
						ShopService.UseItem(player, itemId)
					end)
				end
			elseif tool then
				tool:Destroy()
			end
		end
	end

	-- Arma equipada (una sola)
	local weaponId = WeaponService.Get(player)
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, child in container:GetChildren() do
				local key = child:IsA("Tool") and child:GetAttribute("InventoryKey")
				if type(key) == "string" and string.sub(key, 1, 7) == "Weapon_" and key ~= "Weapon_" .. tostring(weaponId) then
					child:Destroy() -- arma anterior
				end
			end
		end
	end
	if weaponId then
		local item = Config.ShopItems[weaponId]
		local uses = player:GetAttribute("WeaponUses") or -1
		-- Con usos: "Taser (9)"; con el pase Taser infinito: "Taser (∞)"
		local limited = Config.Weapons[weaponId] and Config.Weapons[weaponId].Uses ~= nil
		local name = if uses >= 0
			then string.format("%s (%d)", item.DisplayName, uses)
			elseif limited then item.DisplayName .. " (∞)"
			else item.DisplayName
		local key = "Weapon_" .. weaponId
		local tool = findTool(player, key)
		if tool then
			tool.Name = name
		else
			newTool(player, key, name, item.Description, weaponId, player:GetAttribute("Skin_" .. weaponId), function()
				WeaponService.Use(player)
			end)
		end
	end

	-- Fumigador de entidades (pase): 1 uso por noche
	local fumigatorKey = "Special_Fumigator"
	local fumigatorTool = findTool(player, fumigatorKey)
	if player:GetAttribute("FumigatorReady") == true then
		if not fumigatorTool then
			newTool(player, fumigatorKey, "Fumigador (1 esta noche)", Config.GamePassInfo.Fumigator.Description, "Fumigator", nil, function()
				FumigatorService.Use(player)
			end)
		end
	elseif fumigatorTool then
		fumigatorTool:Destroy()
	end

	syncing[player] = nil
end

function BackpackService.Start()
	local function setup(player: Player)
		local function sync()
			task.defer(BackpackService.Sync, player)
		end
		for itemId, item in Config.ShopItems do
			if item.Use then
				player:GetAttributeChangedSignal("Item_" .. itemId):Connect(sync)
			end
		end
		player:GetAttributeChangedSignal("Weapon"):Connect(sync)
		player:GetAttributeChangedSignal("WeaponUses"):Connect(sync)
		player:GetAttributeChangedSignal("FumigatorReady"):Connect(sync)
		-- Al reaparecer Roblox vacia la mochila: se rehace
		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			sync()
		end)
		sync()
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		syncing[player] = nil
	end)
end

return BackpackService
