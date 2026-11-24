-- EscalatorFX: anima los escalones de las escaleras mecanicas (solo visual, en el cliente).
--
-- El movimiento real lo hace el servidor: la rampa tiene AssemblyLinearVelocity y
-- arrastra a quien la pisa. Aqui solo se desplazan los escalones (partes decorativas
-- de la carpeta "Steps") a lo largo de la rampa para que se vea que se mueve.
-- Atributos del Model (tag Escalator): Surface, Length, Spacing, Speed.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Tags = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Tags"))

local EscalatorFX = {}

local ANIMATE_DISTANCE = 160 -- mas lejos no se nota: no se anima
local REFRESH_SECONDS = 2 -- con StreamingEnabled los escalones pueden llegar tarde

type Entry = {
	Model: Model,
	Steps: { BasePart },
	NextRefresh: number,
}

local entries: { [Model]: Entry } = {}

local function refresh(entry: Entry)
	local folder = entry.Model:FindFirstChild("Steps")
	local list = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(list, child)
			end
		end
	end
	-- Orden estable (por nombre: Step01, Step02...) para repartirlos a lo largo
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	entry.Steps = list
	entry.NextRefresh = os.clock() + REFRESH_SECONDS
end

local function add(inst: Instance)
	if inst:IsA("Model") and not entries[inst] then
		local entry = { Model = inst, Steps = {}, NextRefresh = 0 }
		entries[inst] = entry
		refresh(entry)
	end
end

function EscalatorFX.Start()
	for _, inst in CollectionService:GetTagged(Tags.Escalator) do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.Escalator):Connect(add)
	CollectionService:GetInstanceRemovedSignal(Tags.Escalator):Connect(function(inst)
		entries[inst :: Model] = nil
	end)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local camera = Workspace.CurrentCamera
		local camPos = camera and camera.CFrame.Position or Vector3.zero
		for model, entry in entries do
			if not model.Parent then
				continue
			end
			if now >= entry.NextRefresh then
				refresh(entry)
			end
			local surface = model:GetAttribute("Surface")
			local length = model:GetAttribute("Length")
			local spacing = model:GetAttribute("Spacing")
			local speed = model:GetAttribute("Speed")
			if typeof(surface) ~= "CFrame" or type(length) ~= "number" or type(spacing) ~= "number" or type(speed) ~= "number" then
				continue
			end
			if (surface.Position - camPos).Magnitude > ANIMATE_DISTANCE then
				continue
			end
			-- Desplazamiento comun (modulo positivo tambien para velocidades negativas)
			local offset = (now * speed) % spacing
			for i, step in entry.Steps do
				if step.Parent then
					local s = ((i - 1) * spacing + offset) % length - length / 2
					step.CFrame = surface * CFrame.new(0, 0.1, -s)
				end
			end
		end
	end)
end

return EscalatorFX
