-- Movers: one overlay per shown target. Dragging and the arrow keys write pending positions; the real frame follows.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local Geometry = lib.Geometry

local MIN_SIZE = 18         -- smallest mover side
local DRAG_THRESHOLD = 3    -- UI units the cursor moves before a press becomes a drag
local NUDGE, NUDGE_SHIFT = 1, 10 -- physical pixels per arrow key press
local HOVER_ALPHA = 0.4

-- Blizzard's Edit Mode selection art, drawn from the client's atlases the way its own systems draw it.
local KIT_HIGHLIGHT, KIT_SELECTED = "editmode-actionbar-highlight", "editmode-actionbar-selected"
local SELECTION_LAYOUT = {
	TopRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
	TopLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
	BottomLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
	BottomRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
	TopEdge = { atlas = "_%s-NineSlice-EdgeTop" },
	BottomEdge = { atlas = "_%s-NineSlice-EdgeBottom" },
	LeftEdge = { atlas = "!%s-NineSlice-EdgeLeft" },
	RightEdge = { atlas = "!%s-NineSlice-EdgeRight" },
	Center = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}
local PIECES = {
	"TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
	"TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}

local Handlers = {}
lib.MoverHandlers = Handlers

local function MoverId(addonName, key)
	return addonName .. "\0" .. key
end

-- Geometry of a target's frame in UIParent units.
local function FrameRect(frame)
	local left, bottom = frame:GetLeft(), frame:GetBottom()
	if not left or not bottom then
		return
	end
	local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()

	return left * scale, bottom * scale, frame:GetWidth() * scale, frame:GetHeight() * scale
end

local function PixelSize()
	return PixelUtil.GetNearestPixelSize(1, UIParent:GetEffectiveScale(), 1)
end

local function CreateMover(parent)
	local mover = CreateFrame("Button", nil, parent)
	mover:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	mover.selection = CreateFrame("Frame", nil, mover)
	mover.selection:SetAllPoints()
	mover.hover = CreateFrame("Frame", nil, mover)
	mover.hover:SetAllPoints()
	NineSliceUtil.ApplyLayout(mover.hover, SELECTION_LAYOUT, KIT_HIGHLIGHT)
	for _, piece in ipairs(PIECES) do
		mover.hover[piece]:SetBlendMode("ADD")
	end
	mover.hover:SetAlpha(HOVER_ALPHA)

	-- Text sits on its own child so the selection art never covers it.
	mover.text = CreateFrame("Frame", nil, mover)
	mover.text:SetAllPoints()
	mover.text:SetFrameLevel(mover:GetFrameLevel() + 5)
	mover.name = mover.text:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	mover.name:SetPoint("CENTER")
	mover.name:SetShadowOffset(1, -1)
	mover.subtitle = mover.text:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	mover.subtitle:SetPoint("TOP", mover.name, "BOTTOM", 0, -2)
	mover.coordinates = mover.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	mover.coordinates:SetPoint("BOTTOMLEFT", mover, "TOPLEFT", 3, 4)

	mover:SetScript("OnMouseDown", function(self, button) Handlers.MouseDown(self, button) end)
	mover:SetScript("OnMouseUp", function(self, button) Handlers.MouseUp(self, button) end)
	mover:SetScript("OnEnter", function(self) Handlers.Enter(self) end)
	mover:SetScript("OnLeave", function(self) Handlers.Leave(self) end)

	return mover
end

-- State ----------------------------------------------------------------------------------------------------------

function lib:SelectMover(id)
	self.session.selected = id
	self:RefreshMovers()
end

local function PaintMover(mover, state, hovered, fill, showCoordinates)
	local kit = (state == "selected" or state == "dragging") and KIT_SELECTED or KIT_HIGHLIGHT
	if mover.kit ~= kit then
		NineSliceUtil.ApplyLayout(mover.selection, SELECTION_LAYOUT, kit)
		mover.kit = kit
	end
	mover.hover:SetShown(hovered and state ~= "dragging")
	-- Without the fill only the outline is drawn, so the frame being moved stays visible.
	mover.selection.Center:SetShown(fill)
	mover.hover.Center:SetShown(fill)
	mover.coordinates:SetShown(showCoordinates or state ~= "idle" or hovered)
end

---Places, sizes and paints one mover over its target's frame.
local function LayoutMover(mover, target)
	local left, bottom, width, height = FrameRect(target.frame)
	if not left then
		mover:Hide()
		return
	end
	local moverWidth, moverHeight = math.max(width, MIN_SIZE), math.max(height, MIN_SIZE)
	mover:ClearAllPoints()
	mover:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left - (moverWidth - width) / 2, bottom - (moverHeight - height) / 2)
	mover:SetSize(moverWidth, moverHeight)

	local centerX = left + width / 2 - UIParent:GetWidth() / 2
	local centerY = bottom + height / 2 - UIParent:GetHeight() / 2
	mover.coordinates:SetFormattedText("%d, %d", Round(centerX), Round(centerY))
end

function lib:RefreshMovers()
	local ui = self.ui
	if not ui then
		return
	end
	local session = self.session
	ui.movers = ui.movers or {}
	local used = {}

	if session.open and not session.paused then
		local fill = self:GetPreference("fill")
		local showCoordinates = self:GetPreference("coordinates")
		for _, addonName in ipairs(self.order) do
			local registration = self.registrations[addonName]
			if session.shown[addonName] then
				for _, target in ipairs(registration:Targets()) do
					local id = MoverId(addonName, target.key)
					if not session.hidden[id] and target.frame:IsShown() then
						local mover = ui.movers[id] or CreateMover(ui.moverLayer)
						ui.movers[id] = mover
						mover.addonName, mover.key, mover.id = addonName, target.key, id
						mover.name:SetText(target.label or target.key)
						mover.subtitle:SetText(target.subtitle or "")
						LayoutMover(mover, target)

						local state = "idle"
						if session.drag and session.drag.id == id and session.drag.started then
							state = "dragging"
						elseif session.selected == id then
							state = "selected"
						end
						PaintMover(mover, state, session.hovered == id, fill, showCoordinates)
						mover:Show()
						used[id] = true
					end
				end
			end
		end
	end

	for id, mover in pairs(ui.movers) do
		if not used[id] then
			mover:Hide()
		end
	end
	if session.selected and not used[session.selected] then
		session.selected = nil
	end
end

-- Input ----------------------------------------------------------------------------------------------------------

local function CursorPosition()
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()

	return x / scale, y / scale
end

local function TargetOf(mover)
	local registration = lib.registrations[mover.addonName]

	return registration, registration and registration:Target(mover.key)
end

---Moves a target to a rectangle (UIParent units), clamped to the screen, as a pending position.
local function MoveTo(registration, target, left, bottom, width, height)
	local parentWidth, parentHeight = UIParent:GetWidth(), UIParent:GetHeight()
	left, bottom = Geometry.ClampInto(left, bottom, width, height, parentWidth, parentHeight)
	local point, x, y = Geometry.ToStored(left, bottom, width, height, parentWidth, parentHeight, target.fixedEdge)
	local layoutScale = UIParent:GetEffectiveScale()
	lib:SetPending(registration.addonName, target.key, {
		point = point,
		x = PixelUtil.GetNearestPixelSize(x, layoutScale),
		y = PixelUtil.GetNearestPixelSize(y, layoutScale),
	})
end

function Handlers.MouseDown(mover, button)
	if button ~= "LeftButton" or InCombatLockdown() then
		return
	end
	local registration, target = TargetOf(mover)
	if not target then
		return
	end
	local left, bottom, width, height = FrameRect(target.frame)
	local cursorX, cursorY = CursorPosition()
	lib.session.drag = {
		id = mover.id, registration = registration, target = target, started = false,
		cursorX = cursorX, cursorY = cursorY, left = left, bottom = bottom, width = width, height = height,
	}
	mover:SetScript("OnUpdate", function(self) Handlers.DragUpdate(self) end)
end

function Handlers.DragUpdate(mover)
	local drag = lib.session.drag
	if not drag or InCombatLockdown() then
		Handlers.EndDrag(mover)
		return
	end
	if not IsMouseButtonDown("LeftButton") then
		Handlers.EndDrag(mover)
		return
	end
	local cursorX, cursorY = CursorPosition()
	local dx, dy = cursorX - drag.cursorX, cursorY - drag.cursorY
	if not drag.started then
		if math.abs(dx) < DRAG_THRESHOLD and math.abs(dy) < DRAG_THRESHOLD then
			return
		end
		drag.started = true
		lib.session.selected = drag.id
	end
	if dx == drag.lastDx and dy == drag.lastDy then
		return
	end
	drag.lastDx, drag.lastDy = dx, dy
	MoveTo(drag.registration, drag.target, drag.left + dx, drag.bottom + dy, drag.width, drag.height)
end

function Handlers.EndDrag(mover)
	mover:SetScript("OnUpdate", nil)
	local drag = lib.session.drag
	lib.session.drag = nil
	if drag and not drag.started and drag.id == mover.id then
		lib.session.selected = lib.session.selected ~= mover.id and mover.id or nil
	end
	lib:RefreshMovers()
end

function Handlers.MouseUp(mover, button)
	if button == "LeftButton" then
		Handlers.EndDrag(mover)
	elseif button == "RightButton" and IsShiftKeyDown() then
		lib.session.hidden[mover.id] = true
		lib:RefreshMovers()
	end
end

function Handlers.Enter(mover)
	lib.session.hovered = mover.id
	lib:RefreshMovers()
end

function Handlers.Leave(mover)
	if lib.session.hovered == mover.id then
		lib.session.hovered = nil
	end
	lib:RefreshMovers()
end

local ARROWS = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }

---Moves the selected mover by whole physical pixels. Returns true when the key was used.
function lib:NudgeSelected(key)
	local direction = ARROWS[key]
	local selected = self.session.selected
	local mover = selected and self.ui and self.ui.movers and self.ui.movers[selected]
	if not direction or not mover or not mover:IsShown() then
		return false
	end
	local registration, target = TargetOf(mover)
	local left, bottom, width, height = FrameRect(target.frame)
	if not left then
		return false
	end
	local step = (IsShiftKeyDown() and NUDGE_SHIFT or NUDGE) * PixelSize()
	MoveTo(registration, target, left + direction[1] * step, bottom + direction[2] * step, width, height)

	return true
end
