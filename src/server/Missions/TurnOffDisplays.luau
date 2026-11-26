-- Mision: Apagar escaparates.
-- Apaga la pantalla del escaparate de 3 tiendas de un lado de la galeria (tag
-- StoreDisplay con atributo Wing = zona). Se vuelven a encender la noche siguiente.

local CollectionService = game:GetService("CollectionService")
local Tags = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Tags)
local Multi = require(script.Parent.Multi)

local OFF_COLOR = Color3.fromRGB(12, 12, 14)

local function setOn(display: Instance, on: boolean)
	local screen = display:FindFirstChild("Screen")
	if screen and screen:IsA("SurfaceGui") then
		screen.Enabled = on
	end
	local glow = display:FindFirstChildWhichIsA("Light")
	if glow then
		glow.Enabled = on
	end
	local onColor = display:GetAttribute("OnColor") -- (lo pone el mapa)
	if display:IsA("BasePart") then
		display.Color = if on and typeof(onColor) == "Color3" then onColor else OFF_COLOR
	end
end

return Multi.new({
	Type = "TurnOffDisplays",
	TargetTag = Tags.StoreDisplay,
	TargetAttribute = "Wing",
	ActionText = "Apagar",
	ObjectText = "Pantalla del escaparate",
	OnStep = function(display: BasePart)
		setOn(display, false)
	end,
	ResetNight = function()
		for _, display in CollectionService:GetTagged(Tags.StoreDisplay) do
			setOn(display, true)
		end
	end,
})
