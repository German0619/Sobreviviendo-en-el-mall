-- Mision: Luces de emergencia.
-- En el pasillo de servicio (a oscuras) hay luces de emergencia sin bateria (tag
-- EmergencyBox, atributo Zone). Cambiar la bateria de 3 las enciende hasta la noche
-- siguiente: el pasillo queda un poco iluminado (recompensa para quien se atreve).
-- El Electricista lo hace mas rapido (RepairTask).

local CollectionService = game:GetService("CollectionService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Multi = require(script.Parent.Multi)

local ON = Color3.fromRGB(255, 160, 60)
local OFF = Color3.fromRGB(60, 40, 30)

local function setOn(box: Instance, on: boolean)
	local lens = box:FindFirstChild("Lens")
	if not lens or not lens:IsA("BasePart") then
		return
	end
	lens.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	lens.Color = if on then ON else OFF
	local light = lens:FindFirstChild("RestoredLight")
	if on and not light then
		local d = Config.MissionDetails.RestoreEmergencyLights
		local l = Instance.new("PointLight")
		l.Name = "RestoredLight"
		l.Color = ON
		l.Range = d.Range
		l.Brightness = d.Brightness
		l.Parent = lens
	elseif not on and light then
		light:Destroy()
	end
end

return Multi.new({
	Type = "RestoreEmergencyLights",
	TargetTag = Tags.EmergencyBox,
	TargetAttribute = "Zone",
	ActionText = "Cambiar batería",
	ObjectText = "Luz de emergencia",
	RepairTask = true,
	OnStep = function(box: BasePart)
		setOn(box, true)
	end,
	ResetNight = function()
		for _, box in CollectionService:GetTagged(Tags.EmergencyBox) do
			setOn(box, false)
		end
	end,
})
