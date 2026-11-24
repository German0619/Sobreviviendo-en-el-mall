-- Maniqui convertido: un jugador caido que el Coleccionista convirtio en maniqui a su
-- servicio (jefe de la noche 15). Se comporta como un Maniqui (solo se mueve cuando nadie
-- lo mira), pero es nuevo (no sale de un escaparate), mas oscuro y lleva el nombre del
-- jugador encima. Lo crea server/Bosses/Collector con EnemyService.SpawnTemporary.

local Mannequin = require(script.Parent.Mannequin)

local Converted = {}

local TINT = Color3.fromRGB(95, 85, 80)

function Converted.new(spawnPosition: Vector3, ctx)
	local self = Mannequin.new(spawnPosition, ctx, true)
	for _, d in self.Model:GetDescendants() do
		if d:IsA("BasePart") and d ~= self.Model.PrimaryPart then
			d.Color = TINT
		end
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = "ConvertedName"
	tag.Size = UDim2.fromOffset(200, 26)
	tag.StudsOffsetWorldSpace = Vector3.new(0, self.Height / 2 + 1, 0)
	tag.MaxDistance = 60
	tag.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(230, 120, 120)
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = tag
	tag.Parent = self.Model.PrimaryPart
	return self
end

-- Pone el nombre del jugador convertido (lo llama el jefe al crearlo).
function Converted.SetName(enemy, name: string)
	local label = enemy.Model and enemy.Model:FindFirstChild("Label", true)
	if label and label:IsA("TextLabel") then
		label.Text = "Maniquí de " .. name
	end
end

return Converted
