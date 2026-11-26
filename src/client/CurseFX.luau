-- CurseFX (mall): aviso para el jugador maldito por el maletin perdido (server/CurseService).
-- Bordes morados que laten despacio y un rotulo "MALDITO · recibes el doble de daño".
-- Lee el atributo Cursed del jugador.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local CurseFX = {}

local PURPLE = Color3.fromRGB(160, 70, 230)

function CurseFX.Start()
	local fxGui = Instance.new("ScreenGui")
	fxGui.Name = "CurseFX"
	fxGui.ResetOnSpawn = false
	fxGui.IgnoreGuiInset = true
	fxGui.DisplayOrder = 14
	fxGui.Parent = player:WaitForChild("PlayerGui")
	local edge = Instance.new("Frame")
	edge.Size = UDim2.fromScale(1, 1)
	edge.BackgroundTransparency = 1
	edge.Visible = false
	edge.Parent = fxGui
	local stroke = Instance.new("UIStroke")
	stroke.Color = PURPLE
	stroke.Thickness = 18
	stroke.Transparency = 0.6
	stroke.Parent = edge

	local hudGui = Instance.new("ScreenGui")
	hudGui.Name = "CurseHUD"
	hudGui.ResetOnSpawn = false
	hudGui.DisplayOrder = 14
	hudGui.Parent = player:WaitForChild("PlayerGui")
	UIKit.adapt(hudGui)
	local label = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(460, 26),
		Font = Enum.Font.GothamBlack,
		TextSize = 18,
		TextColor3 = Color3.fromRGB(205, 150, 255),
		TextStrokeTransparency = 0.3,
		Text = string.format("☠ MALDITO · recibes x%g de daño", Config.Curse.DamageMultiplier),
		Visible = false,
		Parent = hudGui,
	})

	local conn: RBXScriptConnection? = nil
	local function refresh()
		local cursed = player:GetAttribute("Cursed") == true
		edge.Visible = cursed
		label.Visible = cursed
		if cursed and not conn then
			conn = RunService.RenderStepped:Connect(function()
				stroke.Transparency = 0.55 + 0.25 * math.sin(os.clock() * 2.2)
			end)
		elseif not cursed and conn then
			conn:Disconnect()
			conn = nil
		end
	end
	player:GetAttributeChangedSignal("Cursed"):Connect(refresh)
	refresh()
end

return CurseFX
