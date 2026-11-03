-- Smooth scrolling lists: a scroll frame that glides to its target (exponential ease, pixel-rounded), with Blizzard's
-- minimal scroll bar beside it. The glide's OnUpdate runs only while it moves.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local EASE_RATE = 14        -- the glide closes 1 - e^(-14 dt) of the distance each frame
local SNAP_DISTANCE = 0.5   -- the glide stops within this many units
local BAR_GAP = 6           -- between the list and its scroll bar
local INSIDE_LANE = 16      -- an inside bar's lane at the list's right: the slim bar 8 from the list, at the edge
local SLIM_TRACK_ALPHA = 0.35
local OVERFLOW_MIN = 1      -- the list overflows once its content is at least this much taller than the view

lib.ScrollHandlers = lib.ScrollHandlers or {}
local Handlers = lib.ScrollHandlers

---@class LibAeonSettingsScroll
lib.Scroll = {}
local scrollMeta = { __index = function(_, name) return lib.Scroll[name] end }

---Creates a smooth scrolling list in `parent`, filling it except for the scroll bar's room on the right.
---@param parent Frame
---@param options table { step: units per wheel notch, row?: snap targets to multiples of this, slim?: a bar with no
---arrows whose track spans the list, inside?: the bar sits inside the list's right edge, laneWhenNeeded?: an inside
---bar's lane is taken from the list only while the list overflows, barInset?: an inside bar's distance from the
---list's right edge, and from its top and bottom }
---@return table scroll with `.child`, the frame to fill
function lib:CreateScroll(parent, options)
	local scroll = setmetatable({ options = options, offset = 0, target = 0, contentHeight = 0 }, scrollMeta)

	local frame = CreateFrame("ScrollFrame", nil, parent)
	frame:SetPoint("TOPLEFT")
	frame:SetPoint("BOTTOMRIGHT", options.inside and -INSIDE_LANE or 0, 0)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta) scroll:ScrollBy(-delta) end)
	frame:SetScript("OnSizeChanged", function() scroll:Layout() end)
	local child = CreateFrame("Frame", nil, frame)
	child:SetSize(1, 1)
	frame:SetScrollChild(child)

	local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	if options.inside then
		local inset = options.barInset or 0
		bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -inset, -inset)
		bar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
	else
		bar:SetPoint("TOPLEFT", frame, "TOPRIGHT", BAR_GAP, 0)
		bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", BAR_GAP, 0)
	end
	if options.slim then
		bar.Back:Hide()
		bar.Forward:Hide()
		local track = bar:GetTrack()
		track:ClearAllPoints()
		track:SetPoint("TOP")
		track:SetPoint("BOTTOM")
		track.Begin:SetAlpha(SLIM_TRACK_ALPHA)
		track.Middle:SetAlpha(SLIM_TRACK_ALPHA)
		track.End:SetAlpha(SLIM_TRACK_ALPHA)
	end
	bar:RegisterCallback(ScrollBarMixin.Event.OnScroll, function(_, percentage)
		Handlers.BarScrolled(scroll, percentage)
	end, scroll)

	local driver = CreateFrame("Frame", nil, frame)
	driver:Hide()
	driver:SetScript("OnUpdate", function(_, elapsed) Handlers.Glide(scroll, elapsed) end)

	scroll.frame, scroll.child, scroll.bar, scroll.driver = frame, child, bar, driver
	scroll:Layout()

	return scroll
end

---@return number how far the list can scroll
function lib.Scroll:Range()
	return math.max(0, self.contentHeight - self.frame:GetHeight())
end

---Sets the height of what the list holds, and lays out the list and its bar.
function lib.Scroll:SetContentHeight(height)
	self.contentHeight = height
	self:Layout()
end

function lib.Scroll:Layout()
	local frame, child = self.frame, self.child
	child:SetWidth(math.max(1, frame:GetWidth()))
	child:SetHeight(math.max(1, self.contentHeight))
	local viewHeight = frame:GetHeight()
	local range = self:Range()
	-- Content that fits exactly can measure a fraction over the snapped view, so overflow takes a whole unit.
	local overflows = range >= OVERFLOW_MIN and viewHeight > 0
	-- Narrowing the list fires OnSizeChanged, which lays out again with the same overflow and stops there. The width
	-- comes from the parent, since the frame's own may not reflect the new anchor until the next layout.
	if self.options.inside and self.options.laneWhenNeeded then
		local lane = overflows and INSIDE_LANE or 0
		frame:SetPoint("BOTTOMRIGHT", -lane, 0)
		child:SetWidth(math.max(1, frame:GetParent():GetWidth() - lane))
	end
	self.bar:SetShown(overflows)
	if overflows then
		self.bar:SetVisibleExtentPercentage(viewHeight / self.contentHeight)
		self.bar:SetPanExtentPercentage(math.min(1, (self.options.step or 60) / range))
	end
	self.target = math.min(self.target, range)
	self:SetOffset(math.min(self.offset, range))
end

---Draws the list at an offset and moves the bar to match.
function lib.Scroll:SetOffset(offset)
	self.offset = offset
	self.frame:SetVerticalScroll(offset)
	local range = self:Range()
	if range > 0 then
		self.updatingBar = true
		self.bar:SetScrollPercentage(offset / range, true)
		self.updatingBar = nil
	end
end

---Glides by wheel notches, snapping the target to whole rows when the list has a row height.
function lib.Scroll:ScrollBy(notches)
	local range = self:Range()
	if range <= 0 then
		return
	end
	local target = self.target + notches * (self.options.step or 60)
	local row = self.options.row
	if row then
		target = math.floor(target / row + 0.5) * row
	end
	self.target = math.max(0, math.min(range, target))
	self.driver:Show()
end

---Moves at once to an offset, stopping any glide.
function lib.Scroll:JumpTo(offset)
	self.target = math.max(0, math.min(self:Range(), offset))
	self.driver:Hide()
	self:SetOffset(self.target)
end

---Glides to an offset (clamped to the list's range).
function lib.Scroll:GlideTo(offset)
	self.target = math.max(0, math.min(self:Range(), offset))
	self.driver:Show()
end

---Keeps a band (top and height in list units) in view, gliding the least distance needed.
function lib.Scroll:Reveal(top, height)
	local viewHeight = self.frame:GetHeight()
	if top < self.target then
		self.target = top
	elseif top + height > self.target + viewHeight then
		self.target = top + height - viewHeight
	else
		return
	end
	self.target = math.max(0, math.min(self:Range(), self.target))
	self.driver:Show()
end

-- The thumb keeps Blizzard's look. Lists made by an older copy of the library still call this from their scripts.
function lib.Scroll:UpdateLit()
	self.bar:GetThumb():SetAlpha(1)
	if not self.options.slim then
		self.bar.Back:SetAlpha(1)
		self.bar.Forward:SetAlpha(1)
	end
end

function Handlers.Glide(scroll, elapsed)
	local distance = scroll.target - scroll.offset
	if math.abs(distance) <= SNAP_DISTANCE then
		scroll:SetOffset(scroll.target)
		scroll.driver:Hide()
		return
	end
	local nextOffset = scroll.offset + distance * (1 - math.exp(-EASE_RATE * math.min(elapsed, 0.1)))
	if distance > 0 then
		nextOffset = math.min(scroll.target, math.ceil(nextOffset))
	else
		nextOffset = math.max(scroll.target, math.floor(nextOffset))
	end
	scroll:SetOffset(nextOffset)
end

-- The thumb, track and arrows move the list at once.
function Handlers.BarScrolled(scroll, percentage)
	if scroll.updatingBar then
		return
	end
	scroll.target = percentage * scroll:Range()
	scroll.driver:Hide()
	scroll.offset = scroll.target
	scroll.frame:SetVerticalScroll(scroll.offset)
end
