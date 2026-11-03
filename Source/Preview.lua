-- The page's fixed part between its header and its scrolling sections: the Preview (the adopter draws a sample
-- into a canvas on a card the page's full width and at most a third of its height, with state pills and a caption)
-- and the page tabs (Blizzard's Options tabs), allowed in two cases only: the same settings for different targets,
-- and large parts sharing one preview. A sample too big for the card shrinks, down to half its size (an editor's,
-- whose parts are clicked and dragged, down to 0.85); past that it scrolls sideways. The sample's parts find their
-- settings: hovering one outlines it in gold, a left click lands on its row.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

-- Kit values (Bronze Hearth).
local PREVIEW_GAP, PREVIEW_HEIGHT, CAPTION_HEIGHT = 18, 84, 16
local SECTION_TITLE_HEIGHT = 30
local ROOM_X, ROOM_Y = 24, 8 -- the canvas keeps this much of the stage free when it shrinks
local LOOK_LEAST, EDITOR_LEAST = 0.5, 0.85 -- the smallest a sample shrinks to before it scrolls sideways instead
local HEADING_INSET, HEADING_BOTTOM = 14, 6 -- the Preview heading, placed as a section's
local WHEEL_STEP, EDGE_WIDTH = 60, 24 -- sideways scrolling: per wheel notch, and the faded edge over hidden sample
local PILL_PAD, PILL_HEIGHT, PILL_GAP, PILL_TOP = 12, 24, 2, 1
local PILL_ART = "common-button-tertiary-%s-small" -- Blizzard's filter buttons: normal, hover, pressed, selected
local TAB_GAP, TAB_TOP, TAB_HEIGHT, TAB_ACTIVE_HEIGHT = 4, 18, 23, 26
local TAB_PAD, TAB_CAP, TAB_FIRST = 18, 7, 4
local TAB_HOVER, TAB_PRESSED = 0.25, 0.5 -- how strongly a tab's added art lights it
local TAB_SOUND = SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB
local PREVIEW_FIELDS = { height = true, states = true, create = true, refresh = true, caption = true, pick = true,
	stop = true, editor = true }
local PART_FIELDS = { text = true, key = true }
local PART_TEXT_PAD, PART_OUTLINE = 2, 2 -- the pad in the sample's own units; the outline in the window's
local PART_LEVEL, TEXT_PART_LEVEL = 50, 300 -- above the sample's own frames; text parts above every other part
local INACTIVE_ALPHA = 0.5
local HINT_GAP = 12

lib.PreviewHandlers = lib.PreviewHandlers or {}
local Handlers = lib.PreviewHandlers
lib.Tab = {}
local tabMeta = { __index = function(_, name) return lib.Tab[name] end }
lib.PreviewModel = {}
local previewMeta = { __index = function(_, name) return lib.PreviewModel[name] end }

-- Model ------------------------------------------------------------------------------------------------------

---Gives the page a Preview above its sections. `info`: `height` (the stage, 84 by default, at most a third of the
---page less the heading and caption; or a function returning it, read each time the page or a tab is shown and held
---while the page stays shown, so a sample sized by settings on other pages fits them without moving as this page's
---settings change); `editor` (true for a sample whose parts are clicked and dragged: it shrinks
---only to 0.85); `states` (a list of names, or a function returning the ones that apply now; pills show when more
---than one does); `create(canvas, preview)` once; `refresh(canvas, state, preview)` on every change, returning the
---sample's natural width and height and marking its parts with `preview:Part` (`preview.room`, `{ width, height }`,
---is the room at full size, for an editor to rearrange itself to fit before it shrinks); `caption(state, scale,
---sideways)` returning a line under the stage; `pick(key, preview)` when a part with a key is clicked;
---`stop(canvas, preview)` to end the sample's animations, called when the state, the page or the window changes.
function lib.PageModel:Preview(info)
	info = info or {}
	for field in pairs(info) do
		if not PREVIEW_FIELDS[field] and field ~= "page" then
			lib:Report(self.window.addonName, ("%s: unknown preview field %q"):format(self.id, tostring(field)))
		end
	end
	info.page = self
	self.preview = setmetatable(info, previewMeta)

	return info
end

---Marks a part of the sample, from `refresh`: hovering it outlines it, a left click lands on its setting.
---`target`: a setting id on this page, "page/id", or a function returning one at click time; nil for a part that
---is only chosen. `options.text`: a font string's part fits its text, 2 larger all round. `options.key` names the
---part: a click chooses it (it keeps its outline) and calls `pick(key)`. Parts declared later are on top; text parts
---are above every other part.
---@param region Region
---@param target string|fun(preview: table): string?|nil
---@param options { text: boolean?, key: any }?
function lib.PreviewModel:Part(region, target, options)
	local page = self.page
	local parts = page.declaredParts
	if not parts then
		lib:Report(page.window.addonName, ("%s: preview:Part is called from refresh only"):format(page.id))
		return
	end
	options = options or {}
	for field in pairs(options) do
		if not PART_FIELDS[field] then
			lib:Report(page.window.addonName, ("%s: unknown preview part field %q"):format(page.id, tostring(field)))
		end
	end
	if region then
		table.insert(parts, { region = region, target = target, text = options.text, key = options.key })
	end
end

---Chooses the part with `key` (nil: none), as a click on it would, without landing or calling `pick`; for a page
---whose chosen part follows a control, such as a slot dropdown.
function lib.PreviewModel:Choose(key)
	self.page.previewChosen = key
	Handlers.PlaceChosen(self.page)
end

---@return any key the chosen part's key, or nil
function lib.PreviewModel:Chosen()
	return self.page.previewChosen
end

---Adds a tab to the page; its sections are declared with `tab:Section(id, title, info?)`. `info.countOverrides` shows
---how many of the tab's settings are overridden.
function lib.PageModel:Tab(id, title, info)
	self.tabs = self.tabs or {}
	local tab = setmetatable({ id = id, title = title, page = self, sections = {},
		countOverrides = info and info.countOverrides }, tabMeta)
	table.insert(self.tabs, tab)

	return tab
end

function lib.Tab:Section(id, title, info)
	local section = self.page:Section(id, title, info)
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
	pill.art = pill:CreateTexture(nil, "BACKGROUND")
	pill.art:SetAllPoints()
	pill.text = pill:CreateFontString(nil, "OVERLAY")
	lib:SetType(pill.text, "secondary")
	pill:SetScript("OnClick", function(self) Handlers.PillClick(fixed.window, self.state) end)
	pill:SetScript("OnEnter", function(self) self.hovered = true; Handlers.PaintPill(self) end)
	pill:SetScript("OnLeave", function(self) self.hovered = false; Handlers.PaintPill(self) end)
	pill:SetScript("OnMouseDown", function(self) self.pressed = true; Handlers.PaintPill(self) end)
	pill:SetScript("OnMouseUp", function(self) self.pressed = false; Handlers.PaintPill(self) end)

	return pill
end

-- Centers the canvas on the stage, or, when it is wider, sets it from the left at the sideways offset, with a faded
-- edge on each side where some of it is out of view. The wheel scrolls only while there is something to scroll.
function Handlers.PlaceCanvas(preview)
	local canvas, stage, overflow = preview.canvas, preview.stage, preview.overflow or 0
	canvas:ClearAllPoints()
	if overflow > 0 then
		-- A scaled frame's offsets count in its own scale.
		canvas:SetPoint("LEFT", stage, "LEFT", (ROOM_X / 2 - preview.offset) / preview.scale, 0)
	else
		canvas:SetPoint("CENTER")
	end
	stage.fadeLeft:SetShown(overflow > 0 and preview.offset > 0)
	stage.fadeRight:SetShown(overflow > 0 and preview.offset < overflow)
	stage:EnableMouseWheel(overflow > 0)
end

function Handlers.Wheel(fixed, delta)
	local preview = fixed.preview
	if not preview.canvas or (preview.overflow or 0) <= 0 then
		return
	end
	preview.offset = math.max(0, math.min(preview.overflow, preview.offset - delta * WHEEL_STEP))
	Handlers.PlaceCanvas(preview)
end

-- The chosen state stays as it is; another sinks at once on the press and lights under the pointer.
function Handlers.PaintPill(pill)
	local pressed = not pill.on and pill.pressed
	local look = pill.on and "selected" or pressed and "pressed" or pill.hovered and "hover" or "normal"
	pill.art:SetAtlas(PILL_ART:format(look))
	pill.text:SetTextColor(lib:GetColor((pill.on or pill.hovered) and "text" or "secondary"))
	pill.text:SetPoint("CENTER", 0, pressed and -1 or 0)
end

-- A tab's art in three pieces: fixed-width caps and a middle that stretches between them.
local function TabPieces(tab, sublevel)
	local pieces = {}
	for index, side in ipairs({ "Left", "Middle", "Right" }) do
		pieces[index] = tab:CreateTexture(nil, "BACKGROUND", nil, sublevel)
		pieces[index].side = side
	end
	local left, middle, right = pieces[1], pieces[2], pieces[3]
	left:SetPoint("BOTTOMLEFT")
	left:SetPoint("TOPLEFT")
	left:SetWidth(TAB_CAP)
	right:SetPoint("BOTTOMRIGHT")
	right:SetPoint("TOPRIGHT")
	right:SetWidth(TAB_CAP)
	middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
	middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")

	return pieces
end

local function ShowPieces(pieces, shown, alpha)
	for _, piece in ipairs(pieces) do
		piece:SetShown(shown and true or false)
		if alpha then
			piece:SetAlpha(alpha)
		end
	end
end

local function CreateTab(fixed)
	local tab = CreateFrame("Button", nil, fixed.tabs)
	tab.art = TabPieces(tab, 0)
	-- The same art again, added over itself, lights a tab under the pointer and more while it is pressed.
	tab.lit = TabPieces(tab, 1)
	for _, piece in ipairs(tab.lit) do
		piece:SetBlendMode("ADD")
	end
	tab.text = tab:CreateFontString(nil, "OVERLAY")
	lib:SetType(tab.text, "body")
	tab:SetScript("OnClick", function(self) Handlers.TabClick(fixed.window, self.tabId) end)
	tab:SetScript("OnEnter", function(self) self.hovered = true; Handlers.PaintTab(self) end)
	tab:SetScript("OnLeave", function(self) self.hovered, self.pressed = nil, nil; Handlers.PaintTab(self) end)
	tab:SetScript("OnMouseDown", function(self, button)
		self.pressed = button == "LeftButton" or nil
		Handlers.PaintTab(self)
	end)
	tab:SetScript("OnMouseUp", function(self) self.pressed = nil; Handlers.PaintTab(self) end)

	return tab
end

function Handlers.PaintTab(tab)
	local prefix = tab.on and "Options_Tab_Active_" or "Options_Tab_"
	for index, piece in ipairs(tab.art) do
		piece:SetAtlas(prefix .. piece.side)
		tab.lit[index]:SetAtlas(prefix .. piece.side)
	end
	tab:SetHeight(tab.on and TAB_ACTIVE_HEIGHT or TAB_HEIGHT)
	tab:SetFrameLevel(tab:GetParent():GetFrameLevel() + (tab.on and 2 or 1))
	-- The selected tab stays as it is; another lights at once on the press, softer under the pointer.
	local pressed = not tab.on and tab.pressed
	local lit = pressed or (not tab.on and tab.hovered)
	ShowPieces(tab.lit, lit, pressed and TAB_PRESSED or TAB_HOVER)
	tab.text:SetTextColor(lib:GetColor(tab.on and "accent" or lit and "text" or "secondary"))
	tab.text:SetPoint("CENTER", 0, pressed and -2 or -1)
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
	lib:SetType(preview.title, "heading", "heading")
	preview.title:SetJustifyV("BOTTOM")
	preview.title:SetPoint("TOPLEFT", HEADING_INSET, -PREVIEW_GAP)
	preview.title:SetHeight(SECTION_TITLE_HEIGHT - HEADING_BOTTOM)
	preview.title:SetText(L.PREVIEW)
	preview.hint = preview:CreateFontString(nil, "OVERLAY")
	lib:SetType(preview.hint, "caption", "secondary")
	preview.hint:SetPoint("BOTTOMLEFT", preview.title, "BOTTOMRIGHT", HINT_GAP, 0)
	preview.hint:SetText(L.PREVIEW_HINT)
	preview.hint:Hide()
	-- The stage is a card; a sample wider than it scrolls sideways under the wheel, faded where it runs off.
	local stage = CreateFrame("Frame", nil, preview)
	stage:SetPoint("TOPLEFT", 0, -(PREVIEW_GAP + SECTION_TITLE_HEIGHT + 1))
	stage:SetPoint("TOPRIGHT", 0, -(PREVIEW_GAP + SECTION_TITLE_HEIGHT + 1))
	stage:SetClipsChildren(true)
	local fill = stage:CreateTexture(nil, "BACKGROUND")
	fill:SetColorTexture(lib:GetColor("card"))
	fill:SetAllPoints()
	for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
		{ "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local line = stage:CreateTexture(nil, "BORDER")
		line:SetColorTexture(lib:GetColor("cardEdge"))
		line:SetPoint(edge[1])
		line:SetPoint(edge[2])
		line:SetSize(1, 1)
	end
	for _, side in ipairs({ "LEFT", "RIGHT" }) do
		local fade = CreateFrame("Frame", nil, stage)
		fade:SetPoint("TOP" .. side)
		fade:SetPoint("BOTTOM" .. side)
		fade:SetWidth(EDGE_WIDTH)
		fade:SetFrameLevel(stage:GetFrameLevel() + 400)
		local texture = fade:CreateTexture(nil, "OVERLAY")
		texture:SetAllPoints()
		texture:SetColorTexture(1, 1, 1, 1)
		local solid, clear = CreateColor(0.07, 0.07, 0.08, 0.9), CreateColor(0.07, 0.07, 0.08, 0)
		texture:SetGradient("HORIZONTAL", side == "LEFT" and solid or clear, side == "LEFT" and clear or solid)
		fade:Hide()
		stage[side == "LEFT" and "fadeLeft" or "fadeRight"] = fade
	end
	stage:SetScript("OnMouseWheel", function(_, delta) Handlers.Wheel(fixed, delta) end)
	stage:EnableMouseWheel(false)
	preview.stage = stage
	preview.caption = preview:CreateFontString(nil, "OVERLAY")
	lib:SetType(preview.caption, "secondary", "secondary")
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
	-- A page change ends the last page's animations and its chosen part.
	if view.previewPage ~= page then
		self:StopPreview()
		view.previewPage = page
		preview.offset = 0
	end

	preview:SetShown(page.preview ~= nil)
	if page.preview then
		-- The preview takes at most a third of the page, heading and caption included.
		local pageHeight = view.content:GetHeight()
		local most = math.floor((pageHeight > 1 and pageHeight or 700) / 3)
			- (PREVIEW_GAP + SECTION_TITLE_HEIGHT + 1 + CAPTION_HEIGHT)
		local stageHeight = page.preview.height
		if type(stageHeight) == "function" then
			stageHeight = lib.CallAdopter(stageHeight, page.preview)
		end
		stageHeight = math.min(tonumber(stageHeight) or PREVIEW_HEIGHT, most)
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
		page.declaredParts = {}
		local roomWidth = preview.stage:GetWidth() - ROOM_X
		local roomHeight = preview.stage:GetHeight() - ROOM_Y
		page.preview.room = { width = roomWidth, height = roomHeight }
		if page.preview.refresh then
			width, height = lib.CallAdopter(page.preview.refresh, canvas, current, page.preview)
		end
		width, height = tonumber(width) or 1, tonumber(height) or 1
		canvas:SetSize(width, height)
		-- Shrinks to fit, but not past its least scale across; a sample still wider scrolls sideways. Its height
		-- always fits.
		local least = page.preview.editor and EDITOR_LEAST or LOOK_LEAST
		local scale = math.max(0.05, math.min(1, roomHeight / height, math.max(least, roomWidth / width)))
		canvas:SetScale(scale)
		preview.canvas, preview.scale = canvas, scale
		preview.overflow = math.max(0, width * scale - roomWidth)
		preview.offset = math.min(preview.offset or 0, preview.overflow)
		Handlers.PlaceCanvas(preview)
		-- While the page is switched off the sample is faded and still; its parts still find their settings.
		local off = page.switch ~= nil and not page.switch:GetValue()
		canvas:SetAlpha(off and INACTIVE_ALPHA or 1)
		page.previewRunning = true
		if off then
			self:StopPreview(page)
		end
		local count = Handlers.PlaceParts(self, page)
		preview.hint:SetShown(count > 0)
		local caption
		local sideways = preview.overflow > 0
		if page.preview.caption then
			caption = lib.CallAdopter(page.preview.caption, current, scale, sideways)
		end
		if not caption then
			local shrunk = scale < 0.999 and L.PREVIEW_SHRUNK:format(math.floor(scale * 100 + 0.5)) or nil
			caption = sideways and (shrunk and shrunk .. " " or "") .. L.PREVIEW_SIDEWAYS or shrunk
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
		window:StopPreview(page)
		page.previewState = state
		PlaySound(TAB_SOUND)
		window:RefreshFixedArea()
	end
end

function Handlers.TabClick(window, tabId)
	local page = window.pageView and window.pageView.shownPage
	if page and page.tab ~= tabId then
		page.tab = tabId
		Handlers.FollowTab(page, tabId)
		PlaySound(TAB_SOUND)
		window:ShowPage()
	end
end

-- Parts ------------------------------------------------------------------------------------------------------

-- A gold outline drawn just inside its frame's edges.
local function CreateOutline(parent)
	local outline = CreateFrame("Frame", nil, parent)
	outline.edges = {}
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
		local edge = outline:CreateTexture(nil, "OVERLAY")
		edge:SetColorTexture(lib:GetColor("accent"))
		edge:SetPoint(side[1])
		edge:SetPoint(side[2])
		edge.horizontal = side[3]
		table.insert(outline.edges, edge)
	end
	outline:Hide()

	return outline
end

-- Puts an outline over a part's hit area, its edges 2 wide in the window whatever the sample's scale.
local function ShowOutline(outline, button)
	outline:ClearAllPoints()
	outline:SetAllPoints(button)
	outline:SetFrameLevel(button:GetFrameLevel() + 1)
	local width = PART_OUTLINE / math.max(0.05, outline:GetParent():GetParent():GetScale())
	for _, edge in ipairs(outline.edges) do
		if edge.horizontal then
			edge:SetHeight(width)
		else
			edge:SetWidth(width)
		end
	end
	outline.button = button
	outline:Show()
end

local function CreatePart(layer, window)
	local button = CreateFrame("Button", nil, layer)
	button:RegisterForClicks("LeftButtonUp")
	button.window = window
	button:SetScript("OnEnter", function(self) Handlers.PartEnter(self) end)
	button:SetScript("OnLeave", function(self) Handlers.PartLeave(self) end)
	button:SetScript("OnHide", function(self) Handlers.PartLeave(self) end)
	button:SetScript("OnClick", function(self) Handlers.PartClick(self) end)

	return button
end

-- A font string's hit area: its text, not its region, 2 larger all round, placed by its justification.
local function FitText(button, fontString)
	local width = fontString:GetStringWidth() + 2 * PART_TEXT_PAD
	local height = fontString:GetStringHeight() + 2 * PART_TEXT_PAD
	button:SetSize(math.max(1, width), math.max(1, height))
	local justify = fontString:GetJustifyH()
	if justify == "LEFT" then
		button:SetPoint("LEFT", fontString, "LEFT", -PART_TEXT_PAD, 0)
	elseif justify == "RIGHT" then
		button:SetPoint("RIGHT", fontString, "RIGHT", PART_TEXT_PAD, 0)
	else
		button:SetPoint("CENTER", fontString, "CENTER")
	end
end

-- Lays the parts `refresh` declared over the sample, reusing the page's hit areas; returns how many show.
function Handlers.PlaceParts(window, page)
	local declared = page.declaredParts or {}
	page.declaredParts = nil
	local canvas = page.previewCanvas
	local layer = page.partLayer
	if not layer then
		if #declared == 0 then
			return 0
		end
		layer = CreateFrame("Frame", nil, canvas)
		layer:SetAllPoints()
		layer.buttons = {}
		layer.hover = CreateOutline(layer)
		layer.chosen = CreateOutline(layer)
		page.partLayer = layer
	end
	local base = canvas:GetFrameLevel() + PART_LEVEL
	local count = 0
	for _, part in ipairs(declared) do
		local region = part.region
		if not region.IsShown or region:IsShown() then
			count = count + 1
			local button = layer.buttons[count] or CreatePart(layer, window)
			layer.buttons[count] = button
			button.part, button.page = part, page
			button:ClearAllPoints()
			if part.text and region.GetStringWidth then
				FitText(button, region)
			else
				button:SetAllPoints(region)
			end
			button:SetFrameLevel(base + (part.text and TEXT_PART_LEVEL or 0) + count)
			button:Show()
		end
	end
	for index = count + 1, #layer.buttons do
		layer.buttons[index]:Hide()
	end
	-- The hovered part keeps its outline across the redraw; the engine sends OnLeave if it moved away.
	local hover = layer.hover
	if hover:IsShown() and hover.button:IsShown() then
		ShowOutline(hover, hover.button)
	end
	Handlers.PlaceChosen(page)

	return count
end

function Handlers.PlaceChosen(page)
	local layer = page.partLayer
	if not layer then
		return
	end
	local key = page.previewChosen
	for _, button in ipairs(layer.buttons) do
		if key ~= nil and button:IsShown() and button.part.key == key then
			ShowOutline(layer.chosen, button)
			return
		end
	end
	layer.chosen:Hide()
end

function Handlers.PartEnter(button)
	ShowOutline(button:GetParent().hover, button)
end

function Handlers.PartLeave(button)
	local hover = button:GetParent().hover
	if hover.button == button then
		hover:Hide()
	end
end

-- A setting named by id on its page or by "page/id" on another.
local function NamedSetting(page, target)
	local pageId, id = target:match("^(.-)/(.+)$")
	local owner = pageId and page.window.pages[pageId] or page

	return owner and owner.settings and owner.settings[id or target]
end

-- A part's setting: by id on its page, "page/id" on another, or from a function at click time.
local function PartSetting(page, target)
	if type(target) == "function" then
		target = lib.CallAdopter(target, page.preview)
	end
	if type(target) ~= "string" then
		return nil
	end
	local setting = NamedSetting(page, target)
	if not setting then
		lib:Report(page.window.addonName, ("%s: a preview part names unknown setting %q"):format(page.id, target))
	end

	return setting
end

---On a page whose keyed parts name settings on its tabs, the chosen part follows the tab: the part whose setting is
---on `tabId`, or none when no part's is. Parts whose setting is named by a function are left out, so no adopter code
---runs for it. Pages without such parts keep their chosen part.
function Handlers.FollowTab(page, tabId)
	local layer = page.partLayer
	if not layer then
		return
	end
	local bound, follow = false, nil
	for _, button in ipairs(layer.buttons) do
		local part = button.part
		if button:IsShown() and part.key ~= nil and type(part.target) == "string" then
			local setting = NamedSetting(page, part.target)
			local tab = setting and setting.page == page and setting.section and setting.section.tab
			if tab then
				bound = true
				if tab.id == tabId and follow == nil then
					follow = part.key
				end
			end
		end
	end
	if bound then
		page.previewChosen = follow
	end
end

-- A click chooses a keyed part (redrawing the page for it), then lands on the part's setting.
function Handlers.PartClick(button)
	local part, page, window = button.part, button.page, button.window
	if part.key ~= nil then
		page.previewChosen = part.key
		if page.preview.pick then
			lib.CallAdopter(page.preview.pick, part.key, page.preview)
		end
		window:Refresh()
	end
	local setting = PartSetting(page, part.target)
	if setting then
		window:LandOn(setting)
	end
end

---Ends the shown page's sample animations (or `page`'s) through its `stop`, once until it is refreshed again. With
---no `page`, the page is also left: its chosen part is cleared, as when another page is shown or the window closes.
function lib.Window:StopPreview(page)
	local view = self.pageView
	local leaving = page == nil
	page = page or (view and view.previewPage)
	if not page then
		return
	end
	if page.previewRunning then
		page.previewRunning = nil
		if page.preview and page.preview.stop then
			lib.CallAdopter(page.preview.stop, page.previewCanvas, page.preview)
		end
	end
	if leaving then
		page.previewChosen = nil
		view.previewPage = nil
	end
end
