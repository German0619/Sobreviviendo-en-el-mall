-- Mision: Sacar la basura.
-- Recoge la bolsa y llevala al contenedor (parte con tag TrashDropoff).
-- Si mueres o te vas con la bolsa, vuelve a su lugar.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Remotes = require(Shared.Remotes)
local Common = require(script.Parent.Common)

local TakeOutTrash = {}

local carrying = {} -- [Player] = { Mission, Bag, Prompt, Complete, Weld, DiedConn }
local dropoffPrompts = {} -- [BasePart] = ProximityPrompt

local function returnBag(player: Player)
	local entry = carrying[player]
	if not entry then
		return
	end
	carrying[player] = nil
	player:SetAttribute("CarryingTrash", nil)
	if entry.DiedConn then
		entry.DiedConn:Disconnect()
	end
	if entry.Weld then
		entry.Weld:Destroy()
	end
	if entry.Bag.Parent then
		entry.Bag.Anchored = true
		entry.Bag.CFrame = entry.HomeCFrame
		entry.Prompt.Enabled = true
	end
end

local function onDropoff(player: Player)
	local entry = carrying[player]
	if not entry then
		Remotes.event("Notify"):FireClient(player, "No llevas ninguna bolsa de basura.", "info")
		return
	end
	-- complete() devuelve false si no se acepta (p. ej. la noche termino)
	if entry.Complete(player) then
		carrying[player] = nil
		player:SetAttribute("CarryingTrash", nil)
	end
end

local function ensureDropoffPrompts()
	for _, part in CollectionService:GetTagged(Tags.TrashDropoff) do
		if part:IsA("BasePart") and not dropoffPrompts[part] then
			local prompt = Common.makePrompt(part, "Tirar basura", "Contenedor", Config.Missions.TakeOutTrash.Duration)
			prompt.Triggered:Connect(onDropoff)
			dropoffPrompts[part] = prompt
		end
	end
end

function TakeOutTrash.CanStart(): boolean
	return #CollectionService:GetTagged(Tags.TrashDropoff) > 0
end

function TakeOutTrash.Begin(mission, complete)
	ensureDropoffPrompts()

	local floor = Common.floorPosition(mission.Spot)
	local homeCFrame = CFrame.new(floor + Vector3.new(0, 1.2, 0))

	local bag = Instance.new("Part")
	bag.Name = "TrashBag"
	bag.Size = Vector3.new(1.8, 2.4, 1.8)
	bag.CFrame = homeCFrame
	bag.Anchored = true
	bag.CanCollide = false
	bag.CanQuery = false
	bag.Massless = true
	bag.Material = Enum.Material.Plastic
	bag.Color = Color3.fromRGB(25, 25, 28)
	bag.Parent = Common.getPropsFolder()
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = bag

	local prompt = Common.makePrompt(bag, "Recoger", "Bolsa de basura", 0.5)

	local function ownerEntry()
		for player, entry in carrying do
			if entry.Mission == mission then
				return player, entry
			end
		end
		return nil, nil
	end

	prompt.Triggered:Connect(function(player: Player)
		if carrying[player] then
			Remotes.event("Notify"):FireClient(player, "Ya llevas una bolsa.", "info")
			return
		end
		if ownerEntry() then
			return
		end
		local character = player.Character
		local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not torso or not humanoid or humanoid.Health <= 0 then
			return
		end

		prompt.Enabled = false
		bag.Anchored = false
		bag.CFrame = torso.CFrame * CFrame.new(0, 0, 1.3)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = bag
		weld.Parent = bag

		carrying[player] = {
			Mission = mission,
			Bag = bag,
			Prompt = prompt,
			Complete = complete,
			Weld = weld,
			HomeCFrame = homeCFrame,
			DiedConn = humanoid.Died:Connect(function()
				returnBag(player)
			end),
		}
		player:SetAttribute("CarryingTrash", true)
		Remotes.event("Notify"):FireClient(player, "Lleva la bolsa al contenedor de la bodega.", "info")
	end)

	return {
		Marker = bag,
		Cleanup = function(_success: boolean)
			local player, entry = ownerEntry()
			if player and entry then
				carrying[player] = nil
				player:SetAttribute("CarryingTrash", nil)
				if entry.DiedConn then
					entry.DiedConn:Disconnect()
				end
			end
			bag:Destroy()
		end,
	}
end

Players.PlayerRemoving:Connect(returnBag)

return TakeOutTrash
