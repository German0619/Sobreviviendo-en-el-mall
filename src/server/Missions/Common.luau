-- Utilidades compartidas por los modulos de mision.
--
-- Cada modulo de mision exporta:
--   CanStart(spot: BasePart, zone: string) -> boolean      (opcional)
--   Begin(mission, complete: (player) -> boolean) -> { Cleanup: (success: boolean) -> (), Marker: BasePart? }
--   ResetNight()                                           (opcional, limpia restos al empezar otra noche)

local Workspace = game:GetService("Workspace")

local Common = {}

function Common.getPropsFolder(): Folder
	local folder = Workspace:FindFirstChild("MissionProps")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MissionProps"
		folder.Parent = Workspace
	end
	return folder
end

function Common.makePrompt(parent: Instance, actionText: string, objectText: string?, holdDuration: number?): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText or ""
	prompt.HoldDuration = holdDuration or 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = parent
	return prompt
end

-- Posicion del suelo bajo una parte de mision (su cara inferior).
function Common.floorPosition(spot: BasePart): Vector3
	return spot.Position - Vector3.new(0, spot.Size.Y / 2, 0)
end

return Common
