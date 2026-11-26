-- Utilidades compartidas por los modulos de mision.
--
-- Fabricas para no repetir codigo: Hold (mantener E en un punto), Multi (varios
-- puntos) y Carry (recoger un objeto y llevarlo).
--
-- Cada modulo de mision exporta:
--   CanStart(spot: BasePart, zone: string) -> boolean      (opcional)
--   Begin(mission, complete: (player) -> boolean) -> { Cleanup: (success: boolean) -> (), Marker: BasePart? }
--   ResetNight()                                           (opcional, limpia restos al empezar otra noche)

local Workspace = game:GetService("Workspace")

local Common = {}

function Common.getPropsFolder(): Folder
	local folder = Workspace:FindFirstChild("MissionProps")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MissionProps"
		folder.Parent = Workspace
	end
	return folder
end

function Common.makePrompt(parent: Instance, actionText: string, objectText: string?, holdDuration: number?): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText or ""
	prompt.HoldDuration = holdDuration or 0
	prompt:SetAttribute("BaseHoldDuration", holdDuration or 0)
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = parent
	return prompt
end

-- Marcador "!" (o el texto que se pase) visible a traves de las paredes.
function Common.makeMarker(part: BasePart, text: string?, color: Color3?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "MissionMarker"
	gui.Size = UDim2.fromOffset(36, 36)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text or "!"
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color or Color3.fromRGB(255, 200, 60)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = part
	return gui
end

-- Charco en el suelo con tag DirtyArea (lo huele el Rastro).
function Common.makePuddle(floor: Vector3, size: number, color: Color3): Part
	local CollectionService = game:GetService("CollectionService")
	local Tags = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Tags)
	local puddle = Instance.new("Part")
	puddle.Name = "Puddle"
	puddle.Shape = Enum.PartType.Cylinder
	puddle.Size = Vector3.new(0.1, size, size)
	puddle.CFrame = CFrame.new(floor + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
	puddle.Anchored = true
	puddle.CanCollide = false
	puddle.CanQuery = false
	puddle.CanTouch = false
	puddle.Material = Enum.Material.Glass
	puddle.Color = color
	puddle.Transparency = 0.2
	puddle.Reflectance = 0.25
	puddle.Parent = Common.getPropsFolder()
	CollectionService:AddTag(puddle, Tags.DirtyArea)
	return puddle
end

-- Sonido 3D en bucle pegado a una parte (Config.Sounds.Missions[name]). Devuelve el
-- Sound (o nil si no hay audio configurado); se quita con :Destroy().
function Common.loopSound(part: BasePart, name: string, maxDistance: number?): Sound?
	local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config)
	local def = Config.Sounds.Missions and Config.Sounds.Missions[name]
	if not def or def.Volume <= 0 then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Mission_" .. name
	sound.SoundId = def.Id
	sound.Volume = def.Volume
	sound.PlaybackSpeed = def.Pitch or 1
	sound.Looped = true
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = maxDistance or 80
	sound.Parent = part
	sound:Play()
	return sound
end

-- Posicion del suelo bajo una parte de mision (su cara inferior).
function Common.floorPosition(spot: BasePart): Vector3
	return spot.Position - Vector3.new(0, spot.Size.Y / 2, 0)
end

return Common
