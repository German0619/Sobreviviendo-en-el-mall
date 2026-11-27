-- SkinFX (lobby y mall): anima los brillos de las skins legendarias y miticas.
-- HeldModels.applySkin marca con el tag SkinAnim las piezas de neon, los anillos y la luz
-- de la skin (atributos SkinAnim = modo y SkinFxPhase = desfase). Se anima en cada cliente
-- (no se replica): en la mano de todos, en la copia de la camara y en las vistas previas.
--   Pulse    late despacio (Luna)
--   Flicker  parpadeo vivo, como fuego o electricidad (Infierno, Tormenta)
--   Nebula   el color va y viene entre azul, violeta y rosa (Galaxia)
--   Rainbow  recorre todos los colores (Prisma)
--   Blaze    del rojo al dorado, con parpadeo de llama (Fenix)

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HeldModels = require(ReplicatedStorage:WaitForChild("Shared").HeldModels)

local SkinFX = {}

type Entry = { Color: Color3, Brightness: number, Phase: number, Mode: string }
local entries: { [Instance]: Entry } = {}

local BLAZE_LOW = Color3.fromRGB(255, 60, 15)
local BLAZE_HIGH = Color3.fromRGB(255, 225, 110)

local function add(inst: Instance)
	if entries[inst] then
		return
	end
	local mode = inst:GetAttribute("SkinAnim")
	if type(mode) ~= "string" then
		return
	end
	local color, brightness = Color3.new(1, 1, 1), 1
	if inst:IsA("BasePart") then
		color = inst.Color
	elseif inst:IsA("Light") then
		color = inst.Color
		brightness = inst.Brightness
	else
		return
	end
	entries[inst] = {
		Color = color,
		Brightness = brightness,
		Phase = inst:GetAttribute("SkinFxPhase") or 0,
		Mode = mode,
	}
end

local function scale(c: Color3, k: number): Color3
	return Color3.new(math.min(c.R * k, 1), math.min(c.G * k, 1), math.min(c.B * k, 1))
end

-- Devuelve (color, factor de brillo) para un instante
local function sample(e: Entry, t: number): (Color3, number)
	local p = e.Phase
	if e.Mode == "Pulse" then
		local k = 0.75 + 0.3 * math.sin(t * 2.4 + p)
		return scale(e.Color, k), k
	elseif e.Mode == "Flicker" then
		local n = math.noise(t * 7, p * 3.1, 0.5) -- -1..1
		local k = 0.8 + 0.35 * n
		if math.noise(t * 2.3, p, 9.7) > 0.42 then
			k += 0.4 -- chispazo
		end
		return scale(e.Color, k), k
	elseif e.Mode == "Nebula" then
		local hue = 0.76 + 0.13 * math.sin(t * 0.9 + p)
		local k = 0.85 + 0.2 * math.sin(t * 1.7 + p * 2)
		return Color3.fromHSV(hue, 0.7, 1), k
	elseif e.Mode == "Rainbow" then
		local hue = (t * 0.22 + p * 0.12) % 1
		return Color3.fromHSV(hue, 0.85, 1), 1
	elseif e.Mode == "Blaze" then
		local a = 0.5 + 0.5 * math.sin(t * 1.6 + p)
		local k = 0.9 + 0.25 * math.noise(t * 6, p, 2.2)
		return BLAZE_LOW:Lerp(BLAZE_HIGH, a), k
	end
	return e.Color, 1
end

function SkinFX.Start()
	local tag = HeldModels.ANIM_TAG
	for _, inst in CollectionService:GetTagged(tag) do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		entries[inst] = nil
	end)

	RunService.RenderStepped:Connect(function()
		if next(entries) == nil then
			return
		end
		local t = os.clock()
		for inst, e in entries do
			if inst.Parent == nil then
				entries[inst] = nil
				continue
			end
			local color, k = sample(e, t)
			if inst:IsA("BasePart") then
				inst.Color = color
			elseif inst:IsA("Light") then
				inst.Color = color
				inst.Brightness = e.Brightness * math.max(k, 0.2)
			end
		end
	end)
end

return SkinFX
