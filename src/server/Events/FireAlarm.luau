-- Alarma de incendio: los rociadores mojan una ZONA (un circulo de Radius studs) alrededor
-- de un jugador de la planta. Dentro vas mas lento y las bengalas se apagan. Suena la
-- alarma (tapa los pasos: favorece al Eco). Apagarla en el panel de alarma mas cercano
-- (mision de evento) termina el evento.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Server = script.Parent.Parent
local LightService = require(Server.LightService)
local MissionService = require(Server.MissionService)
local DefenseService = require(Server.DefenseService)
local PlayerStats = require(Server.PlayerStats)
local MissionsCommon = require(Server.Missions.Common)
local EnemyCommon = require(ServerScriptService:WaitForChild("Enemies"):WaitForChild("Common"))

local ALARM_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local WATER = Color3.fromRGB(170, 205, 235)
local RAIN_HEIGHT = 12 -- altura de los rociadores sobre el suelo

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Centro de la zona mojada: junto a un jugador vivo de esa planta (o un punto de la planta).
local function pickOrigin(floor: number): Vector3?
	local candidates = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and player:GetAttribute("Alive") == true and Config.getFloor(root.Position.Y) == floor then
			table.insert(candidates, root.Position)
		end
	end
	local pos = if #candidates > 0 then candidates[math.random(1, #candidates)] else nil
	if not pos then
		for _ = 1, 10 do
			local point = EnemyCommon.randomPatrolPoint()
			if point and Config.getFloor(point.Y) == floor then
				return point
			end
		end
		return nil
	end
	local floorY = EnemyCommon.floorBelow(pos, 10)
	return Vector3.new(pos.X, floorY or (pos.Y - 3), pos.Z)
end

-- Lluvia de los rociadores y sonido de la alarma sobre la zona.
local function buildSprinklers(origin: Vector3, radius: number): BasePart
	local area = Instance.new("Part")
	area.Name = "SprinklerArea"
	area.Size = Vector3.new(radius * 2, 0.2, radius * 2)
	area.CFrame = CFrame.new(origin + Vector3.new(0, RAIN_HEIGHT, 0))
	area.Anchored = true
	area.CanCollide = false
	area.CanQuery = false
	area.CanTouch = false
	area.Transparency = 1
	area.Parent = MissionsCommon.getPropsFolder()

	local rain = Instance.new("ParticleEmitter")
	rain.Name = "Sprinklers"
	rain.Shape = Enum.ParticleEmitterShape.Box
	rain.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.Color = ColorSequence.new(WATER)
	rain.LightEmission = 0.15
	rain.Transparency = NumberSequence.new(0.3)
	rain.Size = NumberSequence.new(0.08)
	rain.Squash = NumberSequence.new(-2) -- gotas alargadas
	rain.Lifetime = NumberRange.new(0.45, 0.6)
	rain.Speed = NumberRange.new(24, 30)
	rain.Rate = math.clamp(radius * radius * 4 / 30, 40, 200)
	rain.Parent = area

	local sound = Instance.new("Sound")
	sound.Name = "FireAlarm"
	sound.SoundId = ALARM_SOUND
	sound.Looped = true
	sound.Volume = 0.6
	sound.PlaybackSpeed = 1.7
	sound.RollOffMinDistance = radius * 0.5
	sound.RollOffMaxDistance = radius * 2
	sound.Parent = area
	sound:Play()
	return area
end

local function inZone(position: Vector3, origin: Vector3, radius: number): boolean
	local flat = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z).Magnitude
	return flat <= radius and math.abs(position.Y - origin.Y) < 12
end

return {
	CanStart = function(ctx)
		return pickOrigin(ctx.Floor or 1) ~= nil
	end,
	Start = function(ctx)
		local def = ctx.Def
		local floor = ctx.Floor or 1
		local origin = pickOrigin(floor)
		if not origin then
			ctx.Finish()
			return nil
		end
		local radius = def.Radius
		local area = buildSprinklers(origin, radius)
		local zone = LightService.GetZoneAt(origin + Vector3.new(0, 3, 0))
		Remotes.event("Notify"):FireAllClients(
			string.format("Los rociadores se activaron%s.", if zone then " en " .. zone else ""),
			"bad"
		)

		local mission = nil
		local spot = MissionService.GetFreeSpot("SilenceAlarm", floor, origin)
		if spot then
			mission = MissionService.StartEventMission({
				DisplayName = "Apagar la alarma de incendio",
				Spot = spot,
				ActionText = "Apagar",
				ObjectText = "Alarma de incendio",
				HoldSeconds = def.HoldSeconds,
				TimeLimit = def.Duration,
				OnComplete = function()
					ctx.Finish()
				end,
			})
		end

		-- Suelo mojado y bengalas apagadas dentro de la zona mientras dure
		task.spawn(function()
			local warnedFlares = false
			local warnedWet: { [Player]: boolean } = {}
			while not ctx.Ended do
				for _, player in Players:GetPlayers() do
					local root = rootOf(player)
					if root and player:GetAttribute("Alive") == true and inZone(root.Position, origin, radius) then
						PlayerStats.AddEffect(player, "FireAlarm", { WalkSpeed = def.WalkMultiplier }, nil, 1.2)
						if not warnedWet[player] then
							warnedWet[player] = true
							Remotes.event("Notify"):FireClient(player, "El suelo está mojado: vas más lento.", "bad")
						end
					end
				end
				local out = DefenseService.ExtinguishFlares(function(position)
					return inZone(position, origin, radius)
				end)
				if out > 0 and not warnedFlares then
					warnedFlares = true
					Remotes.event("Notify"):FireAllClients("El agua de los rociadores apagó las bengalas.", "bad")
				end
				task.wait(0.5)
			end
		end)

		return function()
			if mission then
				mission.Cancel()
			end
			area:Destroy()
		end
	end,
}
