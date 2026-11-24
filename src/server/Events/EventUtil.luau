-- Utilidades compartidas por los eventos (no es un evento: EventDirector solo carga
-- los modulos cuyo nombre es una clave de Config.Events).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)

local Server = script.Parent.Parent
local LightService = require(Server.LightService)
local EnemyCommon = require(ServerScriptService:WaitForChild("Enemies"):WaitForChild("Common"))

local EventUtil = {}

function EventUtil.rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function EventUtil.alivePlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if player:GetAttribute("Alive") == true and humanoid and humanoid.Health > 0 then
			table.insert(list, player)
		end
	end
	return list
end

-- Distancia al jugador vivo mas cercano.
function EventUtil.nearestPlayerDistance(position: Vector3): number
	local _, _, d = EnemyCommon.nearestAlive(position)
	return d
end

-- Punto libre del suelo dentro de una zona (como Common.randomPatrolPoint, pero de esa zona).
function EventUtil.randomPointInZone(zone: string): Vector3?
	local part = LightService.GetZonePart(zone)
	if not part then
		return nil
	end
	local params = EnemyCommon.raycastParams()
	local floorY = part.Position.Y - part.Size.Y / 2
	for _ = 1, 12 do
		local rel = Vector3.new((math.random() - 0.5) * part.Size.X * 0.8, 0, (math.random() - 0.5) * part.Size.Z * 0.8)
		local top = (part.CFrame * CFrame.new(rel)).Position + Vector3.new(0, part.Size.Y / 2 - 1, 0)
		local hit = Workspace:Raycast(top, Vector3.new(0, -(part.Size.Y + 2), 0), params)
		if hit and math.abs(hit.Position.Y - floorY) < 1.5 then
			return hit.Position
		end
	end
	return nil
end

-- Punto del suelo de una planta a una distancia de los jugadores entre minD y maxD
-- (o el que se pueda). zoneFilter(zone) -> boolean opcional.
function EventUtil.pointOnFloor(floor: number?, minD: number, maxD: number, zoneFilter: ((string) -> boolean)?): Vector3?
	local zones = {}
	for _, zone in LightService.GetZones() do
		local part = LightService.GetZonePart(zone)
		if part and (not floor or Config.getFloor(part.Position.Y - part.Size.Y / 2 + 1) == floor) then
			if not zoneFilter or zoneFilter(zone) then
				table.insert(zones, zone)
			end
		end
	end
	if #zones == 0 then
		return nil
	end
	local fallback = nil
	for _ = 1, 20 do
		local point = EventUtil.randomPointInZone(zones[math.random(1, #zones)])
		if point then
			local d = EventUtil.nearestPlayerDistance(point)
			if d >= minD and d <= maxD then
				return point
			end
			fallback = fallback or point
		end
	end
	return fallback
end

----------------------------------------------------------------------
-- Persianas de las tiendas (tag ShutterControl, parte hija "Shutter")
----------------------------------------------------------------------
-- La persiana mira hacia DENTRO de la tienda (su LookVector), asi que la zona de la
-- tienda es la que hay unos studs detras de ella.

export type Store = { Control: BasePart, Shutter: BasePart, Zone: string, Floor: number }

function EventUtil.getStores(floor: number?): { Store }
	local list = {}
	for _, control in CollectionService:GetTagged(Tags.ShutterControl) do
		local shutter = control:FindFirstChild("Shutter")
		if control:IsA("BasePart") and shutter and shutter:IsA("BasePart") and control:IsDescendantOf(Workspace) then
			local closed = shutter:GetAttribute("ClosedCFrame")
			local base = if typeof(closed) == "CFrame" then closed else shutter.CFrame
			local inside = base.Position + base.LookVector * 8 - Vector3.new(0, 4, 0)
			local zone = LightService.GetZoneAt(inside)
			local storeFloor = Config.getFloor(control.Position.Y)
			if zone and (not floor or storeFloor == floor) and control:GetAttribute("EventSealed") == nil then
				table.insert(list, { Control = control, Shutter = shutter, Zone = zone, Floor = storeFloor })
			end
		end
	end
	return list
end

-- Cierra la persiana hasta el suelo (con colision). Devuelve una funcion que la deja
-- como estaba. seconds = duracion de la animacion.
function EventUtil.sealShutter(store: Store, seconds: number): () -> ()
	local shutter = store.Shutter
	local control = store.Control
	local before = { Size = shutter.Size, CFrame = shutter.CFrame, CanCollide = shutter.CanCollide }
	local closedCF = shutter:GetAttribute("ClosedCFrame")
	local closedSize = shutter:GetAttribute("ClosedSize")
	local baseCF = if typeof(closedCF) == "CFrame" then closedCF else shutter.CFrame
	local baseSize = if typeof(closedSize) == "Vector3" then closedSize else shutter.Size
	local topY = baseCF.Position.Y + baseSize.Y / 2
	local floorY = EnemyCommon.floorBelow(baseCF.Position, 30) or (topY - 12)
	local height = topY - floorY
	local goalCF = baseCF - Vector3.new(0, baseCF.Position.Y - (floorY + height / 2), 0)
	control:SetAttribute("EventSealed", true)
	shutter.CanCollide = true
	TweenService:Create(shutter, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
		Size = Vector3.new(baseSize.X, height, baseSize.Z),
		CFrame = goalCF,
	}):Play()
	return function()
		control:SetAttribute("EventSealed", nil)
		shutter.CanCollide = before.CanCollide
		TweenService:Create(shutter, TweenInfo.new(1.2, Enum.EasingStyle.Linear), {
			Size = before.Size,
			CFrame = before.CFrame,
		}):Play()
	end
end

return EventUtil
