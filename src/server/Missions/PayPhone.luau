-- Mision: Telefono sonando.
-- Un telefono publico (tag PayPhone) suena en algun sitio del mall. La lista no dice donde
-- ("Sigue el timbre") y el marcador solo aparece al acercarse: hay que guiarse por el
-- sonido. Poco tiempo y buen pago. Contestar lo completa.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Sequence = require(script.Parent.Sequence)
local Common = require(script.Parent.Common)

local busy: { [Instance]: boolean } = {}

local PayPhone = {}

function PayPhone.CanStart(): boolean
	return #Sequence.tagged(Tags.PayPhone, busy) > 0
end

function PayPhone.Begin(mission, complete)
	local def = Config.Missions.PayPhone
	local details = Config.MissionDetails.PayPhone
	local phones = Sequence.tagged(Tags.PayPhone, busy)
	if #phones == 0 then
		error("no hay telefonos libres")
	end
	local phone = phones[math.random(1, #phones)]
	busy[phone] = true
	if mission.Value then
		mission.Value:SetAttribute("Zone", "Sigue el timbre")
	end

	local sound = Common.loopSound(phone, "PhoneRing", details.RingDistance)
	local marker = Common.makeMarker(phone, "☎", Color3.fromRGB(255, 200, 60))
	marker.MaxDistance = details.MarkerDistance
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 120)
	light.Range = 8
	light.Brightness = 1.5
	light.Parent = phone
	local running = true
	task.spawn(function()
		while running and light.Parent do
			light.Enabled = not light.Enabled
			task.wait(0.4)
		end
	end)

	local prompt = Common.makePrompt(phone, "Contestar", "Teléfono", def.Duration)
	prompt.Triggered:Connect(function(player: Player)
		complete(player)
	end)

	return {
		Cleanup = function()
			running = false
			busy[phone] = nil
			prompt:Destroy()
			marker:Destroy()
			light:Destroy()
			if sound then
				sound:Destroy()
			end
		end,
	}
end

return PayPhone
