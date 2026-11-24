-- Mision: Regar plantas.
-- Riega 3 maceteros de la zona (tag Planter con atributo Zone).

local Tags = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Tags)
local Multi = require(script.Parent.Multi)

return Multi.new({
	Type = "WaterPlants",
	TargetTag = Tags.Planter,
	TargetAttribute = "Zone",
	ActionText = "Regar",
	ObjectText = "Planta",
	OnStep = function(part)
		-- Un poco de agua que salpica
		local splash = Instance.new("ParticleEmitter")
		splash.Color = ColorSequence.new(Color3.fromRGB(140, 190, 255))
		splash.Size = NumberSequence.new(0.3, 0)
		splash.Lifetime = NumberRange.new(0.4, 0.8)
		splash.Speed = NumberRange.new(3, 6)
		splash.SpreadAngle = Vector2.new(50, 50)
		splash.Acceleration = Vector3.new(0, -20, 0)
		splash.Rate = 0
		splash.Parent = part
		splash:Emit(30)
		task.delay(2, function()
			splash:Destroy()
		end)
	end,
})
