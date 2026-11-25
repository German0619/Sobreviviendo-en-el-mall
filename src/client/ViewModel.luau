-- ViewModel (mall): lo que llevas en las manos, visto en primera persona.
--
-- En primera persona Roblox esconde tu personaje y lo que tiene en la mano, asi que aqui
-- se dibuja una copia LOCAL (no se replica) delante de la camara:
--   * abajo a la derecha, la herramienta equipada de la mochila (atributo ModelId/Skin
--     de la Tool, el mismo modelo que ven los demas en tu mano);
--   * abajo a la izquierda, la linterna, con la lente encendida cuando alumbra.
-- Se balancea un poco al andar. No se ve si estas muerto o escondido.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HeldModels = require(Shared.HeldModels)

local player = Players.LocalPlayer

local ViewModel = {}

-- Posiciones respecto a la camara (derecha, abajo, delante)
local RIGHT_OFFSET = CFrame.new(0.95, -0.85, -1.9) * CFrame.Angles(math.rad(4), math.rad(-6), 0)
local LEFT_OFFSET = CFrame.new(-0.85, -0.8, -1.55) * CFrame.Angles(math.rad(3), math.rad(5), 0)

local NORMAL_BEAM = Color3.fromRGB(255, 244, 214)
local PREMIUM_BEAM = Color3.fromRGB(255, 205, 110)
local UV_BEAM = Color3.fromRGB(150, 80, 255)

local folder: Folder? = nil
local rightModel: Model? = nil
local rightKey: string? = nil -- ModelId|Skin del modelo de la derecha
local leftModel: Model? = nil
local leftPremium = false

local function getFolder(): Folder
	local camera = Workspace.CurrentCamera
	if folder and folder.Parent == camera then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "ViewModel"
	f.Parent = camera
	folder = f
	return f
end

-- Copia local anclada, sin sombra ni colisiones.
local function prepare(model: Model): Model
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	model.Parent = getFolder()
	return model
end

local function equippedTool(): Tool?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Tool")
end

-- Los modelos REALES de tus manos (la herramienta y la linterna) se esconden solo para ti:
-- en primera persona Roblox no los oculta y se verian duplicados con la copia de la camara.
local function hideRealHeld(character: Model)
	for _, child in character:GetChildren() do
		if child:IsA("Tool") or child.Name == "HeldFlashlight" then
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 1
				end
			end
		end
	end
end

local function updateRight()
	local tool = equippedTool()
	local id = tool and tool:GetAttribute("ModelId")
	local skin = tool and tool:GetAttribute("Skin")
	local key = if type(id) == "string" then id .. "|" .. tostring(skin) else nil
	if key == rightKey and (rightModel == nil or rightModel.Parent ~= nil) then
		return
	end
	if rightModel then
		rightModel:Destroy()
		rightModel = nil
	end
	rightKey = key
	if type(id) == "string" then
		local model = HeldModels.build(id, if type(skin) == "string" then skin else nil)
		if model then
			rightModel = prepare(model)
		end
	end
end

local leftSkin: string? = nil

local function updateLeft()
	local premium = player:GetAttribute("Pass_PremiumFlashlight") == true
	-- Skin equipada en el lobby; si no tiene, la dorada del pase Linterna Premium
	local equipped = player:GetAttribute("Skin_Flashlight")
	local skin = if type(equipped) == "string" then equipped elseif premium then "Gold" else nil
	if leftModel and leftModel.Parent and premium == leftPremium and skin == leftSkin then
		return
	end
	if leftModel then
		leftModel:Destroy()
	end
	leftPremium = premium
	leftSkin = skin
	local model = HeldModels.build("Flashlight", skin)
	leftModel = if model then prepare(model) else nil
end

function ViewModel.Start()
	local bob = 0
	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local visible = camera ~= nil
			and humanoid ~= nil
			and humanoid.Health > 0
			and player:GetAttribute("Hidden") ~= true
			and player:GetAttribute("Alive") == true
		if not visible then
			if folder then
				folder.Parent = nil
			end
			return
		end
		local f = getFolder()
		if f.Parent ~= camera then
			f.Parent = camera
		end
		hideRealHeld(character :: Model)
		updateRight()
		updateLeft()

		-- Balanceo al andar
		local speed = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z).Magnitude
		bob += dt * (if speed > 0.1 then 9 else 2)
		local amount = if speed > 0.1 then 0.05 else 0.015
		local sway = CFrame.new(math.sin(bob) * amount, math.abs(math.cos(bob)) * amount, 0)

		local camCF = (camera :: Camera).CFrame
		if rightModel then
			rightModel:PivotTo(camCF * sway * RIGHT_OFFSET)
		end
		if leftModel then
			leftModel:PivotTo(camCF * sway:Inverse() * LEFT_OFFSET)
			local on = player:GetAttribute("FlashlightOn") == true
			local color = if player:GetAttribute("UVOn") == true then UV_BEAM elseif leftPremium then PREMIUM_BEAM else NORMAL_BEAM
			HeldModels.setLit(leftModel, on, color)
		end
	end)
end

return ViewModel
