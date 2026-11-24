-- VendingService: maquinas expendedoras de sodas con efectos temporales.
--
-- * Barata: efecto aleatorio positivo o negativo.  Cara: solo positivos.
-- * Las probabilidades se muestran en la pantalla de la maquina.
-- * Positivas: una a la vez (una nueva reemplaza a la anterior).
-- * Negativas: se ACUMULAN, cada una con su propio tiempo. Si vuelve a salir una que
--   ya tienes, se SUMA su duracion a lo que le quedaba. Conviven con la positiva.
-- * Morir lo quita todo.
-- * Soda a eleccion (Robux): en las maquinas "Premium" hay un segundo boton [R].
--   El jugador ELIGE el efecto (no es aleatorio) y luego paga el producto
--   Config.DevProducts.PremiumSoda, o usa una ficha (data.SodaTokens) si tiene.
--   Si la compra llega cuando no se puede usar, se guarda como ficha.
-- Atributos del Player: SodaEnds_<efecto> = hora del servidor en que termina (uno por
-- soda activa; el HUD los lista).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Place = require(Shared.Place)
local Tags = require(Shared.Tags)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local RunState = require(script.Parent.RunState)
local PlayerStats = require(script.Parent.PlayerStats)

local VendingService = {}

local POSITIVE_KEY = "SodaPos" -- clave del efecto positivo (uno solo)
local NEGATIVE_PREFIX = "Soda_" -- clave de cada negativa: Soda_<efecto>
local ATTR_PREFIX = "SodaEnds_"
local rng = Random.new()
local sodaToken = {} -- [Player] = numero (invalida los temporizadores al limpiar)
local positiveEffect = {} -- [Player] = id de la soda positiva activa
local activeEnds = {} -- [Player] = { [efecto] = hora de fin (servidor) }
local lastUse = {} -- [Player] = os.clock()
local pendingChoice = {} -- [Player] = efecto elegido esperando la compra con Robux

-- Quita todas las sodas del jugador (al morir / reaparecer).
local function clearSoda(player: Player)
	sodaToken[player] = (sodaToken[player] or 0) + 1
	for effectId in activeEnds[player] or {} do
		player:SetAttribute(ATTR_PREFIX .. effectId, nil)
	end
	activeEnds[player] = nil
	positiveEffect[player] = nil
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
	if not RunState.TrySpend(player, machine.Price) then
		Remotes.event("Notify"):FireClient(player, "Billetes insuficientes.", "bad")
		return
	end

	local effectId = Util.weightedRandom(machine.Weights, rng)
	if effectId then
		VendingService.ApplyEffect(player, effectId, 1)
	end
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Quita del HUD una soda cuando se le acaba el tiempo (si no la renovaron antes).
local function expireLater(player: Player, effectId: string, endsAt: number)
	local token = sodaToken[player]
	task.delay(math.max(0, endsAt - Workspace:GetServerTimeNow()) + 0.05, function()
		local ends = activeEnds[player]
		if sodaToken[player] ~= token or not ends or ends[effectId] ~= endsAt then
			return -- se limpio o se le sumo tiempo: ese temporizador ya no vale
		end
		ends[effectId] = nil
		player:SetAttribute(ATTR_PREFIX .. effectId, nil)
		if positiveEffect[player] == effectId then
			positiveEffect[player] = nil
		end
	end)
end

-- Aplica una soda. durationMultiplier: 1.5 en la soda a eleccion.
--   Positiva: reemplaza a la positiva anterior.
--   Negativa: se acumula con las demas; si ya estaba activa, se suma el tiempo.
function VendingService.ApplyEffect(player: Player, effectId: string, durationMultiplier: number?)
	local effect = Config.SodaEffects[effectId]
	if not effect then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local duration = effect.Duration * (durationMultiplier or 1)
	local ends = activeEnds[player] or {}
	activeEnds[player] = ends
	local total = duration
	local message

	if effect.Positive then
		-- Un solo hueco positivo: quitar la positiva anterior del HUD
		local previous = positiveEffect[player]
		if previous and previous ~= effectId then
			ends[previous] = nil
			player:SetAttribute(ATTR_PREFIX .. previous, nil)
		end
		positiveEffect[player] = effectId
		PlayerStats.AddEffect(player, POSITIVE_KEY, effect.Modifiers, effect.Flags, duration)
		message = string.format("%s (%ds)", effect.DisplayName, math.floor(duration))
	else
		-- Negativa: sumar al tiempo que le quedaba (si ya la tenias)
		local remaining = math.max(0, (ends[effectId] or now) - now)
		total = remaining + duration
		PlayerStats.AddEffect(player, NEGATIVE_PREFIX .. effectId, effect.Modifiers, effect.Flags, total)
		message = if remaining > 0
			then string.format("%s +%ds (total %ds)", effect.DisplayName, math.floor(duration), math.floor(total))
			else string.format("%s (%ds)", effect.DisplayName, math.floor(duration))
	end

	local endsAt = now + total
	ends[effectId] = endsAt
	player:SetAttribute(ATTR_PREFIX .. effectId, endsAt)
	expireLater(player, effectId, endsAt)

	Remotes.event("Notify"):FireClient(player, message, if effect.Positive then "good" else "bad")
end

----------------------------------------------------------------------
-- Soda a eleccion (Robux o ficha)
----------------------------------------------------------------------

-- El jugador eligio un efecto en el selector.
local function requestChoice(player: Player, effectId: any)
	if type(effectId) ~= "string" or not table.find(Config.ChoiceSoda.Effects, effectId) then
		return
	end
	local now = os.clock()
	if lastUse[player] and now - lastUse[player] < 1 then
		return
	end
	lastUse[player] = now
	local data = DataService.GetData(player)
	if not data or not isAlive(player) then
		return
	end

	if data.SodaTokens > 0 then
		DataService.Update(player, function(d)
			d.SodaTokens -= 1
		end)
		VendingService.ApplyEffect(player, effectId, Config.ChoiceSoda.DurationMultiplier)
		return
	end
	if Config.DevProducts.PremiumSoda == 0 then
		Remotes.event("Notify"):FireClient(
			player,
			"La soda a elección aún no está configurada (falta Config.DevProducts.PremiumSoda).",
			"bad"
		)
		return
	end
	pendingChoice[player] = effectId
	MarketplaceService:PromptProductPurchase(player, Config.DevProducts.PremiumSoda)
end

-- Lo llama MonetizationService al confirmarse la compra. Siempre devuelve true:
-- si no se puede usar ahora (muerto, en el lobby, otro servidor), queda como ficha.
function VendingService.OnChoiceSodaPurchased(player: Player): boolean
	local effectId = pendingChoice[player]
	pendingChoice[player] = nil
	if effectId and Place.IsMall and isAlive(player) then
		VendingService.ApplyEffect(player, effectId, Config.ChoiceSoda.DurationMultiplier)
		return true
	end
	DataService.Update(player, function(d)
		d.SodaTokens += 1
	end)
	Remotes.event("Notify"):FireClient(
		player,
		"Te guardamos una ficha de soda a elección: úsala en una máquina premium.",
		"info"
	)
	return true
end

----------------------------------------------------------------------
-- Maquinas
----------------------------------------------------------------------

-- Las probabilidades se muestran en la pantalla del panel de la maquina (parte hija
-- "OddsScreen", la crea el mapa) o, si no tiene, en toda la cara frontal.
-- La escala del texto se adapta al ancho de la pantalla (~200 px de ancho).
local function buildOddsDisplay(part: BasePart, machineType: string)
	local machine = Config.VendingMachines[machineType]
	local screen = part:FindFirstChild("OddsScreen")
	local target: BasePart = if screen and screen:IsA("BasePart") then screen else part
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Odds"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = math.max(50, 200 / math.max(target.Size.X, 0.1))
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
	gui.Parent = target
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

	-- Maquina cara: segundo boton para la soda a eleccion (Robux o ficha)
	if machineType == "Premium" then
		local choice = Instance.new("ProximityPrompt")
		choice.Name = "ChoiceSodaPrompt"
		choice.ActionText = "Elegir soda (Robux)"
		choice.ObjectText = Config.ChoiceSoda.DisplayName
		choice.HoldDuration = 0
		choice.MaxActivationDistance = 8
		choice.RequiresLineOfSight = false
		choice.KeyboardKeyCode = Enum.KeyCode.R
		choice.UIOffset = Vector2.new(0, 80)
		choice.Parent = inst
		choice.Triggered:Connect(function(player)
			if isAlive(player) then
				Remotes.event("OpenSodaPicker"):FireClient(player, inst.Position)
			end
		end)
	end
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

function VendingService.Start()
	for _, inst in CollectionService:GetTagged(Tags.VendingMachine) do
		setupMachine(inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.VendingMachine):Connect(setupMachine)
	Remotes.event("RequestChoiceSoda").OnServerEvent:Connect(requestChoice)

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
		activeEnds[player] = nil
		positiveEffect[player] = nil
		pendingChoice[player] = nil
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
