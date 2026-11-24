-- Mision: Objeto perdido.
-- Alguien olvido algo en el mall: llevalo al mostrador de informacion (tag LostAndFound).

local Tags = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Tags)
local Carry = require(script.Parent.Carry)

local ITEMS = {
	{ Size = Vector3.new(1.4, 1.8, 0.9), Color = Color3.fromRGB(40, 90, 160), Material = Enum.Material.Fabric }, -- mochila
	{ Size = Vector3.new(0.4, 2.6, 0.4), Color = Color3.fromRGB(150, 30, 40), Material = Enum.Material.Fabric }, -- paraguas
	{ Size = Vector3.new(1.4, 1, 0.6), Color = Color3.fromRGB(90, 55, 35), Material = Enum.Material.Leather }, -- bolso
	{ Size = Vector3.new(1.2, 1.4, 0.9), Color = Color3.fromRGB(160, 110, 70), Material = Enum.Material.Fabric }, -- peluche
}

return Carry.new({
	Type = "LostItem",
	BuildItem = function()
		local look = ITEMS[math.random(1, #ITEMS)]
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
