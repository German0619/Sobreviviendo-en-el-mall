-- Megafonia hackeada: aparece una Megafonia (src/enemies/Intercom) que anuncia tareas
-- falsas mucho mas seguido durante el evento. Las falsas no salen en la lista de tareas.

local EnemyService = require(script.Parent.Parent.EnemyService)

return {
	Start = function(ctx)
		local def = ctx.Def
		local enemy = EnemyService.SpawnTemporary("Intercom", ctx.Floor, def.Duration)
		if not enemy then
			ctx.Finish()
			return nil
		end
		-- Primer anuncio enseguida y luego cada Interval
		enemy.Def = table.clone(enemy.Def)
		enemy.Def.Interval = def.Interval
		enemy.NextAnnounce = os.clock() + 4
		return function()
			EnemyService.RemoveEnemy(enemy)
		end
	end,
}
