-- Mision: Tapar maniquies.
-- En los grandes almacenes cerrados (a oscuras) alguien ha quitado las sabanas de 3
-- maniquies (tag SheetMannequin en su peana, atributo Zone). Al empezar la tarea se han
-- girado solos hacia otro lado. Hay que volver a taparlos con su sabana.
-- Las sabanas se quitan (y los maniquies vuelven a su sitio) al empezar la noche siguiente.

local CollectionService = game:GetService("CollectionService")
local Tags = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Tags)
local Multi = require(script.Parent.Multi)

local SHEET_COLOR = Color3.fromRGB(226, 224, 216)

local function mannequinOf(stand: BasePart): Model?
	return stand:FindFirstChildWhichIsA("Model")
end

local function cover(stand: BasePart)
	if stand:FindFirstChild("Sheet") then
		return
	end
	local model = mannequinOf(stand)
	local top = stand.Position + Vector3.new(0, 3.3, 0)
	if model then
		local cf, size = model:GetBoundingBox()
		top = cf.Position
		local sheet = Instance.new("Part")
		sheet.Name = "Sheet"
		sheet.Anchored = true
		sheet.CanCollide = false
		sheet.CanQuery = false
		sheet.CanTouch = false
		sheet.Material = Enum.Material.Fabric
		sheet.Color = SHEET_COLOR
		sheet.Size = Vector3.new(size.X + 0.6, size.Y + 0.2, size.Z + 0.6)
		sheet.CFrame = cf * CFrame.new(0, 0.1, 0)
		sheet.Parent = stand
		-- Pico de la sabana sobre la cabeza
		local peak = sheet:Clone()
		peak.Name = "SheetPeak"
		peak.Shape = Enum.PartType.Ball
		peak.Size = Vector3.new(size.X * 0.7, size.X * 0.7, size.X * 0.7)
		peak.CFrame = CFrame.new(top + Vector3.new(0, size.Y / 2, 0))
		peak.Parent = sheet
	end
end

local function uncover(stand: Instance)
	local sheet = stand:FindFirstChild("Sheet")
	if sheet then
		sheet:Destroy()
	end
	local home = stand:GetAttribute("HomeCFrame")
	local model = stand:IsA("BasePart") and mannequinOf(stand)
	if model and typeof(home) == "CFrame" then
		model:PivotTo(home)
	end
end

return Multi.new({
	Type = "CoverMannequins",
	TargetTag = Tags.SheetMannequin,
	TargetAttribute = "Zone",
	ActionText = "Tapar",
	ObjectText = "Maniquí",
	OnActivate = function(stand: BasePart)
		uncover(stand)
		-- Se ha girado solo (hacia un lado al azar)
		local model = mannequinOf(stand)
		if model then
			model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(math.random(100, 260)), 0))
		end
		return nil
	end,
	OnStep = function(stand: BasePart)
		cover(stand)
	end,
	ResetNight = function()
		for _, stand in CollectionService:GetTagged(Tags.SheetMannequin) do
			uncover(stand)
		end
	end,
})
