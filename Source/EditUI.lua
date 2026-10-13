-- The edit session's screen: the tint, the grid, the toolbar and the Escape key. Built on first use.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

local GRID_SPACING = 32
local TOOLBAR_HEIGHT = 52
local TOOLBAR_PADDING = 16  -- left and right, around the centered row of controls
local TOOLBAR_GAP = 8       -- between any two controls, the separator included
local BUTTON_HEIGHT = 28  -- the three-slice button art's own height
local TOGGLE_HEIGHT = 40
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 1, 1.5, 0.1
local SCALE_BUTTON_WIDTH = 28
local TOOLBAR_CLEARANCE = 6  -- space kept between the toolbar's opening spot and any mover
local TOOLBAR_SPOT_STEP = 16 -- step when looking down the screen for a free spot
local TOOLBAR_TOP_HIDDEN = 12 -- how far the toolbar art's top edge sits above the top of the screen
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

---Height of the strip between the top of the game's window and UIParent's top, in UIParent units. It is the
---display's notch when the client moves UIParent down to avoid it (C_UI.ShouldUIParentAvoidNotch), else 0.
function lib:TopInset()
	local worldTop, uiTop = WorldFrame:GetTop(), UIParent:GetTop()
	if not worldTop or not uiTop then
		return 0
	end
	local scale = UIParent:GetEffectiveScale()

	return math.max(0, (worldTop * WorldFrame:GetEffectiveScale() - uiTop * scale) / scale)
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
	-- The grid stays centered on UIParent and also covers the strip above it (a display's notch area).
	local inset = self:TopInset()
	local lineHeight = height + 2 * inset
	local thickness = PixelUtil.GetNearestPixelSize(1, UIParent:GetEffectiveScale(), 1)
	local count = 0
	local function Add(vertical, offset, lineAlpha, length, r, g, b)
		count = count + 1
		local line = GridLine(grid, count)
		line:SetColorTexture(r or ACCENT[1], g or ACCENT[2], b or ACCENT[3], lineAlpha)
		if vertical then
			line:SetSize(thickness, length or lineHeight)
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
	for offset = GRID_SPACING, height / 2 + inset, GRID_SPACING do
		Add(false, offset, alpha)
		if offset <= height / 2 then
			Add(false, -offset, alpha)
		end
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

local function CreateToggle(toolbar, name, iconName, onClick, tooltip)
	local toggle = CreateFrame("Button", nil, toolbar)
	toggle:SetHeight(TOGGLE_HEIGHT)
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
	toggle.tooltip = tooltip

	return toggle
end

function Handlers.ToggleClick(toggle)
	toggle.onClick()
	lib:RefreshToolbar()
end

---Shows a toolbar control's name and what it does, below the toolbar.
local function ShowTooltip(control, title, text)
	if not text then
		return
	end
	local _, centerY = lib.ui.toolbar:GetCenter()
	local low = centerY and centerY * lib.ui.toolbar:GetScale() < UIParent:GetHeight() / 2
	GameTooltip:SetOwner(control, low and "ANCHOR_TOP" or "ANCHOR_BOTTOM")
	GameTooltip:SetText(title, 1, 0.82, 0)
	GameTooltip:AddLine(text, 1, 1, 1, true)
	GameTooltip:Show()
end

function Handlers.ToggleHover(toggle, hovered)
	toggle.hovered = hovered
	if hovered then
		ShowTooltip(toggle, toggle.name:GetText(), toggle.tooltip)
	else
		GameTooltip:Hide()
	end
	lib:RefreshToolbar()
end

local function CreateButton(toolbar, text, onClick, tooltip, template)
	local button = CreateFrame("Button", nil, toolbar, template or "SharedButtonSmallTemplate")
	button:SetText(text)
	button:SetHeight(BUTTON_HEIGHT)
	button:SetScript("OnClick", onClick)
	button:HookScript("OnEnter", function(self) ShowTooltip(self, self.tooltipTitle or text, tooltip) end)
	button:HookScript("OnLeave", function() GameTooltip:Hide() end)

	return button
end

local function CreateToolbar()
	local toolbar = CreateFrame("Frame", nil, UIParent)
	toolbar:SetFrameStrata("FULLSCREEN_DIALOG")
	toolbar:SetHeight(TOOLBAR_HEIGHT)
	toolbar:EnableMouse(true)
	toolbar:SetMovable(true)
	toolbar:SetClampedToScreen(true)
	toolbar:RegisterForDrag("LeftButton")
	toolbar:SetScript("OnDragStart", function(self) Handlers.ToolbarDragStart(self) end)
	toolbar:SetScript("OnDragStop", function(self) Handlers.ToolbarDragStop(self) end)

	-- The same art as the menus, its top edge raised above the screen so the bar hangs from the top edge.
	lib:ApplyPanelArt(toolbar, TOOLBAR_TOP_HIDDEN)

	toolbar.exit = CreateButton(toolbar, L.EXIT, function() lib:RequestClose(false) end, L.TIP_EXIT)
	toolbar.save = CreateButton(toolbar, L.SAVE_AND_EXIT, function() lib:RequestClose(true) end, L.TIP_SAVE)
	toolbar.separator = toolbar:CreateTexture(nil, "ARTWORK")
	toolbar.separator:SetColorTexture(1, 1, 1, 0.12)
	toolbar.separator:SetSize(1, 30)
	toolbar.buttons = { toolbar.exit, toolbar.save }
	toolbar.grid = CreateToggle(toolbar, L.GRID_LINES, "grid", function()
		lib:SetPreference("grid", GRID_MODES[lib:GetPreference("grid")] or "DIMMED")
		lib:RefreshGrid()
	end, L.TIP_GRID)
	toolbar.fill = CreateToggle(toolbar, L.MOVER_FILL, "dark-overlays", function()
		lib:SetPreference("fill", not lib:GetPreference("fill"))
		lib:RefreshMovers()
	end, L.TIP_FILL)
	toolbar.snap = CreateToggle(toolbar, L.SNAP_ELEMENTS, "snap", function()
		lib:SetPreference("snap", not lib:GetPreference("snap"))
	end, L.TIP_SNAP)
	toolbar.coordinates = CreateToggle(toolbar, L.COORDINATES, "coordinates", function()
		lib:SetPreference("coordinates", not lib:GetPreference("coordinates"))
		lib:RefreshMovers()
	end, L.TIP_COORDINATES)
	toolbar.hoverBar = CreateToggle(toolbar, L.HOVER_TOP_BAR, "hover-top-bar", function()
		lib:SetPreference("hoverBar", not lib:GetPreference("hoverBar"))
		lib:RefreshEffects()
	end, L.TIP_HOVER_TOP_BAR)
	toolbar.addons = CreateToggle(toolbar, L.ADDONS, "addons", function() lib:ToggleAddonsWindow() end, L.TIP_ADDONS)
	toolbar.toggles = { toolbar.grid, toolbar.fill, toolbar.snap, toolbar.coordinates,
		toolbar.hoverBar, toolbar.addons }

	-- Toolbar scale, 100 to 150 percent in steps of 10.
	local function Scale(delta)
		local scale = lib:GetPreference("toolbarScale") or SCALE_MIN
		scale = math.max(SCALE_MIN, math.min(SCALE_MAX, Round((scale + delta) * 10) / 10))
		lib:SetPreference("toolbarScale", scale)
		lib:RefreshToolbar()
	end
	toolbar.smaller = CreateButton(toolbar, "-", function() Scale(-SCALE_STEP) end, L.TIP_SMALLER,
		"SharedButtonExtraSmallTemplate")
	toolbar.smaller.tooltipTitle = L.TOOLBAR_SMALLER
	toolbar.larger = CreateButton(toolbar, "+", function() Scale(SCALE_STEP) end, L.TIP_LARGER,
		"SharedButtonExtraSmallTemplate")
	toolbar.larger.tooltipTitle = L.TOOLBAR_LARGER

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
	local hoverBar = self:GetPreference("hoverBar")
	PaintToggle(toolbar.hoverBar, hoverBar, hoverBar and L.ON or L.OFF, toolbar.hoverBar.hovered)
	local shownCount, total = self:ShownAddonCount()
	PaintToggle(toolbar.addons, true, L.ADDONS_SHOWN:format(shownCount, total), toolbar.addons.hovered)
	-- The Addons toggle appears only when more than one addon registered placement.
	toolbar.addons:SetShown(total > 1)

	-- Every button and every toggle takes the width of the widest of its kind, the toggles measured over all their
	-- states, so nothing shifts when a state changes; the row is centered with equal padding.
	-- Measured once per addon count and kept: measuring again at another scale gives slightly different text
	-- widths, which would make the bar change width while it is used.
	if toolbar.measuredFor ~= total then
		toolbar.measuredFor = total
		local buttonWidth = 0
		for _, button in ipairs(toolbar.buttons) do
			buttonWidth = math.max(buttonWidth, button:GetFontString():GetStringWidth() + 30)
		end
		local toggleWidth = 0
		for _, toggle in ipairs(toolbar.toggles) do
			local current = toggle.state:GetText()
			local labelWidth = math.max(toggle.name:GetStringWidth(), toggle.state:GetStringWidth())
			for _, state in ipairs({ L.ON, L.OFF, L.DIMMED, L.BRIGHT, L.ADDONS_SHOWN:format(total, total) }) do
				toggle.state:SetText(state)
				labelWidth = math.max(labelWidth, toggle.state:GetStringWidth())
			end
			toggle.state:SetText(current)
			toggleWidth = math.max(toggleWidth, 6 + 28 + 8 + labelWidth + 10)
		end
		toolbar.buttonWidth, toolbar.toggleWidth = math.ceil(buttonWidth), math.ceil(toggleWidth)
	end
	local buttonWidth, toggleWidth = toolbar.buttonWidth, toolbar.toggleWidth

	local x = TOOLBAR_PADDING
	local function Place(region, width)
		region:ClearAllPoints()
		region:SetPoint("LEFT", toolbar, "LEFT", x, 0)
		x = x + width + TOOLBAR_GAP
	end
	for _, button in ipairs(toolbar.buttons) do
		button:SetWidth(buttonWidth)
		Place(button, buttonWidth)
	end
	Place(toolbar.separator, 1)
	for _, toggle in ipairs(toolbar.toggles) do
		if toggle:IsShown() then
			toggle:SetWidth(toggleWidth)
			Place(toggle, toggleWidth)
		end
	end
	local scale = self:GetPreference("toolbarScale") or SCALE_MIN
	for _, button in ipairs({ toolbar.smaller, toolbar.larger }) do
		button:SetSize(SCALE_BUTTON_WIDTH, BUTTON_HEIGHT)
		Place(button, SCALE_BUTTON_WIDTH)
	end
	toolbar.smaller:SetEnabled(scale > SCALE_MIN)
	toolbar.larger:SetEnabled(scale < SCALE_MAX)
	toolbar:SetScale(scale)
	toolbar:SetWidth(x - TOOLBAR_GAP + TOOLBAR_PADDING)
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
	if lib.ui.flyout and lib.ui.flyout:IsShown() then
		lib:CloseFlyout()
		lib:ShowGuides(nil, nil)
		return
	end
	if lib.session.pick then
		lib:EndPick()
		return
	end
	if lib:CloseAddonsWindow() then
		return
	end
	if lib:CloseMenus() then
		lib:RefreshMovers()
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
	ui.tint:SetAllPoints(WorldFrame) -- the whole window, including a notch strip above UIParent
	ui.tint:SetColorTexture(unpack(TINT))

	ui.grid = CreateFrame("Frame", nil, ui.screen)
	ui.grid:SetAllPoints()
	ui.grid.lines = {}

	ui.guideLayer = CreateFrame("Frame", nil, ui.screen)
	ui.guideLayer:SetAllPoints()
	ui.guideLayer:SetFrameLevel(ui.screen:GetFrameLevel() + 5)

	ui.pickDim = ui.guideLayer:CreateTexture(nil, "ARTWORK")
	ui.pickDim:SetAllPoints(UIParent)
	ui.pickDim:SetColorTexture(0, 0, 0, 1)
	ui.pickDim:Hide()

	ui.moverLayer = CreateFrame("Frame", nil, ui.screen)
	ui.moverLayer:SetAllPoints()
	ui.moverLayer:SetFrameLevel(ui.screen:GetFrameLevel() + 10)

	ui.toolbar = CreateToolbar()

	return ui
end

function lib:LayoutTopInset()
	self:PlaceToolbar()
end

---Places the toolbar. Docked, it hangs from the top of the screen with its border's top out of view, or sits
---below a notch strip with its whole border; `ui.toolbarSlide` raises it during the opening sequence. Once placed
---elsewhere or dragged (`ui.toolbarSpot`, its bottom left in UIParent units) it shows its whole border.
function lib:PlaceToolbar()
	local ui = self.ui
	if not ui then
		return
	end
	local toolbar = ui.toolbar
	local scale = toolbar:GetScale()
	toolbar:ClearAllPoints()
	if ui.toolbarSpot then
		toolbar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", ui.toolbarSpot.left / scale, ui.toolbarSpot.bottom / scale)
		self:SetPanelTopExtra(toolbar, 0)
	else
		toolbar:SetPoint("TOP", UIParent, "TOP", 0, (ui.toolbarSlide or 0) / scale)
		self:SetPanelTopExtra(toolbar, self:TopInset() > 0 and 0 or TOOLBAR_TOP_HIDDEN)
	end
end

---How far above its docked place the toolbar must start to be wholly out of view, notch strip included.
function lib:ToolbarHiddenOffset()
	local scale = self.ui.toolbar:GetScale()

	return (TOOLBAR_HEIGHT + TOOLBAR_TOP_HIDDEN + 8) * scale + self:TopInset()
end

local function Overlaps(aLeft, aBottom, aRight, aTop, bLeft, bBottom, bRight, bTop)
	return aLeft < bRight and aRight > bLeft and aBottom < bTop and aTop > bBottom
end

---Chooses where the toolbar opens: docked at the top when no shown mover lies there, else the highest free spot
---down the middle of the screen, else docked anyway. Returns nil for docked, or the spot's bottom left.
function lib:FindToolbarSpot()
	local ui = self.ui
	local scale = ui.toolbar:GetScale()
	local width, height = ui.toolbar:GetWidth() * scale, TOOLBAR_HEIGHT * scale
	local parentWidth, parentHeight = UIParent:GetWidth(), UIParent:GetHeight()
	local left = (parentWidth - width) / 2
	local rects = {}
	for _, mover in pairs(ui.movers or {}) do
		if mover:IsShown() and mover:GetLeft() then
			table.insert(rects, { mover:GetLeft() - TOOLBAR_CLEARANCE, mover:GetBottom() - TOOLBAR_CLEARANCE,
				mover:GetRight() + TOOLBAR_CLEARANCE, mover:GetTop() + TOOLBAR_CLEARANCE })
		end
	end
	local function Free(bottom)
		for _, rect in ipairs(rects) do
			if Overlaps(left, bottom, left + width, bottom + height, rect[1], rect[2], rect[3], rect[4]) then
				return false
			end
		end

		return true
	end
	if Free(parentHeight - height) then
		return nil
	end
	for bottom = parentHeight - height - TOOLBAR_SPOT_STEP, 0, -TOOLBAR_SPOT_STEP do
		if Free(bottom) then
			return { left = left, bottom = bottom }
		end
	end

	return nil
end

-- The toolbar's background can be dragged to move it anywhere on screen for the rest of the session.
function Handlers.ToolbarDragStart(toolbar)
	if InCombatLockdown() then
		return
	end
	toolbar:SetDontSavePosition(true)
	toolbar:StartMoving()
end

function Handlers.ToolbarDragStop(toolbar)
	toolbar:StopMovingOrSizing()
	local scale = toolbar:GetScale()
	lib.ui.toolbarSpot = { left = toolbar:GetLeft() * scale, bottom = toolbar:GetBottom() * scale }
	lib:PlaceToolbar()
end

-- Display changes resize UIParent and re-anchor frames after the event, so the screen is laid out again on the
-- next frame and once more shortly after.
local function RelayoutEditScreen()
	if lib.session.open and not lib.session.paused then
		lib:LayoutTopInset()
		lib:RefreshGrid()
		lib:RefreshMovers()
	end
end

---Shows the edit screen; `opening` plays the opening sequence and offers the first-time tip.
function lib:ShowEditUI(opening)
	self.ui = self.ui or BuildEditUI()
	local ui = self.ui
	if opening then
		ui.toolbarSpot = nil
		self:PrepareOpening()
	else
		self:StopOpening()
	end
	ui.screen:Show()
	self:RefreshGrid()
	self:RefreshToolbar()
	self:RefreshMovers()
	if opening then
		ui.toolbarSpot = self:FindToolbarSpot()
	end
	self:LayoutTopInset()
	ui.toolbar:Show()
	self:RefreshEffects()
	self:WatchShift(true)
	if opening then
		self:PlayOpening()
		C_Timer.After(1.3, function()
			if lib.session.open and not lib.session.paused then
				lib:ShowFirstTip()
			end
		end)
	end
end

function lib:HideEditUI()
	if not self.ui then
		return
	end
	self:StopOpening()
	self:HideEmblem()
	self:HideFirstTip()
	self:WatchShift(false)
	self.ui.screen:Hide()
	self.ui.toolbar:Hide()
	self:CloseAddonsWindow()
	self:RefreshEffects()
	self:RefreshMovers()
end

-- The grid follows UI scale and resolution changes while edit mode is open.
local layoutEvents = lib.editLayoutEvents or CreateFrame("Frame")
lib.editLayoutEvents = layoutEvents
layoutEvents:RegisterEvent("UI_SCALE_CHANGED")
layoutEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
layoutEvents:RegisterEvent("NOTCHED_DISPLAY_MODE_CHANGED")
layoutEvents:SetScript("OnEvent", function()
	RelayoutEditScreen()
	C_Timer.After(0, RelayoutEditScreen)
	C_Timer.After(0.25, RelayoutEditScreen)
end)
