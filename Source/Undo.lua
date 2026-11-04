-- Undo (Q69, Q86): one history for the whole window, kept for the game session, behind the footer's Undo button.
-- Every value the user saves is recorded, Clear Overrides as one step; a slider's drag or a color pick in progress
-- (until the picker closes) is one step. Undo puts the earlier value back and lands on its row. Profile actions are not undoable and empty the
-- history (`window:ClearUndo()`); values saved from code (`setting:SetValue`) are not recorded. An adopter records a
-- change it made outside a setting, such as a drag in its own preview, with `window:RecordChange`.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

local BUTTON_WIDTH, BUTTON_HEIGHT, BUTTON_GAP, BUTTON_RIGHT = 110, 30, 10, 10 -- kit values
local MERGE_SECONDS = 1.5 -- a control that merges, saved again this soon after, is the same step
local MAX_STEPS = 100

lib.UndoHandlers = lib.UndoHandlers or {}
local Handlers = lib.UndoHandlers

local Copy, Same = lib.CopyValue, lib.SameValue

-- Steps are { time, changes, gesture?, merge?, text?, page?, group? }, each change { setting, before } or
-- { path, before }.
local function History(window)
	window.undoSteps = window.undoSteps or {}

	return window.undoSteps
end

local function Push(window, step)
	local history = History(window)
	history[#history + 1] = step
	if #history > MAX_STEPS then
		table.remove(history, 1)
	end
	window:RefreshUndo()
end

---Records a saved value for Undo (Setting:Request calls it). Saves passing the same `gesture` (a color pick, from
---its first save to its close) are one step; a slider or swatch saved again within moments without one joins the
---step before. A step that ends where it began is dropped.
function lib.Window:RecordUndo(setting, before, after, gesture)
	if setting.noUndo or Same(before, after) then
		return
	end
	local history = History(self)
	local last = history[#history]
	local now = GetTime()
	local joins
	if last and not last.group and last.changes[1].setting == setting and lib.controls[setting.kind].merges then
		if gesture then
			joins = last.gesture == gesture
		else
			joins = not last.gesture and now - last.time < MERGE_SECONDS
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
	Push(self, { time = now, gesture = gesture, changes = { { setting = setting, before = Copy(before) } } })
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

---Records a change the adopter made outside a setting, for Undo. `info.path`: the stored path it changed (written
---back through the declaration's `write`, else the store); `info.before`: the value there before (a table is copied);
---`info.text`: the Undo tooltip's line, what Undo puts back ("Clock back to its place."); `info.page`: the page shown
---when it is undone; `info.merge`: any value, so a change to the same path with the same `merge` moments after the
---last one joins it (a slider's drag). A change to several paths at once gives `info.paths`, `{ { path, before }, ...
---}`, in place of `path` and `before`; Undo puts them back as one step, last first.
function lib.Window:RecordChange(info)
	local paths = type(info) == "table" and info.paths
	if type(paths) == "table" then
		for _, change in ipairs(paths) do
			if type(change) ~= "table" or type(change.path) ~= "string" then
				lib:Report(self.addonName, "RecordChange needs a path for each of its paths")
				return
			end
		end
		if #paths == 0 then
			return
		end
		local copies = {}
		for index, change in ipairs(paths) do
			copies[index] = { path = change.path, before = Copy(change.before) }
		end
		Push(self, { time = GetTime(), changes = copies, text = info.text, page = info.page })
		return
	end
	if type(info) ~= "table" or type(info.path) ~= "string" then
		lib:Report(self.addonName, "RecordChange needs a path")
		return
	end
	local history = History(self)
	local last = history[#history]
	local now = GetTime()
	if info.merge ~= nil and last and last.merge == info.merge and last.changes[1].path == info.path
		and now - last.time < MERGE_SECONDS then
		last.time, last.text = now, info.text
		self:RefreshUndo()
		return
	end
	Push(self, { time = now, changes = { { path = info.path, before = Copy(info.before) } }, text = info.text,
		page = info.page, merge = info.merge })
end

---Empties the history. Profile actions call it: they are not undoable, and a step recorded before one would change a
---different profile.
function lib.Window:ClearUndo()
	if self.undoSteps then
		wipe(self.undoSteps)
	end
	self:RefreshUndo()
end

---@return boolean undoable whether the history holds a step
function lib.Window:CanUndo()
	return self.undoSteps ~= nil and #self.undoSteps > 0
end

-- Shows "Couldn't undo: <reason>." (or without a reason) at the top of the screen, in Title Case: a change made outside
-- a setting has no label to name.
---@param reason string?
local function ShowPathRefusal(reason)
	local message = reason and L.COULDNT_UNDO_REASON:format((reason:gsub("%.$", ""))) or L.COULDNT_UNDO
	UIErrorsFrame:AddExternalErrorMessage(lib.TitleCase(message))
end

---Puts back the values of the latest step and lands on its (first) row. A value the adopter refuses keeps its current
---value and shows the refusal.
function lib.Window:Undo()
	local history = self.undoSteps
	local step = history and table.remove(history)
	if not step then
		return
	end
	for index = #step.changes, 1, -1 do
		local change = step.changes[index]
		local setting = change.setting
		if setting then
			local ok, reason = lib.WriteSetting(setting, Copy(change.before))
			if not ok then
				setting:ShowRefusal(reason)
			end
		else
			local ok, reason = lib.WritePath(self, change.path, Copy(change.before))
			if not ok then
				ShowPathRefusal(reason)
			end
		end
	end
	self:RefreshUndo()
	self:Refresh()
	local setting = step.changes[1].setting
	if setting then
		if self:IsShown() and setting.page and setting:IsShown() then
			self:LandOn(setting)
		end
	elseif step.page and self:IsShown() then
		self:SelectPage(step.page)
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
	local history = window.undoSteps
	local step = history and history[#history]
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	GameTooltip:SetText(L.UNDO, 1, 1, 1)
	if not step then
		GameTooltip:AddLine(L.NOTHING_TO_UNDO, 1, 0.82, 0)
	elseif step.group then
		GameTooltip:AddLine(L.UNDO_SETTINGS:format(#step.changes), 1, 0.82, 0)
	elseif not step.changes[1].setting then
		GameTooltip:AddLine(step.text or L.UNDO_CHANGE, 1, 0.82, 0, true)
	else
		local change = step.changes[1]
		local setting = change.setting
		local value = change.before
		if value == nil then
			value = setting.inherits and setting:InheritedValue() or setting.default
		end
		GameTooltip:AddLine(L.UNDO_TO:format(setting.label or setting.title or tostring(setting.id),
			setting:FormatValue(value)), 1, 0.82,
			0, true)
	end
	GameTooltip:Show()
end
