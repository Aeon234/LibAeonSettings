-- Pure position math in parent units, origin at the parent's bottom left, y up. No frame access.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

---@class LibAeonSettingsGeometry
local Geometry = {}
lib.Geometry = Geometry

local VALID_POINTS = {
	TOPLEFT = true, TOP = true, TOPRIGHT = true,
	LEFT = true, CENTER = true, RIGHT = true,
	BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

---@param point any
---@return boolean
function Geometry.IsPoint(point)
	return VALID_POINTS[point] == true
end

---Picks the anchor point from the third of the parent the rectangle's center lies in, then measures the offset
---from that point of the parent to the same point of the rectangle. `fixedEdge` forces that edge on its axis.
---@param left number
---@param bottom number
---@param width number
---@param height number
---@param parentWidth number
---@param parentHeight number
---@param fixedEdge string? "TOP", "BOTTOM", "LEFT" or "RIGHT"
---@return string point
---@return number x
---@return number y
function Geometry.ToStored(left, bottom, width, height, parentWidth, parentHeight, fixedEdge)
	local centerX, centerY = left + width / 2, bottom + height / 2

	local column = centerX < parentWidth / 3 and "LEFT" or centerX > parentWidth * 2 / 3 and "RIGHT" or ""
	local row = centerY > parentHeight * 2 / 3 and "TOP" or centerY < parentHeight / 3 and "BOTTOM" or ""
	if fixedEdge == "TOP" or fixedEdge == "BOTTOM" then
		row = fixedEdge
	elseif fixedEdge == "LEFT" or fixedEdge == "RIGHT" then
		column = fixedEdge
	end

	local x
	if column == "LEFT" then
		x = left
	elseif column == "RIGHT" then
		x = left + width - parentWidth
	else
		x = centerX - parentWidth / 2
	end

	local y
	if row == "BOTTOM" then
		y = bottom
	elseif row == "TOP" then
		y = bottom + height - parentHeight
	else
		y = centerY - parentHeight / 2
	end

	local point = row .. column
	if point == "" then
		point = "CENTER"
	end

	return point, x, y
end

---Inverse of ToStored: the rectangle's bottom left for a stored point and offset.
---@param point string
---@param x number
---@param y number
---@param width number
---@param height number
---@param parentWidth number
---@param parentHeight number
---@return number left
---@return number bottom
function Geometry.FromStored(point, x, y, width, height, parentWidth, parentHeight)
	local left
	if point:find("LEFT", 1, true) then
		left = x
	elseif point:find("RIGHT", 1, true) then
		left = parentWidth + x - width
	else
		left = parentWidth / 2 + x - width / 2
	end

	local bottom
	if point:find("BOTTOM", 1, true) then
		bottom = y
	elseif point:find("TOP", 1, true) then
		bottom = parentHeight + y - height
	else
		bottom = parentHeight / 2 + y - height / 2
	end

	return left, bottom
end

---@return boolean true when no part of the rectangle lies inside the parent
function Geometry.IsOffScreen(left, bottom, width, height, parentWidth, parentHeight)
	return left + width <= 0 or bottom + height <= 0 or left >= parentWidth or bottom >= parentHeight
end

---Moves the rectangle the least distance needed to lie wholly inside the parent (top left wins when it is larger).
---@return number left
---@return number bottom
function Geometry.ClampInto(left, bottom, width, height, parentWidth, parentHeight)
	left = math.max(0, math.min(left, parentWidth - width))
	bottom = math.min(parentHeight - height, math.max(bottom, 0))

	return left, bottom
end
