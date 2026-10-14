-- The window's navigation: the model (headers, groups, pages and dividers, declared in order) and the sidebar that
-- draws it, with collapsible headers and groups and a smooth scrolling list.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local ROW_HEIGHT = 32
local DIVIDER_HEIGHT = 19       -- a 1-unit rule with 9 above and below
local ICON_SIZE = 16
local CHEVRON_SIZE, GROUP_CHEVRON_SIZE = 14, 12
local GOLD = { 1, 0.82, 0 }
local WHITE = { 1, 1, 1 }
local GROUP_WHITE = { 1, 1, 1, 0.9 }
local SELECT_SOUND = SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB

-- Text inset, font and size by kind; `icon` is the icon's inset and `slotted` the text inset with an icon slot.
local KINDS = {
	top = { inset = 16, font = "body", size = 16 },
	header = { inset = 34, font = "header", size = 16, chevron = 14 },
	group = { inset = 34, font = "body", size = 14, chevron = 18 },
	sub = { inset = 34, font = "body", size = 14, icon = 32, slotted = 54 },
	item = { inset = 52, font = "body", size = 14, icon = 50, slotted = 72 },
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

---Adds a collapsible, gold header to the sidebar.
function lib.Window:Header(id, title)
	return AddNode(self, { kind = "header", id = id, title = title })
end

---Adds a collapsible group under a header.
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

local PAGE_FIELDS = { title = true, description = true, under = true, icon = true, slot = true, switch = true }

---Adds a page: at the top level, under a header, or under a group. `info.icon` (a file or atlas) or `info.slot`
---reserves the 16-unit icon slot before its title. `info.switch` (true, or a setting's fields such as `path` and
---`default`) gives the page an Enabled toggle that dims the page body while off.
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
		parent = parent, icon = info.icon, slot = info.slot or info.icon ~= nil, isPage = true })
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
		self.collapsed[parent.id] = nil
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
	row.label = row:CreateFontString(nil, "OVERLAY")
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)

	row.rule = row:CreateTexture(nil, "ARTWORK")
	row.rule:SetAtlas("Options_HorizontalDivider")
	row.rule:SetHeight(1)
	row.rule:SetPoint("LEFT", 6, 0)
	row.rule:SetPoint("RIGHT", -6, 0)

	row:SetScript("OnClick", function(self) Handlers.Click(window, self) end)
	row:SetScript("OnEnter", function(self) Handlers.Hover(window, self, true) end)
	row:SetScript("OnLeave", function(self) Handlers.Hover(window, self, false) end)

	return row
end

local function PaintRow(window, row)
	local node = row.node
	local selected = node.isPage and window.page == node.id
	row.selected:SetShown(selected)
	row.hover:SetShown(row.hovered and not selected and node.kind ~= "divider")
	if node.isPage then
		row.label:SetTextColor(unpack(selected and GOLD or WHITE))
	elseif node.kind == "header" then
		row.label:SetTextColor(unpack(GOLD))
	elseif node.kind == "group" then
		row.label:SetTextColor(unpack(GROUP_WHITE))
	end
end

local function SetUpRow(window, row, node)
	row.node = node
	local isDivider = node.kind == "divider"
	row:SetHeight(isDivider and DIVIDER_HEIGHT or ROW_HEIGHT)
	row:EnableMouse(not isDivider)
	row.rule:SetShown(isDivider)
	row.label:SetShown(not isDivider)
	row.icon:Hide()
	row.chevron:Hide()
	if isDivider then
		row.selected:Hide()
		row.hover:Hide()
		return
	end

	local kind = KINDS[node.kind]
	lib:SetFont(row.label, kind.font, kind.size)
	row.label:SetText(node.title)
	row.label:ClearAllPoints()
	local inset = kind.inset
	if node.slot and kind.slotted then
		inset = kind.slotted
		if node.icon then
			row.icon:ClearAllPoints()
			row.icon:SetPoint("LEFT", kind.icon, 0)
			if C_Texture.GetAtlasInfo(node.icon) then
				row.icon:SetAtlas(node.icon)
			else
				row.icon:SetTexture(node.icon)
			end
			row.icon:Show()
		end
	end
	row.label:SetPoint("LEFT", inset, 0)
	row.label:SetPoint("RIGHT", -6, 0)
	if kind.chevron then
		local size = node.kind == "group" and GROUP_CHEVRON_SIZE or CHEVRON_SIZE
		row.chevron:SetSize(size, size)
		row.chevron:ClearAllPoints()
		row.chevron:SetPoint("CENTER", row, "LEFT", kind.chevron, 0)
		row.chevron:SetRotation(window.collapsed[node.id] and math.pi / 2 or 0)
		row.chevron:SetAlpha(node.kind == "group" and 0.7 or 1)
		row.chevron:SetVertexColor(unpack(node.kind == "header" and GOLD or WHITE))
		row.chevron:Show()
	end
	PaintRow(window, row)
end

local function Hidden(window, node)
	local parent = node.parent
	while parent do
		if window.collapsed[parent.id] then
			return true
		end
		parent = parent.parent
	end

	return false
end

---Lays out the sidebar's rows for the entries that show (collapsed headers and groups hide what is under them).
function lib.Window:RefreshSidebar()
	local sidebar = self.sidebar
	if not sidebar then
		return
	end
	sidebar.rows = sidebar.rows or {}
	local y, count = 0, 0
	for _, node in ipairs(self.nav) do
		if not Hidden(self, node) then
			count = count + 1
			local row = sidebar.rows[count] or CreateRow(self)
			sidebar.rows[count] = row
			SetUpRow(self, row, node)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", sidebar.child, "TOPLEFT", 0, -y)
			row:SetPoint("RIGHT", sidebar.child, "RIGHT", 0, 0)
			row:Show()
			y = y + row:GetHeight()
		end
	end
	for index = count + 1, #sidebar.rows do
		sidebar.rows[index]:Hide()
	end
	sidebar:SetContentHeight(y)
	self.navChanged = nil
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
	elseif node.kind == "header" or node.kind == "group" then
		window.collapsed[node.id] = not window.collapsed[node.id] or nil
		window:RefreshSidebar()
	end
end

function Handlers.Hover(window, row, hovered)
	row.hovered = hovered
	PaintRow(window, row)
	window.sidebar:UpdateLit()
end
