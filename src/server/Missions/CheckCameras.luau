-- Mision: Revisar camaras.
-- En la oficina de seguridad: al completarla, todo el equipo ve a los enemigos
-- a traves de las paredes unos segundos (Config.MissionDetails.CheckCameras).

local Workspace = game:GetService("Workspace")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Hold = require(script.Parent.Hold)

local function revealEnemies(seconds: number)
	local folder = Workspace:FindFirstChild("Enemies")
	if not folder then
		return
	end
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and not model:FindFirstChild("CameraReveal") then
			local h = Instance.new("Highlight")
			h.Name = "CameraReveal"
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			h.FillColor = Color3.fromRGB(255, 60, 60)
			h.FillTransparency = 0.7
			h.OutlineColor = Color3.fromRGB(255, 120, 120)
			h.Parent = model
			task.delay(seconds, function()
				h:Destroy()
			end)
		end
	end
	Remotes.event("Notify"):FireAllClients(string.format("Cámaras revisadas: ves a todos los enemigos %d s.", seconds), "good")
end

return Hold.new({
	Type = "CheckCameras",
	ActionText = "Revisar",
	ObjectText = "Monitores de seguridad",
	OnEnd = function(_mission, success)
		if success then
			revealEnemies(Config.MissionDetails.CheckCameras.RevealSeconds)
		end
	end,
})
