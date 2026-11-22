-- MonetizationService: compras con Robux (Developer Products).
--
-- MarketplaceService.ProcessReceipt solo puede tener UN callback por servidor:
-- todas las compras pasan por aqui.
--   * Cada recibo se entrega una sola vez: su PurchaseId queda guardado en
--     data.ProcessedReceipts y se guarda en DataStore ANTES de confirmar.
--   * Si algo falla, se devuelve NotProcessedYet y Roblox lo reintenta luego.
-- Los IDs van en Config.DevProducts (0 = aun no creado en la web de Roblox).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local ReviveService = require(script.Parent.ReviveService)

local MonetizationService = {}

local MAX_STORED_RECEIPTS = 100

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind or "info")
end

-- productId -> function(player): boolean (true = entregado)
local handlers: { [number]: (Player) -> boolean } = {}

local function register(productId: number, handler: (Player) -> boolean)
	if productId and productId ~= 0 then
		handlers[productId] = handler
	end
end

local function buildHandlers()
	register(Config.DevProducts.Revive, function(player)
		return ReviveService.OnRevivePurchased(player)
	end)

	register(Config.DevProducts.ClassSlot, function(player)
		local data = DataService.GetData(player)
		if not data then
			return false
		end
		if data.MaxSlots >= Config.Roulette.MaxSlots then
			-- Ya tenia el maximo: compensar con diamantes para no perder la compra
			DataService.AddDiamonds(player, Config.Roulette.SpinCost * 2, true)
			notify(player, "Ya tenías todos los slots: recibiste diamantes a cambio.", "info")
			return true
		end
		DataService.Update(player, function(d)
			d.MaxSlots += 1
			d.ClassSlots[d.MaxSlots] = Config.DefaultClass -- el slot nuevo empieza con la clase por defecto
		end)
		notify(player, string.format("¡Nuevo slot de clase! Ahora tienes %d.", data.MaxSlots), "good")
		return true
	end)

	for _, pack in Config.DevProducts.DiamondPacks do
		register(pack.Id, function(player)
			if not DataService.GetData(player) then
				return false
			end
			DataService.AddDiamonds(player, pack.Amount, true)
			notify(player, string.format("+%d diamantes", pack.Amount), "good")
			return true
		end)
	end
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.WaitForData(player, 15)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receipt.PurchaseId)
	if table.find(data.ProcessedReceipts, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- ya entregado antes
	end

	local handler = handlers[receipt.ProductId]
	if not handler then
		warn("[MonetizationService] Producto sin handler:", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, granted = pcall(handler, player)
	if not ok then
		warn("[MonetizationService] Error entregando", receipt.ProductId, granted)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	DataService.Update(player, function(d)
		table.insert(d.ProcessedReceipts, purchaseId)
		while #d.ProcessedReceipts > MAX_STORED_RECEIPTS do
			table.remove(d.ProcessedReceipts, 1)
		end
	end)
	-- En Studio sin API Services no se puede guardar; igual se entrega.
	if DataService.IsPersistent(player) and not DataService.Save(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Pide al cliente la compra de un producto por nombre.
local function promptProduct(player: Player, kind: any, index: any)
	local productId = 0
	if kind == "ClassSlot" then
		local data = DataService.GetData(player)
		if data and data.MaxSlots >= Config.Roulette.MaxSlots then
			notify(player, "Ya tienes el máximo de slots.", "info")
			return
		end
		productId = Config.DevProducts.ClassSlot
	elseif kind == "Diamonds" and type(index) == "number" then
		local pack = Config.DevProducts.DiamondPacks[index]
		productId = if pack then pack.Id else 0
	else
		return
	end
	if productId == 0 then
		notify(player, "Este producto aún no está configurado (falta su ID en Config.DevProducts).", "bad")
		return
	end
	MarketplaceService:PromptProductPurchase(player, productId)
end

function MonetizationService.Start()
	buildHandlers()
	MarketplaceService.ProcessReceipt = processReceipt
	Remotes.event("RequestBuyProduct").OnServerEvent:Connect(promptProduct)
end

return MonetizationService
