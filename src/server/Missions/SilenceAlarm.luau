-- Mision: Apagar alarma.
-- Salta la alarma de una tienda: luz roja y, mientras suena, ATRAE a los
-- enemigos cercanos (como un petardo). Hay que apagarla en su panel.

local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local DefenseService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("DefenseService"))
local Common = require(script.Parent.Common)
local Hold = require(script.Parent.Hold)

return Hold.new({
	Type = "SilenceAlarm",
	ActionText = "Apagar",
	ObjectText = "Panel de alarma",
	OnBegin = function(mission)
		local spot = mission.Spot
		local beacon = Instance.new("Part")
		beacon.Name = "AlarmBeacon"
		beacon.Shape = Enum.PartType.Ball
		beacon.Size = Vector3.new(0.8, 0.8, 0.8)
		beacon.CFrame = spot.CFrame * CFrame.new(0, spot.Size.Y / 2 + 0.6, 0)
		beacon.Anchored = true
		beacon.CanCollide = false
		beacon.CanQuery = false
		beacon.Material = Enum.Material.Neon
		beacon.Color = Color3.fromRGB(255, 30, 30)
		beacon.Parent = Common.getPropsFolder()
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 30, 30)
		light.Range = 24
		light.Brightness = 3
		light.Parent = beacon

		local removeLure = DefenseService.AddLure(
			spot.Position,
			Config.Missions.SilenceAlarm.TimeLimit + 5,
			Config.MissionDetails.SilenceAlarm.LureRadius
		)

		-- Parpadeo
		local running = true
		task.spawn(function()
			local on = true
			while running and beacon.Parent do
				on = not on
				light.Enabled = on
				beacon.Transparency = if on then 0 else 0.7
				task.wait(0.35)
			end
		end)

		return function()
			running = false
			removeLure()
			beacon:Destroy()
		end
	end,
	OnEnd = function(_mission, _success, stop)
		stop()
	end,
})
