-- Mision progresiva: Inventario.
--   1-3. Contar la mercancia de 3 tiendas, EN ORDEN (tag InventoryShelf, atributo Zone =
--        tienda), de las dos plantas si se puede.
--   4.   Entregar el informe en Administracion (tag DeliveryDesk).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Sequence = require(script.Parent.Sequence)

local busy: { [Instance]: boolean } = {}

-- n estanterias de tiendas distintas; si todas caen en la misma planta, cambia la
-- ultima por una de la otra planta.
local function pick(n: number): { BasePart }
	local pool = Sequence.pickRandom(Sequence.tagged(Tags.InventoryShelf, busy), math.huge)
	local chosen = {}
	for i = 1, math.min(n, #pool) do
		chosen[i] = pool[i]
	end
	if #chosen >= 2 then
		local floor1 = Config.getFloor(chosen[1].Position.Y)
		local mixed = false
		for _, shelf in chosen do
			if Config.getFloor(shelf.Position.Y) ~= floor1 then
				mixed = true
			end
		end
		if not mixed then
			for i = #chosen + 1, #pool do
				if Config.getFloor(pool[i].Position.Y) ~= floor1 then
					chosen[#chosen] = pool[i]
					break
				end
			end
		end
	end
	return chosen
end

return Sequence.new({
	Type = "Inventory",
	CanStart = function(): boolean
		return #Sequence.tagged(Tags.InventoryShelf, busy) >= 3 and #Sequence.tagged(Tags.DeliveryDesk) > 0
	end,
	Plan = function(_mission)
		local shelves = pick(Config.Missions.Inventory.Count or 3)
		local desks = Sequence.tagged(Tags.DeliveryDesk)
		if #shelves < 2 or #desks == 0 then
			return nil
		end
		local stages = {}
		for _, shelf in shelves do
			busy[shelf] = true
			local store = shelf:GetAttribute("Zone")
			table.insert(stages, {
				Targets = {
					{
						Part = shelf,
						Action = "Contar mercancía",
						Object = if type(store) == "string" then "Inventario de " .. store else "Inventario",
					},
				},
			})
		end
		table.insert(stages, {
			Targets = { { Part = desks[math.random(1, #desks)], Action = "Entregar informe", Object = "Administración", Duration = 1 } },
		})
		return {
			Stages = stages,
			Cleanup = function()
				for _, shelf in shelves do
					busy[shelf] = nil
				end
			end,
		}
	end,
})
