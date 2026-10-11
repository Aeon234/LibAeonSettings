-- The edit session's screen: the tint, the grid, the toolbar and the Escape key. Built on first use.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

local GRID_SPACING = 32
local ACCENT = { 0.84, 0.67, 0.36 }
local TINT = { 0.03, 0.023, 0.018, 0.2 }
local GRID_MODES = { DIMMED = "BRIGHT", BRIGHT = "OFF", OFF = "DIMMED" }
local GRID_LABELS = { DIMMED = L.DIMMED, BRIGHT = L.BRIGHT, OFF = L.OFF }
local ICON_ON, ICON_OFF = { 1, 0.82, 0 }, { 0.62, 0.62, 0.62 }
local ICON_ALPHA_ON, ICON_ALPHA_OFF, ICON_ALPHA_HOVER = 0.8, 0.45, 1

-- Every script calls through the library at run time, so a newer copy's code runs on frames an older copy built.
local Handlers = {}
lib.EditUIHandlers = Handlers

local function Texture(name)
	return lib.mediaPath .. "Textures\\" .. name
end

-- Grid ---------------------------------------------------------------------------------------------------------

local function GridLine(grid, index)
	local line = grid.lines[index]
	if not line then
		line = grid:CreateTexture(nil, "BACKGROUND")
		grid.lines[index] = line
	end
	line:ClearAllPoints()
	line:Show()

	return line
end

function lib:RefreshGrid()
	local grid = self.ui and self.ui.grid
	if not grid then
		return
	end
	for _, line in ipairs(grid.lines) do
		line:Hide()
	end
	local mode = self:GetPreference("grid")
	if mode == "OFF" then
		return
	end

	local alpha = mode == "BRIGHT" and 0.3 or 0.15
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	local thickness = PixelUtil.GetNearestPixelSize(1, UIParent:GetEffectiveScale(), 1)
	local count = 0
	local function Add(vertical, offset, lineAlpha, length, r, g, b)
		count = count + 1
		local line = GridLine(grid, count)
		line:SetColorTexture(r or ACCENT[1], g or ACCENT[2], b or ACCENT[3], lineAlpha)
		if vertical then
			line:SetSize(thickness, length or height)
			line:SetPoint("CENTER", grid, "CENTER", offset, 0)
		else
			line:SetSize(length or width, thickness)
			line:SetPoint("CENTER", grid, "CENTER", 0, offset)
		end
	end

	for offset = GRID_SPACING, width / 2, GRID_SPACING do
		Add(true, offset, alpha)
		Add(true, -offset, alpha)
	end
	for offset = GRID_SPACING, height / 2, GRID_SPACING do
		Add(false, offset, alpha)
		Add(false, -offset, alpha)
	end
	local centerAlpha = math.min(0.6, alpha * 3)
	Add(true, 0, centerAlpha)
	Add(false, 0, centerAlpha)
	Add(true, 0, 0.5, 40, 1, 1, 1)
	Add(false, 0, 0.5, 40, 1, 1, 1)
end

-- Toolbar ------------------------------------------------------------------------------------------------------

local function PaintToggle(toggle, on, label, hovered)
	toggle.icon:SetTexture(Texture(on and toggle.iconOn or toggle.iconOff))
	toggle.icon:SetVertexColor(unpack(on and ICON_ON or ICON_OFF))
	toggle.icon:SetAlpha(hovered and ICON_ALPHA_HOVER or on and ICON_ALPHA_ON or ICON_ALPHA_OFF)
	toggle.state:SetText(label)
	toggle.state:SetTextColor(unpack(on and ICON_ON or ICON_OFF))
end

local function CreateToggle(toolbar, name, iconName, onClick)
	local toggle = CreateFrame("Button", nil, toolbar)
	toggle:SetHeight(44)
	toggle.iconOn, toggle.iconOff = "icon-" .. iconName .. "-on", "icon-" .. iconName .. "-off"
	toggle.icon = toggle:CreateTexture(nil, "ARTWORK")
	toggle.icon:SetSize(28, 28)
	toggle.icon:SetPoint("LEFT", 6, 0)
	toggle.name = toggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	toggle.name:SetPoint("TOPLEFT", toggle.icon, "TOPRIGHT", 8, 0)
	toggle.name:SetText(name)
	toggle.state = toggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	toggle.state:SetPoint("TOPLEFT", toggle.name, "BOTTOMLEFT", 0, -2)
	toggle:SetScript("OnClick", function(self) Handlers.ToggleClick(self) end)
	toggle:SetScript("OnEnter", function(self) Handlers.ToggleHover(self, true) end)
	toggle:SetScript("OnLeave", function(self) Handlers.ToggleHover(self, false) end)
	toggle.onClick = onClick

	return toggle
end

function Handlers.ToggleClick(toggle)
	toggle.onClick()
	lib:RefreshToolbar()
end

function Handlers.ToggleHover(toggle, hovered)
	toggle.hovered = hovered
	lib:RefreshToolbar()
end

local function CreateButton(toolbar, text, onClick)
	local button = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
	button:SetText(text)
	button:SetSize(button:GetFontString():GetStringWidth() + 30, 24)
	button:SetScript("OnClick", onClick)

	return button
end

local function CreateToolbar()
	local toolbar = CreateFrame("Frame", nil, UIParent)
	toolbar:SetFrameStrata("FULLSCREEN_DIALOG")
	toolbar:SetHeight(52)
	toolbar:SetPoint("TOP", UIParent, "TOP", 0, 0)
	toolbar:EnableMouse(true)

	local background = toolbar:CreateTexture(nil, "BACKGROUND")
	background:SetPoint("TOPLEFT", 2, 0)
	background:SetPoint("BOTTOMRIGHT", -2, 2)
	background:SetColorTexture(0.05, 0.045, 0.05, 0.92)
	-- The frame art's top edge sits above the screen, so the bar reads as hanging from the top edge.
	local border = toolbar:CreateTexture(nil, "BORDER")
	border:SetAtlas("UI-HUD-ActionBar-Frame")
	border:SetPoint("TOPLEFT", -8, 24)
	border:SetPoint("BOTTOMRIGHT", 8, -8)

	toolbar.exit = CreateButton(toolbar, L.EXIT, function() lib:RequestClose(false) end)
	toolbar.save = CreateButton(toolbar, L.SAVE_AND_EXIT, function() lib:RequestClose(true) end)
	toolbar.separator = toolbar:CreateTexture(nil, "ARTWORK")
	toolbar.separator:SetColorTexture(1, 1, 1, 0.12)
	toolbar.separator:SetSize(1, 30)
	toolbar.grid = CreateToggle(toolbar, L.GRID_LINES, "grid", function()
		lib:SetPreference("grid", GRID_MODES[lib:GetPreference("grid")] or "DIMMED")
		lib:RefreshGrid()
	end)
	toolbar.fill = CreateToggle(toolbar, L.MOVER_FILL, "dark-overlays", function()
		lib:SetPreference("fill", not lib:GetPreference("fill"))
		lib:RefreshMovers()
	end)
	toolbar.snap = CreateToggle(toolbar, L.SNAP_ELEMENTS, "snap", function()
		lib:SetPreference("snap", not lib:GetPreference("snap"))
	end)
	toolbar.coordinates = CreateToggle(toolbar, L.COORDINATES, "coordinates", function()
		lib:SetPreference("coordinates", not lib:GetPreference("coordinates"))
		lib:RefreshMovers()
	end)
	toolbar.toggles = { toolbar.grid, toolbar.fill, toolbar.snap, toolbar.coordinates }

	return toolbar
end

function lib:RefreshToolbar()
	local toolbar = self.ui and self.ui.toolbar
	if not toolbar then
		return
	end
	local mode = self:GetPreference("grid")
	PaintToggle(toolbar.grid, mode ~= "OFF", GRID_LABELS[mode] or L.DIMMED, toolbar.grid.hovered)
	local fill = self:GetPreference("fill")
	PaintToggle(toolbar.fill, fill, fill and L.ON or L.OFF, toolbar.fill.hovered)
	local snap = self:GetPreference("snap")
	PaintToggle(toolbar.snap, snap, snap and L.ON or L.OFF, toolbar.snap.hovered)
	local coordinates = self:GetPreference("coordinates")
	PaintToggle(toolbar.coordinates, coordinates, coordinates and L.ON or L.OFF, toolbar.coordinates.hovered)

	local x = 14
	local function Place(region, width, gap)
		region:ClearAllPoints()
		region:SetPoint("LEFT", toolbar, "LEFT", x, 0)
		x = x + width + gap
	end
	Place(toolbar.exit, toolbar.exit:GetWidth(), 6)
	Place(toolbar.save, toolbar.save:GetWidth(), 12)
	Place(toolbar.separator, 1, 8)
	for _, toggle in ipairs(toolbar.toggles) do
		toggle:SetWidth(6 + 28 + 8 + math.max(toggle.name:GetStringWidth(), toggle.state:GetStringWidth()) + 10)
		Place(toggle, toggle:GetWidth(), 4)
	end
	toolbar:SetWidth(x + 10)
end

-- Screen -------------------------------------------------------------------------------------------------------

function Handlers.KeyDown(frame, key)
	if InCombatLockdown() then
		return
	end
	if key ~= "ESCAPE" then
		frame:SetPropagateKeyboardInput(not lib:NudgeSelected(key))
		return
	end
	frame:SetPropagateKeyboardInput(false)
	if StaticPopup_Visible("LIBAEONSETTINGS_EDIT_EXIT") then
		StaticPopup_Hide("LIBAEONSETTINGS_EDIT_EXIT")
		return
	end
	lib:RequestClose(false)
end

local function BuildEditUI()
	local ui = {}

	ui.screen = CreateFrame("Frame", nil, UIParent)
	ui.screen:SetFrameStrata("FULLSCREEN")
	ui.screen:SetAllPoints(UIParent)
	ui.screen:EnableKeyboard(true)
	ui.screen:SetScript("OnKeyDown", function(self, key) Handlers.KeyDown(self, key) end)

	ui.tint = ui.screen:CreateTexture(nil, "BACKGROUND", nil, -8)
	ui.tint:SetAllPoints()
	ui.tint:SetColorTexture(unpack(TINT))

	ui.grid = CreateFrame("Frame", nil, ui.screen)
	ui.grid:SetAllPoints()
	ui.grid.lines = {}

	ui.guideLayer = CreateFrame("Frame", nil, ui.screen)
	ui.guideLayer:SetAllPoints()
	ui.guideLayer:SetFrameLevel(ui.screen:GetFrameLevel() + 5)

	ui.moverLayer = CreateFrame("Frame", nil, ui.screen)
	ui.moverLayer:SetAllPoints()
	ui.moverLayer:SetFrameLevel(ui.screen:GetFrameLevel() + 10)

	ui.toolbar = CreateToolbar()

	return ui
end

function lib:ShowEditUI()
	self.ui = self.ui or BuildEditUI()
	self.ui.screen:Show()
	self.ui.toolbar:Show()
	self:RefreshGrid()
	self:RefreshToolbar()
	self:RefreshMovers()
end

function lib:HideEditUI()
	if not self.ui then
		return
	end
	self.ui.screen:Hide()
	self.ui.toolbar:Hide()
	self:RefreshMovers()
end

-- The grid follows UI scale and resolution changes while edit mode is open.
local layoutEvents = lib.editLayoutEvents or CreateFrame("Frame")
lib.editLayoutEvents = layoutEvents
layoutEvents:RegisterEvent("UI_SCALE_CHANGED")
layoutEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
layoutEvents:SetScript("OnEvent", function()
	if lib.session.open and not lib.session.paused then
		lib:RefreshGrid()
		lib:RefreshMovers()
	end
end)
