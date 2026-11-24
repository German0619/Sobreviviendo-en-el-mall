-- Baterias debiles: las linternas gastan el doble durante el evento.

local FlashlightService = require(script.Parent.Parent.FlashlightService)

return {
	Start = function(ctx)
		FlashlightService.SetDrainMultiplier(ctx.Def.DrainMultiplier)
		return function()
			FlashlightService.SetDrainMultiplier(1)
		end
	end,
}
