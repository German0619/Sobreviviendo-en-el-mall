-- Piso aislado: unas rejas bloquean el extremo de cada escalera (tag FloorConnector) en
-- una planta, que queda cortada. Solo se bloquea el extremo de esa planta: quien este a
-- mitad de escalera puede bajar o subir por el otro lado. Desbloquear una reja (mision de
-- evento, se puede hacer desde los dos lados) las abre todas. Si caduca, sale otra.

local CollectionService = game:GetService("CollectionService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)

local Server = script.Parent.Parent
local MissionService = require(Server.MissionService)
local MissionsCommon = require(Server.Missions.Common)
local EventUtil = require(script.Parent.EventUtil)

local BAR_COLOR = Color3.fromRGB(150, 30, 30)

local function buildBarrier(position: Vector3, inward: Vector3, width: number): BasePart
	local barrier = Instance.new("Part")
	barrier.Name = "FloorBarrier"
	barrier.Size = Vector3.new(width + 1.6, 8, 0.5)
	barrier.CFrame = CFrame.lookAt(position + Vector3.new(0, 4, 0), position + Vector3.new(0, 4, 0) + inward)
	barrier.Anchored = true
	barrier.CanCollide = true
	barrier.Material = Enum.Material.DiamondPlate
	barrier.Color = BAR_COLOR
	barrier.Transparency = 0.15
	barrier.Parent = MissionsCommon.getPropsFolder()
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0.3
		gui.CanvasSize = Vector2.new(300, 300)
		gui.Parent = barrier
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0.3, 0)
		label.Position = UDim2.fromScale(0, 0.35)
		label.BackgroundColor3 = Color3.fromRGB(240, 200, 30)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(20, 20, 20)
		label.Text = "ACCESO BLOQUEADO"
		label.Parent = gui
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 60, 40)
	light.Range = 10
	light.Brightness = 1
	light.Parent = barrier
	return barrier
end

return {
	CanStart = function(_ctx)
		return #CollectionService:GetTagged(Tags.FloorConnector) > 0
	end,
	Start = function(ctx)
		local def = ctx.Def
		local floor = ctx.Floor or 1
		local barriers = {}
		for _, connector in CollectionService:GetTagged(Tags.FloorConnector) do
			local low, high, width = connector:GetAttribute("Low"), connector:GetAttribute("High"), connector:GetAttribute("Width")
			if typeof(low) == "Vector3" and typeof(high) == "Vector3" and type(width) == "number" then
				local here = if floor == 1 then low else high
				local there = if floor == 1 then high else low
				local inward = Vector3.new(there.X - here.X, 0, there.Z - here.Z).Unit
				table.insert(barriers, buildBarrier(here - inward * 1.2, inward, width))
			end
		end
		if #barriers == 0 then
			ctx.Finish()
			return nil
		end

		-- La mision, en la reja mas cercana a un jugador
		local function closestBarrier(): BasePart
			local best, bestDist = barriers[1], math.huge
			for _, barrier in barriers do
				local d = EventUtil.nearestPlayerDistance(barrier.Position)
				if d < bestDist then
					best, bestDist = barrier, d
				end
			end
			return best
		end

		local mission = nil
		local function offer()
			mission = MissionService.StartEventMission({
				DisplayName = "Desbloquear el acceso a la otra planta",
				Spot = closestBarrier(),
				ActionText = "Desbloquear",
				ObjectText = "Reja",
				HoldSeconds = def.HoldSeconds,
				TimeLimit = def.MissionSeconds,
				RepairTask = true,
				OnComplete = function()
					Remotes.event("Notify"):FireAllClients("Las rejas se abren: las plantas vuelven a estar conectadas.", "good")
					ctx.Finish()
				end,
				OnExpire = function()
					if not ctx.Ended then
						offer()
					end
				end,
			})
		end
		offer()

		ctx.SetEndsAt(def.MaxSeconds)
		task.delay(def.MaxSeconds, ctx.Finish)

		return function()
			if mission then
				mission.Cancel()
			end
			for _, barrier in barriers do
				barrier:Destroy()
			end
		end
	end,
}
