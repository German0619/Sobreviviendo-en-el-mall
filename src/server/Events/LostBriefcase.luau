-- Maletin perdido: un maletin con billetes aparece en una zona oscura (peligrosa) de una
-- planta. Quien lo recoge lo lleva en la mano y va mas lento. Si muere, el maletin cae al
-- suelo y otro puede recogerlo. Tres finales (2026-11-25):
--   * Entregarlo en Objetos perdidos (tag LostAndFound; si no hay, en el mostrador de la
--     tienda o la entrada): +Reward para quien lo entrega.
--   * Quedarselo (prompt "Quedármelo" con [F] mientras lo llevas): +Reward y quedas maldito
--     tu solo (CurseService: doble de dano hasta caer o hasta el final de la noche).
--   * Se acaba el tiempo y nadie hizo nada: malditos TODOS los que siguen en pie.

local CollectionService = game:GetService("CollectionService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Util = require(Shared.Util)

local Server = script.Parent.Parent
local LightService = require(Server.LightService)
local MissionService = require(Server.MissionService)
local PlayerStats = require(Server.PlayerStats)
local RunState = require(Server.RunState)
local SfxService = require(Server.SfxService)
local CurseService = require(Server.CurseService)
local MissionsCommon = require(Server.Missions.Common)
local EventUtil = require(script.Parent.EventUtil)

local LEATHER = Color3.fromRGB(70, 45, 30)

local function findDesk(): BasePart?
	for _, tagName in { Tags.LostAndFound, Tags.ShopCounter, Tags.PlayerSpawn } do
		for _, inst in CollectionService:GetTagged(tagName) do
			if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
				return inst
			end
		end
	end
	return nil
end

local function buildBriefcase(): BasePart
	local case = Instance.new("Part")
	case.Name = "Briefcase"
	case.Size = Vector3.new(1.8, 1.3, 0.5)
	case.Color = LEATHER
	case.Material = Enum.Material.Leather
	case.Anchored = true
	case.CanCollide = false
	case.CanQuery = false
	case.CanTouch = false
	case.Massless = true
	for _, x in { -0.55, 0.55 } do
		local clasp = Instance.new("Part")
		clasp.Name = "Clasp"
		clasp.Size = Vector3.new(0.2, 0.15, 0.55)
		clasp.Color = Color3.fromRGB(230, 190, 70)
		clasp.Material = Enum.Material.Neon -- brilla un poco: se ve en la oscuridad
		clasp.CanCollide = false
		clasp.CanQuery = false
		clasp.Massless = true
		clasp.CFrame = case.CFrame * CFrame.new(x, 0.45, 0)
		clasp.Parent = case
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = case
		weld.Part1 = clasp
		weld.Parent = clasp
	end
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.7, 0.25, 0.2)
	handle.Color = Color3.fromRGB(30, 25, 20)
	handle.CanCollide = false
	handle.CanQuery = false
	handle.Massless = true
	handle.CFrame = case.CFrame * CFrame.new(0, 0.75, 0)
	handle.Parent = case
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = case
	weld.Part1 = handle
	weld.Parent = handle
	return case
end

return {
	CanStart = function(ctx)
		return findDesk() ~= nil and EventUtil.pointOnFloor(ctx.Floor, 15, math.huge) ~= nil
	end,
	Start = function(ctx)
		local def = ctx.Def
		local desk = findDesk()
		-- Zona peligrosa: una de las oscuras de esa planta (o cualquiera lejos de todos)
		local point = EventUtil.pointOnFloor(ctx.Floor, 15, math.huge, function(zone)
			return LightService.IsAmbientDark(zone)
		end) or EventUtil.pointOnFloor(ctx.Floor, 40, 140)
		if not desk or not point then
			ctx.Finish()
			return nil
		end
		local reward = def.Reward + def.RewardPerNight * (ctx.Night - 1)
		local deadline = os.clock() + def.MaxSeconds
		local function timeLeft(): number
			return math.max(5, deadline - os.clock())
		end

		local case = buildBriefcase()
		local carrier: Player? = nil
		local weld: WeldConstraint? = nil
		local removeSlow: (() -> ())? = nil
		local diedConn: RBXScriptConnection? = nil
		local pickupMission, deliverMission = nil, nil
		local keepPrompt: ProximityPrompt? = nil
		local resolved = false -- entregado o alguien se lo quedo
		local offerPickup -- (definida abajo)

		local function release()
			if keepPrompt then
				keepPrompt:Destroy()
				keepPrompt = nil
			end
			if weld then
				weld:Destroy()
				weld = nil
			end
			if removeSlow then
				removeSlow()
				removeSlow = nil
			end
			if diedConn then
				diedConn:Disconnect()
				diedConn = nil
			end
			if carrier then
				carrier:SetAttribute("Carrying", nil)
			end
			carrier = nil
		end

		local function deliver(player: Player)
			resolved = true
			release()
			RunState.AddCash(player, reward)
			SfxService.PlayFor(player, "Pickup")
			Remotes.event("Notify"):FireAllClients(
				string.format("%s entregó el maletín perdido: +%s.", player.DisplayName, Util.formatMoney(reward)),
				"good"
			)
			ctx.Finish()
		end

		-- Quedarselo: el dinero para el y la maldicion tambien
		local function keep(player: Player)
			if resolved or player ~= carrier then
				return
			end
			resolved = true
			release()
			if deliverMission then
				deliverMission.Cancel()
				deliverMission = nil
			end
			RunState.AddCash(player, reward)
			SfxService.PlayFor(player, "Pickup")
			CurseService.Curse(player)
			Remotes.event("Notify"):FireClient(
				player,
				string.format("Te quedaste el maletín: +%s. Estás MALDITO: recibes el doble de daño hasta que caigas.", Util.formatMoney(reward)),
				"bad"
			)
			for _, other in game:GetService("Players"):GetPlayers() do
				if other ~= player then
					Remotes.event("Notify"):FireClient(other, string.format("%s se quedó el maletín y ahora está maldito.", player.DisplayName), "info")
				end
			end
			case:Destroy()
			ctx.Finish()
		end

		local function pickUp(player: Player)
			local character = player.Character
			local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not hand or not humanoid or humanoid.Health <= 0 then
				offerPickup(case.CFrame)
				return
			end
			carrier = player
			case.Anchored = false
			case.CFrame = (hand :: BasePart).CFrame * CFrame.new(0, -0.9, 0)
			weld = Instance.new("WeldConstraint")
			weld.Part0 = hand :: BasePart
			weld.Part1 = case
			weld.Parent = case
			player:SetAttribute("Carrying", "Maletín")
			removeSlow = PlayerStats.AddEffect(player, "Briefcase", { WalkSpeed = def.CarryWalkMultiplier })
			Remotes.event("Notify"):FireClient(
				player,
				string.format("Llevas el maletín (pesa). Entrégalo en Objetos perdidos, o quédatelo [F]: +%s pero quedarás maldito.", Util.formatMoney(reward)),
				"info"
			)
			-- Quedarselo: prompt en el propio maletin con otra tecla (la E es la de entregar)
			keepPrompt = MissionsCommon.makePrompt(case, "Quedármelo", string.format("Maletín (+%s, maldito)", Util.formatMoney(reward)), 2)
			keepPrompt.KeyboardKeyCode = Enum.KeyCode.F
			keepPrompt.GamepadKeyCode = Enum.KeyCode.ButtonY
			keepPrompt.MaxActivationDistance = 10
			keepPrompt.Triggered:Connect(function(p: Player)
				if p ~= carrier then
					Remotes.event("Notify"):FireClient(p, "Solo quien lleva el maletín puede quedárselo.", "info")
					return
				end
				keep(p)
			end)
			diedConn = humanoid.Died:Connect(function()
				-- Cae al suelo donde murio
				local at = case.Position
				release()
				if deliverMission then
					deliverMission.Cancel()
					deliverMission = nil
				end
				if not ctx.Ended then
					offerPickup(CFrame.new(at.X, at.Y - 1.5, at.Z))
				end
			end)
			deliverMission = MissionService.StartEventMission({
				DisplayName = "Entregar el maletín en Objetos perdidos",
				Spot = desk,
				ActionText = "Entregar",
				ObjectText = "Maletín",
				HoldSeconds = 1,
				TimeLimit = timeLeft(),
				Silent = true,
				CanTrigger = function(p: Player)
					return p == carrier, "Solo quien lleva el maletín puede entregarlo."
				end,
				OnComplete = deliver,
			})
		end

		function offerPickup(cf: CFrame)
			case.Anchored = true
			case.CFrame = cf
			case.Parent = MissionsCommon.getPropsFolder()
			pickupMission = MissionService.StartEventMission({
				DisplayName = "Recoger el maletín perdido",
				Spot = case,
				ActionText = "Recoger",
				ObjectText = "Maletín (" .. Util.formatMoney(reward) .. ")",
				HoldSeconds = 0.5,
				TimeLimit = timeLeft(),
				Silent = true,
				CanTrigger = function(p: Player)
					return p:GetAttribute("Carrying") == nil, "Ya llevas algo: entrégalo primero."
				end,
				OnComplete = pickUp,
			})
		end

		offerPickup(CFrame.new(point + Vector3.new(0, 0.7, 0)))
		ctx.SetEndsAt(def.MaxSeconds)
		task.delay(def.MaxSeconds, function()
			if ctx.Ended then
				return -- (la noche termino antes)
			end
			if not resolved then
				-- Nadie lo entrego ni se lo quedo: malditos todos los que siguen en pie
				resolved = true
				local cursed = 0
				for _, player in game:GetService("Players"):GetPlayers() do
					if player:GetAttribute("Alive") == true then
						CurseService.Curse(player)
						cursed += 1
					end
				end
				if cursed > 0 then
					Remotes.event("Notify"):FireAllClients(
						"Nadie entregó el maletín... Están todos MALDITOS: reciben el doble de daño hasta que caigan.",
						"bad"
					)
				end
			end
			ctx.Finish()
		end)

		return function()
			for _, mission in { pickupMission, deliverMission } do
				if mission then
					mission.Cancel()
				end
			end
			release()
			case:Destroy()
		end
	end,
}
