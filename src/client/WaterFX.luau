-- WaterFX: anima el agua de las fuentes (solo visual, en el cliente).
--
-- * Laminas de agua (atributo Spin, rad/s): giran despacio sobre su eje vertical; con
--   dos capas girando en sentidos opuestos el dibujo de ondas/causticas parece moverse.
-- * Texturas que corren (Texture con atributos ScrollU / ScrollV, studs/s): las ondas de
--   la superficie y la red de luz (causticas) del fondo de la fuente del lobby.
-- * Focos sumergidos (atributo Shimmer = true): su luz titila como la luz a traves del agua.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Tags = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Tags"))

local WaterFX = {}

local ANIMATE_DISTANCE = 140

type Scroll = { Texture: Texture, U: number, V: number }
type Entry = { Part: BasePart, Base: CFrame, Light: Light?, BaseBrightness: number, Seed: number, Scrolls: { Scroll } }
local entries: { [BasePart]: Entry } = {}

local function add(inst: Instance)
	if not inst:IsA("BasePart") or entries[inst] then
		return
	end
	local light = inst:FindFirstChildWhichIsA("Light")
	local scrolls = {}
	for _, child in inst:GetChildren() do
		if child:IsA("Texture") then
			local u, v = child:GetAttribute("ScrollU"), child:GetAttribute("ScrollV")
			if type(u) == "number" or type(v) == "number" then
				table.insert(scrolls, { Texture = child, U = u or 0, V = v or 0 })
			end
		end
	end
	entries[inst] = {
		Part = inst,
		Base = inst.CFrame,
		Light = light,
		BaseBrightness = if light then light.Brightness else 0,
		Seed = math.random() * 100,
		Scrolls = scrolls,
	}
end

function WaterFX.Start()
	for _, inst in CollectionService:GetTagged(Tags.FountainWater) do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.FountainWater):Connect(add)
	CollectionService:GetInstanceRemovedSignal(Tags.FountainWater):Connect(function(inst)
		entries[inst :: BasePart] = nil
	end)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local camera = Workspace.CurrentCamera
		local camPos = camera and camera.CFrame.Position or Vector3.zero
		for part, e in entries do
			if not part.Parent then
				entries[part] = nil
				continue
			end
			if (e.Base.Position - camPos).Magnitude > ANIMATE_DISTANCE then
				continue
			end
			local spin = part:GetAttribute("Spin")
			if type(spin) == "number" then
				-- Giro alrededor del eje vertical del mundo (la lamina es un cilindro tumbado)
				part.CFrame = CFrame.new(e.Base.Position) * CFrame.Angles(0, now * spin, 0) * e.Base.Rotation
			end
			for _, s in e.Scrolls do
				local t = s.Texture
				t.OffsetStudsU = (now * s.U) % t.StudsPerTileU
				-- (un vaiven suave encima del avance: el agua no corre en linea recta)
				t.OffsetStudsV = (now * s.V + math.sin(now * 0.7 + e.Seed) * 0.4) % t.StudsPerTileV
			end
			if e.Light and part:GetAttribute("Shimmer") then
				local wave = math.sin(now * 3.1 + e.Seed) * 0.5 + math.sin(now * 5.3 + e.Seed * 2) * 0.3
				e.Light.Brightness = e.BaseBrightness * (1 + 0.25 * wave)
			end
		end
	end)
end

return WaterFX
