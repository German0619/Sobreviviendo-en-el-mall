-- Effects: efectos visuales locales de las sodas (y en el futuro, de clases).
--   Flag_NightVision  -> imagen mas clara y verdosa
--   Flag_BlurryVision -> desenfoque
-- (Flag_InfiniteStamina lo usa Movement; la velocidad la aplica el servidor.)

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local Effects = {}

local TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Sine)

function Effects.Start()
	local nightVision = Instance.new("ColorCorrectionEffect")
	nightVision.Name = "NightVisionEffect"
	nightVision.Enabled = true
	nightVision.Parent = Lighting

	local blur = Instance.new("BlurEffect")
	blur.Name = "SodaBlur"
	blur.Size = 0
	blur.Parent = Lighting

	-- La correccion de color no aclara lo que ya es negro (zonas sin luz): con vision
	-- nocturna tambien se sube la luz ambiente, solo en esta pantalla. El servidor solo
	-- la fija al arrancar (LightService), asi que se guarda la original para devolverla.
	local original: { Ambient: Color3, OutdoorAmbient: Color3, ExposureCompensation: number }? = nil
	local nvActive = false

	local function apply()
		-- Por soda (Flag_) o por la clase Vision nocturna (Perk_)
		local nv = player:GetAttribute("Flag_NightVision") == true or player:GetAttribute("Perk_NightVision") == true
		TweenService:Create(nightVision, TWEEN, {
			Brightness = if nv then 0.12 else 0,
			Contrast = if nv then 0.15 else 0,
			Saturation = if nv then -0.6 else 0,
			TintColor = if nv then Color3.fromRGB(170, 255, 170) else Color3.new(1, 1, 1),
		}):Play()
		if nv and not nvActive then
			original = {
				Ambient = Lighting.Ambient,
				OutdoorAmbient = Lighting.OutdoorAmbient,
				ExposureCompensation = Lighting.ExposureCompensation,
			}
			TweenService:Create(Lighting, TWEEN, {
				Ambient = Color3.fromRGB(85, 110, 85),
				OutdoorAmbient = Color3.fromRGB(70, 95, 70),
				ExposureCompensation = original.ExposureCompensation + 0.3,
			}):Play()
		elseif not nv and nvActive and original then
			TweenService:Create(Lighting, TWEEN, original):Play()
		end
		nvActive = nv

		local blurry = player:GetAttribute("Flag_BlurryVision") == true
		TweenService:Create(blur, TWEEN, { Size = if blurry then 14 else 0 }):Play()
	end

	player:GetAttributeChangedSignal("Flag_NightVision"):Connect(apply)
	player:GetAttributeChangedSignal("Perk_NightVision"):Connect(apply)
	player:GetAttributeChangedSignal("Flag_BlurryVision"):Connect(apply)
	apply()
end

return Effects
