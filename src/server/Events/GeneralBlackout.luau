-- Apagon general: todo el mall se queda a oscuras hasta reiniciar los generadores
-- principales (misiones de evento en los puntos RestartGenerator). Si una caduca,
-- sale otra en el mismo generador: el apagon sigue. Como mucho dura MaxSeconds.

local Server = script.Parent.Parent
local LightService = require(Server.LightService)
local MissionService = require(Server.MissionService)
local Remotes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Remotes)

local REASON = "EventBlackout"

return {
	Start = function(ctx)
		local def = ctx.Def
		local zones = LightService.GetZones()
		for _, zone in zones do
			LightService.Flicker(zone, 1.5)
		end
		task.delay(1.5, function()
			if not ctx.Ended then
				for _, zone in zones do
					LightService.SetReason(zone, REASON, true)
				end
			end
		end)

		local missions = {}
		local pending = 0
		local function offer(spot: BasePart)
			local handle
			handle = MissionService.StartEventMission({
				DisplayName = "Reiniciar generador principal",
				Spot = spot,
				ActionText = "Reiniciar",
				ObjectText = "Generador",
				HoldSeconds = def.HoldSeconds,
				TimeLimit = def.MissionSeconds,
				RepairTask = true,
				OnComplete = function()
					missions[handle] = nil
					pending -= 1
					if pending <= 0 then
						Remotes.event("Notify"):FireAllClients("Generadores en marcha: vuelve la luz.", "good")
						ctx.Finish()
					else
						Remotes.event("Notify"):FireAllClients(string.format("Generador reiniciado. Falta %d.", pending), "info")
					end
				end,
				OnExpire = function()
					missions[handle] = nil
					if not ctx.Ended then
						offer(spot) -- el apagon sigue: otra oportunidad
					end
				end,
			})
			missions[handle] = true
		end

		-- Hasta 2 generadores (uno por planta si se puede)
		for floor = 1, 2 do
			local spot = MissionService.GetFreeSpot("RestartGenerator", floor) or MissionService.GetFreeSpot("RestartGenerator")
			if spot then
				pending += 1
				offer(spot)
			end
		end

		local limit = if pending > 0 then def.MaxSeconds else 60
		ctx.SetEndsAt(limit)
		task.delay(limit, ctx.Finish)

		return function()
			for handle in missions do
				handle.Cancel()
			end
			for _, zone in zones do
				LightService.SetReason(zone, REASON, false)
			end
		end
	end,
}
