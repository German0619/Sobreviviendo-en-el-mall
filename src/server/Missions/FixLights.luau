-- Mision: Reparar luces.
-- Las luces de la zona parpadean y se apagan; hay que ir al tablero electrico.
-- Si no se repara a tiempo, la zona queda a oscuras el resto de la noche
-- (y el Apagon se vuelve mas fuerte).

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config)
local LightService = require(script.Parent.Parent.LightService)
local Common = require(script.Parent.Common)

local REASON = "Broken"

local FixLights = {}

function FixLights.CanStart(_spot: BasePart, zone: string): boolean
	return not LightService.HasReason(zone, REASON)
end

function FixLights.Begin(mission, complete)
	local def = Config.Missions.FixLights
	local zone = mission.Zone

	LightService.Flicker(zone, 1.5)
	LightService.SetReason(zone, REASON, true)

	local prompt = Common.makePrompt(mission.Spot, "Reparar", "Tablero electrico", def.Duration)
	-- El Electricista lo hace mas rapido (lo ajusta su cliente con Perk_RepairSpeed)
	prompt:SetAttribute("RepairTask", true)
	prompt.Triggered:Connect(function(player)
		complete(player)
	end)

	return {
		Marker = mission.Spot,
		Cleanup = function(success: boolean)
			prompt:Destroy()
			if success then
				LightService.SetReason(zone, REASON, false)
			end
			-- Si fallo, la zona sigue rota hasta LightService.ResetAll() en la proxima preparacion.
		end,
	}
end

return FixLights
