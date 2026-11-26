-- Mision: Vaciar papeleras (por etapas).
--   1. Vaciar 3 papeleras de un ala de la galeria (tag Wastebasket, atributo Zone = ala;
--      las de las tiendas de esa ala y la del pasillo), en cualquier orden.
--   2. Tirar la basura en un contenedor (tag TrashDropoff: bodega o estacionamiento).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Sequence = require(script.Parent.Sequence)

local busy: { [Instance]: boolean } = {}

local function binsOf(zone: string): { BasePart }
	local list = {}
	for _, bin in Sequence.tagged(Tags.Wastebasket, busy) do
		if bin:GetAttribute("Zone") == zone then
			table.insert(list, bin)
		end
	end
	return list
end

return Sequence.new({
	Type = "EmptyBins",
	CanStart = function(_spot, zone: string): boolean
		return #binsOf(zone) >= 2 and #Sequence.tagged(Tags.TrashDropoff) > 0
	end,
	Plan = function(mission)
		local bins = Sequence.pickRandom(binsOf(mission.Zone), Config.Missions.EmptyBins.Count or 3)
		local dumpsters = Sequence.tagged(Tags.TrashDropoff)
		if #bins == 0 or #dumpsters == 0 then
			return nil
		end
		local empties = {}
		for _, bin in bins do
			busy[bin] = true
			table.insert(empties, { Part = bin, Action = "Vaciar", Object = "Papelera" })
		end
		local drops = {}
		for _, dumpster in dumpsters do
			table.insert(drops, { Part = dumpster, Action = "Tirar basura", Object = "Contenedor" })
		end
		return {
			Stages = { { Targets = empties }, { Targets = drops, Any = true } },
			Cleanup = function()
				for _, bin in bins do
					busy[bin] = nil
				end
			end,
		}
	end,
})
