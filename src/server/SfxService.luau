-- SfxService: sonidos de acciones (Config.Sounds.Sfx).
--   PlayAt(nombre, posicion | pieza): en 3D, lo oyen todos los que esten cerca
--   PlayFor(jugador, nombre): solo ese jugador, sin posicion (compras, tareas...)
--   PlayForAll(nombre): todos, sin posicion
-- (La musica y el ambiente los pone cada cliente: client/Audio.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local SfxService = {}

local function folder(): Folder
	local f = Workspace:FindFirstChild("Sfx")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Sfx"
		f.Parent = Workspace
	end
	return f :: Folder
end

local function def(name: string)
	local d = Config.Sounds.Sfx[name]
	if not d or d.Volume <= 0 then
		return nil
	end
	return d
end

-- Sonido 3D en una posicion (o pegado a una pieza, que lo lleva si se mueve).
function SfxService.PlayAt(name: string, where: Vector3 | BasePart, volumeScale: number?)
	local d = def(name)
	if not d then
		return
	end
	local parent: Instance
	local holder: BasePart? = nil
	if typeof(where) == "Vector3" then
		holder = Instance.new("Part")
		holder.Name = "Sfx_" .. name
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.new(0.2, 0.2, 0.2)
		holder.Position = where
		holder.Parent = folder()
		parent = holder
	else
		parent = where
	end
	local sound = Instance.new("Sound")
	sound.Name = "Sfx_" .. name
	sound.SoundId = d.Id
	sound.Volume = d.Volume * (volumeScale or 1)
	sound.PlaybackSpeed = d.Pitch or 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 90
	sound.Parent = parent
	sound:Play()
	-- (si no llega a cargar, se borra igual al cabo de un rato)
	local life = 8
	sound.Ended:Once(function()
		life = 0
	end)
	task.delay(0.1, function()
		if sound.TimeLength > 0 then
			life = sound.TimeLength / math.max(sound.PlaybackSpeed, 0.05) + 0.5
		end
		task.wait(life)
		sound:Destroy()
		if holder then
			holder:Destroy()
		end
	end)
end

-- Sonido solo para un jugador (en su pantalla, sin posicion).
function SfxService.PlayFor(player: Player, name: string)
	if def(name) then
		Remotes.event("PlaySfx"):FireClient(player, name)
	end
end

function SfxService.PlayForAll(name: string)
	if def(name) then
		Remotes.event("PlaySfx"):FireAllClients(name)
	end
end

return SfxService
