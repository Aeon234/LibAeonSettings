-- C-11, the dropdown: Blizzard's WowStyle1DropdownTemplate (no step arrows) with Blizzard's menu as a single-choice
-- list, 220 wide. Choices are in Title Case. Pickers: a font picker draws each choice in its own font (Fonts.lua), a
-- texture picker over a sample of its texture, and a sound picker has a speaker left of the button that plays the
-- saved choice (Media.lua). A choice may ask before it saves; a dropdown may be narrower than 220, or fit its choices.
-- An action dropdown keeps no choice: picking runs its `set`, Undo leaves it out and the button shows its placeholder.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

local HEIGHT, TEXT_SIZE = 25, 14
local SCROLL_AFTER, ENTRY_HEIGHT = 20, 20
local MENU_INSETS, ENTRY_PADDING, RADIO_MARK, SCROLL_BAR = 16, 20, 20, 18
local SAMPLE_ALPHA = 0.6
local SPEAKER_SIZE, SPEAKER_ICON, SPEAKER_GAP, SPEAKER_GRAY = 24, 20, 4, 0.85
local FIT_MIN = 90

lib.Dropdown = {}
local dropdownMeta = { __index = function(_, name) return lib.Dropdown[name] end }
lib.DropdownHandlers = lib.DropdownHandlers or {}
local Handlers = lib.DropdownHandlers

local function Choices(setting)
	if setting.picker == "font" then
		return lib:FontChoices()
	elseif setting.picker == "texture" then
		return lib:TextureChoices()
	end
	local options = setting.options
	if type(options) == "function" then
		options = lib.CallAdopter(options, setting)
	end
	options = type(options) == "table" and options or {}
	if setting.picker == "sound" then
		return lib:SoundChoices(options)
	end

	return options
end

-- The saved choice, or nil when the list no longer has it.
local function SavedChoice(setting)
	local value = setting:GetValue()
	for _, choice in ipairs(Choices(setting)) do
		if not choice.title and choice.value == value then
			return choice
		end
	end
end

-- The view's frame holds the button and, for a sound picker, the speaker, so a refused-save shake and the inactive
-- dimming move and cover both.
function lib:CreateDropdown(parent)
	local view = setmetatable({}, dropdownMeta)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(lib.VALUE_WIDTH, HEIGHT)
	local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("RIGHT")
	dropdown:SetSize(lib.VALUE_WIDTH, HEIGHT)
	dropdown:EnableMouseWheel(false)
	lib:SetFont(dropdown.Text, "body", TEXT_SIZE)
	dropdown:SetupMenu(function(_, root) Handlers.Generate(view, root) end)
	-- Measures choices for a dropdown that fits them.
	view.measure = dropdown:CreateFontString(nil, "ARTWORK")
	lib:SetFont(view.measure, "body", TEXT_SIZE)
	view.measure:Hide()
	dropdown:RegisterCallback(DropdownButtonMixin.Event.OnMenuOpen, function() Handlers.Opened(view) end, view)
	-- A texture picker's saved texture, behind the closed button's text.
	local sample = dropdown:CreateTexture(nil, "ARTWORK")
	sample:SetAlpha(SAMPLE_ALPHA)
	sample:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 6, -4)
	sample:SetPoint("BOTTOMRIGHT", dropdown.Arrow, "BOTTOMLEFT", 0, 9)
	sample:Hide()

	local speaker = CreateFrame("Button", nil, frame)
	speaker:SetSize(SPEAKER_SIZE, SPEAKER_SIZE)
	speaker:SetPoint("LEFT")
	speaker.icon = speaker:CreateTexture(nil, "ARTWORK")
	speaker.icon:SetAtlas("voicechat-icon-speaker")
	speaker.icon:SetSize(SPEAKER_ICON, SPEAKER_ICON)
	speaker.icon:SetPoint("CENTER")
	speaker.icon:SetVertexColor(SPEAKER_GRAY, SPEAKER_GRAY, SPEAKER_GRAY)
	speaker:SetScript("OnEnter", function() Handlers.SpeakerEnter(view) end)
	speaker:SetScript("OnLeave", function() Handlers.SpeakerLeave(view) end)
	speaker:SetScript("OnMouseDown", function() Handlers.SpeakerDown(view) end)
	speaker:SetScript("OnMouseUp", function() Handlers.SpeakerUp(view) end)
	speaker:SetScript("OnClick", function() Handlers.Play(view) end)
	speaker:Hide()
	view.frame, view.dropdown, view.sample, view.speaker = frame, dropdown, sample, speaker
	view.width = lib.VALUE_WIDTH

	return view
end

function Handlers.SpeakerEnter(view)
	local speaker = view.speaker
	if speaker:IsEnabled() then
		speaker.icon:SetVertexColor(1, 1, 1)
	end
	GameTooltip:SetOwner(speaker, "ANCHOR_TOP")
	GameTooltip:SetText(L.PLAY_SOUND, 1, 1, 1)
	GameTooltip:Show()
end

function Handlers.SpeakerLeave(view)
	local speaker = view.speaker
	speaker.icon:SetVertexColor(SPEAKER_GRAY, SPEAKER_GRAY, SPEAKER_GRAY)
	speaker.icon:SetPoint("CENTER")
	if GameTooltip:IsOwned(speaker) then
		GameTooltip:Hide()
	end
end

function Handlers.SpeakerDown(view)
	if view.speaker:IsEnabled() then
		view.speaker.icon:SetPoint("CENTER", 1, -1)
	end
end

function Handlers.SpeakerUp(view)
	view.speaker.icon:SetPoint("CENTER")
end

-- Plays the saved choice's sound; never changes the choice.
function Handlers.Play(view)
	local choice = view.setting and SavedChoice(view.setting)
	if choice then
		lib:PlayChoiceSound(choice)
	end
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
	local width = view.width
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
				if choice.texture then
					local sample = button:AttachTexture()
					sample:SetTexture(choice.texture)
					sample:SetDrawLayer("BACKGROUND")
					sample:SetAlpha(SAMPLE_ALPHA)
					sample:SetPoint("TOPLEFT", 18, -2)
					sample:SetPoint("BOTTOMRIGHT", -2, 2)
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
					local r, g, b = lib:GetColor("destructive")
					tooltip:AddLine(choice.blocked, r, g, b, true)
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
		scrollBox:ScrollToElementDataIndex(view.selectedIndex, ScrollBoxConstants.AlignCenter, 0,
			ScrollBoxConstants.NoScrollInterpolation)
	end
end

-- Saves a picked choice, first asking the setting's `confirm(value)` question when it gives one; Cancel saves
-- nothing.
function Handlers.Picked(view, value)
	local setting = view.setting
	if not setting or setting:GetValue() == value then
		return
	end
	local question = setting.confirm
	if type(question) == "function" then
		question = lib.CallAdopter(question, value, setting)
	end
	if not question then
		setting:Request(value)
		return
	end
	lib:CloseConfirm(view.confirming)
	view.confirming = lib:Confirm(question, setting.verb, function()
		view.confirming = nil
		if view.setting == setting then
			setting:Request(value)
		end
	end)
end

-- A value's name in the list, or the value as it is when the list no longer has it.
local function ChoiceText(setting, value)
	-- A font's or texture's name is its value, so the list is not built only to show it.
	if setting.picker == "font" or setting.picker == "texture" then
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

-- The closed button shows the saved choice's name, and a texture picker's texture behind it.
function lib.Dropdown:ShowValue()
	local setting = self.setting
	local value = setting:GetValue()
	self.dropdown:OverrideText(ChoiceText(setting, value) or setting.placeholder or "")
	local texture = setting.picker == "texture" and lib:TextureFile(value)
	if texture then
		self.sample:SetTexture(texture)
	end
	self.sample:SetShown(texture and true or false)
end

-- The width that fits the longest choice (and the placeholder): its text, the radio mark, the entry's padding and
-- the menu's insets, plus the scroll bar for a list that scrolls; at least 90. Each choice is measured in the font
-- its entry draws in (the menu's GameFontHighlight, or the picker's font), the placeholder in the button's.
local function FitWidth(view, setting)
	local measure = view.measure
	local widest = 0
	local choices = Choices(setting)
	local isPicker = setting.picker ~= nil or setting.titleCase == false
	for _, choice in ipairs(choices) do
		local text = isPicker and choice.text or lib.TitleCase(tostring(choice.text or choice.value))
		measure:SetFontObject(choice.font and lib:PickerFont(choice.font) or "GameFontHighlight")
		measure:SetText(text or "")
		widest = math.max(widest, measure:GetUnboundedStringWidth())
	end
	lib:SetFont(measure, "body", TEXT_SIZE)
	if setting.placeholder then
		measure:SetText(setting.placeholder)
		widest = math.max(widest, measure:GetUnboundedStringWidth())
	end
	local width = math.ceil(widest) + RADIO_MARK + ENTRY_PADDING + MENU_INSETS
	if #choices > SCROLL_AFTER then
		width = width + SCROLL_BAR
	end

	return math.max(FIT_MIN, width)
end

-- The control is the setting's `width` (a number, "fit", or 220). A sound picker's button is narrower by the
-- speaker and its gap, so the two together keep both edges in line.
function lib.Dropdown:Bind(setting)
	lib:CloseConfirm(self.confirming)
	self.confirming = nil
	self.setting = setting
	local sound = setting.picker == "sound"
	local width = setting.width == "fit" and FitWidth(self, setting) or tonumber(setting.width) or lib.VALUE_WIDTH
	if sound and setting.width == "fit" then
		width = width + SPEAKER_SIZE + SPEAKER_GAP
	end
	self.total = width
	self.width = sound and width - SPEAKER_SIZE - SPEAKER_GAP or width
	self.frame:SetWidth(self.total)
	self.dropdown:SetWidth(self.width)
	self.speaker:SetShown(sound)
	self:ShowValue()
end

function lib.Dropdown:Update(_, refused)
	self:ShowValue()
	if refused then
		lib:Shake(self.frame)
	end
end

-- Releasing or going inactive closes the list and a confirmation still open.
function lib.Dropdown:Release()
	self.dropdown:CloseMenu()
	lib:CloseConfirm(self.confirming)
	self.confirming = nil
	Handlers.SpeakerLeave(self)
	self.setting = nil
end

function lib.Dropdown:SetActive(active)
	if not active then
		self.dropdown:CloseMenu()
		lib:CloseConfirm(self.confirming)
		self.confirming = nil
		Handlers.SpeakerLeave(self)
	end
	self.dropdown:SetEnabled(active)
	self.speaker:SetEnabled(active)
end

function lib.Dropdown:GetWidth()
	return self.total or lib.VALUE_WIDTH
end

-- An action dropdown needs only `set`: it reads as no choice, and Undo does not record its picks.
local function Init(setting)
	if not setting.action then
		return
	end
	setting.noUndo = true
	if not setting.set then
		lib:Report(setting.window.addonName, ("%s/%s: an action dropdown needs set"):format(setting.page.id,
			tostring(setting.id)))
	end
	if not setting.get and not setting.path then
		setting.get = function() return nil end
	end
end

lib:RegisterControl("Dropdown", {
	fields = { options = true, picker = true, placeholder = true, titleCase = true, confirm = true, verb = true,
		width = true, action = true },
	Init = Init,
	Format = ChoiceText,
	Create = function(half) return lib:CreateDropdown(half) end,
})
