-- Oleada: una horda de enemigos de nivel 1 aparece en una planta durante 60 s y luego
-- se desvanece. Cuantos mas noches, mas grande.

local EnemyService = require(script.Parent.Parent.EnemyService)

return {
	CanStart = function(_ctx)
		return #EnemyService.GetTier1Types() > 0
	end,
	Start = function(ctx)
		local def = ctx.Def
		local count = math.min(def.MaxCount, def.BaseCount + math.floor((ctx.Night - 1) / def.PerNights))
		local types = EnemyService.GetTier1Types()
		local spawned = {}
		task.spawn(function()
			for i = 1, count do
				if ctx.Ended then
					return
				end
				local enemyType = types[(i - 1) % #types + 1]
				local enemy = EnemyService.SpawnTemporary(enemyType, ctx.Floor, def.Duration)
				if enemy then
					table.insert(spawned, enemy)
				end
				task.wait(0.4)
			end
		end)
		return function()
			for _, enemy in spawned do
				EnemyService.RemoveEnemy(enemy)
			end
		end
	end,
}
