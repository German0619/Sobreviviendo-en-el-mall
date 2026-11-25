-- FumigatorService (mall): el Fumigador de entidades (pase Fumigator, Config.Fumigator).
--
-- * Una vez por noche, quien tenga el pase tiene un "Fumigador" en la mochila
--   (atributo FumigatorReady; BackpackService crea la herramienta).
-- * Al usarlo, rocia al enemigo que tenga delante (a Range studs, con linea de vision).
--   Hay que mantenerse quieto y sin recibir dano ChannelSeconds[nivel] segundos
--   (2 / 4 / 8). Si te mueves, te golpean, mueres o el enemigo se aleja, se cancela
--   (sin gastar el uso).
-- * Si sale bien, el enemigo desaparece hasta el final de la noche y NO se repone
--   (ReplaceSeconds = 0; con > 0 vendria otro del mismo tipo). No da billetes ni progreso.
-- * No sirve con los jefes (ni con lo que no tiene cuerpo): Config.Fumigator.Immune.
-- Atributos del Player: FumigatorReady (puede usarlo esta noche), FumigateEndsAt (HUD).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local GameState = require(Shared.GameState)

local DefenseService = require(script.Parent.DefenseService)
local EnemyService = require(script.Parent.EnemyService)

local FumigatorService = {}

local F = Config.Fumigator
local MIST = Color3.fromRGB(140, 255, 140)
local channeling: { [Player]: boolean } = {}
local usedNight: { [Player]: number } = {}

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind or "info")
end

local function owns(player: Player): boolean
	return player:GetAttribute("Pass_Fumigator") == true
end

local function isNight(): boolean
	return GameState.Folder:GetAttribute("Phase") == "Night"
end

local function currentNight(): number
	return GameState.Folder:GetAttribute("Night") or 0
end

-- Deja listo el uso de esta noche (si tiene el pase y aun no lo gasto).
local function refreshReady(player: Player)
	local ready = isNight() and owns(player) and usedNight[player] ~= currentNight()
	player:SetAttribute("FumigatorReady", if ready then true else nil)
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function rayParams(): RaycastParams
	local exclude: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	for _, name in { "Enemies", "MissionProps", "DefenseProps" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(exclude, f)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	return params
end

-- El enemigo mas cercano delante (y que se pueda fumigar).
local function findTarget(player: Player)
	local root = getRoot(player)
	if not root then
		return nil
	end
	local origin = root.Position + Vector3.new(0, 1, 0)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local cosHalf = math.cos(math.rad(F.HalfAngle))
	local params = rayParams()
	local best, bestDist = nil, math.huge
	for _, enemy in DefenseService.GetEnemies() do
		local model = enemy.Model
		local enemyType = enemy.EnemyType
		if enemyType and not F.Immune[enemyType] and model and model.Parent then
			local pos = model:GetPivot().Position
			local offset = pos - origin
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local dist = offset.Magnitude
			if dist <= F.Range and dist < bestDist and (flat.Magnitude < 2 or look:Dot(flat.Unit) >= cosHalf) then
				local hit = Workspace:Raycast(origin, offset, params)
				if not hit or (hit.Position - origin).Magnitude >= dist - 2 then
					best, bestDist = enemy, dist
				end
			end
		end
	end
	return best
end

-- Chorro de niebla verde de la mano al enemigo mientras se fumiga.
local function spray(from: Vector3, to: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = "FumigatorSpray"
	part.Size = Vector3.new(0.4, 0.4, 0.4)
	part.CFrame = CFrame.lookAt(from, to)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	local mist = Instance.new("ParticleEmitter")
	mist.Color = ColorSequence.new(MIST)
	mist.LightEmission = 0.4
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 2.2) })
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	mist.Lifetime = NumberRange.new(0.5, 0.8)
	mist.Speed = NumberRange.new((to - from).Magnitude * 1.4)
	mist.SpreadAngle = Vector2.new(8, 8)
	mist.EmissionDirection = Enum.NormalId.Front
	mist.Rate = 60
	mist.Parent = part
	local folder = Workspace:FindFirstChild("DefenseProps") or Workspace
	part.Parent = folder
	return part
end

local function puff(position: Vector3)
	local fx = Instance.new("Part")
	fx.Size = Vector3.new(0.2, 0.2, 0.2)
	fx.CFrame = CFrame.new(position)
	fx.Anchored = true
	fx.CanCollide = false
	fx.CanQuery = false
	fx.Transparency = 1
	fx.Parent = Workspace:FindFirstChild("DefenseProps") or Workspace
	local cloud = Instance.new("ParticleEmitter")
	cloud.Color = ColorSequence.new(MIST)
	cloud.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
	cloud.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	cloud.Lifetime = NumberRange.new(1, 1.6)
	cloud.Speed = NumberRange.new(3, 7)
	cloud.SpreadAngle = Vector2.new(180, 180)
	cloud.Rate = 0
	cloud.Parent = fx
	cloud:Emit(35)
	task.delay(2, function()
		fx:Destroy()
	end)
end

function FumigatorService.Use(player: Player)
	if channeling[player] then
		return
	end
	if not owns(player) or player:GetAttribute("FumigatorReady") ~= true or not isNight() then
		notify(player, "El fumigador ya se usó esta noche.", "info")
		return
	end
	if player:GetAttribute("Hidden") == true then
		return
	end
	local enemy = findTarget(player)
	if not enemy then
		notify(player, string.format("Acércate a un enemigo (a %d studs) y apúntale.", F.Range), "info")
		return
	end
	local character = player.Character
	local root = getRoot(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end

	local enemyType: string = enemy.EnemyType
	local def = Config.Enemies[enemyType]
	local tier = (def and def.Tier) or 1
	local seconds = F.ChannelSeconds[math.clamp(tier, 1, #F.ChannelSeconds)]
	local startPos = root.Position
	local startHealth = humanoid.Health
	local model = enemy.Model :: Model
	channeling[player] = true
	player:SetAttribute("FumigateEndsAt", Workspace:GetServerTimeNow() + seconds)
	notify(player, string.format("Fumigando a %s: no te muevas (%d s).", def and def.DisplayName or enemyType, seconds), "info")

	local mist = spray(root.Position + Vector3.new(0, 1, 0), model:GetPivot().Position)
	local endsAt = os.clock() + seconds
	local reason: string? = nil
	while os.clock() < endsAt do
		task.wait(0.1)
		if not root.Parent or humanoid.Health <= 0 then
			reason = "Fumigación cancelada."
		elseif humanoid.Health < startHealth then
			reason = "¡Te golpearon! Fumigación cancelada."
		elseif Vector3.new(root.Position.X - startPos.X, 0, root.Position.Z - startPos.Z).Magnitude > F.MoveTolerance then
			reason = "Te moviste: fumigación cancelada."
		elseif not model.Parent or (model:GetPivot().Position - root.Position).Magnitude > F.Range + 3 then
			reason = "El enemigo se alejó: fumigación cancelada."
		elseif not isNight() then
			reason = "Fumigación cancelada."
		end
		if reason then
			break
		end
		mist.CFrame = CFrame.lookAt(root.Position + Vector3.new(0, 1, 0), model:GetPivot().Position)
	end
	mist:Destroy()
	channeling[player] = nil
	player:SetAttribute("FumigateEndsAt", nil)
	if reason then
		notify(player, reason .. " Puedes volver a intentarlo.", "bad")
		return
	end

	-- Hecho: desaparece hasta el final de la noche; el director pone otro al minuto
	local position = model:GetPivot().Position
	local floor = Config.getFloor(position.Y - 2)
	puff(position)
	EnemyService.RemoveEnemy(enemy)
	usedNight[player] = currentNight()
	refreshReady(player)
	local name = def and def.DisplayName or enemyType
	if F.ReplaceSeconds > 0 then
		Remotes.event("Notify"):FireAllClients(
			string.format("%s fumigó a %s. Volverá otro en %d s.", player.DisplayName, name, F.ReplaceSeconds),
			"good"
		)
		local token = EnemyService.GetNightToken()
		task.delay(F.ReplaceSeconds, function()
			if EnemyService.GetNightToken() == token then
				EnemyService.SpawnTemporary(enemyType, floor, 3600)
			end
		end)
	else
		Remotes.event("Notify"):FireAllClients(
			string.format("%s fumigó a %s: no volverá esta noche.", player.DisplayName, name),
			"good"
		)
	end
end

-- NightManager: al empezar y al terminar cada noche.
function FumigatorService.RefreshAll()
	for _, player in Players:GetPlayers() do
		refreshReady(player)
	end
end

function FumigatorService.Start()
	local function setup(player: Player)
		player:GetAttributeChangedSignal("Pass_Fumigator"):Connect(function()
			refreshReady(player)
		end)
		refreshReady(player)
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		channeling[player] = nil
		usedNight[player] = nil
	end)
	GameState.Folder:GetAttributeChangedSignal("Phase"):Connect(function()
		-- Partida nueva: las noches vuelven a empezar desde la 1
		if GameState.Folder:GetAttribute("Phase") == "Waiting" then
			usedNight = {}
		end
		FumigatorService.RefreshAll()
	end)
end

return FumigatorService
