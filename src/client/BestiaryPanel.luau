-- BestiaryPanel (solo en el lobby): panel BESTIARIO (boton del libro).
--
--   Izquierda  una casilla por entidad (Config.Bestiary.Order). Al principio todas
--              estan vacias ("?"); cada una se desbloquea al toparse con ella en el mall.
--   Derecha    la seleccionada: foto, nombre, desde que noche sale, que es y como
--              sobrevivirla. Si aun no la encontraste, solo "???".
--
-- Las encontradas llegan en el atributo Bestiary del Player ("Cart,Mannequin"), que
-- pone DataService; las desbloquea server/BestiaryService en el mall.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local NativeUI = require(script.Parent.NativeUI)
local LobbyPanels = require(script.Parent.LobbyPanels)

local COLORS = NativeUI.COLORS
local label, frame, corner, stroke = NativeUI.label, NativeUI.frame, NativeUI.corner, NativeUI.stroke

local BestiaryPanel = {}

local player = Players.LocalPlayer
local B = Config.Bestiary
local ACCENT = Color3.fromRGB(200, 60, 70)
local BOSS = Color3.fromRGB(255, 190, 60)
local LOCKED = Color3.fromRGB(14, 15, 22)
local PAPER = Color3.fromRGB(236, 230, 214) -- marco de la foto (polaroid)

local window: Frame
local diamondsLabel: TextLabel
local countLabel: TextLabel
local cards: { [string]: TextButton } = {}
local detail: {
	Photo: ImageLabel,
	NoPhoto: TextLabel,
	Caption: TextLabel,
	Name: TextLabel,
	Tag: TextLabel,
	Description: TextLabel,
	CounterTitle: TextLabel,
	Counter: TextLabel,
}
local selected: string? = nil

----------------------------------------------------------------------
-- Estado
----------------------------------------------------------------------

local function foundSet(): { [string]: boolean }
	local set = {}
	local raw = player:GetAttribute("Bestiary")
	if type(raw) == "string" and raw ~= "" then
		for _, id in string.split(raw, ",") do
			set[id] = true
		end
	end
	return set
end

-- Foto (Config.Bestiary.Photos; si falta, la inicial del nombre) en un marco de foto
local function setPhoto(image: ImageLabel, placeholder: TextLabel, id: string, entry, unlocked: boolean)
	local photo = B.Photos[id]
	local hasImage = unlocked and type(photo) == "string" and photo ~= ""
	image.Image = if hasImage then photo else ""
	image.ImageTransparency = if hasImage then 0 else 1
	image.BackgroundColor3 = if unlocked then Color3.fromRGB(30, 32, 40) else LOCKED
	placeholder.Visible = not hasImage
	placeholder.Text = if unlocked then string.upper(string.sub(entry.Name, 1, 1)) else "?"
	placeholder.TextColor3 = if unlocked then COLORS.Dim else Color3.fromRGB(70, 72, 90)
end

----------------------------------------------------------------------
-- Refresco
----------------------------------------------------------------------

local function refreshDetail(found: { [string]: boolean })
	local id = selected
	local entry = id and B.Entries[id]
	if not entry then
		return
	end
	local unlocked = found[id :: string] == true
	setPhoto(detail.Photo, detail.NoPhoto, id :: string, entry, unlocked)
	detail.Caption.Text = if unlocked then entry.Name else "???"
	detail.Name.Text = if unlocked then entry.Name else "???"
	detail.Name.TextColor3 = if entry.Boss and unlocked then BOSS else COLORS.Text
	if unlocked then
		detail.Tag.Text = if entry.Boss
			then string.format("☠ JEFE  ·  noche %d", entry.Night)
			else string.format("Aparece desde la noche %d", entry.Night)
		detail.Description.Text = entry.Description
		detail.CounterTitle.Visible = true
		detail.Counter.Text = entry.Counter
	else
		detail.Tag.Text = "Sin descubrir"
		detail.Description.Text = "Aún no te has topado con esta entidad. Sobrevive en el mall para descubrir qué es."
		detail.CounterTitle.Visible = false
		detail.Counter.Text = ""
	end
end

local function refresh()
	if not window then
		return
	end
	diamondsLabel.Text = string.format("💎 %d", player:GetAttribute("Diamonds") or 0)
	local found = foundSet()
	local count = 0
	for _, id in B.Order do
		local entry = B.Entries[id]
		local card = cards[id]
		local unlocked = found[id] == true
		if unlocked then
			count += 1
		end
		setPhoto(card.Photo :: ImageLabel, (card.Photo :: ImageLabel).Placeholder :: TextLabel, id, entry, unlocked)
		local name = card:FindFirstChild("EntryName") :: TextLabel
		name.Text = if unlocked then entry.Name else "???"
		name.TextColor3 = if unlocked then COLORS.Text else COLORS.Dim
		local s = card:FindFirstChildOfClass("UIStroke") :: UIStroke
		if id == selected then
			s.Color = COLORS.Text
			s.Transparency = 0
		elseif entry.Boss and unlocked then
			s.Color = BOSS
			s.Transparency = 0.2
		else
			s.Color = COLORS.Text
			s.Transparency = 0.85
		end
		card.BackgroundColor3 = if id == selected then COLORS.RowSelected elseif unlocked then COLORS.Row else COLORS.Panel
	end
	countLabel.Text = string.format("Encontradas: %d / %d", count, #B.Order)
	refreshDetail(found)
end

----------------------------------------------------------------------
-- Construccion
----------------------------------------------------------------------

-- Foto (ImageLabel "Photo") con su texto "Placeholder" para cuando no hay imagen
local function photoLabel(parent: Instance, size: UDim2, position: UDim2): (ImageLabel, TextLabel)
	local photo = Instance.new("ImageLabel")
	photo.Name = "Photo"
	photo.Size = size
	photo.Position = position
	photo.BackgroundColor3 = LOCKED
	photo.BorderSizePixel = 0
	photo.ScaleType = Enum.ScaleType.Crop
	photo.Image = ""
	photo.Parent = parent
	local placeholder = label(photo, "Placeholder", UDim2.fromScale(1, 0.7), UDim2.fromScale(0, 0.15), 60, {
		Font = Enum.Font.GothamBlack,
		Text = "?",
	})
	return photo, placeholder
end

local function build(gui: ScreenGui)
	local close, plus
	window, diamondsLabel, close, plus = NativeUI.window(gui, "BESTIARIO", ACCENT)
	close.Activated:Connect(function()
		BestiaryPanel.Close()
	end)
	plus.Activated:Connect(function()
		LobbyPanels.open("Shop")
	end)

	local body = frame(window, "Body", UDim2.fromScale(1, 0.89), UDim2.fromScale(0, 0.11))

	-- Izquierda: casillas
	local left = frame(body, "Entries", UDim2.fromScale(0.6, 1), UDim2.fromScale(0, 0))
	countLabel = label(left, "Count", UDim2.fromScale(1, 0.06), UDim2.fromScale(0, 0), 16, {
		TextColor3 = COLORS.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local grid = frame(left, "Grid", UDim2.fromScale(1, 0.92), UDim2.fromScale(0, 0.08))
	local columns = 5
	local rows = math.ceil(#B.Order / columns)
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromScale(0.015, 0.02)
	layout.CellSize = UDim2.fromScale((1 - 0.015 * (columns - 1)) / columns, (1 - 0.02 * (rows - 1)) / rows)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for i, id in B.Order do
		local card = Instance.new("TextButton")
		card.Name = id
		card.LayoutOrder = i
		card.Text = ""
		card.AutoButtonColor = true
		card.BackgroundColor3 = COLORS.Panel
		card.BorderSizePixel = 0
		card.Parent = grid
		corner(card, 0.08)
		stroke(card, COLORS.Text, 0.85, 1.5)
		local photo = photoLabel(card, UDim2.fromScale(0.84, 0.64), UDim2.fromScale(0.08, 0.07))
		corner(photo, 0.06)
		label(card, "EntryName", UDim2.fromScale(0.94, 0.2), UDim2.fromScale(0.03, 0.76), 14, {
			Text = "???",
		})
		card.Activated:Connect(function()
			selected = id
			refresh()
		end)
		cards[id] = card
	end

	-- Derecha: la entidad seleccionada
	local right = frame(body, "Detail", UDim2.fromScale(0.385, 1), UDim2.fromScale(0.615, 0), COLORS.Panel)
	corner(right, 0.04)
	-- Polaroid: papel claro, la foto arriba y el nombre escrito a mano abajo
	local paper = frame(right, "Polaroid", UDim2.fromScale(0.62, 0.48), UDim2.fromScale(0.19, 0.03), PAPER)
	corner(paper, 0.03)
	paper.Rotation = -2
	local photo, noPhoto = photoLabel(paper, UDim2.fromScale(0.9, 0.78), UDim2.fromScale(0.05, 0.05))
	local caption = label(paper, "Caption", UDim2.fromScale(0.9, 0.14), UDim2.fromScale(0.05, 0.84), 20, {
		Font = Enum.Font.PermanentMarker,
		TextColor3 = Color3.fromRGB(40, 36, 32),
		Text = "???",
	})

	local name = label(right, "Name", UDim2.fromScale(0.92, 0.07), UDim2.fromScale(0.04, 0.53), 24, {
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local tag = label(right, "Tag", UDim2.fromScale(0.92, 0.045), UDim2.fromScale(0.04, 0.6), 14, {
		TextColor3 = COLORS.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local description = label(right, "Description", UDim2.fromScale(0.92, 0.13), UDim2.fromScale(0.04, 0.655), 15, {
		Font = Enum.Font.Gotham,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local counterTitle = label(right, "CounterTitle", UDim2.fromScale(0.92, 0.045), UDim2.fromScale(0.04, 0.8), 14, {
		Text = "CÓMO SOBREVIVIR",
		TextColor3 = COLORS.Good,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local counter = label(right, "Counter", UDim2.fromScale(0.92, 0.14), UDim2.fromScale(0.04, 0.85), 15, {
		Font = Enum.Font.Gotham,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	detail = {
		Photo = photo,
		NoPhoto = noPhoto,
		Caption = caption,
		Name = name,
		Tag = tag,
		Description = description,
		CounterTitle = counterTitle,
		Counter = counter,
	}
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function BestiaryPanel.Open()
	if not window then
		return
	end
	-- Seleccion: la que ya estaba, o la primera encontrada, o la primera
	if not selected then
		local found = foundSet()
		for _, id in B.Order do
			if found[id] then
				selected = id
				break
			end
		end
		selected = selected or B.Order[1]
	end
	refresh()
	window.Visible = true
end

function BestiaryPanel.Close()
	if window then
		window.Visible = false
	end
end

function BestiaryPanel.IsOpen(): boolean
	return window ~= nil and window.Visible
end

function BestiaryPanel.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BestiaryPanel"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 7
	gui.Parent = player:WaitForChild("PlayerGui")
	build(gui)

	player.AttributeChanged:Connect(function(attribute: string)
		if (attribute == "Bestiary" or attribute == "Diamonds") and window.Visible then
			refresh()
		end
	end)
end

return BestiaryPanel
