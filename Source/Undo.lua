-- Undo (Q69, Q86): one history for the whole window, kept for the game session, behind the footer's Undo button.
-- Every value the user saves is recorded, Clear Overrides as one step; a slider's drag or a color pick in progress
-- (until the picker closes) is one step. Undo puts the earlier value back and lands on its row. Profile actions are not undoable and empty the
-- history (`window:ClearUndo()`); values saved from code (`setting:SetValue`) are not recorded.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

local BUTTON_WIDTH, BUTTON_HEIGHT, BUTTON_GAP, BUTTON_RIGHT = 110, 30, 10, 10 -- kit values
local MERGE_SECONDS = 1.5 -- a slider or color saved again this soon after is the same step
local MERGES = { Slider = true, Color = true }
local MAX_STEPS = 100

local Handlers = {}
lib.UndoHandlers = Handlers

local function Copy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in pairs(value) do
		copy[key] = Copy(inner)
	end

	return copy
end

local function Same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, inner in pairs(a) do
		if not Same(inner, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end

	return true
end

local function History(window)
	window.undoHistory = window.undoHistory or {}

	return window.undoHistory
end

local function Push(window, step)
	local history = History(window)
	history[#history + 1] = step
	if #history > MAX_STEPS then
		table.remove(history, 1)
	end
	window:RefreshUndo()
end

---Records a saved value for Undo (Setting:Request calls it). A slider or swatch saved again within moments joins
---the step before; a step that ends where it began is dropped.
function lib.Window:RecordUndo(setting, before, after)
	if Same(before, after) then
		return
	end
	local history = History(self)
	local last = history[#history]
	local now = GetTime()
	-- A color pick is one step from first save to close; other merges go by time.
	local pick = setting.boundView and setting.boundView.picking or nil
	local joins
	if last and not last.group and last.changes[1].setting == setting and MERGES[setting.kind] then
		if pick then
			joins = last.pick == pick
		else
			joins = not last.pick and now - last.time < MERGE_SECONDS
		end
	end
	if joins then
		last.time = now
		if Same(last.changes[1].before, after) then
			history[#history] = nil
		end
		self:RefreshUndo()
		return
	end
	Push(self, { time = now, pick = pick, changes = { { setting = setting, before = Copy(before) } } })
end

---Records several values put back at once (Clear Overrides) as one step; `changes` is { { setting, before }, ... }.
function lib.Window:RecordUndoGroup(changes)
	if #changes == 0 then
		return
	end
	for _, change in ipairs(changes) do
		change.before = Copy(change.before)
	end
	Push(self, { time = GetTime(), group = true, changes = changes })
end

---Empties the history. Profile actions call it: they are not undoable, and a step recorded before one would change a
---different profile.
function lib.Window:ClearUndo()
	if self.undoHistory then
		wipe(self.undoHistory)
	end
	self:RefreshUndo()
end

---@return boolean undoable whether the history holds a step
function lib.Window:CanUndo()
	return self.undoHistory ~= nil and #self.undoHistory > 0
end

---Puts back the values of the latest step and lands on its (first) row. A value the adopter's `set` refuses keeps
---its current value and shows the refusal.
function lib.Window:Undo()
	local history = self.undoHistory
	local step = history and table.remove(history)
	if not step then
		return
	end
	for index = #step.changes, 1, -1 do
		local change = step.changes[index]
		local ok, reason = lib.WriteSetting(change.setting, Copy(change.before))
		if not ok then
			change.setting:ShowRefusal(reason)
		end
	end
	self:RefreshUndo()
	self:Refresh()
	local setting = step.changes[1].setting
	if self:IsShown() and setting.page and setting:IsShown() then
		self:LandOn(setting)
	end
end

-- The button --------------------------------------------------------------------------------------------------

---Builds the footer's Undo button, left of Open Edit Mode.
function lib.Window:BuildUndo()
	local footer = self.frame.footer
	local button = CreateFrame("Button", nil, footer, "SharedButtonTemplate")
	button:SetText(L.UNDO)
	button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
	button:SetScript("OnClick", function() Handlers.Click(self) end)
	button:SetMotionScriptsWhileDisabled(true)
	button:SetScript("OnEnter", function() Handlers.Enter(self) end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	footer.undo = button
	self:PlaceUndo()
	self:RefreshUndo()
end

-- Beside Open Edit Mode when the window has it, else at the footer's right.
function lib.Window:PlaceUndo()
	local footer = self.frame and self.frame.footer
	local button = footer and footer.undo
	if not button then
		return
	end
	button:ClearAllPoints()
	if footer.editMode:IsShown() then
		button:SetPoint("RIGHT", footer.editMode, "LEFT", -BUTTON_GAP, 0)
	else
		button:SetPoint("RIGHT", -BUTTON_RIGHT, 0)
	end
end

function lib.Window:RefreshUndo()
	local button = self.frame and self.frame.footer and self.frame.footer.undo
	if not button then
		return
	end
	button:SetEnabled(self:CanUndo())
	if GameTooltip:IsOwned(button) then
		Handlers.Enter(self)
	end
end

function Handlers.Click(window)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	window:Undo()
end

-- The tooltip names what Undo puts back: "Font Size back to 12.", or how many settings a group returns.
function Handlers.Enter(window)
	local button = window.frame.footer.undo
	local history = window.undoHistory
	local step = history and history[#history]
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	GameTooltip:SetText(L.UNDO, 1, 1, 1)
	if not step then
		GameTooltip:AddLine(L.NOTHING_TO_UNDO, 1, 0.82, 0)
	elseif step.group then
		GameTooltip:AddLine(L.UNDO_SETTINGS:format(#step.changes), 1, 0.82, 0)
	else
		local change = step.changes[1]
		local setting = change.setting
		local value = change.before
		if value == nil then
			value = setting.inherits and setting:InheritedValue() or setting.default
		end
		GameTooltip:AddLine(L.UNDO_TO:format(setting.label or tostring(setting.id), setting:FormatValue(value)), 1, 0.82,
			0, true)
	end
	GameTooltip:Show()
end
