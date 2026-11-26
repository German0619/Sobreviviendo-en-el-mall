-- Mision: Reiniciar recreativas.
-- 3 maquinas de la zona de juegos (tag ArcadeMachine, atributo Zone) se encienden solas en
-- modo demo: musica, luces que parpadean y, mientras suenan, ATRAEN a los enemigos cercanos.

local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local DefenseService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("DefenseService"))
local Multi = require(script.Parent.Multi)
local Common = require(script.Parent.Common)

local COLORS = { Color3.fromRGB(255, 60, 200), Color3.fromRGB(60, 220, 255), Color3.fromRGB(255, 200, 40) }

return Multi.new({
	Type = "ResetArcade",
	TargetTag = Tags.ArcadeMachine,
	TargetAttribute = "Zone",
	ActionText = "Reiniciar",
	ObjectText = "Recreativa",
	OnActivate = function(machine: BasePart)
		local light = Instance.new("PointLight")
		light.Name = "DemoLight"
		light.Range = 14
		light.Brightness = 2
		light.Parent = machine
		local sound = Common.loopSound(machine, "Arcade", 70)
		local removeLure = DefenseService.AddLure(
			machine.Position,
			Config.Missions.ResetArcade.TimeLimit + 5,
			Config.MissionDetails.ResetArcade.LureRadius
		)
		local running = true
		task.spawn(function()
			local i = 0
			while running and light.Parent do
				i += 1
				light.Color = COLORS[i % #COLORS + 1]
				task.wait(0.3)
			end
		end)
		return function()
			running = false
			light:Destroy()
			removeLure()
			if sound then
				sound:Destroy()
			end
		end
	end,
})
