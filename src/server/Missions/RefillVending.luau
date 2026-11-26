-- Mision: Rellenar maquina.
-- Recoge una caja de refrescos en un palet (tag StockPickup, bodega o almacen alto) y
-- llevala a la maquina expendedora (el MissionSpot de la mision esta delante de ella).

local Tags = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Tags)
local Carry = require(script.Parent.Carry)
local Sequence = require(script.Parent.Sequence)

return Carry.new({
	Type = "RefillVending",
	CanStart = function()
		return #Sequence.tagged(Tags.StockPickup) > 0
	end,
	BuildItem = function()
		local crate = Instance.new("Part")
		crate.Name = "SodaCrate"
		crate.Size = Vector3.new(2.2, 1.2, 1.6)
		crate.Material = Enum.Material.Plastic
		crate.Color = Color3.fromRGB(190, 35, 40)
		for i = 0, 2 do
			local can = Instance.new("Part")
			can.Name = "Can"
			can.Shape = Enum.PartType.Cylinder
			can.Size = Vector3.new(0.7, 0.45, 0.45)
			can.Material = Enum.Material.Foil
			can.Color = ({ Color3.fromRGB(40, 110, 210), Color3.fromRGB(245, 195, 40), Color3.fromRGB(60, 170, 80) })[i + 1]
			can.CanCollide = false
			can.CanQuery = false
			can.Massless = true
			can.CFrame = crate.CFrame * CFrame.new(-0.6 + i * 0.6, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90))
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = crate
			weld.Part1 = can
			weld.Parent = can
			can.Parent = crate
		end
		return crate
	end,
	-- Sobre un palet al azar: puede tocar cruzar el mall (o cambiar de planta).
	PickupCFrame = function()
		local pallets = Sequence.tagged(Tags.StockPickup)
		local pallet = pallets[math.random(1, #pallets)]
		local offset = Vector3.new(math.random(-15, 15) / 10, 0, math.random(-15, 15) / 10)
		return CFrame.new(pallet.Position + Vector3.new(0, pallet.Size.Y / 2 + 0.7, 0) + offset)
	end,
	DropoffAtSpot = true,
	PickupText = "Caja de refrescos",
	DropoffAction = "Rellenar",
	DropoffObject = "Máquina expendedora",
	CarryHint = "Lleva la caja a la máquina expendedora (marcada con ▼).",
})
