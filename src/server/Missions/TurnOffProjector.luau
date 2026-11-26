-- Mision: Apagar proyector.
-- El proyector de una sala del cine (tag Projector, atributo Zone = sala) se enciende solo:
-- haz de luz fuerte hacia la pantalla y traqueteo. Hay que mantener E en el panel de la
-- cabina (el MissionSpot, al fondo de la sala).

local CollectionService = game:GetService("CollectionService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Tags = require(Shared.Tags)
local Hold = require(script.Parent.Hold)
local Common = require(script.Parent.Common)

local function projectorOf(zone: string): BasePart?
	for _, part in CollectionService:GetTagged(Tags.Projector) do
		if part:IsA("BasePart") and part:GetAttribute("Zone") == zone then
			return part
		end
	end
	return nil
end

return Hold.new({
	Type = "TurnOffProjector",
	ActionText = "Apagar",
	ObjectText = "Proyector",
	OnBegin = function(mission)
		local projector = projectorOf(mission.Zone)
		if not projector then
			return nil
		end
		-- Haz fuerte hacia la pantalla (misma cara que la luz normal del proyector)
		local normal = projector:FindFirstChildWhichIsA("SpotLight")
		local beam = Instance.new("SpotLight")
		beam.Name = "MissionBeam"
		beam.Face = if normal then normal.Face else Enum.NormalId.Front
		beam.Range = 60
		beam.Angle = 35
		beam.Brightness = 4
		beam.Color = Color3.fromRGB(230, 240, 255)
		beam.Parent = projector
		local sound = Common.loopSound(projector, "Projector", 60)
		-- Parpadeo como de pelicula
		local running = true
		task.spawn(function()
			while running and beam.Parent do
				beam.Brightness = 3 + math.random() * 2
				task.wait(0.08 + math.random() * 0.1)
			end
		end)
		return function()
			running = false
			beam:Destroy()
			if sound then
				sound:Destroy()
			end
		end
	end,
	OnEnd = function(_mission, _success, stop)
		if stop then
			stop()
		end
	end,
})
