-- Tienda abierta: la persiana de una tienda baja de golpe y vuelve a subir: dentro hay
-- bolsas de billetes (cada una para quien la coge). Pero la tienda tiene alarma: la
-- primera vez que alguien entra, suena y atrae a los enemigos un rato. El botin
-- desaparece al terminar el evento.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local Server = script.Parent.Parent
local LightService = require(Server.LightService)
local DefenseService = require(Server.DefenseService)
local RunState = require(Server.RunState)
local SfxService = require(Server.SfxService)
local MissionsCommon = require(Server.Missions.Common)
local EventUtil = require(script.Parent.EventUtil)

local ALARM_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local BAG = Color3.fromRGB(70, 110, 60)

local function buildBag(point: Vector3, value: number): Part
	local bag = Instance.new("Part")
	bag.Name = "CashBag"
	bag.Shape = Enum.PartType.Ball
	bag.Size = Vector3.new(1.4, 1.4, 1.4)
	bag.CFrame = CFrame.new(point + Vector3.new(0, 0.7, 0))
	bag.Color = BAG
	bag.Material = Enum.Material.Fabric
	bag.Anchored = true
	bag.CanCollide = false
	bag.CanTouch = false
	bag.Parent = MissionsCommon.getPropsFolder()
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(60, 30)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 1.3, 0)
	tag.MaxDistance = 40
	tag.LightInfluence = 0
	tag.Parent = bag
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(120, 230, 120)
	label.TextStrokeTransparency = 0.3
	label.Text = Util.formatMoney(value)
	label.Parent = tag
	return bag
end

return {
	CanStart = function(ctx)
		return #EventUtil.getStores(ctx.Floor) > 0
	end,
	Start = function(ctx)
		local def = ctx.Def
		-- Una tienda sin nadie dentro, mejor a media distancia de los jugadores
		local best, bestScore = nil, math.huge
		for _, store in EventUtil.getStores(ctx.Floor) do
			local d = EventUtil.nearestPlayerDistance(store.Shutter.Position)
			local occupied = false
			for _, player in EventUtil.alivePlayers() do
				local root = EventUtil.rootOf(player)
				if root and LightService.GetZoneAt(root.Position) == store.Zone then
					occupied = true
				end
			end
			local score = math.abs(d - 50) + math.random() * 30 + (if occupied then 1000 else 0)
			if score < bestScore then
				best, bestScore = store, score
			end
		end
		if not best then
			ctx.Finish()
			return nil
		end
		local zone = best.Zone

		-- La persiana baja de golpe y sube despacio: "se abre"
		local reopen = EventUtil.sealShutter(best, 0.15)
		task.delay(0.8, reopen)

		-- Botin
		local bags = {}
		for _ = 1, def.Bags do
			local point = EventUtil.randomPointInZone(zone)
			if point then
				local value = math.random(def.BagValue[1], def.BagValue[2]) + def.BagValuePerNight * (ctx.Night - 1)
				local bag = buildBag(point, value)
				table.insert(bags, bag)
				local prompt = MissionsCommon.makePrompt(bag, "Coger", "Bolsa de billetes (" .. Util.formatMoney(value) .. ")", 0.4)
				prompt.Triggered:Connect(function(player: Player)
					if ctx.Ended or player:GetAttribute("Alive") ~= true or not bag.Parent then
						return
					end
					bag:Destroy()
					RunState.AddCash(player, value)
					SfxService.PlayFor(player, "Pickup")
					Remotes.event("Notify"):FireClient(player, string.format("+%s del botín de %s.", Util.formatMoney(value), zone), "good")
				end)
			end
		end
		Remotes.event("Notify"):FireAllClients(string.format("La tienda %s se abrió con botín dentro...", zone), "info")

		-- Alarma: la primera vez que alguien entra
		local alarmPart = nil
		task.spawn(function()
			while not ctx.Ended do
				for _, player in EventUtil.alivePlayers() do
					local root = EventUtil.rootOf(player)
					if root and LightService.GetZoneAt(root.Position) == zone then
						local center = LightService.GetZoneCenter(zone) or root.Position
						DefenseService.AddLure(center, def.LureSeconds, def.LureRadius)
						alarmPart = Instance.new("Part")
						alarmPart.Name = "StoreAlarm"
						alarmPart.Size = Vector3.new(0.5, 0.5, 0.5)
						alarmPart.CFrame = CFrame.new(root.Position + Vector3.new(0, 6, 0))
						alarmPart.Anchored = true
						alarmPart.CanCollide = false
						alarmPart.CanQuery = false
						alarmPart.Transparency = 1
						alarmPart.Parent = MissionsCommon.getPropsFolder()
						local light = Instance.new("PointLight")
						light.Color = Color3.fromRGB(255, 40, 30)
						light.Range = 30
						light.Brightness = 3
						light.Parent = alarmPart
						local sound = Instance.new("Sound")
						sound.SoundId = ALARM_SOUND
						sound.Looped = true
						sound.Volume = 0.9
						sound.PlaybackSpeed = 2
						sound.RollOffMaxDistance = 120
						sound.Parent = alarmPart
						sound:Play()
						Remotes.event("Notify"):FireAllClients(
							string.format("¡Saltó la alarma de %s! Los enemigos van hacia allí.", zone),
							"bad"
						)
						-- Parpadeo rojo mientras dura el senuelo
						local untilAt = os.clock() + def.LureSeconds
						while os.clock() < untilAt and alarmPart.Parent do
							light.Enabled = not light.Enabled
							task.wait(0.25)
						end
						if alarmPart.Parent then
							alarmPart:Destroy()
						end
						return
					end
				end
				task.wait(0.3)
			end
		end)

		return function()
			for _, bag in bags do
				bag:Destroy()
			end
			if alarmPart then
				alarmPart:Destroy()
			end
		end
	end,
}
