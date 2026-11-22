-- ClassEffects: habilidades de clase que se notan en este cliente.
--   Perk_RepairSpeed  (Electricista) -> mantener E dura menos en reparaciones
--   Perk_ReviveSpeed  (Medico)       -> mantener E dura menos al revivir
--   Perk_SeeGhostsThroughWalls (Medium) -> resalta fantasmas a traves de paredes
-- (La vision nocturna la aplica Effects; las estadisticas, el servidor.)
--
-- La duracion de un ProximityPrompt se puede cambiar solo en este cliente:
-- el que mantiene el boton es el cliente, asi que cada jugador tiene la suya.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local ClassEffects = {}

local HIGHLIGHT_NAME = "MediumHighlight"

local function adjustPrompt(prompt: ProximityPrompt)
	local base = prompt:GetAttribute("BaseHoldDuration")
	if type(base) ~= "number" then
		return
	end

	if prompt:GetAttribute("ReviveTask") then
		-- Medico: gratis, mantener E. Resto: ficha guardada o Robux (pulsar y confirmar).
		if player:GetAttribute("Perk_FreeRevive") then
			prompt.ActionText = "Revivir (gratis)"
			prompt.HoldDuration = base / math.max(player:GetAttribute("Perk_ReviveSpeed") or 1, 0.1)
		elseif (player:GetAttribute("ReviveTokens") or 0) > 0 then
			prompt.ActionText = "Revivir (usar ficha)"
			prompt.HoldDuration = 0.5
		else
			prompt.ActionText = "Revivir (Robux)"
			prompt.HoldDuration = 0.3
		end
		return
	end

	local speed = 1
	if prompt:GetAttribute("RepairTask") then
		speed = player:GetAttribute("Perk_RepairSpeed") or 1
	end
	prompt.HoldDuration = base / math.max(speed, 0.1)
end

local function updateHighlights()
	local enabled = player:GetAttribute("Perk_SeeGhostsThroughWalls") == true
	local folder = Workspace:FindFirstChild("Enemies")
	if not folder then
		return
	end
	for _, model in folder:GetChildren() do
		local existing = model:FindFirstChild(HIGHLIGHT_NAME)
		local wants = enabled and model:GetAttribute("Ghost") == true
		if wants and not existing then
			local highlight = Instance.new("Highlight")
			highlight.Name = HIGHLIGHT_NAME
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.FillColor = Color3.fromRGB(150, 80, 255)
			highlight.FillTransparency = 0.75
			highlight.OutlineColor = Color3.fromRGB(200, 150, 255)
			highlight.OutlineTransparency = 0.1
			highlight.Parent = model
		elseif not wants and existing then
			existing:Destroy()
		end
	end
end

function ClassEffects.Start()
	ProximityPromptService.PromptShown:Connect(function(prompt)
		-- Tu propio cuerpo no se puede revivir a si mismo
		local character = player.Character
		if prompt:GetAttribute("ReviveTask") and character and prompt:IsDescendantOf(character) then
			prompt.Enabled = false
			return
		end
		adjustPrompt(prompt)
	end)

	player:GetAttributeChangedSignal("Perk_SeeGhostsThroughWalls"):Connect(updateHighlights)
	local function watchFolder(folder: Instance)
		folder.ChildAdded:Connect(function()
			task.defer(updateHighlights)
		end)
		updateHighlights()
	end
	local folder = Workspace:FindFirstChild("Enemies")
	if folder then
		watchFolder(folder)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Enemies" then
			watchFolder(child)
		end
	end)
end

return ClassEffects
