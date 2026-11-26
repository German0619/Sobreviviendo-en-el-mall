-- Fabrica de misiones "recoger un objeto y llevarlo" (basura, cajas, objetos perdidos).
--
-- * El objeto aparece en el MissionSpot (o donde diga PickupCFrame).
-- * Se entrega en cualquier parte con DropoffTag, o en el propio MissionSpot
--   (DropoffAtSpot = true).
-- * Solo se lleva un objeto a la vez (entre todas las misiones de este tipo).
-- * Si mueres o te vas, el objeto vuelve a su sitio.
-- * Mientras lo llevas, el destino muestra un marcador.
--
--   Carry.new({
--     Type = "TakeOutTrash",
--     BuildItem = function() -> BasePart,
--     PickupCFrame = function(mission) -> CFrame?,   -- por defecto, sobre el MissionSpot
--     DropoffTag = Tags.TrashDropoff,  o  DropoffAtSpot = true,
--     PickupText = "Bolsa de basura",
--     DropoffAction = "Tirar basura", DropoffObject = "Contenedor",
--     CarryHint = "Lleva la bolsa al contenedor de la bodega.",
--     CanStart = function(spot, zone)?,
--   })

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Common = require(script.Parent.Common)

local Carry = {}

-- [Player] = entrada del objeto que lleva (compartido por todas las misiones Carry)
local carrying = {}

local function notify(player: Player, message: string)
	Remotes.event("Notify"):FireClient(player, message, "info")
end

-- Suelta el objeto: vuelve a su sitio (o se destruye si la mision ya termino).
local function release(player: Player, returnHome: boolean)
	local entry = carrying[player]
	if not entry then
		return
	end
	carrying[player] = nil
	entry.Mission.Carried = nil -- (MissionService no retira una tarea mientras alguien la lleva)
	player:SetAttribute("Carrying", nil)
	if entry.DiedConn then
		entry.DiedConn:Disconnect()
	end
	if entry.Weld then
		entry.Weld:Destroy()
		entry.Weld = nil
	end
	if entry.DestMarker then
		entry.DestMarker:Destroy()
		entry.DestMarker = nil
	end
	if returnHome and entry.Item.Parent then
		entry.Item.Anchored = true
		entry.Item.CFrame = entry.HomeCFrame
		entry.Prompt.Enabled = true
	end
end

local function nearestTagged(tag: string, position: Vector3): BasePart?
	local best, bestDist = nil, math.huge
	for _, part in CollectionService:GetTagged(tag) do
		if part:IsA("BasePart") then
			local d = (part.Position - position).Magnitude
			if d < bestDist then
				best, bestDist = part, d
			end
		end
	end
	return best
end

function Carry.new(opts)
	local dropoffPrompts: { [BasePart]: ProximityPrompt } = {}
	local module = {}

	local function tryDeliver(player: Player, spot: BasePart?)
		local entry = carrying[player]
		if not entry or entry.Type ~= opts.Type or (spot and entry.Mission.Spot ~= spot) then
			notify(player, "No llevas lo que hace falta aquí.")
			return
		end
		-- complete() devuelve false si no se acepta (p. ej. la noche termino)
		if entry.Complete(player) then
			release(player, false)
		end
	end

	local function ensureDropoffPrompts()
		if not opts.DropoffTag then
			return
		end
		for _, part in CollectionService:GetTagged(opts.DropoffTag) do
			if part:IsA("BasePart") and not dropoffPrompts[part] then
				local prompt = Common.makePrompt(part, opts.DropoffAction, opts.DropoffObject, Config.Missions[opts.Type].Duration)
				prompt.Triggered:Connect(function(player)
					tryDeliver(player, nil)
				end)
				dropoffPrompts[part] = prompt
			end
		end
	end

	function module.CanStart(spot: BasePart, zone: string): boolean
		if opts.DropoffTag and #CollectionService:GetTagged(opts.DropoffTag) == 0 then
			return false
		end
		if opts.CanStart then
			return opts.CanStart(spot, zone)
		end
		return true
	end

	function module.Begin(mission, complete)
		ensureDropoffPrompts()

		local homeCFrame = (opts.PickupCFrame and opts.PickupCFrame(mission))
			or CFrame.new(Common.floorPosition(mission.Spot) + Vector3.new(0, 1.2, 0))
		local item = opts.BuildItem()
		item.Anchored = true
		item.CanCollide = false
		item.CanQuery = false
		item.Massless = true
		item.CFrame = homeCFrame
		item.Parent = Common.getPropsFolder()

		local prompt = Common.makePrompt(item, "Recoger", opts.PickupText, 0.5)

		-- Entrega en el propio MissionSpot (p. ej. el estante de una tienda)
		local spotPrompt: ProximityPrompt? = nil
		if opts.DropoffAtSpot then
			spotPrompt = Common.makePrompt(mission.Spot, opts.DropoffAction, opts.DropoffObject, Config.Missions[opts.Type].Duration)
			spotPrompt.Triggered:Connect(function(player)
				tryDeliver(player, mission.Spot)
			end)
		end

		local function holder(): Player?
			for player, entry in carrying do
				if entry.Mission == mission then
					return player
				end
			end
			return nil
		end

		prompt.Triggered:Connect(function(player: Player)
			if carrying[player] then
				notify(player, "Ya llevas algo. Entrégalo primero.")
				return
			end
			if holder() or player:GetAttribute("Alive") ~= true then
				return
			end
			local character = player.Character
			local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not torso or not humanoid or humanoid.Health <= 0 then
				return
			end

			prompt.Enabled = false
			item.Anchored = false
			item.CFrame = (torso :: BasePart).CFrame * CFrame.new(0, 0, 1.3) -- a la espalda (no tapa la vista)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = torso :: BasePart
			weld.Part1 = item
			weld.Parent = item

			-- Marcador en el destino mientras lo lleva
			local dest = if opts.DropoffAtSpot then mission.Spot else nearestTagged(opts.DropoffTag, item.Position)
			local destMarker = if dest then Common.makeMarker(dest, "▼", Color3.fromRGB(120, 220, 140)) else nil

			carrying[player] = {
				Type = opts.Type,
				Mission = mission,
				Item = item,
				Prompt = prompt,
				Complete = complete,
				Weld = weld,
				HomeCFrame = homeCFrame,
				DestMarker = destMarker,
				DiedConn = humanoid.Died:Connect(function()
					release(player, true)
				end),
			}
			mission.Carried = true
			player:SetAttribute("Carrying", opts.PickupText)
			if opts.CarryHint then
				notify(player, opts.CarryHint)
			end
		end)

		return {
			Marker = item,
			Cleanup = function(_success: boolean)
				local player = holder()
				if player then
					release(player, false)
				end
				if spotPrompt then
					spotPrompt:Destroy()
				end
				item:Destroy()
			end,
		}
	end

	return module
end

Players.PlayerRemoving:Connect(function(player)
	release(player, true)
end)

return Carry
