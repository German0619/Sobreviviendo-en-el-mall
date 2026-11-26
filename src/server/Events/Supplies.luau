-- Suministros: cae una caja en un punto de la planta, ni muy cerca ni muy lejos de los
-- jugadores. Quien la abre (mision de evento) se lleva bengala, bateria y botiquin
-- (lo que le quepa). Si nadie la abre a tiempo, desaparece.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Server = script.Parent.Parent
local MissionService = require(Server.MissionService)
local ShopService = require(Server.ShopService)
local SfxService = require(Server.SfxService)
local MissionsCommon = require(Server.Missions.Common)
local EnemyCommon = require(ServerScriptService:WaitForChild("Enemies"):WaitForChild("Common"))

local WOOD = Color3.fromRGB(150, 110, 60)

local function pickPoint(floor: number?): Vector3?
	local fallback = nil
	for _ = 1, 15 do
		local point = EnemyCommon.randomPatrolPoint()
		if point and (not floor or Config.getFloor(point.Y) == floor) then
			local _, _, d = EnemyCommon.nearestAlive(point)
			if d >= 25 and d <= 90 then
				return point
			end
			fallback = fallback or point
		end
	end
	return fallback
end

local function buildCrate(point: Vector3): Part
	-- Modelo 3D (PropTemplates.SupplyCrate): maleta militar con cruz, con su luz verde
	local mesh = MissionsCommon.templateItem("SupplyCrate", Vector3.new(3.6, 2.2, 2.6))
	if mesh then
		mesh.Name = "SupplyCrate"
		mesh.CFrame = CFrame.new(point + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
		-- Solida, como la caja de piezas (la pieza raiz invisible hace de caja de colision)
		mesh.CanQuery = true
		mesh.CanCollide = true
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(120, 255, 140)
		light.Range = 10
		light.Brightness = 1.2
		light.Parent = mesh
		mesh.Parent = MissionsCommon.getPropsFolder()
		return mesh
	end
	local crate = Instance.new("Part")
	crate.Name = "SupplyCrate"
	crate.Size = Vector3.new(3, 2.2, 3)
	crate.CFrame = CFrame.new(point + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, math.rad(math.random(0, 90)), 0)
	crate.Anchored = true
	crate.Material = Enum.Material.WoodPlanks
	crate.Color = WOOD
	crate.Parent = MissionsCommon.getPropsFolder()
	-- Bandas y cruz verde (botiquin)
	for _, y in { -0.7, 0.7 } do
		local band = Instance.new("Part")
		band.Name = "Band"
		band.Size = Vector3.new(3.06, 0.2, 3.06)
		band.CFrame = crate.CFrame * CFrame.new(0, y, 0)
		band.Anchored = true
		band.CanCollide = false
		band.CanQuery = false
		band.Material = Enum.Material.Metal
		band.Color = Color3.fromRGB(70, 70, 75)
		band.Parent = crate
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(120, 255, 140)
	light.Range = 10
	light.Brightness = 1.2
	light.Parent = crate
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.CanvasSize = Vector2.new(100, 100)
	gui.Parent = crate
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(80, 230, 110)
	label.Text = "+"
	label.Parent = gui
	return crate
end

return {
	CanStart = function(ctx)
		return pickPoint(ctx.Floor) ~= nil
	end,
	Start = function(ctx)
		local def = ctx.Def
		local point = pickPoint(ctx.Floor)
		if not point then
			ctx.Finish()
			return nil
		end
		local crate = buildCrate(point)
		local mission = MissionService.StartEventMission({
			DisplayName = "Abrir la caja de suministros",
			Spot = crate,
			ActionText = "Abrir",
			ObjectText = "Suministros",
			HoldSeconds = def.HoldSeconds,
			TimeLimit = def.MissionSeconds,
			OnComplete = function(player: Player)
				local got = {}
				for itemId, amount in def.Items do
					local given = ShopService.GiveItem(player, itemId, amount)
					if given > 0 then
						SfxService.PlayFor(player, "Pickup")
						table.insert(got, string.format("%s x%d", Config.ShopItems[itemId].DisplayName, given))
					end
				end
				table.sort(got)
				Remotes.event("Notify"):FireClient(
					player,
					if #got > 0 then "Suministros: " .. table.concat(got, ", ") else "La caja tenía cosas, pero ya no te caben.",
					"good"
				)
				ctx.Finish()
			end,
			OnExpire = function()
				Remotes.event("Notify"):FireAllClients("Nadie abrió la caja de suministros: desapareció.", "bad")
				ctx.Finish()
			end,
		})
		ctx.SetEndsAt(def.MissionSeconds)
		return function()
			mission.Cancel()
			crate:Destroy()
		end
	end,
}
