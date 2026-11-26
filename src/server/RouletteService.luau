--!strict
-- RouletteService (lobby): ruletas fisicas de la plaza (Config.LobbyRoulettes).
--
-- Vas a la rueda, pulsas [E] en la consola (el cliente llama a RequestWheelSpin),
-- se cobran los diamantes y la rueda gira para todos:
--   * Clases: ClassService.Spin (mismo precio, descuento VIP, politica de objetos
--     aleatorios y reemplazo de la clase del slot equipado que el panel CLASES).
--   * Skins: CosmeticsService.Spin (precio de la caja, repetida = diamantes).
-- El servidor decide el resultado y el angulo final y lo publica en atributos del
-- modelo (SpinId, SpinFrom, SpinTo, SpinStart, SpinDuration, Spinner, Result...);
-- cada cliente anima la rueda con la hora del servidor (client/LobbyRoulettes).
-- Una rueda gira para una persona a la vez.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Place = require(Shared.Place)

local RouletteBuilder = require(script.Parent.RouletteBuilder)
local ClassService = require(script.Parent.ClassService)
local CosmeticsService = require(script.Parent.CosmeticsService)

local RouletteService = {}

local RC = Config.LobbyRoulettes
local rng = Random.new()
local wheels: { [string]: Model } = {}
local busyUntil: { [string]: number } = {}
local lastRequest: { [Player]: number } = {}

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind or "info")
end

-- Quita el puesto que la rueda sustituye (si sigue en el place).
local function removeStand(standId: string?)
	if not standId then
		return
	end
	for _, stand in CollectionService:GetTagged(Tags.LobbyStand) do
		if stand:GetAttribute("Stand") == standId then
			stand:Destroy()
		end
	end
end

local function nearConsole(player: Player, model: Model): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local console = model:FindFirstChild("Console")
	local button = console and console:FindFirstChild("Button") :: BasePart?
	if not root or not button then
		return false
	end
	return (root.Position - button.Position).Magnitude <= RC.MaxUseDistance
end

-- Sectores (1..n) de la rueda cuyo premio es `key`.
local function sectorsOf(model: Model, key: string): { number }
	local list = {}
	local keys = string.split((model:GetAttribute("SectorKeys") :: string?) or "", ",")
	for i, k in keys do
		if k == key then
			table.insert(list, i)
		end
	end
	return list
end

local function spinWheel(player: Player, kind: any): (boolean, string)
	if type(kind) ~= "string" then
		return false, "Ruleta inválida"
	end
	local model = wheels[kind]
	if not model then
		return false, "Ruleta inválida"
	end
	local now = workspace:GetServerTimeNow()
	if (busyUntil[kind] or 0) > now then
		return false, "La ruleta está girando. Espera tu turno."
	end
	if not nearConsole(player, model) then
		return false, "Acércate a la consola de la ruleta."
	end

	-- Cobro y sorteo (mismas reglas que los paneles)
	local key: string?
	local message: string
	local rarity: string?
	local resultText: string
	if kind == "Classes" then
		local ok, msg, className = ClassService.Spin(player)
		if not ok or type(className) ~= "string" then
			return false, msg
		end
		key, message = className, msg
		rarity = Config.Classes[className].Rarity
		resultText = Config.Classes[className].DisplayName
	else
		local ok, msg, itemId, skinId, duplicate = CosmeticsService.Spin(player)
		if not ok or type(skinId) ~= "string" then
			return false, msg
		end
		key, message = skinId, msg
		rarity = Config.Skins[skinId].Rarity
		resultText = string.format("%s · %s%s", Config.Cosmetics.ItemNames[itemId :: string] or "", Config.Skins[skinId].DisplayName, if duplicate then " (+💎)" else "")
	end

	-- Angulo final: varias vueltas y frena dentro del sector (no siempre en su centro)
	local n = model:GetAttribute("Sectors") :: number
	local sa = 360 / n
	local options = sectorsOf(model, key :: string)
	local sector = if #options > 0 then options[rng:NextInteger(1, #options)] else 1
	local from = (model:GetAttribute("Angle") :: number?) or 0
	local jitter = (rng:NextNumber() - 0.5) * sa * 0.7
	local landing = (-(sector - 1) * sa + jitter - from) % 360
	local to = from + RC.Turns * 360 + landing
	local duration = RC.SpinSeconds
	local start = now + 0.2 -- margen para que llegue a todos

	busyUntil[kind] = start + duration + 1.2
	-- La placa sobre la cabeza y los slots del panel esperan a que se pare la rueda
	if kind == "Classes" then
		player:SetAttribute("SpinRevealAt", start + duration)
	end

	local prompt = model:FindFirstChild("SpinPrompt", true) :: ProximityPrompt?
	if prompt then
		prompt.Enabled = false
	end
	model:SetAttribute("SpinFrom", from)
	model:SetAttribute("SpinTo", to)
	model:SetAttribute("SpinStart", start)
	model:SetAttribute("SpinDuration", duration)
	model:SetAttribute("Spinner", player.DisplayName)
	model:SetAttribute("SpinnerId", player.UserId)
	model:SetAttribute("Result", resultText)
	model:SetAttribute("ResultRarity", rarity)
	model:SetAttribute("ResultSector", sector)
	model:SetAttribute("SpinId", ((model:GetAttribute("SpinId") :: number?) or 0) + 1)

	task.delay(start + duration - now, function()
		-- Deja la rueda en su angulo final para quien entre despues
		model:SetAttribute("Angle", to % 360)
		RouletteBuilder.SetAngle(model, to % 360)
		if player.Parent then
			notify(player, message, "good")
		end
		task.wait(1.2)
		if prompt then
			prompt.Enabled = true
		end
	end)
	return true, ""
end

function RouletteService.Start()
	if not Place.IsLobby then
		return
	end
	local lobby = workspace:FindFirstChild("Lobby")
	local folder = Instance.new("Folder")
	folder.Name = "Roulettes"
	folder.Parent = lobby or workspace
	for kind, def in RC.Wheels do
		removeStand(def.ReplacesStand)
		local model = RouletteBuilder.Build(kind, folder)
		if model then
			wheels[kind] = model
		end
	end

	Remotes.func("RequestWheelSpin").OnServerInvoke = function(player: Player, kind: any)
		local t = os.clock()
		if lastRequest[player] and t - lastRequest[player] < 0.5 then
			return false, "Demasiado rápido"
		end
		lastRequest[player] = t
		return spinWheel(player, kind)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return RouletteService
