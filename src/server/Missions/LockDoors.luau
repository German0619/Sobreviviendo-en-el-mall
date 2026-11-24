-- Mision: Bajar persianas.
-- Baja las persianas de 3 tiendas de un lado de la galeria (tag ShutterControl con
-- atributo Wing = zona). La persiana (parte hija "Shutter") baja hasta media altura.
-- Todas vuelven a subir al empezar la siguiente noche.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Tags = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Tags)
local Multi = require(script.Parent.Multi)

local TWEEN = TweenInfo.new(1.5, Enum.EasingStyle.Linear)

-- Atributos de la persiana: OpenSize/OpenCFrame y ClosedSize/ClosedCFrame (los pone el mapa)
local function setShutter(control: Instance, closed: boolean, instant: boolean?)
	local shutter = control:FindFirstChild("Shutter")
	if not shutter or not shutter:IsA("BasePart") then
		return
	end
	local size = shutter:GetAttribute(if closed then "ClosedSize" else "OpenSize")
	local cframe = shutter:GetAttribute(if closed then "ClosedCFrame" else "OpenCFrame")
	if typeof(size) ~= "Vector3" or typeof(cframe) ~= "CFrame" then
		return
	end
	if instant then
		shutter.Size = size
		shutter.CFrame = cframe
	else
		TweenService:Create(shutter, TWEEN, { Size = size, CFrame = cframe }):Play()
	end
end

return Multi.new({
	Type = "LockDoors",
	TargetTag = Tags.ShutterControl,
	TargetAttribute = "Wing",
	ActionText = "Bajar persiana",
	ObjectText = "Control de persiana",
	OnStep = function(control)
		setShutter(control, true)
	end,
	ResetNight = function()
		for _, control in CollectionService:GetTagged(Tags.ShutterControl) do
			setShutter(control, false, true)
		end
	end,
})
