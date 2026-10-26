-- C-18, the profile dialogs: naming a profile (new, copy, rename), exporting, importing (with the adapter's report
-- lines, Hearthline Q85), and choosing the profile that replaces a deleted one. One dialog per window, built the
-- first time, in the window's own frame (SettingsFrameTemplate) over it; it closes when the window hides.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L
local Profiles = lib.Profiles

-- C-18 values.
local NARROW, WIDE = 356, 520
local INSET_X, INSET_TOP, INSET_BOTTOM = 18, 34, 16
local MESSAGE_SIZE, SMALL_SIZE = 14, 12
local MESSAGE_GAP = 10
local WELL_HEIGHT, WELL_GAP = 180, 6
local WELL_TEXT_LEFT, WELL_TEXT_RIGHT, WELL_TEXT_Y, SCROLL_GAP = 8, 22, 8, 6
local SUMMARY_STEP, REPORT_GAP = 20, 4
local NAME_HEIGHT, NAME_STEP, NAME_INSET = 22, 26, 5
local NAME_GAP = 8 -- extra room above the name box when the import's summary and report sit over it
local ERROR_STEP = 18
local CHOICE_WIDTH, CHOICE_HEIGHT, CHOICE_STEP = 256, 25, 34
local BUTTON_WIDTH, BUTTON_HEIGHT, BUTTON_GAP, BUTTONS_GAP = 120, 26, 8, 8
local RAISE = 80 -- first shown this far above the window's center
local REPORT_ALPHA = 0.72
local BULLET = "|cffc9a54e•|r  "
local WELL_BACKING = { 0, 0, 0, 0.9 }
-- The kit's dialog fill: the panel color, opaque so the page never shows through, under black at 0.45.
local FILL, FILL_SHADE = { 0.122, 0.118, 0.129, 1 }, { 0, 0, 0, 0.45 }
local FILL_LEFT, FILL_TOP, FILL_RIGHT, FILL_BOTTOM = 2, 20, 2, 3
local CLICK_SOUND = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON

lib.ProfileDialogHandlers = lib.ProfileDialogHandlers or {}
local Handlers = lib.ProfileDialogHandlers

-- The large box's font, a named font object as ScrollingEditBoxTemplate takes.
local function WellFont()
	if not lib.dialogFont then
		lib.dialogFont = CreateFont("LibAeonSettingsDialogFont")
		lib:SetFont(lib.dialogFont, "body", SMALL_SIZE)
		lib.dialogFont:SetTextColor(1, 1, 1)
	end

	return "LibAeonSettingsDialogFont"
end

local function Text(parent, size, color)
	local text = parent:CreateFontString(nil, "OVERLAY")
	lib:SetFont(text, "body", size)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	text:SetWordWrap(true)
	if color then
		text:SetTextColor(unpack(color))
	end

	return text
end

local function Button(dialog, onClick)
	local button = CreateFrame("Button", nil, dialog, "SharedButtonTemplate")
	button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
	button:SetText(" ")
	lib:SetFont(button:GetFontString(), "body", MESSAGE_SIZE)
	button:SetScript("OnClick", function()
		PlaySound(CLICK_SOUND)
		onClick()
	end)

	return button
end

-- Building ---------------------------------------------------------------------------------------------------

local function Build(window)
	local dialog = lib:CreateSettingsShell(window.frame:GetName() .. "ProfileDialog", window.frame, "DIALOG")
	for sublevel, color in ipairs({ FILL, FILL_SHADE }) do
		local fill = dialog:CreateTexture(nil, "BACKGROUND", nil, sublevel - 8)
		fill:SetPoint("TOPLEFT", FILL_LEFT, -FILL_TOP)
		fill:SetPoint("BOTTOMRIGHT", -FILL_RIGHT, FILL_BOTTOM)
		fill:SetColorTexture(unpack(color))
	end
	dialog.ClosePanelButton:SetScript("OnClick", function() window:CloseProfileDialog() end)
	-- Escape closes the dialog alone (a box that has focus takes Escape first and lets go of it).
	dialog:EnableKeyboard(true)
	dialog:SetScript("OnKeyDown", function(_, key) Handlers.Key(window, key) end)
	dialog:SetScript("OnHide", function() Handlers.Hidden(window) end)

	dialog.message = Text(dialog, MESSAGE_SIZE)

	-- The large box: ScrollingEditBoxTemplate in GameTooltip's frame.
	local well = CreateFrame("Frame", nil, dialog)
	well:SetHeight(WELL_HEIGHT)
	local backing = well:CreateTexture(nil, "BACKGROUND", nil, -8)
	backing:SetPoint("TOPLEFT", 3, -3)
	backing:SetPoint("BOTTOMRIGHT", -3, 3)
	backing:SetColorTexture(unpack(WELL_BACKING))
	well.NineSlice = CreateFrame("Frame", nil, well, "NineSlicePanelTemplate")
	well.NineSlice:SetAllPoints()
	well.NineSlice:SetFrameLevel(well:GetFrameLevel())
	NineSliceUtil.ApplyLayoutByName(well.NineSlice, "TooltipDefaultLayout")
	if TOOLTIP_DEFAULT_BACKGROUND_COLOR then
		well.NineSlice:SetCenterColor(TOOLTIP_DEFAULT_BACKGROUND_COLOR:GetRGB())
	end
	local box = CreateFrame("Frame", nil, well, "ScrollingEditBoxTemplate")
	box:SetPoint("TOPLEFT", WELL_TEXT_LEFT, -WELL_TEXT_Y)
	box:SetPoint("BOTTOMRIGHT", -WELL_TEXT_RIGHT, WELL_TEXT_Y)
	box:SetFrameLevel(well:GetFrameLevel() + 2)
	box:SetFontObject(WellFont())
	local bar = CreateFrame("EventFrame", nil, well, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", box, "TOPRIGHT", SCROLL_GAP, 0)
	bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", SCROLL_GAP, 0)
	ScrollUtil.RegisterScrollBoxWithScrollBar(box:GetScrollBox(), bar)
	box:RegisterCallback("OnTextChanged", function(_, _, userChanged) Handlers.WellChanged(window, userChanged) end,
		well)
	box:GetEditBox():SetScript("OnEscapePressed", function(editBox) editBox:ClearFocus() end)
	well.box, well.bar = box, bar
	dialog.well = well

	dialog.summary = Text(dialog, SMALL_SIZE)
	dialog.summary:SetWordWrap(false)
	dialog.report = Text(dialog, SMALL_SIZE)
	dialog.report:SetAlpha(REPORT_ALPHA)

	local nameBox = CreateFrame("EditBox", nil, dialog, "InputBoxInstructionsTemplate")
	nameBox:SetHeight(NAME_HEIGHT)
	nameBox:SetAutoFocus(false)
	nameBox:SetMaxLetters(32)
	lib:SetFont(nameBox, "body", MESSAGE_SIZE)
	lib:SetFont(nameBox.Instructions, "body", MESSAGE_SIZE)
	nameBox:HookScript("OnTextChanged", function(_, userInput) Handlers.NameChanged(window, userInput) end)
	nameBox:SetScript("OnEnterPressed", function() Handlers.Enter(window) end)
	nameBox:SetScript("OnEscapePressed", function() nameBox:ClearFocus() end)
	dialog.nameBox = nameBox

	dialog.errorLine = Text(dialog, SMALL_SIZE, { lib:Color("destructive") })
	dialog.errorLine:SetWordWrap(false)

	local choice = CreateFrame("DropdownButton", nil, dialog, "WowStyle1DropdownTemplate")
	choice:SetSize(CHOICE_WIDTH, CHOICE_HEIGHT)
	lib:SetFont(choice.Text, "body", MESSAGE_SIZE)
	choice:SetupMenu(function(_, root) Handlers.Choices(window, root) end)
	dialog.choice = choice

	dialog.cancel = Button(dialog, function() window:CloseProfileDialog() end)
	dialog.cancel:SetPoint("BOTTOMRIGHT", -INSET_X, INSET_BOTTOM)
	dialog.action = Button(dialog, function() Handlers.Action(window) end)
	dialog.action:SetPoint("RIGHT", dialog.cancel, "LEFT", -BUTTON_GAP, 0)

	window.frame:HookScript("OnHide", function() window:CloseProfileDialog() end)
	window.profileDialog = dialog

	return dialog
end

-- Laying out -------------------------------------------------------------------------------------------------

-- Stacks the shown parts from the top, then sizes the dialog to them: insets, content, 8, the buttons.
local function Layout(dialog)
	local width = dialog:GetWidth()
	local inner = width - 2 * INSET_X
	local y = INSET_TOP
	local function Place(region, height, step, x, regionWidth)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", dialog, "TOPLEFT", INSET_X + (x or 0), -y)
		region:SetWidth(regionWidth or inner)
		if height then
			region:SetHeight(height)
		end
		y = y + step
	end
	dialog.message:SetWidth(inner)
	Place(dialog.message, nil, math.ceil(dialog.message:GetStringHeight()) + MESSAGE_GAP)
	if dialog.well:IsShown() then
		Place(dialog.well, WELL_HEIGHT, WELL_HEIGHT + WELL_GAP)
	end
	if dialog.summary:IsShown() then
		Place(dialog.summary, 16, SUMMARY_STEP)
	end
	if dialog.report:IsShown() then
		dialog.report:SetWidth(inner)
		Place(dialog.report, nil, math.ceil(dialog.report:GetStringHeight()) + REPORT_GAP)
	end
	if dialog.nameBox:IsShown() then
		if dialog.summary:IsShown() then
			y = y + NAME_GAP
		end
		Place(dialog.nameBox, NAME_HEIGHT, NAME_STEP, NAME_INSET, inner - 6)
	end
	if dialog.errorLine:IsShown() then
		Place(dialog.errorLine, 16, ERROR_STEP)
	end
	if dialog.choice:IsShown() then
		Place(dialog.choice, CHOICE_HEIGHT, CHOICE_STEP, 0, CHOICE_WIDTH)
	end
	dialog:SetHeight(y + BUTTONS_GAP + BUTTON_HEIGHT + INSET_BOTTOM)
end

-- Opening ----------------------------------------------------------------------------------------------------

local KINDS = {
	new = { title = "NEW_PROFILE", action = "CREATE", width = NARROW },
	copy = { title = "COPY_PROFILE_TITLE", action = "COPY", width = NARROW },
	rename = { title = "RENAME_PROFILE_TITLE", action = "RENAME", width = NARROW },
	export = { title = "EXPORT_PROFILE_TITLE", width = WIDE },
	import = { title = "IMPORT_PROFILE_TITLE", action = "IMPORT", width = WIDE },
	replace = { title = "DELETE_PROFILE_TITLE", action = "DELETE", width = NARROW },
}

---Opens a profile dialog: "new", "copy", "rename", "export", "import" or "replace" (the profile that takes over
---from a deleted one).
function lib.Window:OpenProfileDialog(kind, adapter)
	local spec = KINDS[kind]
	if not spec or not self.frame then
		return
	end
	local dialog = self.profileDialog or Build(self)
	lib:CloseConfirm(self.profileConfirm)
	local current = Profiles.Call(adapter, "Active")
	local state = { kind = kind, adapter = adapter, current = current }
	dialog.state = state
	dialog:SetWidth(spec.width)
	dialog.title:SetText(L[spec.title])
	dialog.action:SetShown(spec.action ~= nil)
	dialog.action:SetText(spec.action and L[spec.action] or "")
	dialog.cancel:SetText(spec.action and CANCEL or CLOSE)
	local shown = lib:ProfileName(current)

	local naming = kind == "new" or kind == "copy" or kind == "rename"
	dialog.well:SetShown(kind == "export" or kind == "import")
	dialog.summary:SetShown(false)
	dialog.report:SetShown(false)
	dialog.nameBox:SetShown(naming)
	dialog.errorLine:SetShown(naming)
	dialog.choice:SetShown(kind == "replace")
	dialog.nameBox:SetText(kind == "rename" and shown or "")
	dialog.nameBox.Instructions:SetText(kind == "copy" and L.COPY_OF:format(shown) or L.PROFILE_NAME)
	dialog.errorLine:SetText("")
	dialog.summary:SetText("")
	dialog.report:SetText("")

	if kind == "new" then
		dialog.message:SetText(L.NEW_PROFILE_MESSAGE)
	elseif kind == "copy" then
		dialog.message:SetText(L.COPY_PROFILE_MESSAGE:format(shown))
	elseif kind == "rename" then
		dialog.message:SetText(L.RENAME_PROFILE_MESSAGE:format(shown))
	elseif kind == "export" then
		dialog.message:SetText(L.EXPORT_MESSAGE)
		state.exported = tostring(Profiles.Call(adapter, "Export") or "")
		dialog.well.box:SetText(state.exported)
	elseif kind == "import" then
		dialog.message:SetText(L.IMPORT_MESSAGE)
		dialog.well.box:SetText("")
	else
		dialog.message:SetText(L.DELETE_CHOOSE:format(shown))
		local rest = {}
		for _, name in ipairs(Profiles.List(adapter)) do
			if name ~= current then
				rest[#rest + 1] = name
			end
		end
		state.rest, state.replacement = rest, rest[1]
		dialog.choice:GenerateMenu()
	end

	Layout(dialog)
	dialog:ClearAllPoints()
	dialog:SetPoint("CENTER", self.frame, "CENTER", 0, RAISE)
	-- Keys reach the game while the dialog shows, all but Escape (Handlers.Key); the window never opens in combat,
	-- where this call is restricted.
	if not InCombatLockdown() then
		dialog:SetPropagateKeyboardInput(true)
	end
	dialog:Show()
	dialog:Raise()
	Handlers.Validate(self)
	if naming then
		dialog.nameBox:SetFocus()
		dialog.nameBox:HighlightText()
	elseif kind == "export" then
		Handlers.SelectExport(self)
	elseif kind == "import" then
		dialog.well.box:SetFocus()
	end
end

function lib.Window:CloseProfileDialog()
	local dialog = self.profileDialog
	if dialog and dialog:IsShown() then
		dialog:Hide()
	end
end

-- Behavior ---------------------------------------------------------------------------------------------------

local function Names(state)
	return Profiles.List(state.adapter)
end

-- Checks the dialog as it stands: the action is inactive until it is valid; a taken or reserved name is said.
function Handlers.Validate(window)
	local dialog = window.profileDialog
	local state = dialog.state
	local kind = state.kind
	local valid, reason = false, nil
	if kind == "new" or kind == "copy" or kind == "rename" then
		local name
		name, reason = lib:CheckProfileName(Names(state), dialog.nameBox:GetText(), kind == "rename" and state.current)
		valid = name ~= nil
		state.name = name
	elseif kind == "import" then
		local info = state.info
		if info then
			local name
			name, reason = lib:CheckProfileName(Names(state), dialog.nameBox:GetText())
			valid = name ~= nil
			state.name = name
		end
	elseif kind == "replace" then
		valid = state.replacement ~= nil
	end
	dialog.errorLine:SetText(reason or "")
	dialog.action:SetEnabled(valid)
	state.valid = valid
end

function Handlers.NameChanged(window, userInput)
	local dialog = window.profileDialog
	if userInput and dialog and dialog:IsShown() then
		Handlers.Validate(window)
	end
end

-- Export is read-only: an edit puts the text back and selects it again.
function Handlers.SelectExport(window)
	local box = window.profileDialog.well.box
	box:SetFocus()
	box:GetEditBox():HighlightText()
end

-- Import decodes the text on every change: a summary naming the profile (or why it is refused), the adapter's
-- report lines, then the name box once the text is a profile.
function Handlers.WellChanged(window, userChanged)
	local dialog = window.profileDialog
	local state = dialog and dialog.state
	if not state or not dialog:IsShown() then
		return
	end
	if state.kind == "export" then
		if userChanged then
			dialog.well.box:SetText(state.exported)
			Handlers.SelectExport(window)
		end
		return
	end
	if state.kind ~= "import" then
		return
	end
	local text = strtrim(dialog.well.box:GetInputText() or "")
	local info, reason
	if text ~= "" then
		info, reason = Profiles.Call(state.adapter, "Decode", text)
		if type(info) ~= "table" then
			info = nil
			reason = reason or L.NOT_A_PROFILE
		end
	end
	state.info = info
	dialog.summary:SetShown(text ~= "")
	if info then
		dialog.summary:SetText(info.summary or L.IMPORT_SUMMARY:format(window.declaration.title or window.addonName,
			tostring(info.name or "")))
		dialog.summary:SetTextColor(1, 1, 1)
	else
		dialog.summary:SetText(reason or "")
		dialog.summary:SetTextColor(lib:Color("destructive"))
	end
	local report = info and type(info.report) == "table" and info.report or nil
	if report and #report > 0 then
		local lines = {}
		for index, line in ipairs(report) do
			lines[index] = BULLET .. tostring(line)
		end
		dialog.report:SetText(table.concat(lines, "\n"))
		dialog.report:SetShown(true)
	else
		dialog.report:SetShown(false)
	end
	dialog.nameBox:SetShown(info ~= nil)
	dialog.errorLine:SetShown(info ~= nil)
	dialog.nameBox.Instructions:SetText(info and tostring(info.name or "") or "")
	Layout(dialog)
	Handlers.Validate(window)
end

function Handlers.Choices(window, root)
	local dialog = window.profileDialog
	local state = dialog and dialog.state
	if not state or not state.rest then
		return
	end
	for _, name in ipairs(state.rest) do
		root:CreateRadio(lib:ProfileName(name), function() return state.replacement == name end, function()
			state.replacement = name
			Handlers.Validate(window)
		end)
	end
end

function Handlers.Enter(window)
	local dialog = window.profileDialog
	if dialog.state and dialog.state.valid then
		Handlers.Action(window)
	end
end

-- Runs the dialog's action through the adapter. A refusal stays in the dialog's error line; success closes it,
-- empties the Undo history, reads every value again and says what happened.
function Handlers.Action(window)
	local dialog = window.profileDialog
	local state = dialog.state
	if not state or not state.valid then
		return
	end
	local adapter, kind = state.adapter, state.kind
	local current = lib:ProfileName(state.current)
	local ok, reason, status
	if kind == "new" then
		ok, reason = Profiles.Call(adapter, "New", state.name)
		status = L.PROFILE_CREATED:format(state.name)
	elseif kind == "copy" then
		ok, reason = Profiles.Call(adapter, "Copy", state.name)
		status = L.PROFILE_COPIED:format(current, state.name)
	elseif kind == "rename" then
		ok, reason = Profiles.Call(adapter, "Rename", state.name)
		status = L.PROFILE_RENAMED:format(current, state.name)
	elseif kind == "import" then
		ok, reason = Profiles.Call(adapter, "Import", state.info, state.name)
		status = L.PROFILE_IMPORTED:format(tostring(state.info.name or ""), state.name)
	elseif kind == "replace" then
		ok, reason = Profiles.Call(adapter, "Delete", state.current, state.replacement)
		status = L.PROFILE_DELETED:format(current, lib:ProfileName(state.replacement))
	end
	if ok == false then
		dialog.errorLine:SetShown(true)
		dialog.errorLine:SetText(reason or L.COULDNT_VERB:format(dialog.action:GetText():lower()))
		Layout(dialog)
		return
	end
	window:CloseProfileDialog()
	Profiles.Finish(window, status)
end

function Handlers.Key(window, key)
	local dialog = window.profileDialog
	if InCombatLockdown() then
		return
	end
	if key == "ESCAPE" then
		dialog:SetPropagateKeyboardInput(false)
		window:CloseProfileDialog()
	else
		dialog:SetPropagateKeyboardInput(true)
	end
end

function Handlers.Hidden(window)
	local dialog = window.profileDialog
	dialog.state = nil
	dialog.nameBox:ClearFocus()
	dialog.well.box:ClearFocus()
end
