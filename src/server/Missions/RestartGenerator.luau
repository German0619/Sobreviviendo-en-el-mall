-- Mision: Reiniciar generador.
-- El generador se apaga y deja sin luz las zonas que alimenta (atributo PowersZones
-- del MissionSpot, separadas por comas; por defecto su propia zona) hasta reiniciarlo.
-- Si falla, siguen a oscuras el resto de la noche.

local LightService = require(script.Parent.Parent.LightService)
local Hold = require(script.Parent.Hold)

local REASON = "Generator"

local function zonesOf(mission): { string }
	local list = {}
	local attr = mission.Spot:GetAttribute("PowersZones")
	if type(attr) == "string" and attr ~= "" then
		for zone in string.gmatch(attr, "[^,]+") do
			table.insert(list, (string.gsub(zone, "^%s*(.-)%s*$", "%1")))
		end
	else
		table.insert(list, mission.Zone)
	end
	return list
end

return Hold.new({
	Type = "RestartGenerator",
	ActionText = "Reiniciar",
	ObjectText = "Generador",
	RepairTask = true, -- el Electricista lo hace mas rapido
	OnBegin = function(mission)
		local zones = zonesOf(mission)
		for _, zone in zones do
			LightService.Flicker(zone, 1.2)
			LightService.SetReason(zone, REASON, true)
		end
		return zones
	end,
	OnEnd = function(_mission, success, zones)
		if success then
			for _, zone in zones do
				LightService.SetReason(zone, REASON, false)
			end
		end
	end,
})
