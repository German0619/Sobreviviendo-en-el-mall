-- Hora de oro: las tareas pagan el doble... pero los enemigos van mas rapido.

local Server = script.Parent.Parent
local MissionService = require(Server.MissionService)
local EnemyService = require(Server.EnemyService)

return {
	Start = function(ctx)
		MissionService.SetRewardMultiplier(ctx.Def.RewardMultiplier)
		EnemyService.SetEventSpeed(ctx.Def.EnemySpeedMultiplier)
		return function()
			MissionService.SetRewardMultiplier(1)
			EnemyService.SetEventSpeed(1)
		end
	end,
}
