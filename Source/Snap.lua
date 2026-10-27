-- Snapping: candidate lines collected once when a drag starts, and the guide lines shown while one is matched.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local SNAP_DISTANCE = 6     -- virtual pixels (UI units times UIParent's effective scale)
local GRID_SPACING = 32
local GUIDE_ALPHA = 0.55
local GUIDE_FADE = 0.1 -- the guides' spring response: they fade in and out instead of popping

---@return number threshold in UI units
function lib:SnapThreshold()
	return SNAP_DISTANCE / UIParent:GetEffectiveScale()
end

---Lines a drag can snap to: the screen's edges and center, the grid lines while the grid shows, and the edges and
---centers of every other shown mover's frame, or only the chosen snap target's when the mover has one. Movers in
---`followers` (those attached to the dragged one) are left out.
---@param dragId string
---@param targetRect fun(target: table): number?, number?, number?, number? what each other mover covers
---@param followers table<string, boolean>
---@return table xs, table ys
function lib:SnapCandidates(dragId, targetRect, followers)
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	local xs, ys = {}, {}
	local only = self.session.snapTargets and self.session.snapTargets[dragId]

	if not only then
		for _, value in ipairs({ 0, width / 2, width }) do
			table.insert(xs, { value = value })
		end
		for _, value in ipairs({ 0, height / 2, height }) do
			table.insert(ys, { value = value })
		end
		if self:GetPreference("grid") ~= "OFF" then
			for offset = GRID_SPACING, width / 2, GRID_SPACING do
				table.insert(xs, { value = width / 2 + offset })
				table.insert(xs, { value = width / 2 - offset })
			end
			for offset = GRID_SPACING, height / 2, GRID_SPACING do
				table.insert(ys, { value = height / 2 + offset })
				table.insert(ys, { value = height / 2 - offset })
			end
		end
	end

	for id, mover in pairs(self.ui and self.ui.movers or {}) do
		if id ~= dragId and mover:IsShown() and mover.target and (not only or only == id) and not followers[id] then
			local left, bottom, frameWidth, frameHeight = targetRect(mover.target)
			if left then
				for _, value in ipairs({ left, left + frameWidth / 2, left + frameWidth }) do
					table.insert(xs, { value = value, from = id })
				end
				for _, value in ipairs({ bottom, bottom + frameHeight / 2, bottom + frameHeight }) do
					table.insert(ys, { value = value, from = id })
				end
			end
		end
	end

	return xs, ys
end

local function Guide(ui, index)
	ui.guides = ui.guides or {}
	local guide = ui.guides[index]
	if not guide then
		guide = ui.guideLayer:CreateTexture(nil, "OVERLAY")
		guide:SetColorTexture(lib:GetColor("accent", GUIDE_ALPHA))
		guide:SetAlpha(0)
		guide:Hide()
		ui.guides[index] = guide
	end

	return guide
end

-- Fades a guide in or out on its own spring, made on first use; it hides once gone.
function lib.SnapFade(guide, shown)
	if not guide.fade then
		guide.fade = lib:CreateSpring(0, function(value)
			guide:SetAlpha(value)
			guide:SetShown(value > 0)
		end, { response = GUIDE_FADE, epsilon = 0.01 })
	end
	if guide.fade.target ~= (shown and 1 or 0) then
		guide.fade:To(shown and 1 or 0)
	end
end

---Shows a vertical guide at `x` and a horizontal one at `y` (UI units); nil hides that guide.
function lib:ShowGuides(x, y)
	local ui = self.ui
	if not ui then
		return
	end
	local thickness = PixelUtil.GetNearestPixelSize(1, UIParent:GetEffectiveScale(), 1)
	local vertical, horizontal = Guide(ui, 1), Guide(ui, 2)
	lib.SnapFade(vertical, x ~= nil)
	lib.SnapFade(horizontal, y ~= nil)
	-- Started on a screen pixel, as the grid's lines are, so a guide covers the grid line it matches.
	local pixel = self:PixelSize()
	if x then
		vertical:ClearAllPoints()
		vertical:SetSize(thickness, UIParent:GetHeight())
		vertical:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", lib.Geometry.PixelLineStart(x, thickness, pixel), 0)
	end
	if y then
		horizontal:ClearAllPoints()
		horizontal:SetSize(UIParent:GetWidth(), thickness)
		horizontal:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, lib.Geometry.PixelLineStart(y, thickness, pixel))
	end
end
