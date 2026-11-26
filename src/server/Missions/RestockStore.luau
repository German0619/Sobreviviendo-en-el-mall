-- Mision: Reponer tienda.
-- Recoge una caja en la bodega (tag StockPickup) y llevala al estante de la
-- tienda (el MissionSpot de la mision).

local CollectionService = game:GetService("CollectionService")
local Tags = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Tags)
local Carry = require(script.Parent.Carry)
local Common = require(script.Parent.Common)

local function pickups(): { BasePart }
	local list = {}
	for _, part in CollectionService:GetTagged(Tags.StockPickup) do
		if part:IsA("BasePart") then
			table.insert(list, part)
		end
	end
	return list
end

return Carry.new({
	Type = "RestockStore",
	CanStart = function()
		return #pickups() > 0
	end,
	BuildItem = function()
		local mesh = Common.templateItem("StockBox", Vector3.new(1.7, 2.2, 1.5))
		if mesh then
			mesh.Name = "StockBox"
			return mesh
		end
		local box = Instance.new("Part")
		box.Name = "StockBox"
		box.Size = Vector3.new(2, 1.6, 2)
		box.Material = Enum.Material.Cardboard
		box.Color = Color3.fromRGB(170, 130, 85)
		return box
	end,
	-- Sobre un palet de la bodega, un poco desplazada para que no se apilen.
	-- Con 2 plantas: preferir un palet de la misma planta que el estante.
	PickupCFrame = function(mission)
		local list = pickups()
		local spot = mission and mission.Spot
		if spot and spot:IsA("BasePart") then
			local sameFloor = {}
			for _, part in list do
				if math.abs(part.Position.Y - spot.Position.Y) < 8 then
					table.insert(sameFloor, part)
				end
			end
			if #sameFloor > 0 then
				list = sameFloor
			end
		end
		local pallet = list[math.random(1, #list)]
		local offset = Vector3.new(math.random(-15, 15) / 10, 0, math.random(-15, 15) / 10)
		return CFrame.new(pallet.Position + Vector3.new(0, pallet.Size.Y / 2 + 0.8, 0) + offset)
	end,
	DropoffAtSpot = true,
	PickupText = "Caja de mercancía",
	DropoffAction = "Reponer",
	DropoffObject = "Estante",
	CarryHint = "Lleva la caja al estante de la tienda (marcado con ▼).",
})
