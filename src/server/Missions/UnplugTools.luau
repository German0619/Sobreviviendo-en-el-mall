-- Mision: Desenchufar herramientas.
-- En la obra del Ala Sur (a oscuras) se encienden solas 3 herramientas (tag PowerTool,
-- atributo Zone): ruido de obra, chispas y un foco de trabajo que parpadea. Mientras
-- suenan ATRAEN a los enemigos cercanos. Hay que desenchufarlas una a una.

local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local DefenseService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("DefenseService"))
local Multi = require(script.Parent.Multi)
local Common = require(script.Parent.Common)

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

return Multi.new({
	Type = "UnplugTools",
	TargetTag = Tags.PowerTool,
	TargetAttribute = "Zone",
	ActionText = "Desenchufar",
	ObjectText = "Herramienta",
	OnActivate = function(tool: BasePart)
		local light = Instance.new("PointLight")
		light.Name = "WorkLight"
		light.Color = Color3.fromRGB(255, 190, 110)
		light.Range = 16
		light.Brightness = 1.4
		light.Shadows = true
		light.Parent = tool
		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "Sparks"
		sparks.Texture = SPARK_TEXTURE
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90))
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new(0.25, 0)
		sparks.Lifetime = NumberRange.new(0.2, 0.5)
		sparks.Speed = NumberRange.new(8, 14)
		sparks.SpreadAngle = Vector2.new(60, 60)
		sparks.Acceleration = Vector3.new(0, -30, 0)
		sparks.Rate = 25
		sparks.Parent = tool
		local sound = Common.loopSound(tool, "PowerTool", 70)
		local removeLure = DefenseService.AddLure(
			tool.Position,
			Config.Missions.UnplugTools.TimeLimit + 5,
			Config.MissionDetails.UnplugTools.LureRadius
		)
		-- El foco de obra falla (mal enchufado)
		local running = true
		task.spawn(function()
			while running and light.Parent do
				light.Enabled = math.random() > 0.15
				task.wait(math.random(5, 30) / 100)
			end
		end)
		return function()
			running = false
			light:Destroy()
			sparks:Destroy()
			removeLure()
			if sound then
				sound:Destroy()
			end
		end
	end,
})
