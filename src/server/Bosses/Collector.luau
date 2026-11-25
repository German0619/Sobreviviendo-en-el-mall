-- Jefe: El Coleccionista (noche 15).
--
-- * Su cuerpo es el enemigo "Collector" (src/enemies/Collector): persigue a quien ve.
-- * Conversiones: cuando alguien cae, sobre su cuerpo sale una cuenta atras de
--   TransformSeconds. Si no lo reviven a tiempo, el cuerpo se convierte en un maniqui
--   enemigo con su nombre (enemigo "Converted"), ya no se le puede revivir esta noche, y
--   el Coleccionista se vuelve mas rapido.
-- * Se le vence con Offerings ofrendas: objetos perdidos repartidos por el mall, cada uno
--   de una tienda. Hay que recogerlo (mision de evento) y llevarlo al pedestal de su
--   tienda (otra mision, solo quien lo lleva). Con todas, se lleva su coleccion y se va
--   (y los maniquies convertidos desaparecen).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Server = script.Parent.Parent
local EnemyService = require(Server.EnemyService)
local MissionService = require(Server.MissionService)
local ReviveService = require(Server.ReviveService)
local MissionsCommon = require(Server.Missions.Common)
local EventUtil = require(Server.Events.EventUtil)
local EnemyCommon = require(ServerScriptService:WaitForChild("Enemies"):WaitForChild("Common"))
local Converted = require(ServerScriptService:WaitForChild("Enemies"):WaitForChild("Converted"))

local GOLD = Color3.fromRGB(255, 210, 120)

local function notifyAll(text: string, kind: string)
	Remotes.event("Notify"):FireAllClients(text, kind)
end

local function buildItem(storeName: string): BasePart
	local item = Instance.new("Part")
	item.Name = "LostOffering"
	item.Size = Vector3.new(1.2, 1.2, 1.2)
	item.Material = Enum.Material.SmoothPlastic
	item.Color = Color3.fromRGB(200, 60, 90)
	item.CanCollide = false
	item.CanQuery = false
	item.CanTouch = false
	item.Massless = true
	item.Anchored = true
	local ribbon = Instance.new("Part")
	ribbon.Name = "Ribbon"
	ribbon.Size = Vector3.new(1.25, 0.2, 1.25)
	ribbon.Color = GOLD
	ribbon.Material = Enum.Material.Neon
	ribbon.CanCollide = false
	ribbon.CanQuery = false
	ribbon.Massless = true
	ribbon.CFrame = item.CFrame
	ribbon.Parent = item
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = item
	weld.Part1 = ribbon
	weld.Parent = ribbon
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(180, 24)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 1.4, 0)
	tag.MaxDistance = 45
	tag.LightInfluence = 0
	tag.Parent = item
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = GOLD
	label.TextStrokeTransparency = 0.3
	label.Text = "Objeto de " .. storeName
	label.Parent = tag
	return item
end

local function buildPedestal(point: Vector3, storeName: string): BasePart
	local pedestal = Instance.new("Part")
	pedestal.Name = "OfferingPedestal"
	pedestal.Shape = Enum.PartType.Cylinder
	pedestal.Size = Vector3.new(2.4, 2.2, 2.2)
	pedestal.CFrame = CFrame.new(point + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pedestal.Anchored = true
	pedestal.Material = Enum.Material.Marble
	pedestal.Color = Color3.fromRGB(230, 225, 215)
	pedestal.Parent = MissionsCommon.getPropsFolder()
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 8
	light.Brightness = 0.8
	light.Parent = pedestal
	pedestal:SetAttribute("Store", storeName)
	return pedestal
end

return {
	Start = function(ctx)
		local def = ctx.Def
		local collector = EnemyService.SpawnTemporary("Collector", 1, 3600)
		if not collector then
			warn("[Boss Collector] No se pudo crear al Coleccionista")
			ctx.Defeat()
			return nil
		end
		collector.BossSpeed = ctx.SpeedBoost -- (desde la noche 25)

		local converted = {} -- enemigos "Converted"
		local convertedCount = 0
		local delivered = 0
		local offerings = {} -- estado de cada ofrenda
		local total = 0

		local function updateProgress()
			ctx.SetProgress(string.format("Ofrendas %d/%d  ·  Convertidos: %d", delivered, total, convertedCount))
		end

		local function defeat()
			notifyAll("El Coleccionista recoge su colección y se va. Los maniquíes vuelven a quedarse quietos.", "good")
			for _, enemy in converted do
				EnemyService.RemoveEnemy(enemy)
			end
			EnemyService.RemoveEnemy(collector)
			ctx.Defeat()
		end

		--------------------------------------------------------------
		-- Ofrendas
		--------------------------------------------------------------
		local function release(o)
			if o.Weld then
				o.Weld:Destroy()
				o.Weld = nil
			end
			if o.DiedConn then
				o.DiedConn:Disconnect()
				o.DiedConn = nil
			end
			if o.Carrier then
				o.Carrier:SetAttribute("Carrying", nil)
			end
			o.Carrier = nil
		end

		local offerPickup -- (definida abajo)

		local function pickUp(o, player: Player)
			local character = player.Character
			local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not hand or not humanoid or humanoid.Health <= 0 then
				offerPickup(o, o.Item.CFrame)
				return
			end
			o.Carrier = player
			o.Item.Anchored = false
			o.Item.CFrame = (hand :: BasePart).CFrame * CFrame.new(0, -0.9, 0)
			o.Weld = Instance.new("WeldConstraint")
			o.Weld.Part0 = hand :: BasePart
			o.Weld.Part1 = o.Item
			o.Weld.Parent = o.Item
			player:SetAttribute("Carrying", "Ofrenda")
			Remotes.event("Notify"):FireClient(player, "Llévalo al pedestal de " .. o.Store .. ".", "info")
			o.DiedConn = humanoid.Died:Connect(function()
				local at = o.Item.Position
				release(o)
				if o.Deliver then
					o.Deliver.Cancel()
					o.Deliver = nil
				end
				if not ctx.Ended then
					offerPickup(o, CFrame.new(at.X, at.Y - 1.5, at.Z))
				end
			end)
			o.Deliver = MissionService.StartEventMission({
				DisplayName = "Devolver el objeto a " .. o.Store,
				Spot = o.Pedestal,
				ActionText = "Devolver",
				ObjectText = "Ofrenda",
				HoldSeconds = def.DeliverHold,
				TimeLimit = 900,
				Silent = true,
				CanTrigger = function(p: Player)
					return p == o.Carrier, "Solo quien lleva el objeto puede devolverlo."
				end,
				OnComplete = function(p: Player)
					release(o)
					o.Deliver = nil
					o.Done = true
					-- Queda sobre el pedestal
					o.Item.Anchored = true
					o.Item.CFrame = o.Pedestal.CFrame * CFrame.Angles(0, 0, math.rad(-90)) * CFrame.new(0, 1.8, 0)
					delivered += 1
					updateProgress()
					if delivered >= total then
						defeat()
					else
						notifyAll(string.format("%s devolvió una ofrenda. Quedan %d.", p.DisplayName, total - delivered), "good")
					end
				end,
			})
		end

		function offerPickup(o, cf: CFrame)
			o.Item.Anchored = true
			o.Item.CFrame = cf
			o.Item.Parent = MissionsCommon.getPropsFolder()
			o.Pickup = MissionService.StartEventMission({
				DisplayName = "Recoger el objeto perdido de " .. o.Store,
				Spot = o.Item,
				ActionText = "Recoger",
				ObjectText = "Objeto de " .. o.Store,
				HoldSeconds = def.PickupHold,
				TimeLimit = 900,
				Silent = true,
				CanTrigger = function(p: Player)
					return p:GetAttribute("Carrying") == nil, "Ya llevas algo: entrégalo primero."
				end,
				OnComplete = function(p: Player)
					o.Pickup = nil
					pickUp(o, p)
				end,
				OnExpire = function()
					if not ctx.Ended and not o.Done and not o.Carrier then
						offerPickup(o, o.Item.CFrame)
					end
				end,
			})
		end

		-- Tiendas distintas; el objeto aparece en otra zona, lejos de los jugadores
		local stores = EventUtil.getStores(nil)
		for i = #stores, 2, -1 do
			local j = math.random(1, i)
			stores[i], stores[j] = stores[j], stores[i]
		end
		for i = 1, math.min(def.Offerings, #stores) do
			local store = stores[i]
			local pedestalPoint = EventUtil.randomPointInZone(store.Zone)
			local itemPoint = EventUtil.pointOnFloor(nil, def.OfferingMinDistance, math.huge, function(zone)
				return zone ~= store.Zone
			end)
			if pedestalPoint and itemPoint then
				local o = {
					Store = store.Zone,
					Item = buildItem(store.Zone),
					Pedestal = buildPedestal(pedestalPoint, store.Zone),
					Done = false,
				}
				table.insert(offerings, o)
				total += 1
				offerPickup(o, CFrame.new(itemPoint + Vector3.new(0, 0.8, 0)))
			end
		end
		updateProgress()
		if total == 0 then
			defeat()
			return nil
		end

		--------------------------------------------------------------
		-- Conversiones: los caidos se vuelven maniquies si no los reviven a tiempo
		--------------------------------------------------------------
		local downedConn = ReviveService.Downed:Connect(function(player: Player, root: BasePart)
			if ctx.Ended or ctx.Defeated then
				return
			end
			local countdown = Instance.new("BillboardGui")
			countdown.Name = "CollectorCountdown"
			countdown.Size = UDim2.fromOffset(220, 30)
			countdown.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
			countdown.AlwaysOnTop = true
			countdown.MaxDistance = 150
			countdown.LightInfluence = 0
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamBold
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(255, 120, 120)
			label.TextStrokeTransparency = 0.3
			label.Parent = countdown
			countdown.Parent = root
			notifyAll(string.format("¡Revivan a %s antes de %d s o el Coleccionista lo convertirá en maniquí!", player.DisplayName, def.TransformSeconds), "bad")

			local endsAt = os.clock() + def.TransformSeconds
			while os.clock() < endsAt do
				if ctx.Ended or ctx.Defeated or not ReviveService.IsDowned(player) or not root.Parent then
					countdown:Destroy()
					return -- revivido (o se acabo la noche)
				end
				label.Text = string.format("Se convierte en maniquí: %ds", math.ceil(endsAt - os.clock()))
				task.wait(0.25)
			end
			countdown:Destroy()

			-- Convertido: el cuerpo desaparece y en su sitio se levanta un maniqui
			ReviveService.Forfeit(player)
			local position = root.Position
			local character = root.Parent
			if character then
				for _, d in character:GetDescendants() do
					if d:IsA("BasePart") or d:IsA("Decal") then
						d.Transparency = 1
					end
				end
			end
			local floorY = EnemyCommon.floorBelow(position, 10) or (position.Y - 3)
			local enemy = EnemyService.SpawnTemporary("Converted", Config.getFloor(floorY + 1), 3600, Vector3.new(position.X, floorY, position.Z))
			if enemy then
				Converted.SetName(enemy, player.DisplayName)
				table.insert(converted, enemy)
			end
			convertedCount += 1
			collector:SetConverted(convertedCount)
			updateProgress()
			notifyAll(string.format("%s se ha convertido en un maniquí del Coleccionista. Ahora es más rápido.", player.DisplayName), "bad")
		end)

		return function()
			downedConn.Disconnect()
			for _, o in offerings do
				for _, mission in { o.Pickup, o.Deliver } do
					if mission then
						mission.Cancel()
					end
				end
				release(o)
				o.Item:Destroy()
				o.Pedestal:Destroy()
			end
			for _, enemy in converted do
				EnemyService.RemoveEnemy(enemy)
			end
			EnemyService.RemoveEnemy(collector)
		end
	end,
}
