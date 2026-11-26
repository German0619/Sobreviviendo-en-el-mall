--!strict
-- BestiaryService (mall): desbloquea las entradas del bestiario (Config.Bestiary) en los
-- datos del jugador. El panel BESTIARIO del lobby las muestra (atributo Bestiary).
--
-- Como se encuentra cada entidad:
--   * Con cuerpo: cada CheckSeconds se mira si el jugador tiene alguna a la vista (a menos
--     de SeeRange, delante de el y sin paredes en medio). Muy cerca (CloseRange) cuenta
--     aunque no la mire de frente.
--   * Las de Config.Bestiary.NotBySight (se disfrazan o no tienen cuerpo) las descubre su
--     propio modulo al sufrirlas, con BestiaryService.Discover (desde los enemigos, via
--     enemies/Common.discover).
--   * Jefes: al empezar su noche, para todos (BossService).
-- Sin aviso de lo que hace ni de como contrarrestarla: eso se lee en el lobby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)

local B = Config.Bestiary

local BestiaryService = {}

function BestiaryService.Discover(player: Player, entityId: string)
	local entry = B.Entries[entityId]
	if not entry then
		return
	end
	local data = DataService.GetData(player)
	if not data or data.Bestiary[entityId] then
		return
	end
	DataService.Update(player, function(d)
		d.Bestiary[entityId] = true
	end)
	Remotes.event("Notify"):FireClient(player, string.format("📖 Nueva entrada en el bestiario: %s (léela en el lobby).", entry.Name), "event")
	if RunService:IsStudio() then
		print(string.format("[Bestiario] %s encontró: %s", player.Name, entityId))
	end
end

function BestiaryService.DiscoverForAll(entityId: string)
	for _, player in Players:GetPlayers() do
		BestiaryService.Discover(player, entityId)
	end
end

----------------------------------------------------------------------
-- A la vista
----------------------------------------------------------------------

-- Ignora personajes, enemigos y objetos de mision (solo tapan las paredes y el mapa)
local function rayParams(enemies: Instance): RaycastParams
	local exclude: { Instance } = { enemies }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local props = Workspace:FindFirstChild("MissionProps")
	if props then
		table.insert(exclude, props)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	return params
end

local function checkSight()
	local enemies = Workspace:FindFirstChild("Enemies")
	if not enemies then
		return
	end
	local visible: { { Type: string, Position: Vector3 } } = {}
	for _, model in enemies:GetChildren() do
		local enemyType = model:GetAttribute("EnemyType")
		if model:IsA("Model") and type(enemyType) == "string" and B.Entries[enemyType] and not B.NotBySight[enemyType] then
			table.insert(visible, { Type = enemyType, Position = model:GetPivot().Position })
		end
	end
	if #visible == 0 then
		return
	end

	local params: RaycastParams? = nil
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		local character = player.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if data and head and root and player:GetAttribute("Alive") == true then
			for _, enemy in visible do
				if not data.Bestiary[enemy.Type] then
					local offset = enemy.Position - head.Position
					local dist = offset.Magnitude
					if dist <= B.SeeRange and dist > 0.1 then
						-- En primera persona el personaje mira hacia donde mira la camara
						local facing = dist <= B.CloseRange or root.CFrame.LookVector:Dot(offset.Unit) >= B.ViewDot
						if facing then
							params = params or rayParams(enemies)
							if Workspace:Raycast(head.Position, offset, params) == nil then
								BestiaryService.Discover(player, enemy.Type)
							end
						end
					end
				end
			end
		end
	end
end

function BestiaryService.Start()
	task.spawn(function()
		while true do
			task.wait(B.CheckSeconds)
			local ok, err = pcall(checkSight)
			if not ok then
				warn("[BestiaryService]", err)
			end
		end
	end)
end

return BestiaryService
