-- Jefe: Luni, la mascota (noche 5).
--
-- * Su cuerpo es el enemigo "Luni" (src/enemies/Luni): corre detras del grupo mas
--   numeroso; el destello y compania solo la frenan.
-- * Se la vence en el cuarto de un generador (punto RestartGenerator, el mas cercano al
--   grupo al empezar): hay que atraerla hasta alli y activar el "apagon de sector" (mision
--   de evento, mantener E) MIENTRAS ella esta dentro (a RoomRadius del panel).
-- * El progreso dice a que distancia esta Luni del cuarto.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local Server = script.Parent.Parent
local EnemyService = require(Server.EnemyService)
local LightService = require(Server.LightService)
local MissionService = require(Server.MissionService)

local function notifyAll(text: string, kind: string)
	Remotes.event("Notify"):FireAllClients(text, kind)
end

-- Centro de los jugadores vivos (para elegir el generador mas cercano al grupo).
local function playersCenter(): Vector3?
	local sum, n = Vector3.zero, 0
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and player:GetAttribute("Alive") == true then
			sum += root.Position
			n += 1
		end
	end
	return if n > 0 then sum / n else nil
end

return {
	Start = function(ctx)
		local def = ctx.Def
		local enemy = EnemyService.SpawnTemporary("Luni", 1, 3600)
		if not enemy then
			warn("[Boss Luni] No se pudo crear a Luni")
			ctx.Defeat()
			return nil
		end

		local mission = nil
		local panel: BasePart? = nil
		local zone = "?"

		local function luniDistance(): number
			if not panel or not enemy.Model or not enemy.Model.Parent then
				return math.huge
			end
			local p = enemy:GetPosition()
			local feetY = p.Y - enemy.Height / 2
			if math.abs(feetY - (panel.Position.Y - 3.5)) > 8 then
				return math.huge -- otra planta
			end
			return Vector3.new(p.X - panel.Position.X, 0, p.Z - panel.Position.Z).Magnitude
		end

		-- Jugando solo, el apagon es casi instantaneo (si no, Luni te alcanza mientras aprietas)
		local function holdSeconds(): number
			local alive = 0
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("Alive") == true then
					alive += 1
				end
			end
			return if alive <= 1 then def.SoloHoldSeconds else def.HoldSeconds
		end

		local function offer()
			if not panel then
				return
			end
			mission = MissionService.StartEventMission({
				DisplayName = "Apagón de sector con Luni dentro (" .. zone .. ")",
				Spot = panel,
				ActionText = "Apagón de sector",
				ObjectText = "Generador",
				HoldSeconds = holdSeconds(),
				TimeLimit = 900,
				Silent = true,
				CanTrigger = function(_player: Player)
					local d = luniDistance()
					if d <= def.RoomRadius then
						return true
					end
					if d == math.huge then
						return false, "Luni no está en esta planta: atráela hasta el cuarto del generador."
					end
					return false, string.format("Luni tiene que estar dentro del cuarto (está a %d studs).", math.floor(d))
				end,
				OnComplete = function(player: Player)
					enemy:PowerDown()
					LightService.Flicker(zone, 2.5)
					notifyAll(string.format("¡%s activó el apagón de sector! Luni se queda sin energía.", player.DisplayName), "good")
					ctx.Defeat()
					task.delay(6, function()
						EnemyService.RemoveEnemy(enemy)
					end)
				end,
				OnExpire = function()
					if not ctx.Ended and not ctx.Defeated then
						offer()
					end
				end,
			})
		end

		-- Generador: el mas cercano al grupo (si estan todos ocupados, se reintenta)
		local function pickPanel(): boolean
			panel = MissionService.GetFreeSpot("RestartGenerator", nil, playersCenter())
			if not panel then
				return false
			end
			zone = LightService.GetZoneAt(panel.Position) or (panel:GetAttribute("Zone") :: string?) or "?"
			offer()
			notifyAll("Atraigan a Luni al cuarto del generador (" .. zone .. ") y activen el apagón de sector.", "info")
			return true
		end
		if not pickPanel() then
			ctx.SetProgress("Esperando un generador libre...")
		end

		-- Progreso: a que distancia esta Luni del cuarto
		task.spawn(function()
			while not ctx.Ended and not ctx.Defeated do
				if not panel then
					pickPanel()
				else
					local d = luniDistance()
					if d <= def.RoomRadius then
						ctx.SetProgress("¡Luni está en el cuarto! Activen el apagón")
					elseif d == math.huge then
						ctx.SetProgress("Luni está en otra planta que el generador (" .. zone .. ")")
					else
						ctx.SetProgress(string.format("Luni a %d studs del generador (%s)", math.floor(d), zone))
					end
				end
				task.wait(1)
			end
		end)

		return function()
			if mission then
				mission.Cancel()
			end
			EnemyService.RemoveEnemy(enemy)
		end
	end,
}
