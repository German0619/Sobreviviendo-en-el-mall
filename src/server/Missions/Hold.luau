-- Fabrica de misiones "mantener E en un punto" (el MissionSpot de la mision).
--
--   Hold.new({
--     Type = "CheckCameras",            -- clave de Config.Missions
--     ActionText = "Revisar", ObjectText = "Monitores",
--     RepairTask = true?,               -- el Electricista lo hace mas rapido
--     CanStart = function(spot, zone) -> boolean?,
--     OnBegin = function(mission) -> estado?,        -- al aparecer la mision
--     OnEnd = function(mission, success, estado)?,   -- al completarse o fallar
--     ResetNight = function()?,
--   })

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config)
local Common = require(script.Parent.Common)

local Hold = {}

function Hold.new(opts)
	local module = {
		CanStart = opts.CanStart,
		ResetNight = opts.ResetNight,
	}

	function module.Begin(mission, complete)
		local def = Config.Missions[opts.Type]
		local state = if opts.OnBegin then opts.OnBegin(mission) else nil

		local prompt = Common.makePrompt(mission.Spot, opts.ActionText, opts.ObjectText, def.Duration)
		if opts.RepairTask then
			prompt:SetAttribute("RepairTask", true)
		end
		prompt.Triggered:Connect(function(player)
			complete(player)
		end)

		return {
			Marker = mission.Spot,
			Cleanup = function(success: boolean)
				prompt:Destroy()
				if opts.OnEnd then
					opts.OnEnd(mission, success, state)
				end
			end,
		}
	end

	return module
end

return Hold
