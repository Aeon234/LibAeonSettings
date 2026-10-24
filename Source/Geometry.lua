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
---@param grow string? "LEFT", "RIGHT", "CENTER", "UP" or "DOWN": the direction a resize grows, which fixes the
---opposite edge (CENTER keeps the horizontal middle); it overrides `fixedEdge` on its axis
---@return string point
---@return number x
---@return number y
function Geometry.ToStored(left, bottom, width, height, parentWidth, parentHeight, fixedEdge, grow)
	local centerX, centerY = left + width / 2, bottom + height / 2

	local column = centerX < parentWidth / 3 and "LEFT" or centerX > parentWidth * 2 / 3 and "RIGHT" or ""
	local row = centerY > parentHeight * 2 / 3 and "TOP" or centerY < parentHeight / 3 and "BOTTOM" or ""
	if fixedEdge == "TOP" or fixedEdge == "BOTTOM" then
		row = fixedEdge
	elseif fixedEdge == "LEFT" or fixedEdge == "RIGHT" then
		column = fixedEdge
	end
	if grow == "LEFT" then
		column = "RIGHT"
	elseif grow == "RIGHT" then
		column = "LEFT"
	elseif grow == "CENTER" then
		column = ""
	elseif grow == "UP" then
		row = "BOTTOM"
	elseif grow == "DOWN" then
		row = "TOP"
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

---Finds the snap that moves a rectangle the least on one axis: each of `edges` (the rectangle's start, middle and
---end) against each candidate line within `threshold`. A tie prefers a line that belongs to another frame.
---@param edges number[]
---@param candidates { value: number, from: string? }[]
---@param threshold number
---@return { delta: number, value: number, from: string? }?
function Geometry.NearestSnap(edges, candidates, threshold)
	local best
	for _, edge in ipairs(edges) do
		for _, candidate in ipairs(candidates) do
			local delta = candidate.value - edge
			local distance = math.abs(delta)
			if distance <= threshold then
				local bestDistance = best and math.abs(best.delta)
				if not best or distance < bestDistance or (distance == bestDistance and candidate.from and not best.from) then
					best = { delta = delta, value = candidate.value, from = candidate.from }
				end
			end
		end
	end

	return best
end

---Where a line meant to be centered on `position` starts so it covers whole screen pixels: its left or bottom edge on
---the nearest pixel boundary.
---@param position number the line's intended center, in UI units from its parent's left or bottom edge
---@param thickness number the line's thickness, a whole number of pixels
---@param pixel number one screen pixel, in UI units
---@return number start
function Geometry.PixelLineStart(position, thickness, pixel)
	return math.floor((position - thickness / 2) / pixel + 0.5) * pixel
end

---The position of one of a rectangle's nine points.
---@return number x
---@return number y
function Geometry.PointPosition(left, bottom, width, height, point)
	local x = point:find("LEFT", 1, true) and left or point:find("RIGHT", 1, true) and left + width or left + width / 2
	local y = point:find("BOTTOM", 1, true) and bottom or point:find("TOP", 1, true) and bottom + height
		or bottom + height / 2

	return x, y
end

-- Anchoring to a side of another frame: the attached frame's point, and the point of the frame it attaches to.
local SIDE_POINTS = {
	TOP = { "BOTTOM", "TOP" },
	BOTTOM = { "TOP", "BOTTOM" },
	LEFT = { "RIGHT", "LEFT" },
	RIGHT = { "LEFT", "RIGHT" },
}

---@param side string "TOP", "BOTTOM", "LEFT" or "RIGHT"
---@return string? childPoint
---@return string? parentPoint
function Geometry.SidePoints(side)
	local points = SIDE_POINTS[side]
	if points then
		return points[1], points[2]
	end
end

---Offset from the parent's side point to the child's matching point, for rectangles in the same units.
---@return number x
---@return number y
function Geometry.AnchorOffset(side, childLeft, childBottom, childWidth, childHeight, parentLeft, parentBottom,
	parentWidth, parentHeight)
	local childPoint, parentPoint = Geometry.SidePoints(side)
	local childX, childY = Geometry.PointPosition(childLeft, childBottom, childWidth, childHeight, childPoint)
	local parentX, parentY = Geometry.PointPosition(parentLeft, parentBottom, parentWidth, parentHeight, parentPoint)

	return childX - parentX, childY - parentY
end
