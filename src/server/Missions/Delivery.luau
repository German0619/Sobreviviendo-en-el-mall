-- Mision progresiva: Entrega de paquete.
--   1. Recoger el paquete en un palet de la bodega o del almacen alto (tag StockPickup).
--   2. Entregarlo en el mostrador de una tienda (tag StoreCounter), mejor de la OTRA planta.
--   3. Firmar el albaran en Administracion (tag DeliveryDesk).
-- Quien lo recoge lo lleva a la espalda (solo de aspecto) hasta entregarlo.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Sequence = require(script.Parent.Sequence)
local Common = require(script.Parent.Common)

local busyCounters: { [Instance]: boolean } = {}

local function buildPackage(): Part
	local box = Instance.new("Part")
	box.Name = "DeliveryPackage"
	box.Size = Vector3.new(2.2, 1.6, 1.8)
	box.Material = Enum.Material.Cardboard
	box.Color = Color3.fromRGB(185, 145, 95)
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	local tape = Instance.new("Part")
	tape.Name = "Tape"
	tape.Size = Vector3.new(2.25, 0.05, 0.4)
	tape.Material = Enum.Material.SmoothPlastic
	tape.Color = Color3.fromRGB(220, 60, 50)
	tape.Anchored = true
	tape.CanCollide = false
	tape.CanQuery = false
	tape.CanTouch = false
	tape.Parent = box
	return box
end

local function placeOnPallet(item: Part, pallet: BasePart)
	local offset = Vector3.new(math.random(-12, 12) / 10, 0, math.random(-12, 12) / 10)
	item.CFrame = CFrame.new(pallet.Position + Vector3.new(0, pallet.Size.Y / 2 + item.Size.Y / 2, 0) + offset)
	local tape = item:FindFirstChild("Tape") :: BasePart?
	if tape then
		tape.CFrame = item.CFrame * CFrame.new(0, item.Size.Y / 2, 0)
	end
end

-- Copia del paquete soldada a la espalda del jugador (se quita al entregar).
local function carryOnBack(player: Player): BasePart?
	local character = player.Character
	local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
	if not torso or not torso:IsA("BasePart") then
		return nil
	end
	local box = buildPackage()
	box:ClearAllChildren()
	box.Anchored = false
	box.Massless = true
	box.CFrame = torso.CFrame * CFrame.new(0, 0, 1.3)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = box
	weld.Parent = box
	box.Parent = character
	return box
end

return Sequence.new({
	Type = "Delivery",
	CanStart = function(): boolean
		return #Sequence.tagged(Tags.StockPickup) > 0
			and #Sequence.tagged(Tags.StoreCounter, busyCounters) > 0
			and #Sequence.tagged(Tags.DeliveryDesk) > 0
	end,
	Plan = function(_mission)
		local pallets = Sequence.tagged(Tags.StockPickup)
		local counters = Sequence.tagged(Tags.StoreCounter, busyCounters)
		local desks = Sequence.tagged(Tags.DeliveryDesk)
		if #pallets == 0 or #counters == 0 or #desks == 0 then
			return nil
		end
		local pallet = pallets[math.random(1, #pallets)]
		-- Mostrador de la otra planta si lo hay (asi hay que cruzar el mall)
		local palletFloor = Config.getFloor(pallet.Position.Y)
		local otherFloor = {}
		for _, counter in counters do
			if Config.getFloor(counter.Position.Y) ~= palletFloor then
				table.insert(otherFloor, counter)
			end
		end
		local pool = if #otherFloor > 0 then otherFloor else counters
		local counter = pool[math.random(1, #pool)]
		local desk = desks[math.random(1, #desks)]
		busyCounters[counter] = true

		local package = buildPackage()
		placeOnPallet(package, pallet)
		package.Parent = Common.getPropsFolder()
		local onBack: BasePart? = nil

		local store = counter:GetAttribute("Zone")
		return {
			Stages = {
				{
					Targets = {
						{
							Part = package,
							Action = "Recoger",
							Object = "Paquete",
							Duration = 0.5,
							OnDone = function(player: Player)
								package.Transparency = 1
								local tape = package:FindFirstChild("Tape") :: BasePart?
								if tape then
									tape.Transparency = 1
								end
								onBack = carryOnBack(player)
							end,
						},
					},
				},
				{
					Targets = {
						{
							Part = counter,
							Action = "Entregar paquete",
							Object = if type(store) == "string" then "Mostrador de " .. store else "Mostrador",
							OnDone = function()
								if onBack then
									onBack:Destroy()
									onBack = nil
								end
							end,
						},
					},
				},
				{
					Targets = {
						{ Part = desk, Action = "Firmar", Object = "Albarán de entrega" },
					},
				},
			},
			Cleanup = function()
				busyCounters[counter] = nil
				package:Destroy()
				if onBack then
					onBack:Destroy()
				end
			end,
		}
	end,
})
