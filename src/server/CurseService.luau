-- CurseService: maldicion del maletin perdido (Config.Curse).
--   * Curse(player): atributo Cursed = true (Common.damage multiplica el dano), aura morada
--     (Highlight "CurseMark") que ven todos; el cliente (client/CurseFX) muestra su aviso.
--   * Se quita al caer (al revivir ya no estas maldito) y al terminar la noche.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameState = require(Shared.GameState)

local CurseService = {}

local AURA = Color3.fromRGB(150, 60, 220)
local diedConns: { [Player]: RBXScriptConnection } = {}

local function setAura(player: Player, on: boolean)
	local character = player.Character
	if not character then
		return
	end
	local mark = character:FindFirstChild("CurseMark")
	if on and not mark then
		local h = Instance.new("Highlight")
		h.Name = "CurseMark"
		h.FillColor = AURA
		h.FillTransparency = 0.8
		h.OutlineColor = AURA
		h.OutlineTransparency = 0.2
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = character
	elseif not on and mark then
		mark:Destroy()
	end
end

function CurseService.IsCursed(player: Player): boolean
	return player:GetAttribute("Cursed") == true
end

function CurseService.Clear(player: Player)
	player:SetAttribute("Cursed", nil)
	setAura(player, false)
	local conn = diedConns[player]
	diedConns[player] = nil
	if conn then
		conn:Disconnect()
	end
end

function CurseService.Curse(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	player:SetAttribute("Cursed", true)
	setAura(player, true)
	if diedConns[player] then
		diedConns[player]:Disconnect()
	end
	-- Al caer se rompe la maldicion (quien te revive ya no te encuentra maldito)
	diedConns[player] = humanoid.Died:Connect(function()
		CurseService.Clear(player)
	end)
end

function CurseService.ClearAll()
	for _, player in Players:GetPlayers() do
		if CurseService.IsCursed(player) then
			CurseService.Clear(player)
		end
	end
end

function CurseService.Start()
	-- Fin de la noche (o cualquier cambio de fase): nadie sigue maldito
	GameState.Folder:GetAttributeChangedSignal("Phase"):Connect(function()
		if GameState.Folder:GetAttribute("Phase") ~= "Night" then
			CurseService.ClearAll()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local conn = diedConns[player]
		diedConns[player] = nil
		if conn then
			conn:Disconnect()
		end
	end)
end

return CurseService
