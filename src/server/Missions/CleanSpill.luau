-- Mision: Limpiar derrame.
-- Aparece un charco; hay que mantener E para limpiarlo.
-- Los charcos que no se limpian quedan marcados como DirtyArea (los usara el Rastro).

local CollectionService = game:GetService("CollectionService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Common = require(script.Parent.Common)

local CleanSpill = {}

local leftovers = {} -- charcos de misiones falladas

function CleanSpill.Begin(mission, complete)
	local def = Config.Missions.CleanSpill
	local floor = Common.floorPosition(mission.Spot)

	local puddle = Instance.new("Part")
	puddle.Name = "Spill"
	puddle.Shape = Enum.PartType.Cylinder
	puddle.Size = Vector3.new(0.1, 7, 7)
	puddle.CFrame = CFrame.new(floor + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
	puddle.Anchored = true
	puddle.CanCollide = false
	puddle.CanQuery = false
	puddle.Material = Enum.Material.Glass
	puddle.Color = Color3.fromRGB(110, 120, 40)
	puddle.Transparency = 0.15
	puddle.Reflectance = 0.2
	puddle.Parent = Common.getPropsFolder()
	CollectionService:AddTag(puddle, Tags.DirtyArea)

	local prompt = Common.makePrompt(puddle, "Limpiar", "Derrame", def.Duration)
	prompt.Triggered:Connect(function(player)
		complete(player)
	end)

	return {
		Marker = puddle,
		Cleanup = function(success: boolean)
			prompt:Destroy()
			if success then
				puddle:Destroy()
			else
				table.insert(leftovers, puddle)
			end
		end,
	}
end

function CleanSpill.ResetNight()
	for _, puddle in leftovers do
		puddle:Destroy()
	end
	leftovers = {}
end

return CleanSpill
