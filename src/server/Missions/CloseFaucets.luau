-- Mision: Cerrar grifos.
-- 3 grifos de un baño se quedan abiertos (tag Faucet, atributo Zone): sale agua y se oye.
-- Si se acaba el tiempo, queda un charco en el baño (lo huele el Rastro) hasta la noche siguiente.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Multi = require(script.Parent.Multi)
local Common = require(script.Parent.Common)

local puddles: { BasePart } = {}

return Multi.new({
	Type = "CloseFaucets",
	TargetTag = Tags.Faucet,
	TargetAttribute = "Zone",
	ActionText = "Cerrar",
	ObjectText = "Grifo",
	OnActivate = function(spout: BasePart)
		local water = Instance.new("ParticleEmitter")
		water.Name = "RunningWater"
		water.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		water.Color = ColorSequence.new(Color3.fromRGB(190, 220, 245))
		water.LightEmission = 0.1
		water.Size = NumberSequence.new(0.12, 0.05)
		water.Transparency = NumberSequence.new(0.2, 0.8)
		water.Lifetime = NumberRange.new(0.25, 0.35)
		water.Rate = 60
		water.Speed = NumberRange.new(1, 2)
		water.SpreadAngle = Vector2.new(4, 4)
		water.Acceleration = Vector3.new(0, -30, 0)
		water.EmissionDirection = Enum.NormalId.Bottom
		water.Parent = spout
		local sound = Common.loopSound(spout, "Faucet", 45)
		return function()
			water:Destroy()
			if sound then
				sound:Destroy()
			end
		end
	end,
	-- Se acabo el tiempo: el agua rebosa (charco delante del primer grifo que quedo abierto)
	OnFail = function(_mission, pending: { BasePart })
		local spout = pending[1]
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { Common.getPropsFolder() }
		local origin = (spout.CFrame * CFrame.new(0, 0, -2.5)).Position
		local hit = workspace:Raycast(origin, Vector3.new(0, -8, 0), params)
		if hit then
			table.insert(puddles, Common.makePuddle(hit.Position, Config.MissionDetails.CloseFaucets.PuddleSize, Color3.fromRGB(120, 150, 170)))
		end
	end,
	ResetNight = function()
		for _, puddle in puddles do
			puddle:Destroy()
		end
		table.clear(puddles)
	end,
})
