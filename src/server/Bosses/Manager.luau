-- Jefe: El Gerente (noche 10).
--
-- * Su cuerpo es el enemigo "Manager" (src/enemies/Manager): patrulla, marca y persigue.
-- * Tiene Radios radios repartidas por el mall (las dos plantas). Mientras le queden:
--     - cada CallSeconds pide refuerzos de nivel 1 y 2 por el walkie (tantos como radios);
--     - cada ShutterSeconds ordena cerrar las persianas de ShutterStores tiendas
--       (se abren solas a los ShutterCloseSeconds).
-- * Se le vence destruyendo las radios (misiones de evento). Sin radios se rinde y se va.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Server = script.Parent.Parent
local EnemyService = require(Server.EnemyService)
local LightService = require(Server.LightService)
local MissionService = require(Server.MissionService)
local MissionsCommon = require(Server.Missions.Common)
local EventUtil = require(Server.Events.EventUtil)

local function notifyAll(text: string, kind: string)
	Remotes.event("Notify"):FireAllClients(text, kind)
end

local function buildRadio(point: Vector3): BasePart
	local radio = Instance.new("Part")
	radio.Name = "ManagerRadio"
	radio.Size = Vector3.new(1.4, 1.8, 0.9)
	radio.CFrame = CFrame.new(point + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
	radio.Anchored = true
	radio.CanCollide = true
	radio.Material = Enum.Material.SmoothPlastic
	radio.Color = Color3.fromRGB(35, 35, 40)
	radio.Parent = MissionsCommon.getPropsFolder()
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = radio.CFrame * offset
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Parent = radio
		return p
	end
	piece("Antenna", Vector3.new(0.1, 2.2, 0.1), CFrame.new(0.5, 2, 0), Color3.fromRGB(60, 60, 65), Enum.Material.Metal)
	piece("Speaker", Vector3.new(1, 0.8, 0.05), CFrame.new(0, 0.2, -0.46), Color3.fromRGB(70, 70, 75), Enum.Material.DiamondPlate)
	local led = piece("Led", Vector3.new(0.2, 0.2, 0.2), CFrame.new(0.5, 3.15, 0), Color3.fromRGB(255, 40, 30), Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 40, 30)
	light.Range = 9
	light.Brightness = 1.2
	light.Parent = led
	-- Parpadeo: se la ve de lejos en la oscuridad
	task.spawn(function()
		while led.Parent do
			light.Enabled = not light.Enabled
			led.Transparency = if light.Enabled then 0 else 0.7
			task.wait(0.6)
		end
	end)
	return radio
end

local function sparks(position: Vector3)
	local fx = Instance.new("Part")
	fx.Size = Vector3.new(0.2, 0.2, 0.2)
	fx.CFrame = CFrame.new(position)
	fx.Anchored = true
	fx.CanCollide = false
	fx.CanQuery = false
	fx.Transparency = 1
	fx.Parent = MissionsCommon.getPropsFolder()
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 120, 40))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Rate = 0
	emitter.Parent = fx
	emitter:Emit(40)
	task.delay(1.5, function()
		fx:Destroy()
	end)
end

return {
	Start = function(ctx)
		local def = ctx.Def
		local enemy = EnemyService.SpawnTemporary("Manager", 1, 3600)
		if not enemy then
			warn("[Boss Manager] No se pudo crear al Gerente")
			ctx.Defeat()
			return nil
		end

		-- Radios repartidas: alternando plantas y en zonas distintas
		local radios = {} -- [radio] = mission
		local usedZones = {}
		local total = 0
		for i = 1, def.Radios do
			local floor = if i % 2 == 1 then 1 else 2
			local point = EventUtil.pointOnFloor(floor, def.RadioMinDistance, math.huge, function(zone)
				return not usedZones[zone]
			end) or EventUtil.pointOnFloor(nil, def.RadioMinDistance, math.huge)
			if point then
				local zone = LightService.GetZoneAt(point + Vector3.new(0, 3, 0)) or "?"
				usedZones[zone] = true
				local radio = buildRadio(point)
				radio:SetAttribute("Zone", zone)
				radios[radio] = false
				total += 1
			end
		end
		local left = total

		local function updateProgress()
			ctx.SetProgress(string.format("Radios destruidas %d/%d", total - left, total))
		end

		local function defeat()
			notifyAll("Sin radios, el Gerente se rinde y se va del mall.", "good")
			EnemyService.RemoveEnemy(enemy)
			ctx.Defeat()
		end

		local function offer(radio: BasePart)
			local zone = radio:GetAttribute("Zone") or "?"
			local mission
			mission = MissionService.StartEventMission({
				DisplayName = "Destruir la radio del Gerente (" .. zone .. ")",
				Spot = radio,
				ActionText = "Destruir",
				ObjectText = "Radio del Gerente",
				HoldSeconds = def.RadioHoldSeconds,
				TimeLimit = 900,
				Silent = true,
				OnComplete = function(player: Player)
					radios[radio] = nil
					sparks(radio.Position)
					radio:Destroy()
					left -= 1
					updateProgress()
					if left <= 0 then
						defeat()
					else
						notifyAll(string.format("%s destruyó una radio del Gerente. Quedan %d.", player.DisplayName, left), "good")
					end
				end,
				OnExpire = function()
					if not ctx.Ended and radio.Parent then
						offer(radio)
					end
				end,
			})
			radios[radio] = mission
		end
		for radio in radios do
			offer(radio)
		end
		updateProgress()
		if total == 0 then
			defeat() -- sin sitio para las radios: que la noche se pueda ganar
			return nil
		end

		-- Ordenes por el walkie: refuerzos y persianas
		local sealed = {} -- funciones para reabrir
		task.spawn(function()
			local nextCall = os.clock() + def.CallSeconds
			local nextShutters = os.clock() + def.ShutterSeconds * 0.6
			while not ctx.Ended and not ctx.Defeated do
				task.wait(1)
				local model = enemy.Model
				if ctx.Ended or ctx.Defeated or not model or not model.Parent then
					break
				end
				local now = os.clock()
				local floor = Config.getFloor(model:GetPivot().Position.Y)
				if now >= nextCall then
					nextCall = now + def.CallSeconds
					local types = EnemyService.GetTypesForTiers(def.ReinforcementTiers, def.ReinforcementExclude)
					if #types > 0 then
						enemy:Radio(2)
						for _ = 1, left do
							EnemyService.SpawnTemporary(types[math.random(1, #types)], floor, def.ReinforcementSeconds)
						end
						notifyAll(string.format("El Gerente pide refuerzos por el walkie (%d).", left), "bad")
					end
				end
				if now >= nextShutters then
					nextShutters = now + def.ShutterSeconds
					-- Las tiendas mas cercanas a los jugadores
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
					if #names > 0 then
						enemy:Radio(1.5)
						notifyAll("El Gerente ordena cerrar persianas: " .. table.concat(names, ", ") .. ".", "bad")
					end
				end
			end
		end)

		return function()
			for radio, mission in radios do
				if mission then
					mission.Cancel()
				end
				radio:Destroy()
			end
			for reopen in sealed do
				reopen()
			end
			sealed = {}
			EnemyService.RemoveEnemy(enemy)
		end
	end,
}
