-- The page body: the page header (title, description, the page's switch), then its sections, lines and notes in
-- a smooth scrolling list. Rows are pooled halves; each half keeps one view per control kind and binds it to the
-- setting it shows.
--
-- Control views (see Toggle.lua) provide: `.frame`, `Bind(setting)` (draw at once), `Update(instant, refused)`,
-- `Release()`, `SetActive(active)`, `GetWidth()`; optionally `Desaturate(amount)` and `Place(half)`.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

-- Kit values (Bronze Hearth).
local PAGE_LEFT, PAGE_TOP, PAGE_RIGHT, PAGE_BOTTOM = 284, 42, 42, 58
local DEFAULT_WIDTH = 1005
local TITLE_SIZE, TITLE_HEIGHT = 32, 34
local DESCRIPTION_SIZE, DESCRIPTION_GAP = 14, 6
local SWITCH_SIZE, SWITCH_GAP, SWITCH_TOP = 16, 12, 4
local SECTION_GAP, SECTION_TITLE_SIZE, SECTION_TITLE_HEIGHT = 14, 18, 30
local SECTION_RULE_ALPHA = 0.9
local MENU_CENTER = 15 -- the section title's center line, from the header's top
local ROW_HEIGHT, TALL_HEIGHT = 44, 52
local INSET, CONTROL_RIGHT, LABEL_GAP, MIN_LABEL = 20, 64, 12, 80
local LABEL_SIZE, LABEL_HEIGHT, SMALL_SIZE, SMALL_HEIGHT = 14, 17, 12, 15
local NOTE_TOP, NOTE_SIZE, NOTE_LINE = 10, 14, 20
local BOTTOM_PADDING = 14
local ROW_LINE = { 1, 1, 1, 0.06 }
local HALF_LINE = { 1, 1, 1, 0.12 }
local GOLD = { 1, 0.82, 0 }
local DESCRIPTION_COLOR = { 1, 1, 1, 0.72 }
local REASON_COLOR = { 1, 0.549, 0.471, 0.85 }
local INACTIVE_ALPHA, INACTIVE_DESATURATION = 0.5, 0.7
local PAGE_OFF_ALPHA, PAGE_OFF_DESATURATION = 0.5, 0.6
-- Overrides (Q30, Q70): the ◆/↺ gutter, reserved on every half between the control and the inset.
local GUTTER_RIGHT, GUTTER_WIDTH, GUTTER_HEIGHT = 20, 44, 16
local DIAMOND_SIZE, UNDO_SIZE, UNDO_ALPHA = 14, 16, 0.85
local INHERITED_COLOR = { 0.961, 0.824, 0.478, 0.85 }
local RESET_SOUND = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
local HOVER_MARGIN = 4 -- the label's hover region reaches this far past its text lines
local TOOLTIP_REASON = { 1, 0.25, 0.25 }

lib.PageHandlers = lib.PageHandlers or {}
local Handlers = lib.PageHandlers

-- Pools ------------------------------------------------------------------------------------------------------

local function NewPool(create, reset)
	return { create = create, reset = reset, free = {}, used = {} }
end

local function Acquire(pool)
	local object = table.remove(pool.free) or pool.create()
	pool.used[#pool.used + 1] = object
	object:Show()

	return object
end

local function ReleaseAll(pool)
	for index = #pool.used, 1, -1 do
		local object = pool.used[index]
		if pool.reset then
			pool.reset(object)
		end
		object:Hide()
		object:ClearAllPoints()
		pool.free[#pool.free + 1] = object
		pool.used[index] = nil
	end
end

-- Desaturates every texture under a frame, for control views without their own `Desaturate`.
local function DesaturateRegions(amount, ...)
	for index = 1, select("#", ...) do
		local region = select(index, ...)
		if region:IsObjectType("Texture") then
			region:SetDesaturation(amount)
		end
	end
end

local function DesaturateTree(frame, amount)
	DesaturateRegions(amount, frame:GetRegions())
	for index = 1, select("#", frame:GetChildren()) do
		DesaturateTree((select(index, frame:GetChildren())), amount)
	end
end

-- Building ---------------------------------------------------------------------------------------------------

local function CreateHalf(view)
	local half = CreateFrame("Frame", nil, view.scroll.child)
	half.label = half:CreateFontString(nil, "OVERLAY")
	lib:SetFont(half.label, "body", LABEL_SIZE)
	half.label:SetJustifyH("LEFT")
	half.label:SetWordWrap(false)
	half.label:SetHeight(LABEL_HEIGHT)
	half.small = half:CreateFontString(nil, "OVERLAY")
	lib:SetFont(half.small, "body", SMALL_SIZE)
	half.small:SetJustifyH("LEFT")
	half.small:SetWordWrap(false)
	half.small:SetHeight(SMALL_HEIGHT)
	half.small:SetPoint("TOPLEFT", half.label, "BOTTOMLEFT")
	-- An overridden row's inherited value ("Whole Bar: 12"), under the label and any description.
	half.inherited = half:CreateFontString(nil, "OVERLAY")
	lib:SetFont(half.inherited, "body", SMALL_SIZE)
	half.inherited:SetTextColor(unpack(INHERITED_COLOR))
	half.inherited:SetJustifyH("LEFT")
	half.inherited:SetWordWrap(false)
	half.inherited:SetHeight(SMALL_HEIGHT)
	half.controls = {}
	-- Over the label and the lines under it: hovering shows the setting's tooltip (C-03).
	half.hover = CreateFrame("Frame", nil, half)
	half.hover:EnableMouse(true)
	half.hover:SetScript("OnEnter", function() Handlers.LabelEnter(half) end)
	half.hover:SetScript("OnLeave", function() Handlers.LabelLeave(half) end)
	half.hover:SetScript("OnHide", function() Handlers.LabelLeave(half) end)

	local gutter = CreateFrame("Frame", nil, half)
	gutter:SetSize(GUTTER_WIDTH, GUTTER_HEIGHT)
	gutter:SetPoint("RIGHT", -GUTTER_RIGHT, 0)
	gutter:Hide()
	local diamond = CreateFrame("Frame", nil, gutter)
	diamond:SetSize(DIAMOND_SIZE, DIAMOND_SIZE)
	diamond:SetPoint("LEFT", 2, 0)
	diamond:EnableMouse(true)
	local diamondArt = diamond:CreateTexture(nil, "ARTWORK")
	diamondArt:SetTexture(lib.mediaPath .. "Textures\\override-diamond")
	diamondArt:SetAllPoints()
	diamond:SetScript("OnEnter", function() Handlers.DiamondEnter(half) end)
	diamond:SetScript("OnLeave", GameTooltip_Hide)
	local undo = CreateFrame("Button", nil, gutter)
	undo:SetSize(UNDO_SIZE, UNDO_SIZE)
	undo:SetPoint("RIGHT")
	undo:SetNormalAtlas("common-icon-undo")
	undo:GetNormalTexture():SetAlpha(UNDO_ALPHA)
	undo:SetHighlightAtlas("common-icon-undo", "ADD")
	undo:GetHighlightTexture():SetAlpha(0.3)
	undo:SetScript("OnClick", function() Handlers.Undo(half) end)
	undo:SetScript("OnEnter", function() Handlers.UndoEnter(half) end)
	undo:SetScript("OnLeave", GameTooltip_Hide)
	half.gutter, half.diamond, half.undo = gutter, diamond, undo
	-- Over an inactive control: takes its clicks and hover.
	half.blocker = CreateFrame("Frame", nil, half)
	half.blocker:EnableMouse(true)
	half.blocker:Hide()

	return half
end

local function ResetHalf(half)
	if half.view then
		half.view:Release()
		half.view.frame:Hide()
	end
	half.setting, half.view = nil, nil
end

local function CreateSectionHeader(view)
	local header = CreateFrame("Frame", nil, view.scroll.child)
	header.title = header:CreateFontString(nil, "OVERLAY")
	lib:SetFont(header.title, "header", SECTION_TITLE_SIZE)
	header.title:SetTextColor(unpack(GOLD))
	header.title:SetJustifyH("LEFT")
	header.title:SetPoint("TOPLEFT")
	header.title:SetPoint("TOPRIGHT")
	header.title:SetHeight(SECTION_TITLE_HEIGHT)
	header.rule = header:CreateTexture(nil, "ARTWORK")
	header.rule:SetAtlas("Options_HorizontalDivider")
	header.rule:SetAlpha(SECTION_RULE_ALPHA)
	header.rule:SetHeight(1)
	header.rule:SetPoint("BOTTOMLEFT")
	header.rule:SetPoint("BOTTOMRIGHT")

	return header
end

-- A section header's menu goes back to the pool with its header: its list and any question close.
local function ResetSectionHeader(header)
	if header.menu then
		header.menu:Release()
		header.menu.frame:Hide()
		header.menu.blocker:Hide()
	end
	header.menuSetting = nil
end

-- Shows a section's menu on its title line, right-aligned on the title's center line, or hides the header's.
local function BindSectionMenu(view, header, section)
	local setting = section.menu
	if not setting then
		return
	end
	local menu = header.menu
	if not menu then
		menu = lib.controls.Dropdown.Create(header)
		-- Over an inactive menu: takes its clicks and shows the reason on hover.
		menu.blocker = CreateFrame("Frame", nil, header)
		menu.blocker:EnableMouse(true)
		menu.blocker:SetAllPoints(menu.frame)
		menu.blocker:SetScript("OnEnter", function() Handlers.MenuBlockerEnter(header) end)
		menu.blocker:SetScript("OnLeave", GameTooltip_Hide)
		menu.blocker:Hide()
		header.menu = menu
	end
	menu.frame:ClearAllPoints()
	menu.frame:SetPoint("RIGHT", header, "TOPRIGHT", 0, -MENU_CENTER)
	menu:Bind(setting)
	menu.frame:Show()
	menu.blocker:SetFrameLevel(menu.frame:GetFrameLevel() + 10)
	header.menuSetting = setting
	view.menuOf[setting] = menu
end

local function CreateNote(view)
	local note = CreateFrame("Frame", nil, view.scroll.child)
	note.text = note:CreateFontString(nil, "OVERLAY")
	lib:SetFont(note.text, "body", NOTE_SIZE)
	note.text:SetJustifyH("LEFT")
	note.text:SetSpacing(NOTE_LINE - NOTE_SIZE)
	note.text:SetPoint("TOPLEFT", INSET, -NOTE_TOP)
	note.small = note:CreateFontString(nil, "OVERLAY")
	lib:SetFont(note.small, "body", SMALL_SIZE)
	note.small:SetTextColor(unpack(DESCRIPTION_COLOR))
	note.small:SetJustifyH("LEFT")
	note.small:SetPoint("TOPLEFT", note.text, "BOTTOMLEFT")

	return note
end

local function BuildPageView(window)
	local frame = window.frame
	local view = {}
	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", frame, "TOPLEFT", PAGE_LEFT, -PAGE_TOP)
	content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAGE_RIGHT, PAGE_BOTTOM)
	view.content = content

	local header = CreateFrame("Frame", nil, content)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	view.header = header
	view.title = header:CreateFontString(nil, "OVERLAY")
	lib:SetFont(view.title, "header", TITLE_SIZE)
	view.title:SetTextColor(unpack(GOLD))
	view.title:SetJustifyH("LEFT")
	view.title:SetHeight(TITLE_HEIGHT)
	view.title:SetPoint("TOPLEFT")
	view.description = header:CreateFontString(nil, "OVERLAY")
	lib:SetFont(view.description, "body", DESCRIPTION_SIZE)
	view.description:SetTextColor(unpack(DESCRIPTION_COLOR))
	view.description:SetJustifyH("LEFT")
	view.description:SetPoint("TOPLEFT", view.title, "BOTTOMLEFT", 0, -DESCRIPTION_GAP)

	-- The page's switch, top right: "Enabled" and a toggle.
	view.switch = lib:CreateToggle(header, true)
	view.switch.frame:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, -SWITCH_TOP)
	view.switchLabel = header:CreateFontString(nil, "OVERLAY")
	lib:SetFont(view.switchLabel, "header", SWITCH_SIZE)
	view.switchLabel:SetTextColor(unpack(GOLD))
	view.switchLabel:SetPoint("RIGHT", view.switch.frame, "LEFT", -SWITCH_GAP, 0)
	view.switchLabel:SetText(L.ENABLED)

	-- The preview and tabs, between the header and the scrolling sections (Preview.lua), which places the body.
	lib:BuildFixedArea(window, view)
	local body = CreateFrame("Frame", nil, content)
	body:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
	body:SetPoint("BOTTOMRIGHT")
	view.body = body
	view.scroll = lib:CreateScroll(body, { step = 60 })

	view.halves = NewPool(function() return CreateHalf(view) end, ResetHalf)
	view.sectionHeaders = NewPool(function() return CreateSectionHeader(view) end, ResetSectionHeader)
	view.notes = NewPool(function() return CreateNote(view) end)
	view.lines = NewPool(function() return view.scroll.child:CreateTexture(nil, "BORDER") end)
	view.items = {}
	window.pageView = view
	window.offsets = window.offsets or {}

	return view
end

local function BindHalf(view, setting)
	local half = Acquire(view.halves)
	local kind = setting.kind
	local control = half.controls[kind]
	if not control then
		control = lib.controls[kind].Create(half)
		half.controls[kind] = control
	end
	for _, other in pairs(half.controls) do
		other.frame:SetShown(other == control)
	end
	half.setting, half.view = setting, control
	view.halfOf[setting] = half
	control.frame:ClearAllPoints()
	if control.Place then
		control:Place(half)
	else
		control.frame:SetPoint("RIGHT", half, "RIGHT", -CONTROL_RIGHT, 0)
	end
	control:Bind(setting)
	half.label:SetText(setting.label or "")
	half.blocker:ClearAllPoints()
	half.blocker:SetAllPoints(control.frame)
	half.blocker:SetFrameLevel(control.frame:GetFrameLevel() + 10)

	return half
end

---Shows the selected page: its header, then its sections drawn from pooled views, at the scroll offset it last had.
function lib.Window:ShowPage()
	local page = self.pages[self.page]
	if not self.frame or not page then
		return
	end
	local view = self.pageView or BuildPageView(self)
	-- Each page (and each of its tabs) keeps its own scroll offset for the session.
	if view.shownKey then
		self.offsets[view.shownKey] = view.scroll.target
	end
	if view.flash then
		view.flash:Hide()
	end
	ReleaseAll(view.halves)
	ReleaseAll(view.sectionHeaders)
	ReleaseAll(view.notes)
	ReleaseAll(view.lines)
	wipe(view.items)
	-- The shown page's rows by setting and section headers by section; settings and sections hold no frames.
	view.halfOf, view.headerOf = view.halfOf or {}, view.headerOf or {}
	view.menuOf = view.menuOf or {}
	wipe(view.menuOf)
	wipe(view.halfOf)
	wipe(view.headerOf)
	view.shownPage = page

	view.title:SetText(page.title)
	view.description:SetText(page.description or "")
	view.description:SetShown(page.description ~= nil)
	local hasSwitch = page.switch ~= nil
	view.switch.frame:SetShown(hasSwitch)
	view.switchLabel:SetShown(hasSwitch)
	if hasSwitch then
		view.switch:Bind(page.switch)
	else
		view.switch:Release()
	end
	local width = view.content:GetWidth()
	if width <= 1 then
		width = DEFAULT_WIDTH
	end
	view.description:SetWidth(width - (hasSwitch and 200 or 0))
	view.header:SetHeight(TITLE_HEIGHT
		+ (page.description and DESCRIPTION_GAP + view.description:GetStringHeight() or 0))

	local sections = page:ShownSections()
	view.shownKey = page.tab and (page.id .. "/" .. page.tab) or page.id
	self:ShowFixedArea(page)
	for _, section in ipairs(sections) do
		local header = Acquire(view.sectionHeaders)
		header.title:SetText(section.title or "")
		header.section = section
		header.shown = nil
		view.headerOf[section] = header
		BindSectionMenu(view, header, section)
		self:RefreshSectionLink(header, section)
		view.items[#view.items + 1] = { header = header }
		for _, line in ipairs(section.lines) do
			if line.note then
				local note = Acquire(view.notes)
				note.text:SetText(line.note.text or "")
				note.small:SetText(line.note.small or "")
				note.small:SetShown(line.note.small ~= nil)
				view.items[#view.items + 1] = { note = note }
			else
				local item = { wide = line.wide }
				for index = 1, 2 do
					local entry = line[index]
					if entry and entry ~= lib.EMPTY then
						item[index] = BindHalf(view, entry)
					end
				end
				view.items[#view.items + 1] = item
			end
		end
	end

	self:RefreshStates()
	self:LayoutPage()
	view.scroll:JumpTo(self.offsets[view.shownKey] or 0)
end

-- States and layout ------------------------------------------------------------------------------------------

---Redraws one row's state. Returns true when its visibility or height changed, so the page needs laying out again.
local function RefreshHalf(half)
	local setting, control = half.setting, half.view
	local wasShown, wasLines = half.shown, half.lines
	half.shown = setting:IsShown()
	local active, reason, cause = setting:Activity()
	local rowInactive = not active and cause ~= "page" and cause ~= "class"
	-- A swatch following the class color dims only its control: the label stays and needs no reason.
	local controlDimmed = rowInactive or cause == "class"
	-- Desaturate before SetActive, which may set its own (Blizzard's slider dims a step arrow at the range's end).
	local desaturation = controlDimmed and INACTIVE_DESATURATION or not active and PAGE_OFF_DESATURATION or 0
	if control.desaturation ~= desaturation then
		control.desaturation = desaturation
		if control.Desaturate then
			control:Desaturate(desaturation)
		else
			DesaturateTree(control.frame, desaturation)
		end
	end
	control:SetActive(active)
	half.blocker:SetShown(not active)
	half.label:SetAlpha(rowInactive and INACTIVE_ALPHA or 1)
	-- A row following the shared value looks ordinary; changing it overrides it (◆, ↺, the inherited line).
	-- A resettable row changed from its default shows ↺ alone, in the same place.
	local overridden = setting:IsOverridden()
	local changed = not overridden and setting:IsChangedFromDefault()
	control.frame:SetAlpha(controlDimmed and INACTIVE_ALPHA or 1)
	half.gutter:SetShown(overridden or changed)
	half.diamond:SetShown(overridden)
	half.gutter:SetAlpha(rowInactive and INACTIVE_ALPHA or 1)
	half.undo:SetEnabled(active)
	if overridden then
		half.inherited:SetFormattedText("%s: %s", setting.inherits.from, setting:FormatValue(setting:InheritedValue()))
		half.inherited:Show()
	else
		half.inherited:Hide()
	end
	if rowInactive and reason then
		half.small:SetText(reason)
		half.small:SetTextColor(unpack(REASON_COLOR))
		half.small:Show()
	elseif setting.description then
		half.small:SetText(setting.description)
		half.small:SetTextColor(unpack(DESCRIPTION_COLOR))
		half.small:Show()
	else
		half.small:Hide()
	end
	-- A row that can be overridden always keeps room for the inherited line, so overriding never resizes it or
	-- moves its label.
	half.lines = (half.small:IsShown() and 1 or 0) + (setting.inherits and 1 or 0)
	half.tall = half.lines > 0
	half.inherited:ClearAllPoints()
	half.inherited:SetPoint("TOPLEFT", half.small:IsShown() and half.small or half.label, "BOTTOMLEFT")

	-- An open tooltip follows the row's state under the pointer.
	if half.tooltipShown then
		Handlers.LabelEnter(half)
	end

	return half.shown ~= wasShown or half.lines ~= wasLines
end

---Redraws which settings on the shown page are active, hidden or explained, and dims the body while the page's
---switch is off. Returns true when a row's visibility or height changed.
---@return boolean layoutChanged
function lib.Window:RefreshStates()
	local view = self.pageView
	local page = view and view.shownPage
	if not page then
		return false
	end
	local pageOff = page.switch ~= nil and not page.switch:GetValue()
	view.scroll.frame:SetAlpha(pageOff and PAGE_OFF_ALPHA or 1)
	-- Section menus: dimmed and closed while inactive, their reason on hover; closed while their section is hidden.
	for setting, menu in pairs(view.menuOf) do
		local active, reason = setting:Activity()
		active = active and setting.section:IsShown()
		menu:SetActive(active)
		menu.frame:SetAlpha(active and 1 or INACTIVE_ALPHA)
		menu.blocker:SetShown(not active)
		menu.reason = reason
	end
	local layoutChanged = false
	for _, item in ipairs(view.items) do
		local header = item.header
		if header then
			local shown = header.section:IsShown()
			if shown ~= header.shown then
				header.shown = shown
				layoutChanged = true
			end
		end
		for index = 1, 2 do
			if item[index] and RefreshHalf(item[index]) then
				layoutChanged = true
			end
		end
	end

	return layoutChanged
end

local function PlaceHalf(half, child, left, y, width, height)
	half:ClearAllPoints()
	half:SetPoint("TOPLEFT", child, "TOPLEFT", left, -y)
	half.top = y
	half:SetSize(width, height)
	half:SetShown(half.shown)
	local labelWidth = math.max(MIN_LABEL, width - INSET - CONTROL_RIGHT - half.view:GetWidth() - LABEL_GAP)
	half.label:SetWidth(labelWidth)
	half.small:SetWidth(labelWidth)
	half.inherited:SetWidth(labelWidth)
	half.label:ClearAllPoints()
	if half.tall then
		half.label:SetPoint("TOPLEFT", half, "LEFT", INSET, (LABEL_HEIGHT + SMALL_HEIGHT * half.lines) / 2)
	else
		half.label:SetPoint("LEFT", half, "LEFT", INSET, 0)
	end
	local last = half.inherited:IsShown() and half.inherited or half.small:IsShown() and half.small or half.label
	half.hover:ClearAllPoints()
	half.hover:SetPoint("TOPLEFT", half.label, "TOPLEFT", -HOVER_MARGIN, HOVER_MARGIN)
	half.hover:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", HOVER_MARGIN, -HOVER_MARGIN)
end

local function Rule(view, color, left, top, width, height)
	local texture = Acquire(view.lines)
	texture:SetColorTexture(unpack(color))
	texture:SetPoint("TOPLEFT", view.scroll.child, "TOPLEFT", left, -top)
	texture:SetSize(width, height)
end

---Places the shown page's sections, lines and notes: a hidden section is left out with its notes (its rows are
---hidden through their settings); a line both of whose halves are hidden is left out; a hidden half alone keeps its
---place; a line is taller while either half has a second line.
function lib.Window:LayoutPage()
	local view = self.pageView
	if not view or not view.shownPage then
		return
	end
	local child = view.scroll.child
	local width = view.scroll.frame:GetWidth()
	if width <= 1 then
		width = DEFAULT_WIDTH
	end
	local leftWidth = math.floor(width / 2)
	ReleaseAll(view.lines)
	local y, previousLine = 0, false
	local open -- the section header whose rows are being laid out, so each section knows where it ends
	local hidden = false -- the section being laid out is hidden
	for _, item in ipairs(view.items) do
		if item.header then
			if open then
				open.bottom = y
			end
			hidden = item.header.shown == false
			item.header:SetShown(not hidden)
			open = not hidden and item.header or nil
		end
		if hidden then
			if item.note then
				item.note:Hide()
			end
			for index = 1, 2 do
				if item[index] then
					item[index]:Hide()
				end
			end
		elseif item.header then
			y = y + SECTION_GAP
			item.header.top = y
			item.header:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
			item.header:SetSize(width, SECTION_TITLE_HEIGHT + 1)
			y = y + SECTION_TITLE_HEIGHT + 1
			previousLine = false
		elseif item.note then
			local note = item.note
			note.text:SetWidth(width - 2 * INSET)
			note.small:SetWidth(width - 2 * INSET)
			local height = NOTE_TOP + note.text:GetStringHeight() + (note.small:IsShown() and note.small:GetStringHeight() or 0)
			note:Show()
			note:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
			note:SetSize(width, height)
			y = y + height
			previousLine = false
		else
			local first, second = item[1], item[2]
			local shown = (first and first.shown) or (second and second.shown)
			if not shown then
				for index = 1, 2 do
					if item[index] then
						item[index]:Hide()
					end
				end
			else
				if previousLine then
					Rule(view, ROW_LINE, 0, y, width, 1)
					y = y + 1
				end
				local height = ROW_HEIGHT
				for index = 1, 2 do
					local half = item[index]
					if half and half.shown then
						if half.tall then
							height = math.max(height, TALL_HEIGHT)
						end
						if half.setting.height then
							height = math.max(height, half.setting.height + 16)
						end
					end
				end
				if item.wide then
					PlaceHalf(first, child, 0, y, width, height)
				else
					if first then
						PlaceHalf(first, child, 0, y, leftWidth, height)
					end
					if second then
						PlaceHalf(second, child, leftWidth, y, width - leftWidth, height)
					end
					Rule(view, HALF_LINE, leftWidth, y, 1, height)
				end
				y = y + height
				previousLine = true
			end
		end
	end
	if open then
		open.bottom = y
	end
	view.scroll:SetContentHeight(y + BOTTOM_PADDING)
end

---The row drawing a setting on the shown page, or nil.
function lib.Window:RowOf(setting)
	local view = self.pageView

	return view and view.halfOf and view.halfOf[setting]
end

---The header drawn for a section on the shown page, or nil.
function lib.Window:HeaderOf(section)
	local view = self.pageView

	return view and view.headerOf and view.headerOf[section]
end

---The control drawing a setting on the shown page (a row's control, or the page's switch), or nil.
function lib.Window:ControlOf(setting)
	local view = self.pageView
	if not view or not view.halfOf then
		return nil
	end
	if view.shownPage and setting == view.shownPage.switch then
		return view.switch
	end
	local half = view.halfOf[setting]

	return half and half.view or view.menuOf and view.menuOf[setting]
end

---Called when a setting's value changed: redraws its view at once (sliding unless `instant`; shaking when
---`refused`). The rest of the shown page follows on the next frame, once however many values change before it.
function lib.Window:SettingChanged(setting, instant, refused)
	if not self:IsShown() then
		return
	end
	local control = self:ControlOf(setting)
	if control then
		control:Update(instant, refused)
	end
	self.changedSettings = self.changedSettings or {}
	self.changedSettings[setting] = true
	if not self.flushQueued then
		self.flushQueued = true
		C_Timer.After(0, function() self:FlushChanges() end)
	end
end

---Redraws what follows from the values changed since the last call: rows following a shared value, the shown page's
---states, its layout when a row's visibility or height changed, and the fixed area.
function lib.Window:FlushChanges()
	self.flushQueued = nil
	local changed = self.changedSettings
	if not changed or not next(changed) then
		return
	end
	local view = self.pageView
	if self:IsShown() and view and view.shownPage then
		-- A setting marked `redraws` may change what other rows show (a picked slot): every row redraws.
		for setting in pairs(changed) do
			if setting.redraws then
				self:Refresh()
				return
			end
		end
		-- Rows following a shared value redraw it, in case one of the changes was the shared value.
		for _, item in ipairs(view.items) do
			for index = 1, 2 do
				local half = item[index]
				if half and not changed[half.setting] and half.setting.inherits and not half.setting:IsOverridden() then
					half.view:Update(true)
				end
			end
		end
		if self:RefreshStates() then
			self:LayoutPage()
		end
		self:RefreshFixedArea()
	end
	wipe(changed)
end

-- Overrides ---------------------------------------------------------------------------------------------------

-- ◆ names the shared value the row overrides.
-- The label's tooltip (C-03): no title; the full label when it is cut off, the setting's `tooltip`, then the line
-- under the label (description or inactive reason) and the inherited line when they are cut off. Nothing to show,
-- no tooltip.
function Handlers.LabelEnter(half)
	local setting = half.setting
	if not setting then
		return
	end
	local lines = {}
	if half.label:IsTruncated() then
		lines[#lines + 1] = { half.label:GetText(), 1, 1, 1 }
	end
	local tooltip = setting.tooltip
	if type(tooltip) == "function" then
		tooltip = lib.CallAdopter(tooltip, setting)
	end
	if type(tooltip) == "string" and tooltip ~= "" then
		lines[#lines + 1] = { tooltip, 1, 1, 1 }
	end
	if half.small:IsShown() and half.small:IsTruncated() then
		local reason = select(2, setting:Activity())
		local red = reason and half.small:GetText() == reason
		lines[#lines + 1] = { half.small:GetText(), unpack(red and TOOLTIP_REASON or { 1, 1, 1 }) }
	end
	if half.inherited:IsShown() and half.inherited:IsTruncated() then
		lines[#lines + 1] = { half.inherited:GetText(), unpack(INHERITED_COLOR, 1, 3) }
	end
	if #lines == 0 then
		Handlers.LabelLeave(half)
		return
	end
	GameTooltip:SetOwner(half.hover, "ANCHOR_TOP")
	for _, line in ipairs(lines) do
		GameTooltip:AddLine(line[1], line[2], line[3], line[4], true)
	end
	GameTooltip:Show()
	-- Every line is body text: the first takes the body font while this tooltip shows.
	GameTooltipTextLeft1:SetFontObject(GameTooltipText)
	GameTooltipTextRight1:SetFontObject(GameTooltipText)
	half.tooltipShown = true
end

function Handlers.LabelLeave(half)
	if not half.tooltipShown then
		return
	end
	half.tooltipShown = nil
	GameTooltipTextLeft1:SetFontObject(GameTooltipHeaderText)
	GameTooltipTextRight1:SetFontObject(GameTooltipHeaderText)
	if GameTooltip:IsOwned(half.hover) then
		GameTooltip:Hide()
	end
end

function Handlers.MenuBlockerEnter(header)
	local menu = header.menu
	if not menu or not menu.reason then
		return
	end
	GameTooltip:SetOwner(menu.blocker, "ANCHOR_TOP")
	GameTooltip:SetText(menu.reason, REASON_COLOR[1], REASON_COLOR[2], REASON_COLOR[3], 1, true)
	GameTooltip:Show()
end

function Handlers.DiamondEnter(half)
	local setting = half.setting
	if not setting or not setting.inherits then
		return
	end
	GameTooltip:SetOwner(half.gutter, "ANCHOR_TOP")
	GameTooltip:SetText(L.OVERRIDDEN, 1, 0.82, 0)
	GameTooltip:AddLine(("%s: %s"):format(setting.inherits.from, setting:FormatValue(setting:InheritedValue())), 1, 1, 1)
	GameTooltip:Show()
end

function Handlers.UndoEnter(half)
	local setting = half.setting
	if not setting or not (setting.inherits or setting.resettable) then
		return
	end
	GameTooltip:SetOwner(half.gutter, "ANCHOR_TOP")
	GameTooltip:SetText(L.RESET_TO:format(setting.inherits and setting.inherits.from or DEFAULT or "Default"), 1, 1, 1)
	GameTooltip:Show()
end

-- ↺ returns the row to the shared value, or a resettable row to its default.
function Handlers.Undo(half)
	local setting = half.setting
	if not setting then
		return
	end
	if setting:IsOverridden() then
		PlaySound(RESET_SOUND)
		GameTooltip:Hide()
		setting:Reset()
	elseif setting:IsChangedFromDefault() then
		PlaySound(RESET_SOUND)
		GameTooltip:Hide()
		setting:ResetToDefault()
	end
end

---Redraws every value on the shown page at once, for values the adopter changed elsewhere.
function lib.Window:Refresh()
	local view = self.pageView
	if not self:IsShown() or not view or not view.shownPage then
		return
	end
	if view.shownPage.switch then
		view.switch:Update(true)
	end
	for _, menu in pairs(view.menuOf) do
		menu:Update(true)
	end
	for _, item in ipairs(view.items) do
		for index = 1, 2 do
			if item[index] then
				item[index].view:Update(true)
			end
		end
	end
	self:RefreshStates()
	self:LayoutPage()
	self:RefreshFixedArea()
	-- Everything a queued flush would redraw is current now.
	if self.changedSettings then
		wipe(self.changedSettings)
	end
end
