-- Crosshair (mall): mirilla de la pistola (pase Pistola, Fase 16).
--   * Con la pistola en la mano aparece una mirilla en el centro de la pantalla y las
--     balas que quedan. El juego va en primera persona: se apunta con la camara.
--   * Al usar la herramienta (clic / tocar) manda UseWeapon("Pistol", direccion de la
--     camara): el servidor dispara hacia la mirilla (con un poco de ayuda al apuntar).
--   * Pequeño retroceso de la mirilla al disparar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local Crosshair = {}

local GUN_ID = "Pistol"
local COLOR = Color3.fromRGB(255, 240, 220)

function Crosshair.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Crosshair"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")
	UIKit.adapt(gui)

	local center = Instance.new("Frame")
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.fromScale(0.5, 0.5)
	center.Size = UDim2.fromOffset(40, 40)
	center.BackgroundTransparency = 1
	center.Visible = false
	center.Parent = gui
	local function line(size: UDim2, pos: UDim2)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = size
		f.Position = pos
		f.BackgroundColor3 = COLOR
		f.BorderSizePixel = 0
		f.Parent = center
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Thickness = 1
		stroke.Transparency = 0.3
		stroke.Parent = f
		return f
	end
	line(UDim2.fromOffset(2, 9), UDim2.new(0.5, 0, 0.5, -10))
	line(UDim2.fromOffset(2, 9), UDim2.new(0.5, 0, 0.5, 10))
	line(UDim2.fromOffset(9, 2), UDim2.new(0.5, -10, 0.5, 0))
	line(UDim2.fromOffset(9, 2), UDim2.new(0.5, 10, 0.5, 0))
	local dot = line(UDim2.fromOffset(3, 3), UDim2.fromScale(0.5, 0.5))
	UIKit.make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dot })
	local scale = Instance.new("UIScale")
	scale.Parent = center

	local ammo = UIKit.text({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 30, 0.5, 18),
		Size = UDim2.fromOffset(80, 20),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR,
		TextStrokeTransparency = 0.4,
		Text = "",
		Visible = false,
		Parent = gui,
	})

	local function refreshAmmo()
		local uses = player:GetAttribute("WeaponUses_" .. GUN_ID)
		ammo.Text = if type(uses) == "number" and uses >= 0 then string.format("%d balas", uses) else ""
	end
	player:GetAttributeChangedSignal("WeaponUses_" .. GUN_ID):Connect(refreshAmmo)

	local toolConn: RBXScriptConnection? = nil
	local function setGun(tool: Tool?)
		if toolConn then
			toolConn:Disconnect()
			toolConn = nil
		end
		local holding = tool ~= nil
		center.Visible = holding
		ammo.Visible = holding
		if not tool then
			return
		end
		refreshAmmo()
		toolConn = tool.Activated:Connect(function()
			local camera = Workspace.CurrentCamera
			if not camera then
				return
			end
			Remotes.event("UseWeapon"):FireServer(GUN_ID, camera.CFrame.LookVector)
			-- Retroceso de la mirilla
			scale.Scale = 1.6
			TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
		end)
	end

	-- Mirar que herramienta lleva en la mano el personaje
	local function watchCharacter(character: Model)
		local function check()
			local tool = character:FindFirstChildOfClass("Tool")
			setGun(if tool and tool:GetAttribute("ModelId") == GUN_ID then tool else nil)
		end
		character.ChildAdded:Connect(check)
		character.ChildRemoved:Connect(check)
		check()
	end
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end

return Crosshair
