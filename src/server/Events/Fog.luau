-- Neblina: una niebla densa entra poco a poco en todo el mall. Se ve muy poco y los
-- enemigos tambien ven a menos distancia (Config.Detection.SenseRange). Favorece a
-- los que te oyen sin verte (Eco, Ducto, Estatua).

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config)
local LightService = require(script.Parent.Parent.LightService)

return {
	Start = function(ctx)
		local def = ctx.Def
		LightService.SetFog(true, def.FadeSeconds)
		local baseRange = Config.Detection.SenseRange
		Config.Detection.SenseRange = baseRange * def.SenseMultiplier
		return function()
			LightService.SetFog(false, 8)
			Config.Detection.SenseRange = baseRange
		end
	end,
}
