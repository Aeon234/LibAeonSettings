-- The page body: the page header (title, description, and the page's switch as a card of its own), then its
-- preview and tabs and its sections in a smooth scrolling list. A section is a heading over a card of rows, one
-- setting to a line (or two to a line in a choice card), with its notes under the card. Rows are pooled halves; each
-- half keeps one view per control kind and binds it to the setting it shows.
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
local DEFAULT_WIDTH = 674 -- the 1000-wide window less the page's insets
local TITLE_HEIGHT = 30
local DESCRIPTION_GAP = 6
local SWITCH_GAP, SWITCH_ICON, SWITCH_ICON_GAP = 14, 20, 10 -- the switch card: below the title, its icon
local BODY_RESPONSE = 0.32 -- the page below its switch fading away while the switch is off, and back
local SECTION_GAP, SECTION_TITLE_HEIGHT = 18, 30 -- the heading's line also holds a section's menu and link
local HEADING_INSET, HEADING_BOTTOM = 14, 6 -- the heading's text: in from the card's edge, above the card
local MENU_CENTER = 15 -- the section title's center line, from the header's top
local ROW_HEIGHT, TALL_HEIGHT = 44, 52
local INSET, CONTROL_RIGHT, LABEL_GAP, MIN_LABEL = lib.ROW_INSET, lib.CONTROL_RIGHT, 12, 80
local LABEL_HEIGHT, SMALL_HEIGHT = 17, 15
local NOTE_TOP, NOTE_LINE = 7, 16 -- a note under its card: the gap above it and its line height
local BOTTOM_PADDING = 14
local REVEAL_RESPONSE = 0.32 -- a row growing in under the row it depends on, or shrinking away
local INACTIVE_ALPHA, INACTIVE_DESATURATION = 0.5, 0.7
local PAGE_OFF_DESATURATION = 0.6
-- Overrides (Q30, Q70): the ◆/↺ gutter, reserved on every half between the control and the inset.
local GUTTER_RIGHT, GUTTER_WIDTH, GUTTER_HEIGHT = 20, 44, 16
local DIAMOND_SIZE, UNDO_SIZE, UNDO_ALPHA = 14, 16, 0.85
local RESET_SOUND = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
local HOVER_MARGIN = 4 -- the label's hover region reaches this far past its text lines
local TOOLTIP_GAP = 2 -- the label's tooltip sits this far above its row

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
	half.pageView = view
	half.label = half:CreateFontString(nil, "OVERLAY")
	lib:SetType(half.label, "body")
	half.label:SetJustifyH("LEFT")
	half.label:SetWordWrap(false)
	half.label:SetHeight(LABEL_HEIGHT)
	half.small = half:CreateFontString(nil, "OVERLAY")
	lib:SetType(half.small, "secondary", "secondary")
	half.small:SetJustifyH("LEFT")
	half.small:SetWordWrap(false)
	half.small:SetHeight(SMALL_HEIGHT)
	half.small:SetPoint("TOPLEFT", half.label, "BOTTOMLEFT")
	-- An overridden row's inherited value ("Whole Bar: 12"), under the label and any description.
	half.inherited = half:CreateFontString(nil, "OVERLAY")
	lib:SetType(half.inherited, "secondary", "secondary")
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
	if half.reveal then
		half.reveal:Stop()
	end
	half.setting, half.view, half.want, half.revealed, half.grid, half.reason = nil, nil, nil, nil, nil, nil
	half.looksInactive, half.looksReason = nil, nil
	half:SetAlpha(1)
	half:SetClipsChildren(false)
end

local function CreateSectionHeader(view)
	local header = CreateFrame("Frame", nil, view.scroll.child)
	header.title = header:CreateFontString(nil, "OVERLAY")
	lib:SetType(header.title, "heading", "heading")
	header.title:SetJustifyH("LEFT")
	header.title:SetJustifyV("BOTTOM")
	header.title:SetPoint("TOPLEFT", HEADING_INSET, 0)
	header.title:SetPoint("TOPRIGHT")
	header.title:SetHeight(SECTION_TITLE_HEIGHT - HEADING_BOTTOM)

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
	lib:SetType(note.text, "secondary", "secondary")
	note.text:SetJustifyH("LEFT")
	note.text:SetSpacing(NOTE_LINE - lib.TYPE.secondary[2])
	note.text:SetPoint("TOPLEFT", HEADING_INSET, -NOTE_TOP)
	note.small = note:CreateFontString(nil, "OVERLAY")
	lib:SetType(note.small, "secondary", "secondary")
	note.small:SetJustifyH("LEFT")
	note.small:SetSpacing(NOTE_LINE - lib.TYPE.secondary[2])
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
	lib:SetType(view.title, "title", "cream")
	view.title:SetJustifyH("LEFT")
	view.title:SetHeight(TITLE_HEIGHT)
	view.title:SetPoint("TOPLEFT")
	view.description = header:CreateFontString(nil, "OVERLAY")
	lib:SetType(view.description, "body", "secondary")
	view.description:SetJustifyH("LEFT")
	view.description:SetPoint("TOPLEFT", view.title, "BOTTOMLEFT", 0, -DESCRIPTION_GAP)

	-- The page's switch, a card of its own under the title: the page's icon, its name and what it does, and a toggle.
	local card = CreateFrame("Frame", nil, header)
	local fill = card:CreateTexture(nil, "BACKGROUND")
	fill:SetColorTexture(lib:GetColor("card"))
	fill:SetAllPoints()
	for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
		{ "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local line = card:CreateTexture(nil, "BORDER")
		line:SetColorTexture(lib:GetColor("cardEdge"))
		line:SetPoint(edge[1])
		line:SetPoint(edge[2])
		line:SetSize(1, 1)
	end
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(SWITCH_ICON, SWITCH_ICON)
	card.icon:SetPoint("LEFT", INSET, 0)
	card.label = card:CreateFontString(nil, "OVERLAY")
	lib:SetType(card.label, "body")
	card.label:SetJustifyH("LEFT")
	card.label:SetWordWrap(false)
	card.small = card:CreateFontString(nil, "OVERLAY")
	lib:SetType(card.small, "secondary", "secondary")
	card.small:SetJustifyH("LEFT")
	card.small:SetWordWrap(false)
	card.small:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT")
	view.switch = lib:CreateToggle(card)
	view.switch.frame:SetPoint("RIGHT", -INSET, 0)
	view.switchCard = card

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
	view.fills = NewPool(function() return view.scroll.child:CreateTexture(nil, "BACKGROUND") end)
	view.items = {}
	view.window = window
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
---`growIn`: the page was just switched on, so what is below its switch fades in.
---@param growIn boolean?
function lib.Window:ShowPage(growIn)
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
	local switch = page.switch
	-- With a switch, the page's description moves onto the switch's card unless the switch has its own.
	local switchText = switch and (switch.description or page.description)
	local description = not (switch and not switch.description) and page.description or nil
	view.description:SetText(description or "")
	view.description:SetShown(description ~= nil)
	local width = view.content:GetWidth()
	if width <= 1 then
		width = DEFAULT_WIDTH
	end
	view.description:SetWidth(width)
	local headerHeight = TITLE_HEIGHT + (description and DESCRIPTION_GAP + view.description:GetStringHeight() or 0)
	local card = view.switchCard
	card:SetShown(switch ~= nil)
	if switch then
		view.switch:Bind(switch)
		card.label:SetText(switch.label or page.title)
		card.small:SetText(switchText or "")
		card.small:SetShown(switchText ~= nil)
		local hasIcon = page.icon ~= nil
		card.icon:SetShown(hasIcon)
		if hasIcon then
			if C_Texture.GetAtlasInfo(page.icon) then
				card.icon:SetAtlas(page.icon)
			else
				local crop = page.iconCrop or 0
				card.icon:SetTexture(page.icon)
				card.icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
			end
		end
		local textLeft = INSET + (hasIcon and SWITCH_ICON + SWITCH_ICON_GAP or 0)
		local textWidth = width - textLeft - INSET - view.switch:GetWidth() - LABEL_GAP
		card.label:SetWidth(textWidth)
		card.small:SetWidth(textWidth)
		card.label:ClearAllPoints()
		local cardHeight = switchText and TALL_HEIGHT or ROW_HEIGHT
		if switchText then
			card.label:SetPoint("TOPLEFT", card, "LEFT", textLeft, (LABEL_HEIGHT + SMALL_HEIGHT) / 2)
		else
			card.label:SetPoint("LEFT", textLeft, 0)
		end
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", view.header, "TOPLEFT", 0, -(headerHeight + SWITCH_GAP))
		card:SetPoint("TOPRIGHT", view.header, "TOPRIGHT", 0, -(headerHeight + SWITCH_GAP))
		card:SetHeight(cardHeight)
		headerHeight = headerHeight + SWITCH_GAP + cardHeight
	else
		view.switch:Release()
	end
	view.header:SetHeight(headerHeight)

	-- Below a switch that is off, nothing is built until it is first turned on.
	local on = not switch or switch:GetValue() and true or false
	view.built = on
	local presence = Handlers.BodyPresence(view)
	if growIn then
		presence:Jump(0)
		presence:To(1)
	else
		presence:Jump(on and 1 or 0)
	end
	if not on then
		self:StopPreview()
		view.shownKey = page.tab and (page.id .. "/" .. page.tab) or page.id
		view.scroll:SetContentHeight(0)
		Handlers.Announce(self, view, page)
		return
	end

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
		local block = { header = header, rows = {}, notes = {}, grid = lib.ChoiceGrid(self, section) }
		for _, line in ipairs(section.lines) do
			if line.note then
				local note = Acquire(view.notes)
				note.text:SetText(line.note.text or "")
				note.small:SetText(line.note.small or "")
				note.small:SetShown(line.note.small ~= nil)
				table.insert(block.notes, note)
			else
				for index = 1, 2 do
					local entry = line[index]
					if entry and entry ~= lib.EMPTY then
						local half = BindHalf(view, entry)
						half.grid = block.grid
						table.insert(block.rows, half)
					end
				end
			end
		end
		if not block.grid then
			lib.OrderUnderParents(block.rows)
		end
		view.items[#view.items + 1] = block
	end

	-- Rows take their first state without moving.
	view.settling = true
	self:RefreshStates()
	view.settling = nil
	self:LayoutPage()
	view.scroll:JumpTo(self.offsets[view.shownKey] or 0)
	Handlers.Announce(self, view, page)
end

-- Tells adopters which page (and tab) shows, once per page or tab, and again after the window reopens.
function Handlers.Announce(window, view, page)
	if view.announced ~= view.shownKey then
		view.announced = view.shownKey
		lib:Fire("OnPageShown", window.addonName, page.id, page.tab)
	end
end

-- States and layout ------------------------------------------------------------------------------------------

---Redraws one row's state. Returns true when its visibility or height changed, so the page needs laying out again.
local function RefreshHalf(half)
	local setting, control = half.setting, half.view
	local wasWant, wasLines = half.want, half.lines
	local active, reason, cause = setting:Activity()
	-- A row whose parent in its own card is off leaves, under that parent; a choice-card row stays, dimmed.
	half.want = setting:IsShown() and not (cause == "depends" and not half.grid and lib.ParentOffInSection(setting))
	local rowInactive = not active and cause ~= "page" and cause ~= "class"
	-- A row on its way out keeps the look it had, so its exit shows no dimming or inactive reason; its control still
	-- stops answering at once.
	local leaving = not half.want and (half.revealed or 0) > 0
	local looksInactive, looksReason = rowInactive, reason
	if leaving then
		looksInactive, looksReason = half.looksInactive, half.looksReason
	else
		half.looksInactive, half.looksReason = rowInactive, reason
	end
	-- A swatch following the class color dims only its control: the label stays and needs no reason.
	local controlDimmed = looksInactive or cause == "class"
	-- Desaturate before SetActive, which may set its own (Blizzard's slider dims a step arrow at the range's end).
	local desaturation = controlDimmed and INACTIVE_DESATURATION or not active and not leaving and PAGE_OFF_DESATURATION
		or 0
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
	half.label:SetAlpha(looksInactive and INACTIVE_ALPHA or 1)
	-- A row following the shared value looks ordinary; changing it overrides it (◆, ↺, the inherited line).
	-- A resettable row changed from its default shows ↺ alone, in the same place.
	local overridden = setting:IsOverridden()
	local changed = not overridden and setting:IsChangedFromDefault()
	control.frame:SetAlpha(controlDimmed and INACTIVE_ALPHA or 1)
	half.gutter:SetShown(overridden or changed)
	half.diamond:SetShown(overridden)
	half.gutter:SetAlpha(looksInactive and INACTIVE_ALPHA or 1)
	half.undo:SetEnabled(active)
	if overridden then
		half.inherited:SetFormattedText("%s: %s", setting.inherits.from, setting:FormatValue(setting:InheritedValue()))
		half.inherited:Show()
	else
		half.inherited:Hide()
	end
	-- A choice-card row has no second line: its reason shows in its tooltip.
	half.reason = rowInactive and reason or nil
	if half.grid then
		half.small:Hide()
		half.inherited:Hide()
	elseif looksInactive and looksReason then
		half.small:SetText(looksReason)
		half.small:SetTextColor(lib:GetColor("destructive"))
		half.small:Show()
	elseif setting.description then
		half.small:SetText(setting.description)
		half.small:SetTextColor(lib:GetColor("secondary"))
		half.small:Show()
	else
		half.small:Hide()
	end
	-- A row that can be overridden always keeps room for the inherited line, so overriding never resizes it or
	-- moves its label.
	half.lines = half.grid and 0 or (half.small:IsShown() and 1 or 0) + (setting.inherits and 1 or 0)
	half.tall = half.lines > 0
	half.inherited:ClearAllPoints()
	half.inherited:SetPoint("TOPLEFT", half.small:IsShown() and half.small or half.label, "BOTTOMLEFT")

	-- An open tooltip follows the row's state under the pointer.
	if half.tooltipShown then
		Handlers.LabelEnter(half)
	end

	Handlers.Reveal(half)

	return half.want ~= wasWant or half.lines ~= wasLines
end

-- Moves a row toward its wanted visibility: at once while the page settles or the window is hidden, else on a
-- spring that lays the page out again on every step. `revealed` runs 0 (gone) to 1 (full height).
function Handlers.Reveal(half)
	local target = half.want and 1 or 0
	local view = half.pageView
	if not half.reveal then
		half.reveal = lib:CreateSpring(target, function(value)
			half.revealed = value
			if not half.settling then
				half.pageView.window:LayoutPage()
			end
		end, { response = REVEAL_RESPONSE, epsilon = 0.002 })
	end
	if half.revealed == nil or view.settling or half.grid or not view.window:IsShown() then
		half.settling = true
		half.reveal:Jump(target)
		half.settling = nil
	elseif half.reveal.target ~= target then
		half.reveal:To(target)
	end
end

---Redraws which settings on the shown page are active, hidden or explained, and dims the body while the page's
---Returns true when a row's visibility or height changed.
---@return boolean layoutChanged
function lib.Window:RefreshStates()
	local view = self.pageView
	local page = view and view.shownPage
	if not page then
		return false
	end
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
	for _, block in ipairs(view.items) do
		local header = block.header
		local shown = header.section:IsShown()
		if shown ~= header.shown then
			header.shown = shown
			layoutChanged = true
		end
		for _, half in ipairs(block.rows) do
			if RefreshHalf(half) then
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
	half:Show()
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

local function Rule(view, color, left, top, width, height, alpha)
	local texture = Acquire(view.lines)
	texture:SetColorTexture(color[1], color[2], color[3], (color[4] or 1) * (alpha or 1))
	texture:SetPoint("TOPLEFT", view.scroll.child, "TOPLEFT", left, -top)
	texture:SetSize(width, height)
end

---Places the shown page's sections: each a heading, a card holding its rows one to a line (two in a choice card),
---then its notes under the card. A hidden section is left out with its rows and notes; a row growing in or leaving
---takes its share of its height, faded by as much.
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
	ReleaseAll(view.lines)
	ReleaseAll(view.fills)
	local y = 0
	for _, block in ipairs(view.items) do
		local header = block.header
		if header.shown == false then
			header:Hide()
			header.top, header.bottom = nil, nil
			for _, half in ipairs(block.rows) do
				half:Hide()
			end
			for _, note in ipairs(block.notes) do
				note:Hide()
			end
		else
			y = y + SECTION_GAP
			header:Show()
			header.top = y
			header:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
			header:SetSize(width, SECTION_TITLE_HEIGHT)
			y = y + SECTION_TITLE_HEIGHT
			local cardTop = y
			if block.grid then
				y = Handlers.LayoutGrid(view, block.rows, child, width, y)
			else
				local previous = false
				for _, half in ipairs(block.rows) do
					local share = half.revealed or 0
					if share <= 0 then
						half:Hide()
					else
						-- The separator above and the row shrink together, unrounded, so a row ends without a step.
						if previous then
							Rule(view, lib.COLOR.separator, INSET, y, width - INSET, 1, share)
							y = y + share
						end
						local height = half.tall and TALL_HEIGHT or ROW_HEIGHT
						if half.setting.height then
							height = math.max(height, half.setting.height + 16)
						end
						height = height * share
						PlaceHalf(half, child, 0, y, width, height)
						-- Not clipped: a row clipping its children while it grows in from nothing draws none of them
						-- until it is whole. Its content fades with the square of its share instead, so it stays faint
						-- while the row is too short to hold it.
						half:SetAlpha(share * share)
						y = y + height
						previous = true
					end
				end
			end
			if y > cardTop then
				Handlers.Card(view, cardTop, width, y - cardTop)
			end
			header.bottom = y
			for _, note in ipairs(block.notes) do
				local textWidth = width - 2 * HEADING_INSET
				note.text:SetWidth(textWidth)
				note.small:SetWidth(textWidth)
				local height = NOTE_TOP + note.text:GetStringHeight()
					+ (note.small:IsShown() and note.small:GetStringHeight() or 0)
				note:Show()
				note:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
				note:SetSize(width, height)
				y = y + height
			end
		end
	end
	view.scroll:SetContentHeight(y + BOTTOM_PADDING)
end

-- What lies below the page's switch (preview, tabs and sections), 0 gone to 1 shown, on a spring: it fades, and
-- hides at rest at 0.
function Handlers.BodyPresence(view)
	if not view.bodyPresence then
		view.bodyPresence = lib:CreateSpring(1, function(value)
			local shown = value > 0
			view.body:SetAlpha(value)
			view.body:SetShown(shown)
			view.fixed:SetAlpha(value)
			view.fixed:SetShown(shown)
		end, { response = BODY_RESPONSE, epsilon = 0.002 })
	end

	return view.bodyPresence
end

-- A card behind a section's rows: a faint fill inside a 1-unit edge.
function Handlers.Card(view, top, width, height)
	local fill = Acquire(view.fills)
	fill:SetColorTexture(lib:GetColor("card"))
	fill:SetPoint("TOPLEFT", view.scroll.child, "TOPLEFT", 0, -top)
	fill:SetSize(width, height)
	fill:Show()
	Rule(view, lib.COLOR.cardEdge, 0, top, width, 1)
	Rule(view, lib.COLOR.cardEdge, 0, top + height - 1, width, 1)
	Rule(view, lib.COLOR.cardEdge, 0, top + 1, 1, height - 2)
	Rule(view, lib.COLOR.cardEdge, width - 1, top + 1, 1, height - 2)
end

-- A choice card's rows, two to a line, left to right then down; a hidden row gives up its place. Returns the y
-- below the last line.
function Handlers.LayoutGrid(view, rows, child, width, y)
	local columnWidth = math.floor(width / 2)
	local column, lineTop, first = 0, y, true
	for _, half in ipairs(rows) do
		if not half.want then
			half:Hide()
		else
			if column == 0 then
				if not first then
					Rule(view, lib.COLOR.separator, INSET, y, width - INSET, 1)
					y = y + 1
				end
				lineTop, first = y, false
			else
				Rule(view, lib.COLOR.separator, columnWidth, lineTop, 1, ROW_HEIGHT)
			end
			PlaceHalf(half, child, column * columnWidth, lineTop, column == 0 and columnWidth or width - columnWidth,
				ROW_HEIGHT)
			half:SetAlpha(1)
			half:SetClipsChildren(false)
			y = lineTop + ROW_HEIGHT
			column = 1 - column
		end
	end

	return y
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
		-- The page's switch: the rest of the page fades away while it is off, and is built the first time it is on.
		local switch = view.shownPage.switch
		if switch and changed[switch] then
			self:PaintSidebar()
			if switch:GetValue() and not view.built then
				wipe(changed)
				self:ShowPage(true)
				return
			end
			Handlers.BodyPresence(view):To(switch:GetValue() and 1 or 0)
		end
		-- Rows following a shared value redraw it, in case one of the changes was the shared value.
		for _, block in ipairs(view.items) do
			for _, half in ipairs(block.rows) do
				if not changed[half.setting] and half.setting.inherits and not half.setting:IsOverridden() then
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
		lines[#lines + 1] = { half.small:GetText(), lib:GetColor(red and "destructive" or "text") }
	end
	if half.grid and half.reason then
		lines[#lines + 1] = { half.reason, lib:GetColor("destructive") }
	end
	if half.inherited:IsShown() and half.inherited:IsTruncated() then
		lines[#lines + 1] = { half.inherited:GetText(), 1, 1, 1 }
	end
	if #lines == 0 then
		Handlers.LabelLeave(half)
		return
	end
	-- Above the row, its left edge on the label's, wherever the row's control sits and however wide it is.
	GameTooltip:SetOwner(half.hover, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint("BOTTOMLEFT", half, "TOPLEFT", INSET, TOOLTIP_GAP)
	-- Every line is body text: the first takes the body font while this tooltip shows, set before Show sizes the
	-- tooltip so its width fits the font drawn.
	GameTooltipTextLeft1:SetFontObject(GameTooltipText)
	GameTooltipTextRight1:SetFontObject(GameTooltipText)
	half.tooltipShown = true
	for _, line in ipairs(lines) do
		GameTooltip:AddLine(line[1], line[2], line[3], line[4], true)
	end
	GameTooltip:Show()
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
	local r, g, b = lib:GetColor("destructive")
	GameTooltip:SetText(menu.reason, r, g, b, 1, true)
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
	local switch = view.shownPage.switch
	if switch then
		view.switch:Update(true)
		self:PaintSidebar()
		if (switch:GetValue() and true or false) ~= view.built then
			self:ShowPage()
			return
		end
	end
	for _, menu in pairs(view.menuOf) do
		menu:Update(true)
	end
	for _, block in ipairs(view.items) do
		for _, half in ipairs(block.rows) do
			half.view:Update(true)
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
