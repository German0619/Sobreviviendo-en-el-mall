-- PassService: Game Passes (compras permanentes con Robux). Corre en lobby y mall.
--
-- * Al entrar se comprueba cada pase de Config.GamePasses (UserOwnsGamePassAsync).
-- * Si lo compra durante la partida, se activa al momento (PromptGamePassPurchaseFinished).
-- * El cliente lo ve en el atributo Pass_<Nombre> del Player.
-- * En Studio se pueden simular con Config.Debug.StudioOwnedPasses.
--
-- Efectos (los aplica cada sistema leyendo PassService.Owns o el atributo):
--   DoubleMoney        NightManager: x2 en el pago de cada noche.
--   PremiumFlashlight  FlashlightService: Linterna Pro siempre, con haz dorado.
--   VIP                Etiqueta VIP sobre la cabeza (aqui) y nombre dorado en las salas.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Place = require(Shared.Place)

local PassService = {}

-- (player, passName) se acaba de comprar un pase
PassService.Granted = Signal.new()

local owned: { [Player]: { [string]: boolean } } = {}

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind or "info")
end

local function passNameById(passId: number): string?
	for name, id in Config.GamePasses do
		if id ~= 0 and id == passId then
			return name
		end
	end
	return nil
end

function PassService.Owns(player: Player, passName: string): boolean
	local list = owned[player]
	return list ~= nil and list[passName] == true
end

----------------------------------------------------------------------
-- Etiqueta VIP
----------------------------------------------------------------------

local function addVipTag(character: Model)
	if Place.IsLobby then
		return -- en el lobby la placa de PlazaService ya muestra el VIP (nombre dorado)
	end
	local head = character:WaitForChild("Head", 10)
	if not head or head:FindFirstChild("VipTag") then
		return
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = "VipTag"
	tag.Size = UDim2.fromOffset(60, 22)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0)
	tag.MaxDistance = 40
	tag.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(40, 30, 5)
	label.BackgroundTransparency = 0.25
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(255, 200, 60)
	label.Text = "VIP"
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label
	label.Parent = tag
	tag.Parent = head
end

----------------------------------------------------------------------
-- Ownership
----------------------------------------------------------------------

local function grant(player: Player, passName: string)
	local list = owned[player] or {}
	owned[player] = list
	if list[passName] then
		return
	end
	list[passName] = true
	player:SetAttribute("Pass_" .. passName, true)
	if passName == "VIP" and player.Character then
		task.spawn(addVipTag, player.Character)
	end
	PassService.Granted:Fire(player, passName)
end

local function loadPasses(player: Player)
	owned[player] = owned[player] or {}
	if RunService:IsStudio() then
		for _, passName in Config.Debug.StudioOwnedPasses or {} do
			if Config.GamePasses[passName] ~= nil then
				grant(player, passName)
			end
		end
	end
	for passName, passId in Config.GamePasses do
		if passId ~= 0 and not PassService.Owns(player, passName) then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
			end)
			if not ok then
				warn("[PassService] No se pudo comprobar el pase", passName, has)
			elseif has and player.Parent then
				grant(player, passName)
			end
		end
	end
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

function PassService.Start()
	Remotes.event("RequestBuyPass").OnServerEvent:Connect(function(player: Player, passName: any)
		if type(passName) ~= "string" or Config.GamePasses[passName] == nil then
			return
		end
		if PassService.Owns(player, passName) then
			notify(player, "Ya tienes este pase.")
			return
		end
		local passId = Config.GamePasses[passName]
		if passId == 0 then
			notify(player, "Este pase aún no está configurado (falta su ID en Config.GamePasses).", "bad")
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, passId)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local passName = passNameById(passId)
		if purchased and passName then
			grant(player, passName)
			local info = Config.GamePassInfo[passName]
			notify(player, "¡Pase activado: " .. (if info then info.DisplayName else passName) .. "!", "good")
		end
	end)

	local function setup(player: Player)
		player.CharacterAdded:Connect(function(character)
			if PassService.Owns(player, "VIP") then
				addVipTag(character)
			end
		end)
		task.spawn(function()
			loadPasses(player)
			if player.Character and PassService.Owns(player, "VIP") then
				addVipTag(player.Character)
			end
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)
end

return PassService
