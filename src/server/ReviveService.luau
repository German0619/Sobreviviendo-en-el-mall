-- ReviveService: revivir a jugadores caidos durante la noche.
--
-- Al caer, el cuerpo queda en el suelo con un "+" rojo visible a traves de
-- las paredes. Formas de revivir:
--   * Medico (Perk FreeRevive): GRATIS, manteniendo E sobre el cuerpo.
--   * Cualquier companero: paga Robux (producto Revive) desde el cuerpo.
--   * El propio caido: paga Robux desde su pantalla de muerte.
--   * Si tienes "fichas de revivir" (compras que no se pudieron usar), se usa
--     una ficha en vez de pedir Robux.
-- La entrega de la compra la hace MonetizationService -> OnRevivePurchased.
-- Atributo del Player: Downed (true mientras su cuerpo se puede revivir)

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local GameState = require(Shared.GameState)

local DataService = require(script.Parent.DataService)
local PlayerStats = require(script.Parent.PlayerStats)

local ReviveService = {}

local downed = {} -- [Player] = { Prompt, Marker, Root }
local pending = {} -- [comprador] = jugador a revivir

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind or "info")
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return player:GetAttribute("Alive") == true and humanoid ~= nil and humanoid.Health > 0
end

local function clear(player: Player)
	local entry = downed[player]
	if not entry then
		return
	end
	downed[player] = nil
	player:SetAttribute("Downed", nil)
	if entry.Prompt then
		entry.Prompt:Destroy()
	end
	if entry.Marker then
		entry.Marker:Destroy()
	end
end

function ReviveService.IsDowned(player: Player): boolean
	return downed[player] ~= nil and GameState.Folder:GetAttribute("Phase") == "Night"
end

-- Revive de verdad (ya pagado / gratis).
local function revive(player: Player, by: Player)
	local entry = downed[player]
	if not entry or not player.Parent then
		return false
	end
	local position = entry.Root.Position
	clear(player)

	player:SetAttribute("SpawnHealthFraction", Config.Revive.HealthFraction)
	player:LoadCharacter()
	if player.Character then
		player.Character:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
	end
	player:SetAttribute("Alive", true)

	local message = if by == player
		then player.DisplayName .. " volvió a la vida"
		else string.format("%s revivió a %s", by.DisplayName, player.DisplayName)
	Remotes.event("Notify"):FireAllClients(message, "good")
	return true
end

-- Paga (ficha o Robux) para revivir a `target`.
local function requestPaidRevive(buyer: Player, target: Player)
	if not ReviveService.IsDowned(target) then
		return
	end
	local data = DataService.GetData(buyer)
	if data and data.ReviveTokens > 0 then
		DataService.Update(buyer, function(d)
			d.ReviveTokens -= 1
		end)
		revive(target, buyer)
		return
	end
	if Config.DevProducts.Revive == 0 then
		notify(buyer, "Revivir con Robux aún no está configurado (falta el ID del producto).", "bad")
		return
	end
	pending[buyer] = target
	MarketplaceService:PromptProductPurchase(buyer, Config.DevProducts.Revive)
end

-- Lo llama MonetizationService al confirmarse una compra de revivir.
-- Siempre devuelve true: si ya no se puede usar, se guarda como ficha.
function ReviveService.OnRevivePurchased(buyer: Player): boolean
	local target = pending[buyer]
	pending[buyer] = nil
	if not target and ReviveService.IsDowned(buyer) then
		target = buyer
	end
	if target and ReviveService.IsDowned(target) and revive(target, buyer) then
		return true
	end
	DataService.Update(buyer, function(d)
		d.ReviveTokens += 1
	end)
	notify(buyer, "No había nadie que revivir: te guardamos una ficha de revivir.", "info")
	return true
end

-- Lo llama NightManager cuando un participante cae durante la noche.
function ReviveService.OnDowned(player: Player, character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	clear(player)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RevivePrompt"
	prompt.ActionText = "Revivir"
	prompt.ObjectText = player.DisplayName
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	-- El cliente ajusta texto y duracion segun su clase (ClassEffects)
	prompt:SetAttribute("ReviveTask", true)
	prompt:SetAttribute("BaseHoldDuration", Config.Revive.HoldSeconds)
	prompt.Parent = root

	local marker = Instance.new("BillboardGui")
	marker.Name = "ReviveMarker"
	marker.Size = UDim2.fromOffset(40, 40)
	marker.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	marker.AlwaysOnTop = true
	marker.MaxDistance = 150
	marker.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = "+"
	label.TextColor3 = Color3.fromRGB(235, 60, 60)
	label.TextStrokeTransparency = 0.3
	label.Parent = marker
	marker.Parent = root

	prompt.Triggered:Connect(function(reviver: Player)
		if reviver == player or not isAlive(reviver) or not ReviveService.IsDowned(player) then
			return
		end
		if PlayerStats.GetPerk(reviver, "FreeRevive") then
			-- (la duracion la controla el cliente del Medico; aqui basta con que lo complete)
			revive(player, reviver)
		else
			requestPaidRevive(reviver, player)
		end
	end)

	downed[player] = { Prompt = prompt, Marker = marker, Root = root }
	player:SetAttribute("Downed", true)
end

-- Al terminar la noche se quitan todos los cuerpos revivibles.
function ReviveService.Clear()
	for player in downed do
		clear(player)
	end
	pending = {}
end

function ReviveService.Start()
	Remotes.event("RequestSelfRevive").OnServerEvent:Connect(function(player: Player)
		requestPaidRevive(player, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		clear(player)
		pending[player] = nil
	end)
end

return ReviveService
