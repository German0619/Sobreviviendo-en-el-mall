--!strict
-- Estado de la partida replicado a todos los clientes mediante atributos.
--
-- GameState (Folder) atributos:
--   Phase        "Waiting" | "Preparation" | "Night" | "Results" | "Upgrades" | "GameOver"
--   Night        numero de noche
--   GameHour     0..6 (12 AM -> 6 AM)
--   PhaseEndsAt  workspace:GetServerTimeNow() en que termina la fase (0 = sin limite)
-- GameState.Missions (Folder): un Configuration por mision activa con atributos
--   Type, DisplayName, Zone, ExpiresAt, Reward

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAME = "GameState"

local folder: Folder
local missions: Folder

if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild(NAME)
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = NAME
		folder:SetAttribute("Phase", "Waiting")
		folder:SetAttribute("Night", 1)
		folder:SetAttribute("GameHour", 0)
		folder:SetAttribute("PhaseEndsAt", 0)
		folder.Parent = ReplicatedStorage
	end
	local m = folder:FindFirstChild("Missions")
	if m then
		missions = m :: Folder
	else
		missions = Instance.new("Folder")
		missions.Name = "Missions"
		missions.Parent = folder
	end
else
	folder = ReplicatedStorage:WaitForChild(NAME) :: Folder
	missions = folder:WaitForChild("Missions") :: Folder
end

return {
	Folder = folder,
	Missions = missions,
}
