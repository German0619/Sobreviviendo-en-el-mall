-- VendingService: maquinas expendedoras de sodas con efectos temporales.
--
-- * Barata: efecto aleatorio positivo o negativo.  Cara: solo positivos.
-- * Las probabilidades se muestran en la cara frontal de la maquina.
-- * Solo una soda activa a la vez; morir la quita.
-- Atributos del Player: SodaName, SodaEndsAt, SodaPositive

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local PlayerStats = require(script.Parent.PlayerStats)

local VendingService = {}

local EFFECT_ID = "Soda"
local rng = Random.new()
local sodaToken = {} -- [Player] = numero (para no borrar una soda mas nueva)
local lastUse = {} -- [Player] = os.clock()

local function clearSoda(player: Player)
	sodaToken[player] = (sodaToken[player] or 0) + 1
	player:SetAttribute("SodaName", nil)
	player:SetAttribute("SodaEndsAt", nil)
	player:SetAttribute("SodaPositive", nil)
end

-- Probabilidades en porcentaje, ordenadas de mayor a menor.
function VendingService.GetOdds(machineType: string): { { Id: string, Percent: number } }
	local machine = Config.VendingMachines[machineType]
	local list = {}
	if not machine then
		return list
	end
	local total = 0
	for _, w in machine.Weights do
		total += w
	end
	for id, w in machine.Weights do
		table.insert(list, { Id = id, Percent = w / total * 100 })
	end
	table.sort(list, function(a, b)
		return a.Percent > b.Percent
	end)
	return list
end

local function buyFrom(player: Player, machineType: string)
	local machine = Config.VendingMachines[machineType]
	if not machine then
		return
	end
	local now = os.clock()
	if lastUse[player] and now - lastUse[player] < 1 then
		return
	end
	lastUse[player] = now

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not DataService.GetData(player) then
		return
	end
	if not DataService.TrySpend(player, machine.Price) then
		Remotes.event("Notify"):FireClient(player, "Dinero insuficiente.", "bad")
		return
	end

	local effectId = Util.weightedRandom(machine.Weights, rng)
	local effect = effectId and Config.SodaEffects[effectId]
	if not effect then
		return
	end

	PlayerStats.AddEffect(player, EFFECT_ID, effect.Modifiers, effect.Flags, effect.Duration)

	clearSoda(player)
	local token = sodaToken[player]
	player:SetAttribute("SodaName", effect.DisplayName)
	player:SetAttribute("SodaEndsAt", Workspace:GetServerTimeNow() + effect.Duration)
	player:SetAttribute("SodaPositive", effect.Positive)
	task.delay(effect.Duration, function()
		if sodaToken[player] == token then
			clearSoda(player)
		end
	end)

	Remotes.event("Notify"):FireClient(
		player,
		string.format("%s (%ds)", effect.DisplayName, effect.Duration),
		if effect.Positive then "good" else "bad"
	)
end

----------------------------------------------------------------------
-- Maquinas
----------------------------------------------------------------------

local function buildOddsDisplay(part: BasePart, machineType: string)
	local machine = Config.VendingMachines[machineType]
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Odds"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Brightness = 1.5

	local list = Instance.new("Frame")
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	list.BackgroundTransparency = 0.2
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.Parent = list

	local function line(textValue: string, color: Color3, size: number, order: number)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -16, 0, size + 6)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = size
		label.TextColor3 = color
		label.Text = textValue
		label.LayoutOrder = order
		label.Parent = list
	end

	line(machine.DisplayName, Color3.fromRGB(255, 220, 120), 26, 0)
	line(Util.formatMoney(machine.Price), Color3.fromRGB(255, 255, 255), 22, 1)
	line("Probabilidades:", Color3.fromRGB(180, 180, 190), 18, 2)
	for i, odd in VendingService.GetOdds(machineType) do
		local effect = Config.SodaEffects[odd.Id]
		local color = if effect.Positive then Color3.fromRGB(110, 220, 130) else Color3.fromRGB(235, 100, 100)
		line(string.format("%s  %d%%", effect.DisplayName, math.floor(odd.Percent + 0.5)), color, 18, 2 + i)
	end
	gui.Parent = part
end

local function setupMachine(inst: Instance)
	if not inst:IsA("BasePart") or inst:FindFirstChild("VendingPrompt") then
		return
	end
	local machineType = inst:GetAttribute("MachineType")
	local machine = machineType and Config.VendingMachines[machineType]
	if not machine then
		warn("[VendingService] Maquina sin MachineType valido:", inst:GetFullName())
		return
	end

	buildOddsDisplay(inst, machineType)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VendingPrompt"
	prompt.ActionText = "Comprar soda (" .. Util.formatMoney(machine.Price) .. ")"
	prompt.ObjectText = machine.DisplayName
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = inst
	prompt.Triggered:Connect(function(player)
		buyFrom(player, machineType)
	end)
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

function VendingService.Start()
	for _, inst in CollectionService:GetTagged(Tags.VendingMachine) do
		setupMachine(inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.VendingMachine):Connect(setupMachine)

	-- Morir (o reaparecer) quita la soda
	local function setup(player: Player)
		player.CharacterAdded:Connect(function()
			clearSoda(player)
			PlayerStats.ClearEffects(player)
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		sodaToken[player] = nil
		lastUse[player] = nil
	end)

	-- Efecto Regeneracion
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, player in Players:GetPlayers() do
				local regen = PlayerStats.HasFlag(player, "RegenPerSecond")
				if type(regen) == "number" then
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 then
						humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + regen * 0.5)
					end
				end
			end
		end
	end)
end

return VendingService
