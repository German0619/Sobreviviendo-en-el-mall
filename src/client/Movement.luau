-- Movement: correr con Shift (o boton en movil) gastando estamina.
-- La estamina se publica como atributo local "Stamina" (solo en este cliente)
-- para que el HUD la muestre.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local player = Players.LocalPlayer

local Movement = {}

local BASE_FOV = 70
local SPRINT_FOV = 78

local wantSprint = false
local stamina = Config.Stats.Stamina.Base
local exhausted = false
local lastSprint = 0

local function getMaxStamina(): number
	return player:GetAttribute("MaxStamina") or Config.Stats.Stamina.Base
end

function Movement.Start()
	player.CharacterAdded:Connect(function()
		stamina = getMaxStamina()
		exhausted = false
	end)

	ContextActionService:BindAction("Sprint", function(_, state)
		if state == Enum.UserInputState.Begin then
			wantSprint = true
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			wantSprint = false
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("Sprint", "Correr")
	ContextActionService:SetPosition("Sprint", UDim2.new(1, -170, 1, -90))

	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		local maxStamina = getMaxStamina()
		local infinite = player:GetAttribute("Flag_InfiniteStamina") == true
		local moving = humanoid.MoveDirection.Magnitude > 0.1
		local sprinting = wantSprint and moving and not exhausted and (stamina > 0 or infinite)
		local now = os.clock()

		if sprinting then
			lastSprint = now
			if not infinite then
				stamina -= Config.Movement.StaminaDrainPerSecond * dt
				if stamina <= 0 then
					stamina = 0
					exhausted = true
				end
			end
		elseif now - lastSprint >= Config.Movement.StaminaRegenDelay then
			stamina = math.min(maxStamina, stamina + Config.Movement.StaminaRegenPerSecond * dt)
		end
		if exhausted and stamina >= maxStamina * 0.3 then
			exhausted = false
		end
		stamina = math.min(stamina, maxStamina)

		local walk = player:GetAttribute("WalkSpeed") or Config.Stats.WalkSpeed.Base
		local sprint = player:GetAttribute("SprintSpeed") or walk * Config.Movement.SprintMultiplier
		humanoid.WalkSpeed = if sprinting then sprint else walk

		player:SetAttribute("Stamina", stamina)
		player:SetAttribute("Exhausted", exhausted)

		local camera = Workspace.CurrentCamera
		if camera then
			local targetFov = if sprinting then SPRINT_FOV else BASE_FOV
			camera.FieldOfView += (targetFov - camera.FieldOfView) * math.min(dt * 8, 1)
		end
	end)
end

return Movement
