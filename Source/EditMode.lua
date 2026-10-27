-- The edit session: opening and closing, pending positions, combat pause and the account preferences.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

-- Q149, Q150: EllesmereUI's unlock-mode sound on opening; Blizzard Edit Mode's quit sound on Save and Exit and on an
-- Exit with nothing changed. Exit Without Saving plays only its popup's sound.
local OPEN_SOUND = SOUNDKIT and SOUNDKIT.UI_DRAGONRIDING_FULL_NODE or 201528
local CLOSE_SOUND = SOUNDKIT and SOUNDKIT.IG_MAINMENU_QUIT or 854

---@class LibAeonSettingsSession
---@field open boolean
---@field paused boolean true while combat hides an open session
---@field opener string the addon edit mode was opened from
---@field shown table<string, boolean> addons whose movers are shown
---@field pending table<string, table<string, LibAeonSettingsPosition>> addon -> key -> position, not yet saved
---@field hidden table<string, boolean> movers hidden for this session
---@field selected string? the selected mover's id
---@field hovered string? the hovered mover's id
---@field drag table? the drag in progress
lib.session = lib.session or { open = false, paused = false, shown = {}, pending = {}, hidden = {} }

local PREFERENCE_DEFAULTS = {
	grid = "DIMMED", fill = false, snap = true, coordinates = false, hoverBar = false,
	toolbarScale = 1, tipSeen = false,
}

-- Edit mode preferences are account-wide, kept under `editMode` in every adopting addon's `account` table.

---@return any
function lib:GetPreference(name)
	local opener = self.session.opener and self.registrations[self.session.opener]
	local first = { opener and opener.declaration.account }
	for _, account in ipairs(lib:AccountTables()) do
		table.insert(first, account)
	end
	for _, account in ipairs(first) do
		if type(account) == "function" then
			account = account()
		end
		local saved = type(account) == "table" and account.editMode
		if saved and saved[name] ~= nil then
			return saved[name]
		end
	end

	return PREFERENCE_DEFAULTS[name]
end

function lib:SetPreference(name, value)
	for _, account in ipairs(lib:AccountTables()) do
		account.editMode = account.editMode or {}
		account.editMode[name] = value
	end
end

---@return LibAeonSettingsPosition?
function lib:GetPending(addonName, key)
	local pending = self.session.pending[addonName]

	return pending and pending[key]
end

---Records an unsaved position and draws the frame there, then redraws the movers unless `skipRefresh` is true (the
---caller redraws the ones that changed).
---@param position LibAeonSettingsPosition?
---@param skipRefresh boolean?
function lib:SetPending(addonName, key, position, skipRefresh)
	local registration = self.registrations[addonName]
	local target = registration and registration:Target(key)
	if not target or not self.session.open then
		return
	end
	self.session.pending[addonName] = self.session.pending[addonName] or {}
	self.session.pending[addonName][key] = position
	registration:ApplyTarget(target)
	if not skipRefresh then
		self:RefreshMovers()
	end
end

---Shows or hides one addon's sample content.
function lib:ShowAddonSamples(addonName, shown)
	local registration = self.registrations[addonName]
	for _, target in ipairs(registration and registration:Targets() or {}) do
		if type(target.sample) == "function" then
			local ok, err = pcall(target.sample, shown)
			if not ok then
				self:Report(addonName, ("sample for %s failed: %s"):format(target.key, tostring(err)))
			end
		end
	end
end

---Shows or hides the sample content of every addon shown in the session.
local function ShowSamples(session, shown)
	for addonName in pairs(session.shown) do
		lib:ShowAddonSamples(addonName, shown)
	end
end

---@return boolean
function lib:IsDirty()
	for _, keys in pairs(self.session.pending) do
		if next(keys) then
			return true
		end
	end

	return false
end

---@return boolean
function lib:IsEditing()
	return self.session.open
end

-- Blizzard panels edit mode must not draw over. Closing them from addon code is avoided: the Settings panel commits
-- its changes as it closes, which addon code should not trigger, so edit mode waits for them to close instead.
local BLOCKING_PANELS = { "SettingsPanel", "GameMenuFrame" }

local function BlockingPanelShown()
	for _, name in ipairs(BLOCKING_PANELS) do
		local panel = _G[name]
		if panel and panel:IsShown() then
			return true
		end
	end

	return false
end

function lib:OnBlockingPanelHidden()
	local waiting = self.session.waitingOpener
	if waiting and not BlockingPanelShown() then
		self.session.waitingOpener = nil
		C_Timer.After(0, function() self:OpenEditMode(waiting) end)
	end
end

local function WaitForBlockingPanels(addonName)
	lib.session.waitingOpener = addonName
	lib.hookedPanels = lib.hookedPanels or {}
	for _, name in ipairs(BLOCKING_PANELS) do
		local panel = _G[name]
		if panel and not lib.hookedPanels[name] then
			lib.hookedPanels[name] = true
			panel:HookScript("OnHide", function() lib:OnBlockingPanelHidden() end)
		end
	end
	UIErrorsFrame:AddMessage(L.WAITING_FOR_PANELS, 1, 0.82, 0)
end

---Opens edit mode from an addon that registered placement. Refused in combat; while the game menu or Blizzard's
---settings are open, it opens once they close.
---@param addonName string
function lib:OpenEditMode(addonName)
	local session = self.session
	if session.open then
		return
	end
	if not self.registrations[addonName] then
		self:Report(addonName, "OpenEditMode: the addon has not registered placement")
		return
	end
	if InCombatLockdown() then
		session.waitingOpener = nil
		UIErrorsFrame:AddMessage(L.COMBAT_REFUSED, lib:GetColor("destructive"))
		return
	end
	if BlockingPanelShown() then
		WaitForBlockingPanels(addonName)
		return
	end

	session.waitingOpener = nil
	-- Edit mode draws over the whole screen; the library's settings windows close first.
	for _, window in pairs(self.windows or {}) do
		window:Close()
	end
	session.open = true
	session.paused = false
	session.opener = addonName
	session.shown = { [addonName] = true }
	session.pending = {}
	session.hidden = {}
	session.selected, session.hovered, session.drag = nil, nil, nil
	session.expanded, session.pick, session.snapTargets, session.sizeOriginals = nil, nil, nil, nil
	-- Targets declared by a function are read again as editing begins.
	for _, registration in pairs(self.registrations) do
		registration:RefreshTargets()
	end
	ShowSamples(session, true)
	self:ShowEditUI(true)
	PlaySound(OPEN_SOUND)
	self.editEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
	self.editEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
end

---Leaves edit mode, saving every pending position first when `save` is true; otherwise they are dropped.
---@param save boolean
function lib:CloseEditMode(save)
	local session = self.session
	if not session.open then
		return
	end
	-- A drop still settling lands first, so its position is among the pending ones. The screen starts fading
	-- before anything else is undone, so the movers stay drawn as they were while it fades.
	lib.MoverHandlers.EndSettle()
	self:HideEditUI(true)
	local pending = session.pending
	local returnTo = session.returnTo
	session.returnTo = nil
	session.open = false
	session.paused = false
	session.pending = {}
	self.editEvents:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self.editEvents:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:CloseMenus()
	if session.pick then
		self:EndPick()
	end
	self:RestoreSizes(save)
	ShowSamples(session, false)
	session.selected, session.hovered, session.drag = nil, nil, nil

	for addonName, keys in pairs(pending) do
		local registration = self.registrations[addonName]
		if registration then
			if save then
				for key, position in pairs(keys) do
					registration:Write(key, position)
				end
			end
			registration:Apply()
		end
	end

	-- Edit mode opened from a settings window goes back to it.
	if returnTo then
		C_Timer.After(0, function()
			if not InCombatLockdown() and not lib:IsEditing() then
				returnTo:Open()
			end
		end)
	end
end

---Exit and Escape: closes at once when nothing changed, otherwise asks whether to save.
function lib:RequestClose(save)
	if save or not self:IsDirty() then
		PlaySound(CLOSE_SOUND)
		self:CloseEditMode(save)
		return
	end
	StaticPopup_Show("LIBAEONSETTINGS_EDIT_EXIT")
end

StaticPopupDialogs.LIBAEONSETTINGS_EDIT_EXIT = {
	text = L.UNSAVED_CHANGES,
	button1 = L.SAVE_AND_EXIT,
	button2 = L.EXIT_WITHOUT_SAVING,
	OnAccept = function() PlaySound(CLOSE_SOUND); lib:CloseEditMode(true) end,
	OnCancel = function() lib:CloseEditMode(false) end,
	noCancelOnEscape = true,
	hideOnEscape = true,
	whileDead = true,
	timeout = 0,
	preferredIndex = 3,
}

-- Combat hides an open session and keeps its pending positions; it returns half a second after combat ends.
lib.editEvents = lib.editEvents or CreateFrame("Frame")
lib.editEvents:SetScript("OnEvent", function(_, event)
	local session = lib.session
	if not session.open then
		return
	end
	if event == "PLAYER_REGEN_DISABLED" then
		session.paused = true
		lib.MoverHandlers.EndSettle()
		lib:HideEditUI(true)
		lib:CloseMenus()
		if session.pick then
			lib:EndPick()
		end
		StaticPopup_Hide("LIBAEONSETTINGS_EDIT_EXIT")
	elseif event == "PLAYER_REGEN_ENABLED" then
		C_Timer.After(0.5, function()
			if session.open and session.paused and not InCombatLockdown() then
				session.paused = false
				lib:ShowEditUI("return")
			end
		end)
	end
end)
