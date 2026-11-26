-- Mision: Sacar la basura.
-- Recoge la bolsa y llevala al contenedor (parte con tag TrashDropoff, en la bodega).

local Tags = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Tags)
local Carry = require(script.Parent.Carry)
local Common = require(script.Parent.Common)

return Carry.new({
	Type = "TakeOutTrash",
	BuildItem = function()
		local mesh = Common.templateItem("TrashBag", Vector3.new(1.8, 2.2, 1.8))
		if mesh then
			mesh.Name = "TrashBag"
			return mesh
		end
		local bag = Instance.new("Part")
		bag.Name = "TrashBag"
		bag.Size = Vector3.new(1.8, 2.4, 1.8)
		bag.Material = Enum.Material.Plastic
		bag.Color = Color3.fromRGB(25, 25, 28)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = bag
		return bag
	end,
	DropoffTag = Tags.TrashDropoff,
	PickupText = "Bolsa de basura",
	DropoffAction = "Tirar basura",
	DropoffObject = "Contenedor",
	CarryHint = "Lleva la bolsa al contenedor de la bodega.",
})
