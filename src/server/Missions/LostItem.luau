-- Mision: Objeto perdido.
-- Alguien olvido algo en el mall: llevalo al mostrador de informacion (tag LostAndFound).

local Tags = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Tags)
local Carry = require(script.Parent.Carry)

local Common = require(script.Parent.Common)

-- Template: modelo 3D de ServerStorage.PropTemplates (si falta, la pieza de color)
local ITEMS = {
	{ Template = "LostBackpack", Size = Vector3.new(1.4, 1.8, 0.9), Color = Color3.fromRGB(40, 90, 160), Material = Enum.Material.Fabric }, -- mochila
	{ Template = "Umbrella", Size = Vector3.new(0.6, 2.6, 0.6), Color = Color3.fromRGB(150, 30, 40), Material = Enum.Material.Fabric }, -- paraguas
	{ Template = "LostHandbag", Size = Vector3.new(1.4, 1.3, 0.6), Color = Color3.fromRGB(90, 55, 35), Material = Enum.Material.Leather }, -- bolso
	{ Template = "TeddyBear", Size = Vector3.new(1.2, 1.4, 1.1), Color = Color3.fromRGB(160, 110, 70), Material = Enum.Material.Fabric }, -- peluche
}

return Carry.new({
	Type = "LostItem",
	BuildItem = function()
		local look = ITEMS[math.random(1, #ITEMS)]
		local mesh = Common.templateItem(look.Template, look.Size)
		if mesh then
			mesh.Name = "LostItem"
			return mesh
		end
		local item = Instance.new("Part")
		item.Name = "LostItem"
		item.Size = look.Size
		item.Material = look.Material
		item.Color = look.Color
		return item
	end,
	DropoffTag = Tags.LostAndFound,
	PickupText = "Objeto perdido",
	DropoffAction = "Entregar",
	DropoffObject = "Objetos perdidos",
	CarryHint = "Lleva el objeto al mostrador de información de la entrada.",
})
