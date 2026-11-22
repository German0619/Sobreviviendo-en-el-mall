-- FlashlightService: linterna de cada jugador (autoritativa en el servidor).
--
-- El cliente pide encender/apagar; el servidor decide, gasta bateria y
-- responde si la linterna esta alumbrando un punto (lo usan los enemigos).
-- Atributos del Player: Battery, FlashlightOn

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local FlashlightService = {}

local ATTACHMENT_NAME = "FlashlightAttachment"
local COS_DETECT = math.cos(math.rad(Config.Flashlight.DetectHalfAngle))
local COS_DETECT_PRO = math.cos(math.rad(Config.Flashlight.DetectHalfAngle + Config.FlashlightPro.ExtraDetectAngle))

-- El inventario (por vida) lo lleva ShopService y lo publica en atributos del servidor.
local function hasPro(player: Player): boolean
	return (player:GetAttribute("Item_FlashlightPro") or 0) > 0
end

local function getMaxBattery(player: Player): number
	return player:GetAttribute("MaxBattery") or Config.Stats.Battery.Base
end

local function getSpotLight(player: Player): SpotLight?
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local att = head and head:FindFirstChild(ATTACHMENT_NAME)
	return att and att:FindFirstChildOfClass("SpotLight")
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function FlashlightService.IsOn(player: Player): boolean
	return player:GetAttribute("FlashlightOn") == true
end

function FlashlightService.SetOn(player: Player, on: boolean)
	if on and ((player:GetAttribute("Battery") or 0) <= 0 or not isAlive(player)) then
		on = false
	end
	player:SetAttribute("FlashlightOn", on)
	local light = getSpotLight(player)
	if light then
		light.Enabled = on
	end
end

function FlashlightService.Recharge(player: Player, amount: number?)
	local max = getMaxBattery(player)
	local current = player:GetAttribute("Battery") or 0
	player:SetAttribute("Battery", math.min(max, if amount then current + amount else max))
end

-- Actualiza el haz (p. ej. al comprar la Linterna Pro).
function FlashlightService.Refresh(player: Player)
	local light = getSpotLight(player)
	if light then
		light.Angle = Config.Flashlight.Angle + (if hasPro(player) then Config.FlashlightPro.ExtraAngle else 0)
	end
end

-- Devuelve true si la linterna de `player` alumbra `position` (cono + linea de vision).
function FlashlightService.IsLighting(player: Player, position: Vector3): boolean
	if not FlashlightService.IsOn(player) then
		return false
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not head or not root then
		return false
	end

	local toTarget = position - head.Position
	local dist = toTarget.Magnitude
	if dist > Config.Flashlight.Range or dist < 0.01 then
		return false
	end

	-- La camara en primera persona gira el personaje con ella: usamos su frente
	-- (en horizontal) como direccion de la linterna.
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
	if look.Magnitude < 0.01 or flat.Magnitude < 0.01 then
		return dist < 4
	end
	if look.Unit:Dot(flat.Unit) < (if hasPro(player) then COS_DETECT_PRO else COS_DETECT) then
		return false
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	local enemies = Workspace:FindFirstChild("Enemies")
	if enemies then
		table.insert(exclude, enemies)
	end
	local props = Workspace:FindFirstChild("MissionProps")
	if props then
		table.insert(exclude, props)
	end
	params.FilterDescendantsInstances = exclude
	return Workspace:Raycast(head.Position, toTarget, params) == nil
end

function FlashlightService.GetLightingPlayers(position: Vector3): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if FlashlightService.IsLighting(player, position) then
			table.insert(list, player)
		end
	end
	return list
end

local function onCharacterAdded(player: Player, character: Model)
	local head = character:WaitForChild("Head", 10)
	if not head then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = ATTACHMENT_NAME
	att.Position = Vector3.new(0.4, -0.3, -0.6)
	att.Parent = head

	local light = Instance.new("SpotLight")
	light.Range = Config.Flashlight.Range
	light.Angle = Config.Flashlight.Angle + (if hasPro(player) then Config.FlashlightPro.ExtraAngle else 0)
	light.Brightness = Config.Flashlight.Brightness
	light.Color = Color3.fromRGB(255, 244, 214)
	light.Shadows = true
	light.Face = Enum.NormalId.Front
	light.Enabled = false
	light.Parent = att

	player:SetAttribute("FlashlightOn", false)

	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			FlashlightService.SetOn(player, false)
		end)
	end
end

function FlashlightService.Start()
	Remotes.event("ToggleFlashlight").OnServerEvent:Connect(function(player: Player, wantOn: any)
		FlashlightService.SetOn(player, wantOn == true)
	end)

	local function setup(player: Player)
		player:SetAttribute("Battery", getMaxBattery(player))
		player:SetAttribute("FlashlightOn", false)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
		-- Si sube la bateria maxima (mejora), no dejar la actual por encima del limite.
		player:GetAttributeChangedSignal("MaxBattery"):Connect(function()
			local max = getMaxBattery(player)
			if (player:GetAttribute("Battery") or 0) > max then
				player:SetAttribute("Battery", max)
			end
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end

	-- Consumo de bateria
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.2)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, player in Players:GetPlayers() do
				if FlashlightService.IsOn(player) then
					local drain = Config.Flashlight.DrainPerSecond
						* (if hasPro(player) then Config.FlashlightPro.DrainMultiplier else 1)
					local battery = (player:GetAttribute("Battery") or 0) - drain * dt
					player:SetAttribute("Battery", math.max(battery, 0))
					if battery <= 0 then
						FlashlightService.SetOn(player, false)
					end
				end
			end
		end
	end)
end

return FlashlightService
