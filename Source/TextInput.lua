-- C-13, the text input: Blizzard's InputBoxInstructionsTemplate, one line, 220 in all; the default shows gray as
-- the placeholder while the box is empty. Enter or clicking away saves; Escape puts the saved text back. The setting
-- remembers where the cursor was when the box last lost focus, so a control beside it can insert text there.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

local BOX_INSET, BOX_HEIGHT = 5, 22 -- the template's left border hangs 5 outside the box
local TEXT_SIZE = 14

lib.TextInput = {}
local textMeta = { __index = function(_, name) return lib.TextInput[name] end }
lib.TextInputHandlers = lib.TextInputHandlers or {}
local Handlers = lib.TextInputHandlers

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
	box:SetScript("OnEscapePressed", function() view.canceling = true; box:ClearFocus() end)
	box:HookScript("OnEditFocusLost", function() Handlers.FocusLost(view) end)
	view.frame, view.box = frame, box

	return view
end

local function Trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The text the box shows for a value: the default shows as the empty box's placeholder when empty is allowed.
local function ShownText(setting, value)
	if value == setting.default and setting.allowEmpty then
		return ""
	end

	return value ~= nil and tostring(value) or ""
end

-- Why `text` cannot be saved by the setting's rules (empty allowed or not, its length, its check), or nil.
local function Reason(setting, text)
	if text == "" and not setting.allowEmpty then
		return L.CANT_BE_EMPTY
	elseif setting.maxLetters and strlenutf8(text) > setting.maxLetters then
		return L.MAX_LETTERS:format(setting.maxLetters)
	elseif text ~= "" and setting.validate then
		return lib.CallAdopter(setting.validate, text, setting)
	end
end

-- The byte offset after the first `characters` UTF-8 characters of `text`, clamped to its length.
---@param text string
---@param characters integer
---@return integer
local function ByteOffset(text, characters)
	local count = 0
	for index = 1, #text do
		local byte = text:byte(index)
		-- A byte that does not continue a multi-byte sequence starts a character.
		if byte < 0x80 or byte >= 0xC0 then
			if count == characters then
				return index - 1
			end
			count = count + 1
		end
	end

	return #text
end

-- Draws the saved text, unless the player is typing.
function lib.TextInput:ShowValue()
	local setting = self.setting
	if not setting or self.box:HasFocus() then
		return
	end
	self.box:SetText(ShownText(setting, setting:GetValue()))
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
	self.canceling = true
	self.box:ClearFocus()
	self.canceling = nil
	self.setting = nil
end

-- Going inactive drops an edit in progress.
function lib.TextInput:SetActive(active)
	if not active and self.box:HasFocus() then
		self.canceling = true
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
	view.canceling = true
	view.box:ClearFocus()
	view.canceling = nil
	local reason = Reason(setting, text)
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
	if view.setting then
		view.setting.textCursor = view.box:GetCursorPosition()
	end
	if view.canceling then
		view.canceling = nil
		view:ShowValue()
		return
	end
	Handlers.Commit(view)
end

-- The text cursor ---------------------------------------------------------------------------------------------

---Where the cursor was, in UTF-8 characters, when the text input's box last lost focus; nil before it ever had
---focus. A text input shared by several values (one box for the picked slot) keeps one position for all of them.
---@return integer?
function lib.Setting:TextCursor()
	return self.textCursor
end

---Moves the remembered cursor position (nil forgets it, so the next insertion goes at the end).
---@param position integer?
function lib.Setting:SetTextCursor(position)
	self.textCursor = position
end

---Inserts `text` into a text input's value where its cursor last was (at the end if it never had focus), saves it by
---the input's rules as the player's own change, and leaves the cursor after the insertion. Returns whether it saved.
---@param text string
---@return boolean saved
function lib.Setting:InsertText(text)
	if self.kind ~= "TextInput" then
		lib:Report(self.window.addonName, ("%s/%s: InsertText needs a text input"):format(self.page.id, self.id))
		return false
	end
	text = tostring(text or "")
	local current = ShownText(self, self:GetValue())
	local length = strlenutf8(current)
	local position = math.max(0, math.min(length, math.floor(tonumber(self.textCursor) or length)))
	local offset = ByteOffset(current, position)
	local value = current:sub(1, offset) .. text .. current:sub(offset + 1)
	local reason = Reason(self, value)
	if reason then
		self:Refuse(reason)
		return false
	end
	self.textCursor = position + strlenutf8(text)
	if value == "" then
		value = self.default
	end
	if value == self:GetValue() then
		return true
	end

	return self:Request(value)
end

lib:RegisterControl("TextInput", {
	fields = { allowEmpty = true, maxLetters = true, validate = true },
	Format = function(_, value) return value ~= nil and tostring(value) or "" end,
	Create = function(half) return lib:CreateTextInput(half) end,
})
