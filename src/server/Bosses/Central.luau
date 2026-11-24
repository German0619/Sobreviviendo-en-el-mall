-- Jefe: La Central (noche 20). La IA de seguridad del mall: no tiene cuerpo.
--
-- * Camaras: encendidas toda la noche (aunque no haya Vigilante). Si una te ve, los
--   enemigos van a tu posicion (un senuelo).
-- * Cada ActionSeconds hace una de estas cosas: apaga las luces de la zona de un jugador,
--   cierra las persianas de las tiendas mas cercanas o anuncia tareas falsas por
--   megafonia (una Megafonia temporal).
-- * Se la vence reiniciando sus Servers servidores, en plantas distintas, CASI A LA VEZ:
--   al reiniciar el primero empieza una cuenta atras (SyncSeconds; jugando solo,
--   SoloSyncSeconds). Si no estan todos antes de que acabe, los vuelve a encender.
--   Los servidores son los monitores de seguridad (puntos CheckCameras) de cada planta y,
--   si faltan, armarios de servidores repartidos por el mall.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Server = script.Parent.Parent
local EnemyService = require(Server.EnemyService)
local LightService = require(Server.LightService)
local MissionService = require(Server.MissionService)
local DefenseService = require(Server.DefenseService)
local MissionsCommon = require(Server.Missions.Common)
local EventUtil = require(Server.Events.EventUtil)
local SecurityCamera = require(ServerScriptService:WaitForChild("Enemies"):WaitForChild("SecurityCamera"))

local RED = Color3.fromRGB(255, 50, 40)
local GREEN = Color3.fromRGB(60, 230, 110)
local LIGHT_REASON = "Central"

local function say(text: string, kind: string?)
	Remotes.event("Notify"):FireAllClients("CENTRAL: " .. text, kind or "bad")
end

-- Armario de servidores (si no hay monitores en esa planta).
local function buildRack(point: Vector3): BasePart
	local rack = Instance.new("Part")
	rack.Name = "CentralServer"
	rack.Size = Vector3.new(2.4, 6, 1.6)
	rack.CFrame = CFrame.new(point + Vector3.new(0, 3, 0)) * CFrame.Angles(0, math.rad(math.random(0, 3) * 90), 0)
	rack.Anchored = true
	rack.Material = Enum.Material.Metal
	rack.Color = Color3.fromRGB(28, 30, 36)
	rack.Parent = MissionsCommon.getPropsFolder()
	for row = 0, 5 do
		local slot = Instance.new("Part")
		slot.Name = "Slot"
		slot.Size = Vector3.new(2.1, 0.5, 0.05)
		slot.CFrame = rack.CFrame * CFrame.new(0, -2.3 + row * 0.9, -0.82)
		slot.Anchored = true
		slot.CanCollide = false
		slot.CanQuery = false
		slot.Material = Enum.Material.DiamondPlate
		slot.Color = Color3.fromRGB(50, 52, 60)
		slot.Parent = rack
	end
	return rack
end

-- Piloto del servidor: rojo (encendido = la Central manda) o verde (reiniciado).
local function buildLed(spot: BasePart): BasePart
	local led = Instance.new("Part")
	led.Name = "CentralServerLed"
	led.Shape = Enum.PartType.Ball
	led.Size = Vector3.new(0.6, 0.6, 0.6)
	led.CFrame = CFrame.new(spot.Position + Vector3.new(0, spot.Size.Y / 2 + 0.6, 0))
	led.Anchored = true
	led.CanCollide = false
	led.CanQuery = false
	led.Material = Enum.Material.Neon
	led.Color = RED
	led.Parent = MissionsCommon.getPropsFolder()
	local light = Instance.new("PointLight")
	light.Color = RED
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = led
	return led
end

local function setLed(led: BasePart, restarted: boolean)
	local color = if restarted then GREEN else RED
	led.Color = color
	local light = led:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = color
	end
end

local function aliveCount(): number
	local n = 0
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Alive") == true then
			n += 1
		end
	end
	return n
end

return {
	Start = function(ctx)
		local def = ctx.Def
		say("Protocolo de seguridad activado. Intrusos detectados.")

		------------------------------------------------------------
		-- Servidores
		------------------------------------------------------------
		local servers = {}
		local function farEnough(position: Vector3): boolean
			for _, s in servers do
				if (s.Spot.Position - position).Magnitude < def.ServerMinSpacing then
					return false
				end
			end
			return true
		end
		local function addServer(spot: BasePart, built: boolean)
			local zone = LightService.GetZoneAt(spot.Position) or (spot:GetAttribute("Zone") :: string?) or "?"
			table.insert(servers, { Spot = spot, Built = built, Zone = zone, Led = buildLed(spot), Restarted = false })
		end
		-- Monitores de seguridad de cada planta (la "sala de control")
		for floor = 1, 2 do
			if #servers < def.Servers then
				local spot = MissionService.GetFreeSpot("CheckCameras", floor)
				if spot then
					addServer(spot, false)
				end
			end
		end
		-- El resto, armarios repartidos (alternando plantas, lejos de los otros)
		local floor = 1
		local tries = 0
		while #servers < def.Servers and tries < 30 do
			tries += 1
			local point = EventUtil.pointOnFloor(floor, 20, math.huge)
			if point and farEnough(point) then
				addServer(buildRack(point), true)
				floor = 3 - floor
			end
		end
		local total = #servers

		local windowEndsAt: number? = nil
		local restartedCount = 0

		local function updateProgress()
			if windowEndsAt then
				ctx.SetProgress(string.format("Servidores %d/%d  ·  ¡Rápido! %ds", restartedCount, total, math.max(0, math.ceil(windowEndsAt - os.clock()))))
			else
				ctx.SetProgress(string.format("Servidores reiniciados %d/%d", restartedCount, total))
			end
		end

		local function defeat()
			say("Sistema... descon...ectado.", "good")
			-- Las camaras siguen girando, pero ya no avisan a nadie
			SecurityCamera.ReportMessage = ""
			ctx.Defeat()
		end

		local offer -- (definida abajo)
		local function onRestarted(server, player: Player)
			server.Restarted = true
			server.Mission = nil
			setLed(server.Led, true)
			restartedCount += 1
			if restartedCount >= total then
				windowEndsAt = nil
				updateProgress()
				defeat()
				return
			end
			if not windowEndsAt then
				local seconds = if aliveCount() <= 1 then def.SoloSyncSeconds else def.SyncSeconds
				windowEndsAt = os.clock() + seconds
				say(string.format("Reinicio detectado. Restaurando en %d s...", seconds))
			end
			Remotes.event("Notify"):FireAllClients(
				string.format("%s reinició un servidor (%s). Faltan %d.", player.DisplayName, server.Zone, total - restartedCount),
				"good"
			)
			updateProgress()
		end

		function offer(server)
			server.Mission = MissionService.StartEventMission({
				DisplayName = "Reiniciar servidor de la Central (" .. server.Zone .. ")",
				Spot = server.Spot,
				ActionText = "Reiniciar servidor",
				ObjectText = "Servidor",
				HoldSeconds = def.RestartHold,
				TimeLimit = 900,
				RepairTask = true,
				Silent = true,
				OnComplete = function(player: Player)
					onRestarted(server, player)
				end,
				OnExpire = function()
					if not ctx.Ended and not server.Restarted then
						offer(server)
					end
				end,
			})
		end
		for _, server in servers do
			offer(server)
		end
		updateProgress()
		if total == 0 then
			defeat()
			return nil
		end

		------------------------------------------------------------
		-- Camaras: si una te ve, los enemigos van hacia ti
		------------------------------------------------------------
		EnemyService.EnsureCameras()
		SecurityCamera.ReportMessage = "¡LA CENTRAL te ha visto por una cámara! Los enemigos van hacia ti."
		local spottedConn = SecurityCamera.Spotted:Connect(function(_player: Player, position: Vector3)
			if not ctx.Ended and not ctx.Defeated then
				DefenseService.AddLure(position, def.CameraLureSeconds, def.CameraLureRadius)
			end
		end)

		------------------------------------------------------------
		-- Acciones: luces, persianas, megafonia
		------------------------------------------------------------
		local darkZones = {} -- [zona] = true (apagadas por la Central)
		local sealed = {} -- [funcion para reabrir] = true
		local intercoms = {}

		local function randomPlayerRoot(): BasePart?
			local list = EventUtil.alivePlayers()
			if #list == 0 then
				return nil
			end
			return EventUtil.rootOf(list[math.random(1, #list)])
		end

		local actions = {
			Lights = function()
				local root = randomPlayerRoot()
				local zone = root and LightService.GetZoneAt(root.Position)
				if not zone or LightService.IsAmbientDark(zone) or darkZones[zone] then
					return false
				end
				darkZones[zone] = true
				LightService.Flicker(zone, 1)
				task.delay(1, function()
					if darkZones[zone] then
						LightService.SetReason(zone, LIGHT_REASON, true)
					end
				end)
				task.delay(def.LightsOutSeconds, function()
					if darkZones[zone] then
						darkZones[zone] = nil
						LightService.SetReason(zone, LIGHT_REASON, false)
					end
				end)
				say("Ahorro de energía en " .. zone .. ".")
				return true
			end,
			Shutters = function()
				local stores = EventUtil.getStores(nil)
				table.sort(stores, function(a, b)
					return EventUtil.nearestPlayerDistance(a.Shutter.Position) < EventUtil.nearestPlayerDistance(b.Shutter.Position)
				end)
				local names = {}
				for i = 1, math.min(def.ShutterStores, #stores) do
					local reopen = EventUtil.sealShutter(stores[i], 1.5)
					sealed[reopen] = true
					table.insert(names, stores[i].Zone)
					task.delay(def.ShutterCloseSeconds, function()
						if sealed[reopen] then
							sealed[reopen] = nil
							reopen()
						end
					end)
				end
				if #names == 0 then
					return false
				end
				say("Cierre de seguridad: " .. table.concat(names, ", ") .. ".")
				return true
			end,
			Intercom = function()
				local root = randomPlayerRoot()
				local enemy = EnemyService.SpawnTemporary("Intercom", if root then Config.getFloor(root.Position.Y) else 1, def.IntercomSeconds)
				if not enemy then
					return false
				end
				enemy.Def = table.clone(enemy.Def)
				enemy.Def.Interval = def.IntercomInterval
				enemy.NextAnnounce = os.clock() + 3
				table.insert(intercoms, enemy)
				say("Nuevas instrucciones por megafonía. Obedezcan.")
				return true
			end,
		}
		local order = { "Lights", "Shutters", "Intercom" }

		task.spawn(function()
			local nextAction = os.clock() + def.ActionSeconds * 0.5
			while not ctx.Ended and not ctx.Defeated do
				task.wait(0.5)
				local now = os.clock()
				-- Cuenta atras del reinicio: si no estan todos, vuelve a encenderlos
				if windowEndsAt then
					if now >= windowEndsAt then
						windowEndsAt = nil
						restartedCount = 0
						for _, server in servers do
							if server.Restarted then
								server.Restarted = false
								setLed(server.Led, false)
								offer(server)
							end
						end
						say("Reinicio incompleto. Sistemas restaurados.")
					end
					updateProgress()
				end
				if now >= nextAction then
					nextAction = now + def.ActionSeconds
					-- Una accion al azar (si no se puede, la siguiente)
					local start = math.random(1, #order)
					for k = 0, #order - 1 do
						local name = order[(start + k - 1) % #order + 1]
						if actions[name]() then
							break
						end
					end
				end
			end
		end)

		return function()
			spottedConn.Disconnect()
			SecurityCamera.ReportMessage = nil
			for _, server in servers do
				if server.Mission then
					server.Mission.Cancel()
				end
				server.Led:Destroy()
				if server.Built then
					server.Spot:Destroy()
				end
			end
			for zone in darkZones do
				LightService.SetReason(zone, LIGHT_REASON, false)
			end
			darkZones = {}
			for reopen in sealed do
				reopen()
			end
			sealed = {}
			for _, enemy in intercoms do
				EnemyService.RemoveEnemy(enemy)
			end
		end
	end,
}
