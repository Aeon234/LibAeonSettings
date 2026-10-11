-- The cog menu of a mover, and pick mode (choosing another mover by clicking it).

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L
local Geometry = lib.Geometry

local SNAP_TARGET_COLOR = { 0.31, 0.82, 0.42 }
local PICK_DIM = 0.5

---Moves a target, as a pending position, to a rectangle in UIParent units (clamped to the screen). An anchored
---target stays anchored, with its offsets measured again.
function lib:MoveTargetTo(addonName, target, left, bottom, width, height)
	left, bottom = Geometry.ClampInto(left, bottom, width, height, UIParent:GetWidth(), UIParent:GetHeight())
	self:SetPending(addonName, target.key, self:PositionForRect(addonName, target, left, bottom, width, height))
end

-- Size changes are applied live through the target's `size.set` and undone with the first size seen in the session
-- when edit mode closes without saving (lib:SetTargetSize).
local function SetSize(mover, width, height)
	lib:SetTargetSize(mover.addonName, mover.target, width, height)
	lib.registrations[mover.addonName]:ApplyTarget(mover.target)
	lib:RefreshMovers()
end

function lib:RestoreSizes(save)
	local originals = self.session.sizeOriginals
	self.session.sizeOriginals = nil
	if save or not originals then
		return
	end
	for _, original in pairs(originals) do
		local registration = self.registrations[original.addonName]
		local target = registration and registration:Target(original.key)
		if target and type(target.size) == "table" then
			target.size.set(original.width, original.height)
		end
	end
end

local function ElementOptions(mover)
	local settings = mover.target.settings
	local addonName = mover.addonName
	local target = mover.target
	lib:CloseEditMode(true)
	if type(settings) == "function" then
		local ok, err = pcall(settings, target)
		if not ok then
			lib:Report(addonName, ("settings for %s failed: %s"):format(target.key, tostring(err)))
		end
	end
end

-- Screen positions as a 3 by 3 grid, read row by row: horizontal and vertical placement (0 start, 0.5 middle, 1 end).
local RELATIVE = {
	{ L.TOP_LEFT, 0, 1 }, { L.TOP, 0.5, 1 }, { L.TOP_RIGHT, 1, 1 },
	{ L.LEFT, 0, 0.5 }, { L.CENTER, 0.5, 0.5 }, { L.RIGHT, 1, 0.5 },
	{ L.BOTTOM_LEFT, 0, 0 }, { L.BOTTOM, 0.5, 0 }, { L.BOTTOM_RIGHT, 1, 0 },
}

local function OpenRelative(mover, row)
	lib:OpenFlyout(row, 150, function(menu)
		for _, entry in ipairs(RELATIVE) do
			local name, horizontal, vertical = entry[1], entry[2], entry[3]
			menu:Action(name, function()
				local _, _, width, height = lib:FrameRect(mover.target.frame)
				if not width then
					return
				end
				local left = (UIParent:GetWidth() - width) * horizontal
				local bottom = (UIParent:GetHeight() - height) * vertical
				lib:ShowGuides(nil, nil)
				lib:MoveTargetTo(mover.addonName, mover.target, left, bottom, width, height)
				lib:RefreshMenu()
			end, {
				onEnter = function()
					lib:ShowGuides(UIParent:GetWidth() * horizontal, UIParent:GetHeight() * vertical)
				end,
				onLeave = function() lib:ShowGuides(nil, nil) end,
			})
		end
	end)
end

---Opens (or, from the same mover, closes) the cog menu for a mover.
function lib:ToggleCogMenu(mover)
	if self:MenuOwner() == mover.id then
		self:CloseMenus()
		self:RefreshMovers()
		return
	end
	self.session.selected = mover.id
	self.session.expanded = mover.id
	self:RefreshMovers()
	self:OpenMenu(mover.id, mover.cog, function(menu)
		local target = mover.target
		menu:Hint(L.COG_HINT)
		if target.settings then
			menu:Action(L.ELEMENT_OPTIONS, function() ElementOptions(mover) end)
		end
		menu:Separator()

		if type(target.size) == "table" and type(target.size.get) == "function" and type(target.size.set) == "function" then
			local width, height = target.size.get()
			local position = self.registrations[mover.addonName]:Current(target)
			local function MatchedReason(match, text)
				local other = match and self:ResolveTarget(match.addon, match.key)

				return match and text:format(other and (other.label or other.key) or match.key) or nil
			end
			menu:Number(L.WIDTH, Round(width), function(value) SetSize(mover, value, height) lib:RefreshMenu() end,
				MatchedReason(position.matchWidth, L.WIDTH_MATCHED_REASON))
			menu:Number(L.HEIGHT, Round(height), function(value) SetSize(mover, width, value) lib:RefreshMenu() end,
				MatchedReason(position.matchHeight, L.HEIGHT_MATCHED_REASON))
			if position.matchWidth then
				menu:Number(L.EXTRA_WIDTH, position.matchWidth.extra or 0, function(value)
					self:SetMatchExtra(mover.id, "matchWidth", value)
					self:RefreshMenu()
				end)
			end
			if position.matchHeight then
				menu:Number(L.EXTRA_HEIGHT, position.matchHeight.extra or 0, function(value)
					self:SetMatchExtra(mover.id, "matchHeight", value)
					self:RefreshMenu()
				end)
			end
		end

		local left, bottom, frameWidth, frameHeight = self:FrameRect(target.frame)
		if left then
			local centerX = left + frameWidth / 2 - UIParent:GetWidth() / 2
			local centerY = bottom + frameHeight / 2 - UIParent:GetHeight() / 2
			menu:Number(L.X_POSITION, Round(centerX), function(value)
				self:MoveTargetTo(mover.addonName, target, UIParent:GetWidth() / 2 + value - frameWidth / 2, bottom, frameWidth, frameHeight)
				self:RefreshMenu()
			end)
			menu:Number(L.Y_POSITION, Round(centerY), function(value)
				self:MoveTargetTo(mover.addonName, target, left, UIParent:GetHeight() / 2 + value - frameHeight / 2, frameWidth, frameHeight)
				self:RefreshMenu()
			end)
		end

		local anchor = self.registrations[mover.addonName]:Current(target).anchor
		if anchor then
			local other = self:ResolveTarget(anchor.addon, anchor.key)
			menu:Separator()
			menu:Action(L.ANCHORED_TO:format(other and (other.label or other.key) or anchor.key))
			menu:Number(L.OFFSET_X, Round(anchor.x), function(value)
				self:SetAnchorOffset(mover.id, value, anchor.y)
				self:RefreshMenu()
			end)
			menu:Number(L.OFFSET_Y, Round(anchor.y), function(value)
				self:SetAnchorOffset(mover.id, anchor.x, value)
				self:RefreshMenu()
			end)
		end
		menu:Separator()

		local snapTarget = self.session.snapTargets and self.session.snapTargets[mover.id]
		local snapMover = snapTarget and self.ui.movers[snapTarget]
		if snapMover then
			local _, label = menu:Action(L.SNAP_TARGET:format(snapMover.name:GetText() or ""), function()
				self.session.snapTargets[mover.id] = nil
				self:RefreshMenu()
			end)
			label:SetTextColor(unpack(SNAP_TARGET_COLOR))
		else
			menu:Action(L.SELECT_SNAP_TARGET, function() self:StartPick("snap", mover.id) end)
		end
		menu:Action(L.CENTER_ON_SCREEN, function()
			local l, b, w, h = self:FrameRect(target.frame)
			if l then
				self:MoveTargetTo(mover.addonName, target, (UIParent:GetWidth() - w) / 2, b, w, h)
				self:RefreshMenu()
			end
		end)
		menu:Action(L.RELATIVE_TO_SCREEN, function(row) OpenRelative(mover, row) end, { arrow = true })
		menu:Action(L.RESET_POSITION, function()
			self:SetPending(mover.addonName, target.key, CopyTable(target.default))
			self:RefreshMenu()
		end)
	end)
	self.MoverHandlers.PaintCog(mover.cog)
end

-- Pick mode -----------------------------------------------------------------------------------------------------

---Starts choosing another mover for `source`: the screen dims, and the next click on a mover completes the pick.
---@param kind string "snap" (later "anchor", "matchWidth", "matchHeight")
function lib:StartPick(kind, source)
	self:CloseMenus()
	self.session.pick = { kind = kind, source = source }
	self.session.expanded = nil
	if self.ui and self.ui.pickDim then
		self.ui.pickDim:SetAlpha(PICK_DIM)
		self.ui.pickDim:Show()
	end
	self:RefreshMovers()
end

function lib:EndPick()
	self.session.pick = nil
	if self.ui and self.ui.pickDim then
		self.ui.pickDim:Hide()
	end
	self:RefreshMovers()
end

---Completes or cancels the pick with the clicked mover.
function lib:PickMover(id)
	local pick = self.session.pick
	if not pick then
		return
	end
	if self:CompleteLinkPick(pick, id) then
		return
	end
	if id ~= pick.source and pick.kind == "snap" then
		self.session.snapTargets = self.session.snapTargets or {}
		self.session.snapTargets[pick.source] = id
	end
	self:EndPick()
end
