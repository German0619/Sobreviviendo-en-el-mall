-- Spectate: al caer, "No revivir" en la pantalla de muerte (HUD) deja ver la partida
-- desde un companero vivo, en tercera persona.
--
-- * ◀ / ▶ (o Q / E, o los gatillos del mando) cambian de companero.
-- * "Volver" regresa a la pantalla de muerte (para revivirte con Robux o ficha).
-- * Tu cuerpo sigue en el suelo: un Medico (o alguien que pague) te puede revivir igual.
-- * Termina solo al revivir, al acabar la noche o si no queda nadie vivo.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameState = require(Shared.GameState)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local Spectate = {}

local active = false
local target: Player? = nil
local saved: { CameraMode: Enum.CameraMode, MinZoom: number, MaxZoom: number }? = nil
local gui: ScreenGui? = nil
local nameLabel: TextLabel? = nil

local function aliveHumanoid(p: Player): Humanoid?
	if p == player or p:GetAttribute("Alive") ~= true then
		return nil
	end
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function candidates(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if aliveHumanoid(p) then
			table.insert(list, p)
		end
	end
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

function Spectate.IsActive(): boolean
	return active
end

function Spectate.HasTargets(): boolean
	return #candidates() > 0
end

local function watch(p: Player)
	local humanoid = aliveHumanoid(p)
	if not humanoid then
		return
	end
	target = p
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = humanoid
	if nameLabel then
		nameLabel.Text = "Viendo a " .. p.DisplayName
	end
end

-- step = 1 (siguiente) o -1 (anterior)
local function cycle(step: number)
	local list = candidates()
	if #list == 0 then
		Spectate.Stop()
		return
	end
	local index = table.find(list, target :: any) or 0
	index = ((index - 1 + step) % #list) + 1
	watch(list[index])
end

local function buildGui()
	if gui then
		return
	end
	local screen = UIKit.make("ScreenGui", {
		Name = "Spectate",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	UIKit.adapt(screen)
	local bar = UIKit.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(520, 56),
		BackgroundColor3 = Color3.fromRGB(12, 12, 16),
		BackgroundTransparency = 0.2,
		Parent = screen,
	}, { UIKit.corner(10) })
	local function button(textValue: string, x: number, width: number, color: Color3, onClick: () -> ())
		local b = UIKit.make("TextButton", {
			Position = UDim2.fromOffset(x, 6),
			Size = UDim2.fromOffset(width, 44),
			BackgroundColor3 = color,
			Font = Enum.Font.GothamBold,
			TextSize = 18,
			TextColor3 = Color3.fromRGB(235, 235, 235),
			Text = textValue,
			Modal = true, -- libera el raton
			Parent = bar,
		}, { UIKit.corner(8) })
		b.Activated:Connect(onClick)
		return b
	end
	button("◀", 6, 48, Color3.fromRGB(45, 45, 55), function()
		cycle(-1)
	end)
	nameLabel = UIKit.make("TextLabel", {
		Position = UDim2.fromOffset(60, 6),
		Size = UDim2.fromOffset(250, 44),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = Color3.fromRGB(235, 235, 235),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		Parent = bar,
	})
	button("▶", 316, 48, Color3.fromRGB(45, 45, 55), function()
		cycle(1)
	end)
	button("Volver", 370, 144, Color3.fromRGB(150, 50, 50), function()
		Spectate.Stop()
	end)
	gui = screen
end

function Spectate.Begin(): boolean
	if active then
		return true
	end
	local list = candidates()
	if #list == 0 then
		return false
	end
	buildGui()
	active = true
	saved = {
		CameraMode = player.CameraMode,
		MinZoom = player.CameraMinZoomDistance,
		MaxZoom = player.CameraMaxZoomDistance,
	}
	-- Tercera persona detras del companero
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMaxZoomDistance = 16
	player.CameraMinZoomDistance = 8
	watch(list[1])
	if gui then
		gui.Enabled = true
	end
	ContextActionService:BindAction("SpectateCycle", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			local back = input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonL1
			cycle(if back then -1 else 1)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
	return true
end

function Spectate.Stop()
	if not active then
		return
	end
	active = false
	target = nil
	ContextActionService:UnbindAction("SpectateCycle")
	if gui then
		gui.Enabled = false
	end
	if saved then
		player.CameraMinZoomDistance = saved.MinZoom
		player.CameraMaxZoomDistance = saved.MaxZoom
		player.CameraMode = saved.CameraMode
		saved = nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		Workspace.CurrentCamera.CameraSubject = humanoid
	end
end

function Spectate.Start()
	-- Comprobacion periodica: el companero cae o se va, tu revives, acaba la noche
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		if not active then
			return
		end
		elapsed += dt
		if elapsed < 0.25 then
			return
		end
		elapsed = 0
		if player:GetAttribute("Alive") == true or GameState.Folder:GetAttribute("Phase") ~= "Night" then
			Spectate.Stop()
			return
		end
		if not target or not aliveHumanoid(target) then
			cycle(1)
		end
	end)
	-- Al revivir aparece un personaje nuevo: la camara vuelve a ti
	player.CharacterAdded:Connect(function()
		Spectate.Stop()
	end)
end

return Spectate
