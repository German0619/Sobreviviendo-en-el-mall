-- Camaras amigas: las camaras de seguridad funcionan. Quien las use en los monitores
-- (punto de la mision CheckCameras) hace que todos vean a todas las entidades a traves
-- de las paredes durante RevealSeconds. Si el mapa no tiene monitores, se revela al instante.

local Remotes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Remotes)

local Server = script.Parent.Parent
local MissionService = require(Server.MissionService)
local EnemyService = require(Server.EnemyService)

return {
	Start = function(ctx)
		local def = ctx.Def
		local function reveal()
			local count = EnemyService.RevealAll(def.RevealSeconds)
			Remotes.event("Notify"):FireAllClients(
				string.format("Cámaras: %d entidades a la vista durante %d s.", count, def.RevealSeconds),
				"good"
			)
			ctx.SetEndsAt(def.RevealSeconds)
			task.delay(def.RevealSeconds, ctx.Finish)
		end

		local spot = MissionService.GetFreeSpot("CheckCameras")
		if not spot then
			reveal()
			return nil
		end
		local mission = MissionService.StartEventMission({
			DisplayName = "Usar las cámaras de seguridad",
			Spot = spot,
			ActionText = "Usar cámaras",
			ObjectText = "Monitores",
			HoldSeconds = def.HoldSeconds,
			TimeLimit = def.MissionSeconds,
			OnComplete = function()
				reveal()
			end,
			OnExpire = function()
				ctx.Finish()
			end,
		})
		ctx.SetEndsAt(def.MissionSeconds)
		return function()
			mission.Cancel()
		end
	end,
}
