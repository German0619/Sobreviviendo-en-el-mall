-- MissionMarkers (mall): las marcas "!" de las tareas (BillboardGui "MissionMarker",
-- las crea el servidor: MissionService, Missions/Common, la Megafonia) se agrandan al
-- acercarte. Lejos (FarDistance o mas) tienen su tamano normal; desde ahi crecen hasta
-- MaxScale a NearDistance. Solo en este cliente: el servidor no se entera.
-- Si el servidor cambia el tamano de una marca (p. ej. "FALSA" con la Linterna UV),
-- ese pasa a ser su tamano normal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local player = Players.LocalPlayer
local S = Config.MissionMarkers

local MissionMarkers = {}

-- Written: el ultimo Size que pusimos nosotros. Las senales llegan diferidas, asi que
-- un cambio de Size distinto de ese es un tamano nuevo del servidor.
type Entry = { Base: UDim2, Scale: number, Written: UDim2? }

local known: { [BillboardGui]: Entry } = setmetatable({}, { __mode = "k" }) :: any
local markers: { [BillboardGui]: Entry } = {} -- las que estan en el mapa ahora

local function setSize(gui: BillboardGui, entry: Entry, size: UDim2)
	gui.Size = size
	entry.Written = gui.Size -- (ya redondeado: el Offset es entero)
end

local function track(gui: Instance)
	if not gui:IsA("BillboardGui") or gui.Name ~= "MissionMarker" or markers[gui] then
		return
	end
	local entry = known[gui]
	if not entry then
		local newEntry: Entry = { Base = gui.Size, Scale = 1 }
		entry = newEntry
		known[gui] = newEntry
		gui:GetPropertyChangedSignal("Size"):Connect(function()
			if gui.Size ~= newEntry.Written then
				newEntry.Base = gui.Size
				newEntry.Scale = 0 -- volver a aplicar la escala en el siguiente cuadro
			end
		end)
		gui.AncestryChanged:Connect(function()
			if markers[gui] and not gui:IsDescendantOf(Workspace) then
				-- Sale del mapa (la Megafonia guarda su marca y la vuelve a poner):
				-- se queda con su tamano normal
				markers[gui] = nil
				newEntry.Scale = 1
				setSize(gui, newEntry, newEntry.Base)
			end
		end)
		gui.Destroying:Connect(function()
			markers[gui] = nil
		end)
	end
	markers[gui] = entry
end

local function markerPosition(gui: BillboardGui): Vector3?
	local target = gui.Adornee or gui.Parent
	if target and target:IsA("BasePart") then
		return target.Position + gui.StudsOffsetWorldSpace
	elseif target and target:IsA("Attachment") then
		return target.WorldPosition + gui.StudsOffsetWorldSpace
	end
	return nil
end

local function viewerPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return camera and camera.CFrame.Position
end

local function scaled(size: UDim2, k: number): UDim2
	return UDim2.new(size.X.Scale * k, size.X.Offset * k, size.Y.Scale * k, size.Y.Offset * k)
end

function MissionMarkers.Start()
	for _, inst in Workspace:GetDescendants() do
		track(inst)
	end
	Workspace.DescendantAdded:Connect(track)

	local span = math.max(S.FarDistance - S.NearDistance, 1)
	RunService.RenderStepped:Connect(function(dt)
		if next(markers) == nil then
			return
		end
		local viewer = viewerPosition()
		if not viewer then
			return
		end
		local blend = math.min(1, dt * 10)
		for gui, entry in markers do
			local pos = markerPosition(gui)
			if pos then
				-- 0 lejos, 1 cerca (curva suave)
				local t = math.clamp((S.FarDistance - (pos - viewer).Magnitude) / span, 0, 1)
				t = t * t * (3 - 2 * t)
				local target = 1 + (S.MaxScale - 1) * t
				local k = if entry.Scale <= 0 then target else entry.Scale + (target - entry.Scale) * blend
				if math.abs(k - entry.Scale) > 0.002 then
					entry.Scale = k
					setSize(gui, entry, scaled(entry.Base, k))
				end
			end
		end
	end)
end

return MissionMarkers
