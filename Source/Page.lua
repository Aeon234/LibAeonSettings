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
	half.controls = {}
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
	if half.setting then
		half.setting.boundView = nil
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
	view.switch = lib:CreateToggle(header)
	view.switch.frame:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, -SWITCH_TOP)
	view.switchLabel = header:CreateFontString(nil, "OVERLAY")
	lib:SetFont(view.switchLabel, "header", SWITCH_SIZE)
	view.switchLabel:SetTextColor(unpack(GOLD))
	view.switchLabel:SetPoint("RIGHT", view.switch.frame, "LEFT", -SWITCH_GAP, 0)
	view.switchLabel:SetText(L.ENABLED)

	local body = CreateFrame("Frame", nil, content)
	body:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
	body:SetPoint("BOTTOMRIGHT")
	view.body = body
	view.scroll = lib:CreateScroll(body, { step = 60 })

	view.halves = NewPool(function() return CreateHalf(view) end, ResetHalf)
	view.sectionHeaders = NewPool(function() return CreateSectionHeader(view) end)
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
	setting.boundView = control
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
	if view.shownPage then
		self.offsets[view.shownPage.id] = view.scroll.target
	end
	if view.shownPage and view.shownPage.switch then
		view.shownPage.switch.boundView = nil
	end
	ReleaseAll(view.halves)
	ReleaseAll(view.sectionHeaders)
	ReleaseAll(view.notes)
	ReleaseAll(view.lines)
	wipe(view.items)
	view.shownPage = page

	view.title:SetText(page.title)
	view.description:SetText(page.description or "")
	view.description:SetShown(page.description ~= nil)
	local hasSwitch = page.switch ~= nil
	view.switch.frame:SetShown(hasSwitch)
	view.switchLabel:SetShown(hasSwitch)
	if hasSwitch then
		view.switch:Bind(page.switch)
		page.switch.boundView = view.switch
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

	for _, section in ipairs(page.sections or {}) do
		local header = Acquire(view.sectionHeaders)
		header.title:SetText(section.title or "")
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
	view.scroll:JumpTo(self.offsets[page.id] or 0)
end

-- States and layout ------------------------------------------------------------------------------------------

local function RefreshHalf(half)
	local setting, control = half.setting, half.view
	half.shown = setting:IsShown()
	local active, reason, cause = setting:Activity()
	local rowInactive = not active and cause ~= "page"
	-- Desaturate before SetActive, which may set its own (Blizzard's slider dims a step arrow at the range's end).
	local desaturation = rowInactive and INACTIVE_DESATURATION or not active and PAGE_OFF_DESATURATION or 0
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
	control.frame:SetAlpha(rowInactive and INACTIVE_ALPHA or 1)
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
	half.tall = half.small:IsShown()
end

---Redraws which settings on the shown page are active, hidden or explained, and dims the body while the page's
---switch is off.
function lib.Window:RefreshStates()
	local view = self.pageView
	local page = view and view.shownPage
	if not page then
		return
	end
	local pageOff = page.switch ~= nil and not page.switch:GetValue()
	view.scroll.frame:SetAlpha(pageOff and PAGE_OFF_ALPHA or 1)
	for _, item in ipairs(view.items) do
		for index = 1, 2 do
			if item[index] then
				RefreshHalf(item[index])
			end
		end
	end
end

local function PlaceHalf(half, child, left, y, width, height)
	half:ClearAllPoints()
	half:SetPoint("TOPLEFT", child, "TOPLEFT", left, -y)
	half:SetSize(width, height)
	half:SetShown(half.shown)
	local labelWidth = math.max(MIN_LABEL, width - INSET - CONTROL_RIGHT - half.view:GetWidth() - LABEL_GAP)
	half.label:SetWidth(labelWidth)
	half.small:SetWidth(labelWidth)
	half.label:ClearAllPoints()
	if half.tall then
		half.label:SetPoint("TOPLEFT", half, "LEFT", INSET, (LABEL_HEIGHT + SMALL_HEIGHT) / 2)
	else
		half.label:SetPoint("LEFT", half, "LEFT", INSET, 0)
	end
end

local function Rule(view, color, left, top, width, height)
	local texture = Acquire(view.lines)
	texture:SetColorTexture(unpack(color))
	texture:SetPoint("TOPLEFT", view.scroll.child, "TOPLEFT", left, -top)
	texture:SetSize(width, height)
end

---Places the shown page's sections, lines and notes: a line both of whose halves are hidden is left out; a hidden
---half alone keeps its place; a line is taller while either half has a second line.
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
	for _, item in ipairs(view.items) do
		if item.header then
			y = y + SECTION_GAP
			item.header:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
			item.header:SetSize(width, SECTION_TITLE_HEIGHT + 1)
			y = y + SECTION_TITLE_HEIGHT + 1
			previousLine = false
		elseif item.note then
			local note = item.note
			note.text:SetWidth(width - 2 * INSET)
			note.small:SetWidth(width - 2 * INSET)
			local height = NOTE_TOP + note.text:GetStringHeight() + (note.small:IsShown() and note.small:GetStringHeight() or 0)
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
	view.scroll:SetContentHeight(y + BOTTOM_PADDING)
end

---Called when a setting's value changed: redraws its view (sliding unless `instant`; shaking when `refused`),
---then the states and layout of the shown page.
function lib.Window:SettingChanged(setting, instant, refused)
	if not self:IsShown() then
		return
	end
	if setting.boundView then
		setting.boundView:Update(instant, refused)
	end
	self:RefreshStates()
	self:LayoutPage()
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
	for _, item in ipairs(view.items) do
		for index = 1, 2 do
			if item[index] then
				item[index].view:Update(true)
			end
		end
	end
	self:RefreshStates()
	self:LayoutPage()
end
