-- Mision: Reiniciar cajas.
-- Reinicia las cajas registradoras de 3 tiendas de un lado de la galeria (tag
-- CashRegister con atributo Wing = zona). La pantalla de la caja parpadea al reiniciarla.

local Tags = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Tags)
local Multi = require(script.Parent.Multi)

return Multi.new({
	Type = "ResetRegisters",
	TargetTag = Tags.CashRegister,
	TargetAttribute = "Wing",
	ActionText = "Reiniciar",
	ObjectText = "Caja registradora",
	OnStep = function(register: BasePart)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(90, 170, 255)
		light.Range = 6
		light.Brightness = 1.5
		light.Parent = register
		task.delay(1.2, function()
			light:Destroy()
		end)
	end,
})
