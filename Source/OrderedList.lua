-- C-20, the ordered list: a numbered row per item, top to bottom, with up and down arrows (MinimalScrollBar's step
-- arrows) and, when the list has them, an on/off checkbox per item. The setting's value is the order, a list of item
-- values; the checkboxes are stored beside it, one path per value. A wide row with no label: `title` names it in
-- Undo and search, and each item's text is searchable on its own.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

-- Kit values (Bronze Hearth, the Micro-Menu prototype).
local ROW_HEIGHT = 40
local NUMBER_WIDTH, NUMBER_GAP = 56, 14
local ARROWS_WIDTH, ARROW_WIDTH, ARROW_HEIGHT, ARROW_GAP = 120, 17, 11, 14
local CHECKBOX_RIGHT = 20
local OFF_ALPHA, END_ALPHA = 0.5, 0.25
local SOUND_MOVE = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
local SOUND_ON = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
local SOUND_OFF = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF

lib.OrderedList = {}
local listMeta = { __index = function(_, name) return lib.OrderedList[name] end }

-- Order -------------------------------------------------------------------------------------------------------

---The whole order: the saved values in their order, then each default value the saved order lacks, in the default's
---order. Values no item has keep their place, so an item a client lacks returns to it.
---@param saved any[]?
---@param default any[]?
---@return any[] order
function lib:FullOrder(saved, default)
	local order, seen = {}, {}
	for _, value in ipairs(type(saved) == "table" and saved or {}) do
		if not seen[value] then
			seen[value] = true
			order[#order + 1] = value
		end
	end
	for _, value in ipairs(type(default) == "table" and default or {}) do
		if not seen[value] then
			seen[value] = true
			order[#order + 1] = value
		end
	end

	return order
end

---Moves `value` past the next shown value up (`step` -1) or down (1); values not shown keep their places relative to
---the rest.
---@param order any[] the whole order
---@param value any
---@param step integer
---@param shown table<any, boolean> the values with items
---@return any[]? moved a new order, or nil when it is at that end already
function lib:MoveInOrder(order, value, step, shown)
	local from
	for index, other in ipairs(order) do
		if other == value then
			from = index
		end
	end
	if not from then
		return nil
	end
	local to = from + step
	while order[to] ~= nil and not shown[order[to]] do
		to = to + step
	end
	if order[to] == nil then
		return nil
	end
	local moved = {}
	for index, other in ipairs(order) do
		moved[index] = other
	end
	moved[from], moved[to] = moved[to], moved[from]

	return moved
end

-- The setting -------------------------------------------------------------------------------------------------

---@return table[] items `{ value, text }` for each item shown, in the list's order
function lib.Setting:OrderedItems()
	local items = self.items
	if type(items) == "function" then
		items = lib.CallAdopter(items, self)
	end
	local byValue = {}
	for _, item in ipairs(type(items) == "table" and items or {}) do
		byValue[item.value] = item
	end
	local shown = {}
	for _, value in ipairs(lib:FullOrder(self:GetValue(), self.default)) do
		if byValue[value] then
			shown[#shown + 1] = byValue[value]
		end
	end

	return shown
end

local function EnabledPath(setting, value)
	return setting.enabled.path .. "." .. tostring(value)
end

---@return boolean on whether the item is on; true for a list without checkboxes
function lib.Setting:ItemEnabled(value)
	local enabled = self.enabled
	if not enabled then
		return true
	end
	local stored = lib.ReadStorePath(self.window, EnabledPath(self, value))
	if stored == nil and type(enabled.default) == "table" then
		stored = enabled.default[value]
	end

	return stored and true or false
end

---Turns an item on or off, recorded for Undo.
function lib.Setting:SetItemEnabled(item, on)
	local path = EnabledPath(self, item.value)
	local before = lib.ReadStorePath(self.window, path)
	local ok, reason = lib.WriteSetting({ window = self.window, path = path, keys = { strsplit(".", path) } }, on)
	if not ok then
		self:ShowRefusal(reason)
	else
		self.window:RecordChange({ path = path, before = before, page = self.page.id,
			text = L.UNDO_TO:format(item.text, before and L.ON or L.OFF) })
	end
	self.window:SettingChanged(self, true, not ok)
end

-- The view ----------------------------------------------------------------------------------------------------

local function Arrow(parent, art)
	local arrow = CreateFrame("Button", nil, parent)
	arrow:SetSize(ARROW_WIDTH, ARROW_HEIGHT)
	arrow:SetNormalAtlas(art)
	arrow:SetHighlightAtlas(art .. "-over")
	arrow:SetPushedAtlas(art .. "-down")

	return arrow
end

local function CreateRow(view)
	local row = CreateFrame("Frame", nil, view.frame)
	row:SetHeight(ROW_HEIGHT)
	row.line = row:CreateTexture(nil, "BACKGROUND")
	row.line:SetColorTexture(lib:GetColor("separator"))
	row.line:SetHeight(1)
	row.line:SetPoint("TOPLEFT")
	row.line:SetPoint("TOPRIGHT")
	row.number = row:CreateFontString(nil, "OVERLAY")
	lib:SetType(row.number, "secondary", "secondary")
	row.number:SetJustifyH("RIGHT")
	row.number:SetPoint("LEFT", 0, 0)
	row.number:SetWidth(NUMBER_WIDTH - NUMBER_GAP)
	row.name = row:CreateFontString(nil, "OVERLAY")
	lib:SetType(row.name, "body")
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.name:SetPoint("LEFT", NUMBER_WIDTH, 0)
	-- Centered in what follows the number, by anchors, so it is right before the page has a width to measure.
	row.arrows = CreateFrame("Frame", nil, row)
	row.arrows:SetSize(ARROWS_WIDTH, ROW_HEIGHT)
	row.arrows:SetPoint("CENTER", row, "CENTER", NUMBER_WIDTH / 2, 0)
	row.name:SetPoint("RIGHT", row.arrows, "LEFT", -8, 0)
	row.up = Arrow(row.arrows, "minimal-scrollbar-arrow-top")
	row.up:SetPoint("RIGHT", row.arrows, "CENTER", -ARROW_GAP / 2, 0)
	row.down = Arrow(row.arrows, "minimal-scrollbar-arrow-bottom")
	row.down:SetPoint("LEFT", row.arrows, "CENTER", ARROW_GAP / 2, 0)
	row.up:SetScript("OnClick", function() view:Move(row.item, -1) end)
	row.down:SetScript("OnClick", function() view:Move(row.item, 1) end)
	row.check = CreateFrame("CheckButton", nil, row, "MinimalCheckboxTemplate")
	row.check:SetSize(30, 29)
	row.check:SetPoint("RIGHT", -CHECKBOX_RIGHT, 0)
	row.check:SetScript("OnClick", function()
		local on = row.check:GetChecked() and true or false
		PlaySound(on and SOUND_ON or SOUND_OFF)
		if view.setting then
			view.setting:SetItemEnabled(row.item, on)
		end
	end)

	return row
end

function lib:CreateOrderedList(parent)
	local view = setmetatable({ rows = {}, active = true }, listMeta)
	view.frame = CreateFrame("Frame", nil, parent)

	return view
end

-- Across the line between the half's insets.
function lib.OrderedList:Place(half)
	self.frame:SetPoint("TOPLEFT", half, "TOPLEFT", 0, -8)
	self.frame:SetPoint("BOTTOMRIGHT", half, "BOTTOMRIGHT", -64, 8)
end

function lib.OrderedList:Bind(setting)
	self.setting = setting
	self:Update()
end

function lib.OrderedList:Update(_, refused)
	local setting = self.setting
	if not setting then
		return
	end
	local items = setting:OrderedItems()
	local height = math.max(#items, 1) * ROW_HEIGHT
	-- The page sizes the row from the setting's height: a list that gains or loses items lays the page out again.
	if height ~= setting.height then
		setting.height = height
		if self.frame:IsVisible() then
			C_Timer.After(0, function() setting.window:LayoutPage() end)
		end
	end
	for index, item in ipairs(items) do
		local row = self.rows[index]
		if not row then
			row = CreateRow(self)
			self.rows[index] = row
		end
		row.item = item
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
		row.line:SetShown(index > 1)
		row.number:SetText(index)
		row.name:SetText(item.text)
		local on = setting:ItemEnabled(item.value)
		row.name:SetAlpha(on and 1 or OFF_ALPHA)
		row.check:SetShown(setting.enabled ~= nil)
		row.check:SetChecked(on)
		row.check:SetEnabled(self.active)
		local first, last = index == 1, index == #items
		row.up:SetEnabled(self.active and not first)
		row.up:SetAlpha(first and END_ALPHA or 1)
		row.down:SetEnabled(self.active and not last)
		row.down:SetAlpha(last and END_ALPHA or 1)
		row:Show()
	end
	for index = #items + 1, #self.rows do
		self.rows[index]:Hide()
	end
	if refused then
		lib:Shake(self.frame)
	end
end

---Moves an item one shown place up or down, recorded for Undo as a change of the order.
function lib.OrderedList:Move(item, step)
	local setting = self.setting
	if not setting or not item then
		return
	end
	local shown = {}
	for _, other in ipairs(setting:OrderedItems()) do
		shown[other.value] = true
	end
	local moved = lib:MoveInOrder(lib:FullOrder(setting:GetValue(), setting.default), item.value, step, shown)
	if moved then
		PlaySound(SOUND_MOVE)
		setting:Request(moved)
	end
end

function lib.OrderedList:Release()
	self.setting = nil
end

function lib.OrderedList:SetActive(active)
	self.active = active
	self:Update()
end

function lib.OrderedList:GetWidth()
	return 0
end

lib:RegisterControl("OrderedList", {
	fields = { title = true, items = true, enabled = true },
	Format = function() return L.EARLIER_ORDER end,
	Init = function(setting)
		setting.wide = true
		setting.height = ROW_HEIGHT
		if setting.enabled ~= nil and (type(setting.enabled) ~= "table" or type(setting.enabled.path) ~= "string") then
			lib:Report(setting.window.addonName, ("%s/%s: enabled needs a path"):format(setting.page.id, setting.id))
			setting.enabled = nil
		end
	end,
	Create = function(half) return lib:CreateOrderedList(half) end,
})
