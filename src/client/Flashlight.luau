-- Flashlight: camara en primera persona y linterna con F (o boton en movil).
-- El servidor decide si se enciende y gasta la bateria; aqui solo pedimos
-- el cambio y apuntamos la luz hacia donde mira la camara.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer

local Flashlight = {}

local ATTACHMENT_NAME = "FlashlightAttachment"
-- Posicion de la linterna respecto a la camara (a la derecha y un poco abajo)
local HOLD_OFFSET = CFrame.new(0.6, -0.5, -0.8)

local lastToggle = 0

local function toggle()
	if os.clock() - lastToggle < 0.2 then
		return
	end
	lastToggle = os.clock()
	local wantOn = player:GetAttribute("FlashlightOn") ~= true
	if wantOn and (player:GetAttribute("Battery") or 0) <= 0 then
		return
	end
	Remotes.event("ToggleFlashlight"):FireServer(wantOn)
end

function Flashlight.Start()
	player.CameraMode = Enum.CameraMode.LockFirstPerson

	ContextActionService:BindAction("Flashlight", function(_, state)
		if state == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle("Flashlight", "Luz")
	ContextActionService:SetPosition("Flashlight", UDim2.new(1, -170, 1, -160))

	-- Apuntar la linterna con la camara (incluida la inclinacion arriba/abajo).
	-- Es solo visual en este cliente; el servidor usa la direccion del personaje.
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local att = head and head:FindFirstChild(ATTACHMENT_NAME)
		local camera = Workspace.CurrentCamera
		if att and camera then
			att.WorldCFrame = camera.CFrame * HOLD_OFFSET
		end
	end)
end

return Flashlight
