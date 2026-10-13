-- C-13, the text input: Blizzard's InputBoxInstructionsTemplate, one line, 220 in all; the default shows gray as
-- the placeholder while the box is empty. Enter or clicking away saves; Escape puts the saved text back.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

local BOX_INSET, BOX_HEIGHT = 5, 22 -- the template's left border hangs 5 outside the box
local TEXT_SIZE = 14

lib.TextInput = {}
local textMeta = { __index = function(_, name) return lib.TextInput[name] end }
local Handlers = {}
lib.TextInputHandlers = Handlers

function lib:CreateTextInput(parent)
	local view = setmetatable({}, textMeta)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(lib.VALUE_WIDTH, lib.CONTROL_HEIGHT)
	local box = CreateFrame("EditBox", nil, frame, "InputBoxInstructionsTemplate")
	box:SetPoint("LEFT", BOX_INSET, 0)
	box:SetPoint("RIGHT")
	box:SetHeight(BOX_HEIGHT)
	box:SetAutoFocus(false)
	lib:SetFont(box, "body", TEXT_SIZE)
	box:SetScript("OnEnterPressed", function() Handlers.Commit(view) end)
	box:SetScript("OnEscapePressed", function() view.cancelling = true; box:ClearFocus() end)
	box:HookScript("OnEditFocusLost", function() Handlers.FocusLost(view) end)
	view.frame, view.box = frame, box

	return view
end

local function Trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Draws the saved text, unless the player is typing.
function lib.TextInput:ShowValue()
	local setting = self.setting
	if not setting or self.box:HasFocus() then
		return
	end
	local value = setting:GetValue()
	if value == setting.default and setting.allowEmpty then
		value = ""
	end
	self.box:SetText(value or "")
	self.box:SetCursorPosition(0)
end

function lib.TextInput:Bind(setting)
	self.setting = setting
	self.box:ClearFocus()
	self.box.Instructions:SetText(setting.default or "")
	self.box:SetMaxLetters(setting.maxLetters or 0)
	self:ShowValue()
end

function lib.TextInput:Update(_, refused)
	self:ShowValue()
	if refused then
		lib:Shake(self.frame)
	end
end

function lib.TextInput:Release()
	self.cancelling = true
	self.box:ClearFocus()
	self.cancelling = nil
	self.setting = nil
end

-- Going inactive drops an edit in progress.
function lib.TextInput:SetActive(active)
	if not active and self.box:HasFocus() then
		self.cancelling = true
		self.box:ClearFocus()
	end
	self.box:SetEnabled(active)
end

function lib.TextInput:GetWidth()
	return lib.VALUE_WIDTH
end

-- Saves the typed text by the setting's rules (empty allowed or not, its length, its check), or refuses it.
function Handlers.Commit(view)
	local setting = view.setting
	if not setting then
		return
	end
	local text = Trim(view.box:GetText())
	view.cancelling = true
	view.box:ClearFocus()
	view.cancelling = nil
	local reason
	if text == "" and not setting.allowEmpty then
		reason = L.CANT_BE_EMPTY
	elseif setting.maxLetters and strlenutf8(text) > setting.maxLetters then
		reason = L.MAX_LETTERS:format(setting.maxLetters)
	elseif text ~= "" and setting.validate then
		reason = lib.CallAdopter(setting.validate, text, setting)
	end
	if reason then
		setting:Refuse(reason)
		return
	end
	local value = text
	if text == "" then
		value = setting.default
	end
	if value == setting:GetValue() then
		view:ShowValue()
		return
	end
	setting:Request(value)
end

-- Clicking away saves, as Enter does; Escape, a recycled row or going inactive puts the saved text back.
function Handlers.FocusLost(view)
	if view.cancelling then
		view.cancelling = nil
		view:ShowValue()
		return
	end
	Handlers.Commit(view)
end

lib:RegisterControl("TextInput", {
	fields = { allowEmpty = true, maxLetters = true, validate = true },
	Create = function(half) return lib:CreateTextInput(half) end,
})
