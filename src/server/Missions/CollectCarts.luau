-- Mision: Juntar carritos (estacionamiento).
--   1. Recoger 3 carritos abandonados por el estacionamiento (tag CartSpot), en cualquier orden.
--   2. Dejarlos en el corral de carritos (tag CartCorral).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Sequence = require(script.Parent.Sequence)
local Common = require(script.Parent.Common)

local busy: { [Instance]: boolean } = {}

local STEEL = Color3.fromRGB(175, 178, 184)
local DARK = Color3.fromRGB(35, 35, 38)

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance?, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Material = material or Enum.Material.Metal
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = parent
	return p
end

-- Carrito de la compra de piezas (la cesta es la parte principal: lleva el prompt).
local function buildCart(spot: BasePart): Part
	-- Modelo 3D del carrito (PropTemplates.ShoppingCart) si esta en el place
	local mesh = Common.templateItem("ShoppingCart", Vector3.new(2.2, 3.6, 3.4))
	if mesh then
		mesh.Name = "Cart"
		mesh.CFrame = CFrame.new(spot.Position + Vector3.new(0, 1.8 - spot.Size.Y / 2, 0)) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
		mesh.Parent = Common.getPropsFolder()
		return mesh
	end
	local cf =CFrame.new(spot.Position + Vector3.new(0, 2.6 - spot.Size.Y / 2, 0)) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
	local basket = part("Cart", Vector3.new(2.4, 1.8, 3.4), cf, STEEL, nil, Enum.Material.DiamondPlate)
	basket.Transparency = 0.35
	part("CartHandle", Vector3.new(2.6, 0.2, 0.2), cf * CFrame.new(0, 1.2, 2), Color3.fromRGB(200, 40, 40), basket, Enum.Material.Plastic)
	part("CartFrame", Vector3.new(2, 0.2, 3.2), cf * CFrame.new(0, -1.6, 0.2), STEEL, basket)
	for _, x in { -0.9, 0.9 } do
		for _, z in { -1.3, 1.5 } do
			local wheel = part("CartWheel", Vector3.new(0.3, 0.7, 0.7), cf * CFrame.new(x, -2.25, z), DARK, basket, Enum.Material.Rubber)
			wheel.Shape = Enum.PartType.Cylinder
		end
	end
	basket.Parent = Common.getPropsFolder()
	return basket
end

return Sequence.new({
	Type = "CollectCarts",
	CanStart = function(): boolean
		return #Sequence.tagged(Tags.CartSpot, busy) >= 2 and #Sequence.tagged(Tags.CartCorral) > 0
	end,
	Plan = function(_mission)
		local spots = Sequence.pickRandom(Sequence.tagged(Tags.CartSpot, busy), Config.Missions.CollectCarts.Count or 3)
		local corrals = Sequence.tagged(Tags.CartCorral)
		if #spots == 0 or #corrals == 0 then
			return nil
		end
		local carts = {}
		local pickups = {}
		for _, spot in spots do
			busy[spot] = true
			local cart = buildCart(spot)
			table.insert(carts, cart)
			table.insert(pickups, {
				Part = cart,
				Action = "Recoger",
				Object = "Carrito",
				OnDone = function()
					cart:Destroy()
				end,
			})
		end
		local drops = {}
		for _, corral in corrals do
			table.insert(drops, { Part = corral, Action = "Dejar carritos", Object = "Corral" })
		end
		return {
			Stages = { { Targets = pickups }, { Targets = drops, Any = true } },
			Cleanup = function()
				for _, spot in spots do
					busy[spot] = nil
				end
				for _, cart in carts do
					cart:Destroy()
				end
			end,
		}
	end,
})
