-- Mision: Recoger bandejas (patio de comidas).
--   1. Recoger 3 bandejas olvidadas en las mesas (tag TraySpot), en cualquier orden.
--   2. Tirarlas en uno de los cubos del patio (tag TrayBin).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Sequence = require(script.Parent.Sequence)
local Common = require(script.Parent.Common)

local busy: { [Instance]: boolean } = {}

local TRAY_COLORS = { Color3.fromRGB(200, 60, 50), Color3.fromRGB(230, 170, 40), Color3.fromRGB(60, 120, 190) }

local function part(name: string, size: Vector3, cf: CFrame, material: Enum.Material, color: Color3, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Material = material
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = parent
	return p
end

-- Bandeja con un vaso y un envoltorio arrugado, sobre el punto de la mesa.
local function buildTray(spot: BasePart): Part
	-- Apoyada sobre la mesa que haya debajo del punto (la mesa puede ser un modelo 3D)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { Common.getPropsFolder() }
	local hit = workspace:Raycast(spot.Position + Vector3.new(0, 2, 0), Vector3.new(0, -6, 0), params)
	local position = if hit then hit.Position + Vector3.new(0, 0.06, 0) else spot.Position
	local cf = CFrame.new(position) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
	local tray = part("Tray", Vector3.new(2, 0.12, 1.4), cf, Enum.Material.Plastic, TRAY_COLORS[math.random(1, #TRAY_COLORS)])
	local cup = part("Cup", Vector3.new(0.7, 0.45, 0.45), cf * CFrame.new(0.5, 0.42, 0.2) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.SmoothPlastic, Color3.fromRGB(235, 235, 230), tray)
	cup.Shape = Enum.PartType.Cylinder
	local wrap = part("Wrapper", Vector3.new(0.6, 0.35, 0.6), cf * CFrame.new(-0.4, 0.25, -0.1), Enum.Material.Foil, Color3.fromRGB(210, 200, 170), tray)
	wrap.Shape = Enum.PartType.Ball
	tray.Parent = Common.getPropsFolder()
	return tray
end

return Sequence.new({
	Type = "ClearTrays",
	CanStart = function(): boolean
		return #Sequence.tagged(Tags.TraySpot, busy) >= 2 and #Sequence.tagged(Tags.TrayBin) > 0
	end,
	Plan = function(_mission)
		local spots = Sequence.pickRandom(Sequence.tagged(Tags.TraySpot, busy), Config.Missions.ClearTrays.Count or 3)
		local bins = Sequence.tagged(Tags.TrayBin)
		if #spots == 0 or #bins == 0 then
			return nil
		end
		local trays = {}
		local pickups = {}
		for _, spot in spots do
			busy[spot] = true
			local tray = buildTray(spot)
			table.insert(trays, tray)
			table.insert(pickups, {
				Part = tray,
				Action = "Recoger",
				Object = "Bandeja",
				OnDone = function()
					tray:Destroy()
				end,
			})
		end
		local drops = {}
		for _, bin in bins do
			table.insert(drops, { Part = bin, Action = "Tirar bandejas", Object = "Cubo" })
		end
		return {
			Stages = { { Targets = pickups }, { Targets = drops, Any = true } },
			Cleanup = function()
				for _, spot in spots do
					busy[spot] = nil
				end
				for _, tray in trays do
					tray:Destroy()
				end
			end,
		}
	end,
})
