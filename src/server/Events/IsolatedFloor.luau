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
local BAR_HEIGHT = 8 -- parte visible de la reja (con el cartel)
local BAR_MARGIN = 2 -- la reja sobresale esto por cada lado (tapa barandillas y pasamanos)
local SIDE_LEN = 12 -- largo (en planta) de las paredes laterales del tramo bloqueado

-- Pared invisible con colision (no la tocan los rayos: linterna, armas, vision). Impide
-- saltar la reja desde el pasamanos o colarse a la rampa por encima de la barandilla.
local function invisibleWall(name: string, size: Vector3, cf: CFrame): BasePart
	local wall = Instance.new("Part")
	wall.Name = name
	wall.Size = size
	wall.CFrame = cf
	wall.Anchored = true
	wall.CanCollide = true
	wall.CanQuery = false
	wall.CanTouch = false
	wall.CastShadow = false
	wall.Transparency = 1
	wall.Parent = MissionsCommon.getPropsFolder()
	return wall
end

local function buildBarrier(position: Vector3, inward: Vector3, width: number): BasePart
	local barrier = Instance.new("Part")
	barrier.Name = "FloorBarrier"
	barrier.Size = Vector3.new(width + BAR_MARGIN * 2, BAR_HEIGHT, 0.5)
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
		local blockers = {} -- paredes invisibles (se borran con las rejas)
		local ends = {}
		for _, connector in CollectionService:GetTagged(Tags.FloorConnector) do
			local low, high, width = connector:GetAttribute("Low"), connector:GetAttribute("High"), connector:GetAttribute("Width")
			if typeof(low) == "Vector3" and typeof(high) == "Vector3" and type(width) == "number" then
				local here = if floor == 1 then low else high
				local there = if floor == 1 then high else low
				local flat = Vector3.new(there.X - here.X, 0, there.Z - here.Z)
				table.insert(ends, {
					Here = here,
					Inward = flat.Unit,
					Lateral = flat.Unit:Cross(Vector3.yAxis),
					Width = width,
					Rise = high.Y - low.Y, -- altura entre plantas
					Run = flat.Magnitude,
				})
			end
		end
		for _, e in ends do
			local barrierPos = e.Here - e.Inward * 1.2
			table.insert(barriers, buildBarrier(barrierPos, e.Inward, e.Width))
			-- Encima de la reja, hasta casi el techo: nadie la salta desde el pasamanos
			local capH = e.Rise - 0.6 - BAR_HEIGHT
			if capH > 0 then
				local capCenter = barrierPos + Vector3.new(0, BAR_HEIGHT + capH / 2, 0)
				table.insert(blockers, invisibleWall("FloorBarrierCap", Vector3.new(e.Width + BAR_MARGIN * 2, capH, 0.5), CFrame.lookAt(capCenter, capCenter + e.Inward)))
			end
			-- Paredes por fuera de las barandillas en el primer tramo: nadie se sube a la
			-- rampa por el lateral. Entre dos escaleras pegadas (pares de mecanicas) no hace
			-- falta: la de al lado tambien esta bloqueada.
			local top = e.Here.Y + e.Rise - 0.6
			local bottom = if floor == 1 then e.Here.Y else e.Here.Y - e.Rise * SIDE_LEN / math.max(e.Run, 1) - 1.5
			for _, side in { -1, 1 } do
				local covered = false
				for _, other in ends do
					if other ~= e then
						local d = other.Here - e.Here
						local lateral = d:Dot(e.Lateral) * side
						if math.abs(d:Dot(e.Inward)) < 2 and lateral > 0 and lateral < e.Width + 1.5 then
							covered = true
							break
						end
					end
				end
				if not covered then
					local center = e.Here
						+ e.Lateral * side * (e.Width / 2 + 0.6)
						+ e.Inward * (SIDE_LEN / 2 - 1.2)
					center = Vector3.new(center.X, (top + bottom) / 2, center.Z)
					table.insert(blockers, invisibleWall("FloorBarrierSide", Vector3.new(0.5, top - bottom, SIDE_LEN), CFrame.lookAt(center, center + e.Inward)))
				end
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
			for _, wall in blockers do
				wall:Destroy()
			end
		end
	end,
}
