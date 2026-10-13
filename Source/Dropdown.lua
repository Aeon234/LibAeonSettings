-- C-11, the dropdown: Blizzard's WowStyle1DropdownTemplate (no step arrows) with Blizzard's menu as a single-choice
-- list, 220 wide. Choices are in Title Case; a font picker draws each choice in its own font. Also the suite's six
-- outline choices and the flags each one gives `SetFont`.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

local HEIGHT, TEXT_SIZE = 25, 14
local SCROLL_AFTER, ENTRY_HEIGHT = 20, 20
local MENU_INSETS, ENTRY_PADDING, RADIO_MARK, SCROLL_BAR = 16, 20, 20, 18
local PICKER_FONT_SIZE = 14
local REASON_COLOR = { 1, 0.549, 0.471 }

-- Blizzard's own fonts under LibSharedMedia's names, plus the library's, for a font picker without LibSharedMedia.
local FALLBACK_FONTS = {
	{ "Arial Narrow", "Fonts\\ARIALN.TTF" },
	{ "Friz Quadrata TT", "Fonts\\FRIZQT__.TTF" },
	{ "Morpheus", "Fonts\\MORPHEUS.TTF" },
	{ "Skurri", "Fonts\\SKURRI.TTF" },
}

-- The suite's six outline choices (Alex, 2026-10-07), always with the Slug variants. `SLUG` is a `SetFont` flag,
-- comma-joined with the outline.
lib.OUTLINES = {
	{ value = "NONE", text = L.OUTLINE_NONE },
	{ value = "OUTLINE", text = L.OUTLINE_OUTLINE },
	{ value = "THICKOUTLINE", text = L.OUTLINE_THICK },
	{ value = "SLUG", text = L.OUTLINE_SLUG },
	{ value = "SLUG_OUTLINE", text = L.OUTLINE_SLUG_OUTLINE },
	{ value = "SLUG_THICKOUTLINE", text = L.OUTLINE_SLUG_THICK },
}
local OUTLINE_FLAGS = { NONE = "", OUTLINE = "OUTLINE", THICKOUTLINE = "THICKOUTLINE", SLUG = "SLUG",
	SLUG_OUTLINE = "SLUG, OUTLINE", SLUG_THICKOUTLINE = "SLUG, THICKOUTLINE" }

---@return string flags for `SetFont`, from one of the six outline values
function lib:OutlineFlags(value)
	return OUTLINE_FLAGS[value] or ""
end

lib.Dropdown = {}
local dropdownMeta = { __index = function(_, name) return lib.Dropdown[name] end }
local Handlers = {}
lib.DropdownHandlers = Handlers

-- One font object per file, for drawing a font picker's choices. Font objects are named globals.
lib.pickerFonts = lib.pickerFonts or {}
local function PickerFont(file)
	local font = lib.pickerFonts[file]
	if not font then
		lib.pickerFontCount = (lib.pickerFontCount or 0) + 1
		font = CreateFont("LibAeonSettingsPickerFont" .. lib.pickerFontCount)
		font:SetFont(file, PICKER_FONT_SIZE, "")
		font:SetTextColor(1, 1, 1)
		lib.pickerFonts[file] = font
	end

	return font
end

-- The choices of a font picker: LibSharedMedia's fonts, read each time the list opens, or the fallback list.
local function FontChoices()
	local choices = {}
	local media = LibStub("LibSharedMedia-3.0", true)
	if media then
		local files = media:HashTable("font")
		for _, name in ipairs(media:List("font")) do
			table.insert(choices, { value = name, text = name, font = files[name] })
		end
	else
		for _, entry in ipairs(FALLBACK_FONTS) do
			table.insert(choices, { value = entry[1], text = entry[1], font = entry[2] })
		end
		table.insert(choices, { value = "Expressway", text = "Expressway", font = lib.mediaPath .. "Fonts\\Expressway.ttf" })
		table.insert(choices, { value = "Gilroy Bold", text = "Gilroy Bold", font = lib.mediaPath .. "Fonts\\GilroyBold.ttf" })
		table.sort(choices, function(a, b) return a.value < b.value end)
	end

	return choices
end

local function Choices(setting)
	if setting.picker == "font" then
		return FontChoices()
	end
	local options = setting.options
	if type(options) == "function" then
		options = lib.CallAdopter(options, setting)
	end

	return type(options) == "table" and options or {}
end

function lib:CreateDropdown(parent)
	local view = setmetatable({}, dropdownMeta)
	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetSize(lib.VALUE_WIDTH, HEIGHT)
	dropdown:EnableMouseWheel(false)
	lib:SetFont(dropdown.Text, "body", TEXT_SIZE)
	dropdown:SetupMenu(function(_, root) Handlers.Generate(view, root) end)
	dropdown:RegisterCallback(DropdownButtonMixin.Event.OnMenuOpen, function() Handlers.Opened(view) end, view)
	view.frame, view.dropdown = dropdown, dropdown

	return view
end

-- Builds the list each time it opens: radios marking the saved choice, titles, blocked choices gray with their
-- reason, every entry as wide as its share of the list.
function Handlers.Generate(view, root)
	local setting = view.setting
	if not setting then
		return
	end
	local choices = Choices(setting)
	local scrolls = #choices > SCROLL_AFTER
	local width = lib.VALUE_WIDTH
	if scrolls then
		root:SetScrollMode(SCROLL_AFTER * ENTRY_HEIGHT)
		root:SetMinimumWidth(width - SCROLL_BAR)
	else
		root:SetMinimumWidth(width)
		root:SetMaximumWidth(width)
	end
	local share = width - MENU_INSETS - ENTRY_PADDING - RADIO_MARK - (scrolls and SCROLL_BAR or 0)
	local isPicker = setting.picker ~= nil
	view.selectedIndex = nil
	for index, choice in ipairs(choices) do
		local text = isPicker and choice.text or lib.TitleCase(tostring(choice.text or choice.value))
		if choice.title then
			root:CreateTitle(text)
		else
			local value = choice.value
			local radio = root:CreateRadio(text,
				function() return view.setting and view.setting:GetValue() == value end,
				function() Handlers.Picked(view, value) end, value)
			if view.setting:GetValue() == value then
				view.selectedIndex = index
			end
			local font = choice.font and PickerFont(choice.font)
			radio:AddInitializer(function(button)
				local fontString = button.fontString
				if not fontString then
					return
				end
				if font then
					fontString:SetFontObject(font)
				end
				-- Every entry measures its full share, so each row spans the list and clicks anywhere on it;
				-- longer names are cut short.
				fontString:SetWordWrap(false)
				fontString:SetJustifyH("LEFT")
				fontString:SetWidth(share)
			end)
			if choice.blocked then
				radio:SetEnabled(false)
				radio:SetTooltip(function(tooltip)
					tooltip:AddLine(choice.blocked, REASON_COLOR[1], REASON_COLOR[2], REASON_COLOR[3], true)
				end)
			elseif choice.tooltip then
				radio:SetTooltip(function(tooltip)
					tooltip:AddLine(choice.tooltip, 1, 1, 1, true)
				end)
			end
		end
	end
end

-- A scrolling list opens with the saved choice in its middle.
function Handlers.Opened(view)
	local menu = view.dropdown.menu
	local scrollBox = menu and menu.ScrollBox
	if view.selectedIndex and scrollBox and scrollBox.ScrollToElementDataIndex and scrollBox:HasDataProvider() then
		scrollBox:ScrollToElementDataIndex(view.selectedIndex, ScrollBoxConstants.AlignCenter,
			ScrollBoxConstants.NoScrollInterpolation)
	end
end

function Handlers.Picked(view, value)
	local setting = view.setting
	if setting and setting:GetValue() ~= value then
		setting:Request(value)
	end
end

-- A value's name in the list, or the value as it is when the list no longer has it.
local function ChoiceText(setting, value)
	for _, choice in ipairs(Choices(setting)) do
		if not choice.title and choice.value == value then
			return setting.picker and choice.text or lib.TitleCase(tostring(choice.text or choice.value))
		end
	end

	return value ~= nil and tostring(value) or nil
end

-- The closed button shows the saved choice's name.
function lib.Dropdown:ShowValue()
	local setting = self.setting
	self.dropdown:OverrideText(ChoiceText(setting, setting:GetValue()) or setting.placeholder or "")
end

function lib.Dropdown:Bind(setting)
	self.setting = setting
	self:ShowValue()
end

function lib.Dropdown:Update(_, refused)
	self:ShowValue()
	if refused then
		lib:Shake(self.frame)
	end
end

function lib.Dropdown:Release()
	self.dropdown:CloseMenu()
	self.setting = nil
end

function lib.Dropdown:SetActive(active)
	if not active then
		self.dropdown:CloseMenu()
	end
	self.dropdown:SetEnabled(active)
end

function lib.Dropdown:GetWidth()
	return lib.VALUE_WIDTH
end

lib:RegisterControl("Dropdown", {
	fields = { options = true, picker = true, placeholder = true },
	Format = ChoiceText,
	Create = function(half) return lib:CreateDropdown(half) end,
})
