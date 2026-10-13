-- The page's fixed part between its header and its scrolling sections: the Preview (the adopter draws a sample
-- into a canvas the library shrinks to fit, with state pills and a caption) and the page tabs (Blizzard's Options
-- tabs), allowed in two cases only: the same settings for different targets, and large parts sharing one preview.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

-- Kit values (Bronze Hearth).
local PREVIEW_GAP, PREVIEW_HEIGHT, CAPTION_HEIGHT = 18, 84, 16
local SECTION_TITLE_SIZE, SECTION_TITLE_HEIGHT = 18, 30
local ROOM_X, ROOM_Y = 24, 8 -- the canvas keeps this much of the stage free when it shrinks
local PILL_SIZE, PILL_PAD, PILL_HEIGHT, PILL_GAP, PILL_TOP = 12, 10, 18, 2, 4
local PILL_LINE = { 1, 1, 1, 0.12 }
local PILL_ON_LINE = { 0.620, 0.459, 0.290, 1 }
local PILL_ON_FILL = { 0.620, 0.459, 0.290, 0.2 }
local TAB_GAP, TAB_TOP, TAB_HEIGHT, TAB_ACTIVE_HEIGHT = 4, 18, 23, 26
local TAB_PAD, TAB_CAP, TAB_SIZE, TAB_FIRST = 18, 7, 15, 4
local GOLD = { 1, 0.82, 0 }
local DESCRIPTION_COLOR = { 1, 1, 1, 0.72 }
local TAB_TEXT = { 1, 1, 1, 0.75 }
local TAB_SOUND = SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB
local PREVIEW_FIELDS = { height = true, states = true, create = true, refresh = true, caption = true }

local Handlers = {}
lib.PreviewHandlers = Handlers
lib.Tab = {}
local tabMeta = { __index = function(_, name) return lib.Tab[name] end }

-- Model ------------------------------------------------------------------------------------------------------

---Gives the page a Preview above its sections. `info`: `height` (the stage, 84 by default); `states` (a list of
---names, or a function returning the ones that apply now; pills show when more than one does); `create(canvas,
---preview)` once; `refresh(canvas, state, preview)` on every change, returning the sample's natural width and
---height (the canvas shrinks to fit the stage); `caption(state, scale)` returning a line under the stage.
function lib.PageModel:Preview(info)
	info = info or {}
	for field in pairs(info) do
		if not PREVIEW_FIELDS[field] then
			lib:Report(self.window.addonName, ("%s: unknown preview field %q"):format(self.id, tostring(field)))
		end
	end
	self.preview = info

	return info
end

---Adds a tab to the page; its sections are declared with `tab:Section(id, title)`. `info.countOverrides` shows
---how many of the tab's settings are overridden.
function lib.PageModel:Tab(id, title, info)
	self.tabs = self.tabs or {}
	local tab = setmetatable({ id = id, title = title, page = self, sections = {},
		countOverrides = info and info.countOverrides }, tabMeta)
	table.insert(self.tabs, tab)

	return tab
end

function lib.Tab:Section(id, title)
	local section = self.page:Section(id, title)
	section.tab = self
	table.insert(self.sections, section)

	return section
end

---@return integer count overridden settings in the tab's sections
function lib.Tab:CountOverrides()
	local count = 0
	for _, section in ipairs(self.sections) do
		for _, line in ipairs(section.lines) do
			for index = 1, 2 do
				local entry = line[index]
				if type(entry) == "table" and entry.IsOverridden and entry:IsOverridden() then
					count = count + 1
				end
			end
		end
	end

	return count
end

---The sections the page view shows: the selected tab's, or all of the page's.
function lib.PageModel:ShownSections()
	if not self.tabs then
		return self.sections
	end
	local selected = self.tabs[1]
	for _, tab in ipairs(self.tabs) do
		if tab.id == self.tab then
			selected = tab
		end
	end
	self.tab = selected.id

	return selected.sections
end

-- Building ---------------------------------------------------------------------------------------------------

local function CreatePill(fixed)
	local pill = CreateFrame("Button", nil, fixed.preview)
	pill:SetHeight(PILL_HEIGHT)
	pill.fill = pill:CreateTexture(nil, "BACKGROUND")
	pill.fill:SetAllPoints()
	pill.edges = {}
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
		local edge = pill:CreateTexture(nil, "BORDER")
		edge:SetPoint(side[1])
		edge:SetPoint(side[2])
		if side[3] then
			edge:SetHeight(1)
		else
			edge:SetWidth(1)
		end
		table.insert(pill.edges, edge)
	end
	pill.text = pill:CreateFontString(nil, "OVERLAY")
	lib:SetFont(pill.text, "body", PILL_SIZE)
	pill.text:SetPoint("CENTER")
	pill:SetScript("OnClick", function(self) Handlers.PillClick(fixed.window, self.state) end)
	pill:SetScript("OnEnter", function(self) if not self.on then self.text:SetTextColor(1, 1, 1) end end)
	pill:SetScript("OnLeave", function(self) Handlers.PaintPill(self) end)

	return pill
end

function Handlers.PaintPill(pill)
	local line = pill.on and PILL_ON_LINE or PILL_LINE
	for _, edge in ipairs(pill.edges) do
		edge:SetColorTexture(unpack(line))
	end
	pill.fill:SetColorTexture(unpack(pill.on and PILL_ON_FILL or { 0, 0, 0, 0 }))
	pill.text:SetTextColor(unpack(pill.on and GOLD or DESCRIPTION_COLOR))
end

local function TabPiece(tab, layer)
	local texture = tab:CreateTexture(nil, layer)
	texture:SetPoint("BOTTOM")

	return texture
end

local function CreateTab(fixed)
	local tab = CreateFrame("Button", nil, fixed.tabs)
	tab.left, tab.middle, tab.right = TabPiece(tab, "BACKGROUND"), TabPiece(tab, "BACKGROUND"), TabPiece(tab, "BACKGROUND")
	tab.left:ClearAllPoints()
	tab.left:SetPoint("BOTTOMLEFT")
	tab.left:SetPoint("TOPLEFT")
	tab.left:SetWidth(TAB_CAP)
	tab.right:ClearAllPoints()
	tab.right:SetPoint("BOTTOMRIGHT")
	tab.right:SetPoint("TOPRIGHT")
	tab.right:SetWidth(TAB_CAP)
	tab.middle:ClearAllPoints()
	tab.middle:SetPoint("TOPLEFT", tab.left, "TOPRIGHT")
	tab.middle:SetPoint("BOTTOMRIGHT", tab.right, "BOTTOMLEFT")
	tab.text = tab:CreateFontString(nil, "OVERLAY")
	lib:SetFont(tab.text, "body", TAB_SIZE)
	tab.text:SetPoint("CENTER", 0, -1)
	tab:SetScript("OnClick", function(self) Handlers.TabClick(fixed.window, self.tabId) end)
	tab:SetScript("OnEnter", function(self) if not self.on then self.text:SetTextColor(1, 1, 1) end end)
	tab:SetScript("OnLeave", function(self) Handlers.PaintTab(self) end)

	return tab
end

function Handlers.PaintTab(tab)
	local prefix = tab.on and "Options_Tab_Active_" or "Options_Tab_"
	tab.left:SetAtlas(prefix .. "Left")
	tab.middle:SetAtlas(prefix .. "Middle")
	tab.right:SetAtlas(prefix .. "Right")
	tab:SetHeight(tab.on and TAB_ACTIVE_HEIGHT or TAB_HEIGHT)
	tab:SetFrameLevel(tab:GetParent():GetFrameLevel() + (tab.on and 2 or 1))
	tab.text:SetTextColor(unpack(tab.on and GOLD or TAB_TEXT))
end

---Builds the fixed part of the page view: called by the page view when it is built.
function lib:BuildFixedArea(window, view)
	local fixed = CreateFrame("Frame", nil, view.content)
	fixed:SetPoint("TOPLEFT", view.header, "BOTTOMLEFT")
	fixed:SetPoint("TOPRIGHT", view.header, "BOTTOMRIGHT")
	fixed:SetHeight(1)
	fixed.window = window

	local preview = CreateFrame("Frame", nil, fixed)
	preview:SetPoint("TOPLEFT")
	preview:SetPoint("TOPRIGHT")
	preview.title = preview:CreateFontString(nil, "OVERLAY")
	lib:SetFont(preview.title, "header", SECTION_TITLE_SIZE)
	preview.title:SetTextColor(unpack(GOLD))
	preview.title:SetPoint("TOPLEFT", 0, -PREVIEW_GAP)
	preview.title:SetHeight(SECTION_TITLE_HEIGHT)
	preview.title:SetText(L.PREVIEW)
	preview.rule = preview:CreateTexture(nil, "ARTWORK")
	preview.rule:SetAtlas("Options_HorizontalDivider")
	preview.rule:SetAlpha(0.9)
	preview.rule:SetHeight(1)
	preview.rule:SetPoint("TOPLEFT", 0, -(PREVIEW_GAP + SECTION_TITLE_HEIGHT))
	preview.rule:SetPoint("TOPRIGHT", 0, -(PREVIEW_GAP + SECTION_TITLE_HEIGHT))
	preview.stage = CreateFrame("Frame", nil, preview)
	preview.stage:SetPoint("TOPLEFT", 0, -(PREVIEW_GAP + SECTION_TITLE_HEIGHT + 1))
	preview.stage:SetPoint("TOPRIGHT", 0, -(PREVIEW_GAP + SECTION_TITLE_HEIGHT + 1))
	preview.stage:SetClipsChildren(true)
	preview.caption = preview:CreateFontString(nil, "OVERLAY")
	lib:SetFont(preview.caption, "body", 12)
	preview.caption:SetTextColor(unpack(DESCRIPTION_COLOR))
	preview.caption:SetPoint("TOPLEFT", preview.stage, "BOTTOMLEFT")
	preview.caption:SetPoint("TOPRIGHT", preview.stage, "BOTTOMRIGHT")
	preview.caption:SetHeight(CAPTION_HEIGHT)
	preview.pills = {}
	fixed.preview = preview

	local tabs = CreateFrame("Frame", nil, fixed)
	tabs:SetPoint("LEFT")
	tabs:SetPoint("RIGHT")
	tabs:SetHeight(TAB_TOP + TAB_ACTIVE_HEIGHT + 1)
	tabs.rule = tabs:CreateTexture(nil, "ARTWORK")
	tabs.rule:SetAtlas("Options_HorizontalDivider")
	tabs.rule:SetHeight(1)
	tabs.rule:SetPoint("BOTTOMLEFT")
	tabs.rule:SetPoint("BOTTOMRIGHT")
	tabs.buttons = {}
	fixed.tabs = tabs

	view.fixed = fixed

	return fixed
end

-- Showing ----------------------------------------------------------------------------------------------------

local function States(page)
	local states = page.preview.states
	if type(states) == "function" then
		states = lib.CallAdopter(states, page.preview)
	end

	return type(states) == "table" and states or {}
end

---Lays out the fixed part for the shown page: the preview with its pills, then the tabs. Returns its height.
function lib.Window:ShowFixedArea(page)
	local view = self.pageView
	local fixed = view.fixed
	local preview, tabs = fixed.preview, fixed.tabs
	local height = 0

	preview:SetShown(page.preview ~= nil)
	if page.preview then
		local stageHeight = page.preview.height or PREVIEW_HEIGHT
		preview.stage:SetHeight(stageHeight)
		local previewHeight = PREVIEW_GAP + SECTION_TITLE_HEIGHT + 1 + stageHeight + CAPTION_HEIGHT
		preview:SetHeight(previewHeight)
		-- One canvas per page, made the first time its preview shows; others are hidden.
		for _, other in pairs(self.pages) do
			if other.previewCanvas and other ~= page then
				other.previewCanvas:Hide()
			end
		end
		if not page.previewCanvas then
			page.previewCanvas = CreateFrame("Frame", nil, preview.stage)
			page.previewCanvas:SetPoint("CENTER")
			page.previewCanvas:SetSize(1, 1)
			if page.preview.create then
				lib.CallAdopter(page.preview.create, page.previewCanvas, page.preview)
			end
		end
		page.previewCanvas:Show()
		height = previewHeight
	end

	tabs:SetShown(page.tabs ~= nil)
	if page.tabs then
		tabs:ClearAllPoints()
		tabs:SetPoint("TOPLEFT", fixed, "TOPLEFT", 0, -height)
		tabs:SetPoint("TOPRIGHT", fixed, "TOPRIGHT", 0, -height)
		height = height + TAB_TOP + TAB_ACTIVE_HEIGHT + 1
	end
	fixed:SetHeight(math.max(1, height))
	view.body:ClearAllPoints()
	view.body:SetPoint("TOPLEFT", fixed, "BOTTOMLEFT", 0, height > 0 and 0 or 1)
	view.body:SetPoint("BOTTOMRIGHT", view.content, "BOTTOMRIGHT")
	self:RefreshFixedArea()
end

---Redraws the pills, the sample (shrunk to fit, with its caption) and the tab labels; runs after every change.
function lib.Window:RefreshFixedArea()
	local view = self.pageView
	local page = view and view.shownPage
	if not page then
		return
	end
	local fixed = view.fixed
	if page.preview then
		local preview = fixed.preview
		local states = States(page)
		local current = page.previewState
		local found = false
		for _, state in ipairs(states) do
			found = found or state == current
		end
		if not found then
			current = states[1]
			page.previewState = current
		end
		-- Pills, right-aligned on the Preview title's line, only when there is a choice.
		local right = 0
		for index = #states, 1, -1 do
			local pill = preview.pills[index] or CreatePill(fixed)
			preview.pills[index] = pill
			pill.state, pill.on = states[index], states[index] == current
			pill.text:SetText(states[index])
			pill:SetWidth(math.ceil(pill.text:GetUnboundedStringWidth()) + 2 * PILL_PAD)
			pill:ClearAllPoints()
			pill:SetPoint("TOPRIGHT", preview, "TOPRIGHT", -right, -(PREVIEW_GAP + PILL_TOP))
			right = right + pill:GetWidth() + PILL_GAP
			Handlers.PaintPill(pill)
			pill:SetShown(#states > 1)
		end
		for index = #states + 1, #preview.pills do
			preview.pills[index]:Hide()
		end

		local canvas = page.previewCanvas
		local width, height
		if page.preview.refresh then
			width, height = lib.CallAdopter(page.preview.refresh, canvas, current, page.preview)
		end
		width, height = tonumber(width) or 1, tonumber(height) or 1
		canvas:SetSize(width, height)
		local roomWidth = preview.stage:GetWidth() - ROOM_X
		local roomHeight = preview.stage:GetHeight() - ROOM_Y
		local scale = math.min(1, roomWidth / width, roomHeight / height)
		canvas:SetScale(math.max(0.05, scale))
		local caption
		if page.preview.caption then
			caption = lib.CallAdopter(page.preview.caption, current, scale)
		end
		if not caption and scale < 0.999 then
			caption = L.PREVIEW_SHRUNK:format(math.floor(scale * 100 + 0.5))
		end
		preview.caption:SetText(caption or "")
	end

	if page.tabs then
		local tabs = fixed.tabs
		local x = TAB_FIRST
		for index, tab in ipairs(page.tabs) do
			local button = tabs.buttons[index] or CreateTab(fixed)
			tabs.buttons[index] = button
			button.tabId, button.on = tab.id, tab.id == page.tab
			local title = tab.title
			local count = tab.countOverrides and tab:CountOverrides() or 0
			if count > 0 then
				title = ("%s |T%sTextures\\override-diamond:11:11:0:0|t%d"):format(title, lib.mediaPath, count)
			end
			button.text:SetText(title)
			button:SetWidth(math.ceil(button.text:GetUnboundedStringWidth()) + 2 * TAB_PAD)
			button:ClearAllPoints()
			button:SetPoint("BOTTOMLEFT", tabs, "BOTTOMLEFT", x, 1)
			x = x + button:GetWidth() + TAB_GAP
			Handlers.PaintTab(button)
			button:Show()
		end
		for index = #page.tabs + 1, #tabs.buttons do
			tabs.buttons[index]:Hide()
		end
	end
end

function Handlers.PillClick(window, state)
	local page = window.pageView and window.pageView.shownPage
	if page and page.previewState ~= state then
		page.previewState = state
		PlaySound(TAB_SOUND)
		window:RefreshFixedArea()
	end
end

function Handlers.TabClick(window, tabId)
	local page = window.pageView and window.pageView.shownPage
	if page and page.tab ~= tabId then
		page.tab = tabId
		PlaySound(TAB_SOUND)
		window:ShowPage()
	end
end
