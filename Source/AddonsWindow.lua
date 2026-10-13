-- The Addons window: every addon that registered placement, each turned on or off for the edit session.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

local WINDOW_WIDTH = 240
local ROW_HEIGHT = 28
local PADDING = 10

local Handlers = {}
lib.AddonsWindowHandlers = Handlers

---Shows or hides another addon's movers for this session. The addon edit mode was opened from always shows; an
---addon turned off keeps its pending changes until Save or Exit.
function lib:SetAddonShown(addonName, shown)
	local session = self.session
	if not session.open or addonName == session.opener or not self.registrations[addonName] then
		return
	end
	if (session.shown[addonName] == true) == shown then
		return
	end
	session.shown[addonName] = shown or nil
	self:ShowAddonSamples(addonName, shown)
	local owner = self:MenuOwner()
	if not shown and owner and owner:find(addonName .. "\0", 1, true) == 1 then
		self:CloseMenus()
	end
	self:RefreshMovers()
	self:RefreshToolbar()
	self:RefreshAddonsWindow()
end

---@return number shown, number total
function lib:ShownAddonCount()
	local shown = 0
	for _, addonName in ipairs(self.order) do
		if self.session.shown[addonName] then
			shown = shown + 1
		end
	end

	return shown, #self.order
end

local function CreateWindow()
	local window = CreateFrame("Frame", nil, UIParent)
	window:SetFrameStrata("FULLSCREEN_DIALOG")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetClampedToScreen(true)
	window:SetWidth(WINDOW_WIDTH)
	lib:ApplyPanelArt(window)
	window.title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	window.title:SetPoint("TOP", 0, -PADDING)
	window.title:SetText(L.ADDONS)
	window.rows = {}
	window:Hide()

	return window
end

local function Row(window, index)
	local row = window.rows[index]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, window)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", window, "TOPLEFT", PADDING, -(PADDING + 20 + (index - 1) * ROW_HEIGHT))
	row:SetPoint("RIGHT", window, "RIGHT", -PADDING, 0)
	row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.check:SetSize(26, 26)
	row.check:SetPoint("LEFT")
	row.check:SetScript("OnClick", function(self) Handlers.Click(self) end)
	row.check:SetScript("OnEnter", function(self) Handlers.Enter(self) end)
	row.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.label:SetPoint("LEFT", row.check, "RIGHT", 6, 0)
	window.rows[index] = row

	return row
end

function Handlers.Click(check)
	lib:SetAddonShown(check.addonName, check:GetChecked())
	lib:RefreshAddonsWindow()
end

function Handlers.Enter(check)
	if check.addonName == lib.session.opener then
		GameTooltip:SetOwner(check, "ANCHOR_RIGHT")
		GameTooltip:SetText(L.OPENED_FROM_ADDON, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end
end

function lib:RefreshAddonsWindow()
	local window = self.ui and self.ui.addonsWindow
	if not window or not window:IsShown() then
		return
	end
	local session = self.session
	for index, addonName in ipairs(self.order) do
		local row = Row(window, index)
		local registration = self.registrations[addonName]
		row.check.addonName = addonName
		row.check:SetChecked(session.shown[addonName] == true)
		row.check:SetEnabled(addonName ~= session.opener)
		row.label:SetText(registration.title or addonName)
		row.label:SetFontObject(addonName == session.opener and "GameFontDisable" or "GameFontHighlight")
		row:Show()
	end
	for index = #self.order + 1, #window.rows do
		window.rows[index]:Hide()
	end
	window:SetHeight(PADDING * 2 + 20 + #self.order * ROW_HEIGHT)
end

---Opens or closes the Addons window below the toolbar's Addons toggle.
function lib:ToggleAddonsWindow()
	local ui = self.ui
	ui.addonsWindow = ui.addonsWindow or CreateWindow()
	local window = ui.addonsWindow
	if window:IsShown() then
		window:Hide()
		return
	end
	self:CloseMenus()
	window:ClearAllPoints()
	window:SetPoint("TOP", ui.toolbar.addons, "BOTTOM", 0, -12)
	window:Show()
	self:RefreshAddonsWindow()
end

---Closes the Addons window. Returns true when it was open.
function lib:CloseAddonsWindow()
	local window = self.ui and self.ui.addonsWindow
	if window and window:IsShown() then
		window:Hide()
		return true
	end

	return false
end
