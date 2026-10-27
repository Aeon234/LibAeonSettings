-- The window's navigation: the model (headers, groups, pages and dividers, declared in order) and the sidebar that
-- draws it one level deep in a smooth scrolling list: headers and groups are headings that fold the entries under
-- them, and every page is an entry at the same indent.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local ROW_HEIGHT = 30
local DIVIDER_HEIGHT = 19       -- a 1-unit rule with 9 above and below
local ICON_SIZE, ICON_LEFT, ENTRY_TEXT = 18, 13, 40 -- an entry's icon and text
local HEADING_TEXT, HEADING_BOTTOM = 28, 7 -- a heading's text: in from the left, up from the row's bottom
local CHEVRON_SIZE, CHEVRON_CENTER = 10, 14
local HOLDING_WIDTH = 110 -- room for the name of the page a folded heading holds
local HOVER_ALPHA = 0.7 -- the hover art while hovered; full while pressed
local FOLD_RESPONSE = 0.3
local OFF_ALPHA = 0.45 -- a page whose switch is off
local SELECT_SOUND = SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB

-- Headings (headers and groups alike) and entries (pages at any depth), by node kind.
local KINDS = {
	top = { role = "body" },
	sub = { role = "body" },
	item = { role = "body" },
	header = { role = "navHeading", heading = true },
	group = { role = "navHeading", heading = true },
}

lib.SidebarHandlers = lib.SidebarHandlers or {}
local Handlers = lib.SidebarHandlers

-- Model ------------------------------------------------------------------------------------------------------

local function AddNode(window, node)
	if window.nodes[node.id] then
		lib:Report(window.addonName, ("navigation id %q is used twice"):format(node.id))
		return
	end
	window.nodes[node.id] = node
	table.insert(window.nav, node)
	window.navChanged = true
	window.searchIndex = nil

	return node
end

local function Parent(window, under, kinds)
	if under == nil then
		return nil, true
	end
	local parent = window.nodes[under]
	if not parent or not kinds[parent.kind] then
		lib:Report(window.addonName, ("%q is not a header or group to place an entry under"):format(tostring(under)))
		return nil, false
	end

	return parent, true
end

---Adds a heading to the sidebar; clicking it folds the entries under it.
function lib.Window:Header(id, title)
	return AddNode(self, { kind = "header", id = id, title = title })
end

---Adds a group under a header. It draws as a heading of its own, like a header, and its pages sit at the same
---indent as every other page.
function lib.Window:Group(id, title, header)
	local parent, ok = Parent(self, header, { header = true })
	if ok then
		return AddNode(self, { kind = "group", id = id, title = title, parent = parent })
	end
end

---Adds a dividing rule to the sidebar.
function lib.Window:Divider()
	self.dividers = (self.dividers or 0) + 1

	return AddNode(self, { kind = "divider", id = "\0divider" .. self.dividers })
end

local PAGE_FIELDS = { title = true, description = true, under = true, icon = true, iconCrop = true, slot = true,
	switch = true }

---Adds a page: at the top level, under a header, or under a group. `info.icon` (a file or atlas) draws before its
---title; `info.iconCrop` cuts that share of a file icon from each edge; `info.slot` is accepted and no longer needed,
---as every entry keeps the icon's room. `info.switch` (true, or a setting's fields such as `path` and `default`)
---gives the page a switch on a card of its own, the rest of the page there only while it is on.
---@return table? page
function lib.Window:Page(id, info)
	info = info or {}
	for field in pairs(info) do
		if not PAGE_FIELDS[field] then
			lib:Report(self.addonName, ("page %s: unknown field %q"):format(tostring(id), tostring(field)))
		end
	end
	local parent, ok = Parent(self, info.under, { header = true, group = true })
	if not ok then
		return
	end
	local kind = not parent and "top" or parent.kind == "header" and "sub" or "item"
	local page = AddNode(self, { kind = kind, id = id, title = info.title or id, description = info.description,
		parent = parent, icon = info.icon, iconCrop = info.iconCrop, isPage = true })
	if page then
		self.pages[id] = page
		table.insert(self.pageOrder, page)
		lib:InitPage(self, page, info)
	end

	return page
end

---Shows a page, opening any collapsed header or group above it.
function lib.Window:SelectPage(id)
	local page = self.pages[id]
	if not page then
		lib:Report(self.addonName, ("SelectPage: no page %q"):format(tostring(id)))
		return
	end
	local changed = self.page ~= id
	self.page = id
	local parent = page.parent
	while parent do
		if self.collapsed[parent.id] then
			Handlers.Fold(self, parent, false)
		end
		parent = parent.parent
	end
	if self.frame then
		if changed and self.frame:IsShown() and SELECT_SOUND then
			PlaySound(SELECT_SOUND)
		end
		self:RefreshSidebar()
		if self.ShowPage then
			self:ShowPage()
		end
	end
end

-- View -------------------------------------------------------------------------------------------------------

local function CreateRow(window)
	local row = CreateFrame("Button", nil, window.sidebar.child)
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp")

	row.selected = row:CreateTexture(nil, "BACKGROUND")
	row.selected:SetAtlas("common-button-list-small-selected")
	row.selected:SetAllPoints()
	row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.hover:SetTexture(lib.mediaPath .. "Textures\\nav-hover")
	row.hover:SetTextureSliceMargins(16, 16, 16, 16)
	if Enum.UITextureSliceMode then
		row.hover:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
	end
	row.hover:SetScale(0.5)
	row.hover:SetAllPoints()
	row.hover:Hide()

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON_SIZE, ICON_SIZE)
	row.chevron = row:CreateTexture(nil, "ARTWORK")
	row.chevron:SetTexture(lib.mediaPath .. "Textures\\chevron")
	row.chevron:SetSize(CHEVRON_SIZE, CHEVRON_SIZE)
	row.label = row:CreateFontString(nil, "OVERLAY")
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	-- On a folded heading that holds the shown page: that page's name, at the right.
	row.holding = row:CreateFontString(nil, "OVERLAY")
	lib:SetType(row.holding, "body", "accent")
	row.holding:SetJustifyH("RIGHT")
	row.holding:SetWordWrap(false)
	row.holding:SetWidth(HOLDING_WIDTH)

	row.rule = row:CreateTexture(nil, "ARTWORK")
	row.rule:SetAtlas("Options_HorizontalDivider")
	row.rule:SetHeight(1)
	row.rule:SetPoint("LEFT", 6, 0)
	row.rule:SetPoint("RIGHT", -6, 0)

	row:SetScript("OnClick", function(self) Handlers.Click(window, self) end)
	row:SetScript("OnEnter", function(self) Handlers.Hover(window, self, true) end)
	row:SetScript("OnLeave", function(self)
		Handlers.Press(window, self, false)
		Handlers.Hover(window, self, false)
	end)
	row:SetScript("OnMouseDown", function(self, button) Handlers.Press(window, self, button == "LeftButton") end)
	row:SetScript("OnMouseUp", function(self) Handlers.Press(window, self, false) end)

	return row
end

---@return boolean holds the shown page sits somewhere under this header or group
local function Holds(window, node)
	local page = window.page and window.pages[window.page]
	local parent = page and page.parent
	while parent do
		if parent == node then
			return true
		end
		parent = parent.parent
	end

	return false
end

local function PaintRow(window, row)
	local node = row.node
	local selected = node.isPage and window.page == node.id
	row.selected:SetShown(selected)
	-- Pressing lights the hover art at once, full; hovering shows it softer.
	local lit = (row.hovered or row.pressed) and node.kind ~= "divider" and (row.pressed or not selected)
	row.hover:SetShown(lit and true or false)
	row.hover:SetAlpha(row.pressed and 1 or HOVER_ALPHA)
	local page = node.isPage and window.pages[node.id]
	local off = page and page.switch and not page.switch:GetValue()
	row.label:SetAlpha(off and OFF_ALPHA or 1)
	row.icon:SetAlpha(off and OFF_ALPHA or 1)
	local holding = false
	if node.isPage then
		row.label:SetTextColor(lib:GetColor(selected and "accent" or "text"))
	elseif KINDS[node.kind] and KINDS[node.kind].heading then
		-- A folded heading over the shown page turns gold and names it.
		holding = window.collapsed[node.id] and Holds(window, node)
		row.label:SetTextColor(lib:GetColor(holding and "accent" or "navHeading"))
		row.chevron:SetVertexColor(lib:GetColor(holding and "accent" or "navHeading"))
		if holding then
			row.holding:SetText(window.pages[window.page].title)
		end
	end
	row.holding:SetShown(holding and true or false)
end

---@return number share how much of a header's or group's entries shows: 1 open, 0 folded, between while folding
local function FoldShare(window, node)
	local fold = window.folds and window.folds[node.id]

	return fold and fold.value or (window.collapsed[node.id] and 0 or 1)
end

-- Folds or opens a header or group on a spring that lays the sidebar out again on every step.
function Handlers.Fold(window, node, folded)
	window.collapsed[node.id] = folded or nil
	window.folds = window.folds or {}
	local fold = window.folds[node.id]
	if not fold then
		fold = lib:CreateSpring(folded and 1 or 0, function() window:RefreshSidebar() end,
			{ response = FOLD_RESPONSE, epsilon = 0.002 })
		window.folds[node.id] = fold
	end
	fold:To(folded and 0 or 1)
end

local function SetUpRow(window, row, node)
	row.node = node
	local isDivider = node.kind == "divider"
	row:EnableMouse(not isDivider)
	row.rule:SetShown(isDivider)
	row.label:SetShown(not isDivider)
	row.icon:Hide()
	row.chevron:Hide()
	if isDivider then
		row.selected:Hide()
		row.hover:Hide()
		row.holding:Hide()
		return
	end

	local kind = KINDS[node.kind]
	local role = lib.TYPE[kind.role]
	lib:SetFont(row.label, role[1], role[2])
	row.label:SetText(node.title)
	row.label:ClearAllPoints()
	row.holding:ClearAllPoints()
	if kind.heading then
		-- Headings sit low in their row, over the entries they hold; the chevron turns as they fold.
		row.label:SetPoint("BOTTOMLEFT", HEADING_TEXT, HEADING_BOTTOM)
		row.label:SetPoint("RIGHT", -(HOLDING_WIDTH + 12), 0)
		row.chevron:ClearAllPoints()
		row.chevron:SetPoint("CENTER", row.label, "LEFT", -(HEADING_TEXT - CHEVRON_CENTER), 0)
		row.chevron:SetRotation((1 - FoldShare(window, node)) * math.pi / 2)
		row.chevron:Show()
		row.holding:SetPoint("BOTTOMRIGHT", -12, HEADING_BOTTOM)
	else
		if node.icon then
			row.icon:ClearAllPoints()
			row.icon:SetPoint("LEFT", ICON_LEFT, 0)
			if C_Texture.GetAtlasInfo(node.icon) then
				row.icon:SetAtlas(node.icon)
			else
				local crop = node.iconCrop or 0
				row.icon:SetTexture(node.icon)
				row.icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
			end
			row.icon:Show()
		end
		row.label:SetPoint("LEFT", ENTRY_TEXT, 0)
		row.label:SetPoint("RIGHT", -6, 0)
	end
	PaintRow(window, row)
end

---@return number share how much of an entry shows: the fold share of every header or group above it, multiplied
local function Share(window, node)
	local share, parent = 1, node.parent
	while parent and share > 0 do
		share = share * FoldShare(window, parent)
		parent = parent.parent
	end

	return share
end

---Lays out the sidebar's rows, one level: headers and groups are headings, every page an entry under them. A row
---under a folding heading takes its share of its height, faded by as much.
function lib.Window:RefreshSidebar()
	local sidebar = self.sidebar
	if not sidebar then
		return
	end
	sidebar.rows = sidebar.rows or {}
	local y, count = 0, 0
	for _, node in ipairs(self.nav) do
		local share = Share(self, node)
		if share > 0 then
			count = count + 1
			local row = sidebar.rows[count] or CreateRow(self)
			sidebar.rows[count] = row
			SetUpRow(self, row, node)
			local height = (node.kind == "divider" and DIVIDER_HEIGHT or ROW_HEIGHT) * share
			row:SetHeight(height)
			row:SetAlpha(share)
			row:SetClipsChildren(share < 1)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", sidebar.child, "TOPLEFT", 0, -y)
			row:SetPoint("RIGHT", sidebar.child, "RIGHT", 0, 0)
			row:Show()
			y = y + height
		end
	end
	for index = count + 1, #sidebar.rows do
		sidebar.rows[index]:Hide()
	end
	sidebar:SetContentHeight(math.floor(y + 0.5))
	self.navChanged = nil
end

---Redraws the shown rows' states (selection, hover, a page switched off) without laying them out again.
function lib.Window:PaintSidebar()
	local sidebar = self.sidebar
	for _, row in ipairs(sidebar and sidebar.rows or {}) do
		if row:IsShown() and row.node then
			PaintRow(self, row)
		end
	end
end

---Builds the sidebar in its region of the window.
function lib.Window:BuildSidebar(region)
	self.collapsed = self.collapsed or {}
	self.sidebar = lib:CreateScroll(region, { step = 2 * ROW_HEIGHT, row = ROW_HEIGHT, slim = true, inside = true })
	self:RefreshSidebar()
end

function Handlers.Click(window, row)
	local node = row.node
	if node.isPage then
		window:SelectPage(node.id)
	elseif KINDS[node.kind] and KINDS[node.kind].heading then
		Handlers.Fold(window, node, not window.collapsed[node.id])
		window:RefreshSidebar()
	end
end

function Handlers.Hover(window, row, hovered)
	row.hovered = hovered
	PaintRow(window, row)
	window.sidebar:UpdateLit()
end

function Handlers.Press(window, row, pressed)
	row.pressed = pressed or nil
	if row.node then
		PaintRow(window, row)
	end
end

