-- What a settings row should look like, worked out from its setting with no frames. The page draws the answer
-- (Page.lua), which holds the alphas, colors and text it means.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local MAX_CHAIN = lib.MAX_CHAIN

---@class LibAeonSettingsRowLook
---@field active boolean? the control answers the player
---@field wanted boolean? the row belongs on the page; false starts it leaving
---@field labelDimmed boolean? the label, gutter and lines under the label dim
---@field controlDimmed boolean? the control dims
---@field pageOff boolean? the control loses color only, under a page switch that is off
---@field marker "overridden"|"changed"|nil overridden shows ◆ and ↺, changed shows ↺ alone
---@field inheritedLine "follows"|"overridden"|nil the line naming the shared value
---@field secondLine "reason"|"description"|nil what the line under the label holds
---@field reason string? the reason the second line shows
---@field tooltipReason string? why the row is inactive now, for a choice card's tooltip
---@field lines integer? how many lines sit under the label

-- A setting up this one's `depends` chain, in its own section, is off.
local function ParentOffInSection(setting)
	local parent, depth = setting:Parent(), 0
	while parent and depth < MAX_CHAIN do
		if parent.section == setting.section and not parent:GetValue() then
			return true
		end
		parent, depth = parent:Parent(), depth + 1
	end

	return false
end

---Works out how a row should look now, overwriting `look`. A row's own table is passed on every call, since a row on
---its way out keeps the look it had; a new or wiped table is a row not yet drawn.
---@param setting table
---@param look LibAeonSettingsRowLook
---@param inGrid boolean? the row is in a choice card
---@param revealed number? how much of its height the row has, 0 to 1
---@return boolean layoutChanged the row's visibility or height changed, so the page needs laying out again
function lib.RowLook(setting, look, inGrid, revealed)
	local wasWanted, wasLines = look.wanted, look.lines
	local active, reason, cause = setting:Activity()
	-- A row whose parent in its own card is off leaves.
	local wanted = setting:IsShown() and not (cause == "depends" and ParentOffInSection(setting))
	local rowInactive = not active and cause ~= "page" and cause ~= "class"
	-- A row on its way out keeps the look it had, so its exit shows no dimming or inactive reason; its control still
	-- stops answering at once.
	local leaving = not wanted and (revealed or 0) > 0
	if not leaving then
		look.labelDimmed, look.reason = rowInactive, reason
	end
	look.active, look.wanted = active, wanted
	-- A swatch following the class color dims only its control: the label stays and needs no reason.
	look.controlDimmed = look.labelDimmed or cause == "class"
	look.pageOff = not look.controlDimmed and not active and not leaving
	-- A row following the shared value names its source; changing it overrides it (◆, ↺, the inherited value).
	-- A resettable row changed from its default shows ↺ alone, in the same place.
	local overridden = setting:IsOverridden()
	local changed = not overridden and setting:IsChangedFromDefault()
	look.marker = overridden and "overridden" or changed and "changed" or nil
	-- A choice-card row has no second line: its reason shows in its tooltip.
	look.tooltipReason = rowInactive and reason or nil
	if inGrid then
		look.inheritedLine, look.secondLine, look.lines = nil, nil, 0
	else
		look.inheritedLine = overridden and "overridden" or setting.inherits and "follows" or nil
		look.secondLine = look.labelDimmed and look.reason and "reason" or setting.description and "description" or nil
		-- A row that can be overridden always keeps room for the inherited line, so overriding never resizes it or
		-- moves its label.
		look.lines = (look.secondLine and 1 or 0) + (setting.inherits and 1 or 0)
	end

	return wanted ~= wasWanted or look.lines ~= wasLines
end
