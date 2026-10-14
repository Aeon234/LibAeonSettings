-- C-11, the dropdown: Blizzard's WowStyle1DropdownTemplate (no step arrows) with Blizzard's menu as a single-choice
-- list, 220 wide. Choices are in Title Case; a font picker draws each choice in its own font (Fonts.lua).

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local HEIGHT, TEXT_SIZE = 25, 14
local SCROLL_AFTER, ENTRY_HEIGHT = 20, 20
local MENU_INSETS, ENTRY_PADDING, RADIO_MARK, SCROLL_BAR = 16, 20, 20, 18
local REASON_COLOR = { 1, 0.549, 0.471 }

lib.Dropdown = {}
local dropdownMeta = { __index = function(_, name) return lib.Dropdown[name] end }
lib.DropdownHandlers = lib.DropdownHandlers or {}
local Handlers = lib.DropdownHandlers

local function Choices(setting)
	if setting.picker == "font" then
		return lib:FontChoices()
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
	local isPicker = setting.picker ~= nil or setting.titleCase == false
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
			local font = choice.font and lib:PickerFont(choice.font)
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
	-- A font's name is its value, so the font list is not built only to show it.
	if setting.picker == "font" then
		return value ~= nil and tostring(value) or nil
	end
	for _, choice in ipairs(Choices(setting)) do
		if not choice.title and choice.value == value then
			return (setting.picker or setting.titleCase == false) and choice.text
				or lib.TitleCase(tostring(choice.text or choice.value))
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
	fields = { options = true, picker = true, placeholder = true, titleCase = true },
	Format = ChoiceText,
	Create = function(half) return lib:CreateDropdown(half) end,
})
