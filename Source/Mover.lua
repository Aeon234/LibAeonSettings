-- Movers: one overlay per shown target. Dragging and the arrow keys write pending positions; the real frame follows.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local Geometry = lib.Geometry

local MIN_SIZE = 18         -- smallest mover side
local EXPANDED_WIDTH, EXPANDED_HEIGHT = 64, 40 -- smallest mover while hovered, with room for the cog
local LINKS_HEIGHT = 16     -- extra height an expanded mover takes for its link row
local ANCHORED_NAME = { 1, 0.7, 0.3 }
local WHITE = { 1, 1, 1 }
local TEXT_PLATE_ALPHA = 0.7
local TEXT_PLATE_PADDING_X, TEXT_PLATE_PADDING_Y = 8, 3
local TEXT_INSET_X, TEXT_INSET_Y = 10, 6 -- the label's offset from the mover's top left
local MIN_LABEL_WIDTH = 32  -- narrowest room for a truncated label; a smaller mover shows it only while expanded
local SUBTITLE_GAP = 2      -- space between the label and the subtitle
local REFUSED = lib.COLOR.destructive
local HOVER_INTENT = 0.12   -- seconds the cursor rests on a mover before it expands
local COG_SIZE = 22
local COG_ALPHA = 0.9
-- Cog states: normal white, hover gold, pressed darker gold, open (its menu showing) gold.
local COG_NORMAL = { 1, 1, 1 }
local COG_HOVER = lib.COLOR.accent
local COG_PRESSED = { 0.8, 0.62, 0.1 }
local EXPAND_DURATION = 0.15 -- seconds the mover takes to grow or shrink
local DRAG_THRESHOLD = 3    -- UI units the cursor moves before a press becomes a drag
local NUDGE, NUDGE_SHIFT = 1, 10 -- physical pixels per arrow key press
local HOVER_ALPHA = 0.4
local SNAP_RESPONSE = 0.18 -- the frame easing onto a snap line and off it
local CAUGHT = 0.5 -- UI units from the line at which the ease ends and the frame follows the cursor again
local SETTLE_RESPONSE, SETTLE_DAMPING = 0.3, 0.8 -- a fast drop's give
local SETTLE_SPEED = 500 -- UI units per second at release above which the drop settles
local SETTLE_SHARE, SETTLE_MOST = 0.25, 600 -- the share of the release speed carried, and its most
local VELOCITY_WINDOW = 0.1 -- seconds of cursor movement the release speed is measured over
local SNAP_PULSE_LOW, SNAP_PULSE_HIGH, SNAP_PULSE_HZ = 0.35, 0.85, 1.5

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

lib.MoverHandlers = lib.MoverHandlers or {}
local Handlers = lib.MoverHandlers

-- Geometry of a target's frame in UIParent units.
local function FrameRect(frame)  -- also lib:FrameRect
	local left, bottom = frame:GetLeft(), frame:GetBottom()
	if not left or not bottom then
		return
	end
	local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()

	return left * scale, bottom * scale, frame:GetWidth() * scale, frame:GetHeight() * scale
end

function lib:FrameRect(frame)
	return FrameRect(frame)
end

-- What a target's mover covers, in UIParent units: its `outline` while that is shown and laid out (a border drawn
-- outside the frame), else its frame.
local function TargetRect(target)
	local outline = target.outline
	if type(outline) == "function" then
		local ok, region = pcall(outline, target)
		outline = ok and region or nil
	end
	if type(outline) == "table" and outline.IsShown and outline:IsShown() then
		local left, bottom = outline:GetLeft(), outline:GetBottom()
		if left and bottom then
			local owner = outline.GetEffectiveScale and outline or outline:GetParent()
			local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()

			return left * scale, bottom * scale, outline:GetWidth() * scale, outline:GetHeight() * scale
		end
	end

	return FrameRect(target.frame)
end

function lib:TargetRect(target)
	return TargetRect(target)
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
	-- A dark plate behind the label (and the link row when expanded) keeps the text readable over the selection
	-- art and whatever the frame itself draws.
	mover.plate = mover.text:CreateTexture(nil, "BACKGROUND")
	mover.plate:SetColorTexture(0, 0, 0, TEXT_PLATE_ALPHA)
	mover.name = mover.text:CreateFontString(nil, "OVERLAY")
	lib:SetType(mover.name, "secondary")
	lib:OutlineText(mover.name)
	mover.name:SetPoint("TOPLEFT", mover, "TOPLEFT", TEXT_INSET_X, -TEXT_INSET_Y)
	mover.name:SetJustifyH("LEFT")
	mover.name:SetWordWrap(false)
	mover.subtitle = mover.text:CreateFontString(nil, "OVERLAY")
	lib:SetType(mover.subtitle, "caption", "tertiary")
	lib:OutlineText(mover.subtitle)
	mover.subtitle:SetPoint("TOPLEFT", mover.name, "BOTTOMLEFT", 0, -SUBTITLE_GAP)
	mover.subtitle:SetJustifyH("LEFT")
	mover.subtitle:SetWordWrap(false)
	mover.coordinates = mover.text:CreateFontString(nil, "OVERLAY")
	lib:SetType(mover.coordinates, "caption")
	lib:OutlineText(mover.coordinates)
	mover.coordinates:SetPoint("BOTTOMLEFT", mover, "TOPLEFT", 3, 4)

	local cog = CreateFrame("Button", nil, mover.text)
	cog:SetSize(COG_SIZE, COG_SIZE)
	cog:SetPoint("TOPRIGHT", mover, "TOPRIGHT", -3, -3)
	-- The library's cog: a white glyph with a black keyline, so it reads over both selection colors.
	cog.icon = cog:CreateTexture(nil, "ARTWORK")
	cog.icon:SetAllPoints()
	cog.icon:SetTexture(lib.mediaPath .. "Textures\\icon-cog-on")
	cog.mover = mover
	cog:RegisterForClicks("LeftButtonUp")
	cog:SetScript("OnClick", function(self) Handlers.CogClick(self.mover) end)
	cog:SetScript("OnEnter", function(self) self.hovered = true; Handlers.PaintCog(self) end)
	cog:SetScript("OnLeave", function(self)
		self.hovered, self.pressed = false, false
		Handlers.PaintCog(self)
		Handlers.Leave(self.mover)
	end)
	cog:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then
			self.pressed = true
			Handlers.PaintCog(self)
		end
	end)
	cog:SetScript("OnMouseUp", function(self) self.pressed = false; Handlers.PaintCog(self) end)
	Handlers.PaintCog(cog)
	cog:Hide()
	mover.cog = cog
	lib:CreateLinks(mover)

	-- Runs only while the mover grows or shrinks.
	mover.animator = CreateFrame("Frame", nil, mover)
	mover.animator.mover = mover
	mover.animator:Hide()
	mover.animator:SetScript("OnUpdate", function(self) Handlers.Animate(self) end)

	mover:SetScript("OnMouseDown", function(self, button) Handlers.MouseDown(self, button) end)
	mover:SetScript("OnMouseUp", function(self, button) Handlers.MouseUp(self, button) end)
	mover:SetScript("OnEnter", function(self) Handlers.Enter(self) end)
	mover:SetScript("OnLeave", function(self) Handlers.Leave(self) end)

	return mover
end

function Handlers.PaintCog(cog)
	local open = lib:MenuOwner() == cog.mover.id
	local color = cog.pressed and COG_PRESSED or (cog.hovered or open) and COG_HOVER or COG_NORMAL
	cog.icon:SetVertexColor(unpack(color))
	cog.icon:SetAlpha((cog.hovered or cog.pressed or open) and 1 or COG_ALPHA)
end

-- State ----------------------------------------------------------------------------------------------------------

function lib:SelectMover(id)
	self.session.selected = id
	self:RefreshMovers()
end

local function PaintMover(mover, state, hovered, fill, showCoordinates, snapTarget, expanded, refused, anchored)
	local kit = (state == "selected" or state == "dragging" or refused) and KIT_SELECTED or KIT_HIGHLIGHT
	if mover.kit ~= kit then
		NineSliceUtil.ApplyLayout(mover.selection, SELECTION_LAYOUT, kit)
		mover.kit = kit
	end
	-- A refused pick flashes the selection art red.
	local r, g, b = 1, 1, 1
	if refused then
		r, g, b = REFUSED[1], REFUSED[2], REFUSED[3]
	end
	for _, piece in ipairs(PIECES) do
		mover.selection[piece]:SetVertexColor(r, g, b)
	end
	mover.name:SetTextColor(unpack(anchored and ANCHORED_NAME or WHITE))
	-- The snap target shows Blizzard's hover art, pulsed while the drag lasts.
	mover.hover:SetShown((hovered and state ~= "dragging") or snapTarget)
	if not snapTarget then
		mover.hover:SetAlpha(HOVER_ALPHA)
	end
	-- Without the fill only the outline is drawn, so the frame being moved stays visible.
	mover.selection.Center:SetShown(fill)
	mover.hover.Center:SetShown(fill)
	mover.coordinates:SetShown(showCoordinates or state ~= "idle" or hovered or expanded)
	Handlers.PaintCog(mover.cog)
end

local function EaseOut(t)
	return 1 - (1 - t) * (1 - t)
end

function Handlers.Animate(animator)
	local mover = animator.mover
	local progress = math.min(1, (GetTime() - animator.start) / EXPAND_DURATION)
	local eased = EaseOut(progress)
	local width = animator.fromWidth + (animator.toWidth - animator.fromWidth) * eased
	local height = animator.fromHeight + (animator.toHeight - animator.fromHeight) * eased
	mover:SetSize(width, height)
	mover.cog:SetAlpha(animator.toExpanded and eased or 1 - eased)
	if progress >= 1 then
		animator:Hide()
		mover.cog:SetShown(animator.toExpanded)
		mover.cog:SetAlpha(1)
	end
end

---Fits the label, subtitle and their plate inside a mover of the given size. Text wider than the room is truncated;
---the subtitle, then the label, is hidden when the mover is too small to hold it.
local function FitText(mover, width, height, expanded, linksWidth)
	local showLinks = expanded and linksWidth > 0
	local room = width - TEXT_INSET_X - (expanded and COG_SIZE + 10 or TEXT_INSET_X)
	local nameHeight = mover.name:GetStringHeight()
	local textBottom = TEXT_INSET_Y + nameHeight + TEXT_PLATE_PADDING_Y
	local showName = room >= MIN_LABEL_WIDTH and height >= textBottom
	local showSubtitle = false
	if showName and not showLinks and (mover.subtitle:GetText() or "") ~= "" then
		local subtitleHeight = mover.subtitle:GetStringHeight()
		showSubtitle = height >= textBottom + SUBTITLE_GAP + subtitleHeight
	end
	mover.name:SetShown(showName)
	mover.subtitle:SetShown(showSubtitle)
	mover.plate:SetShown(showName)
	if not showName then
		return
	end
	mover.name:SetWidth(room)
	mover.subtitle:SetWidth(room)

	local textWidth = math.min(mover.name:GetUnboundedStringWidth(), room)
	local textHeight = nameHeight
	if showLinks then
		textWidth = math.max(textWidth, linksWidth)
		textHeight = textHeight + LINKS_HEIGHT + 1
	elseif showSubtitle then
		textWidth = math.max(textWidth, math.min(mover.subtitle:GetUnboundedStringWidth(), room))
		textHeight = textHeight + SUBTITLE_GAP + mover.subtitle:GetStringHeight()
	end
	mover.plate:ClearAllPoints()
	mover.plate:SetPoint("TOPLEFT", mover, "TOPLEFT", TEXT_INSET_X - TEXT_PLATE_PADDING_X,
		-TEXT_INSET_Y + TEXT_PLATE_PADDING_Y)
	mover.plate:SetSize(textWidth + 2 * TEXT_PLATE_PADDING_X, textHeight + 2 * TEXT_PLATE_PADDING_Y)
end

---Centers a mover on its target's frame and sizes it, growing or shrinking over EXPAND_DURATION when its
---expansion changes; any other change applies at once.
local function LayoutMover(mover, target, expanded, linksWidth)
	local left, bottom, width, height = TargetRect(target)
	if not left then
		mover:Hide()
		return
	end
	local moverWidth, moverHeight = math.max(width, MIN_SIZE), math.max(height, MIN_SIZE)
	if expanded then
		local expandedHeight = EXPANDED_HEIGHT + (linksWidth > 0 and LINKS_HEIGHT or 0)
		-- Room for the label or link row from the left inset, and for the cog on the right.
		local textWidth = math.max(linksWidth, mover.name:GetUnboundedStringWidth())
		if linksWidth == 0 then
			textWidth = math.max(textWidth, mover.subtitle:GetUnboundedStringWidth())
		end
		moverWidth = math.max(moverWidth, EXPANDED_WIDTH, TEXT_INSET_X + textWidth + COG_SIZE + 10)
		moverHeight = math.max(moverHeight, expandedHeight)
	end
	-- Text fits the size the mover ends at, so it never spills past the mover while it grows or shrinks.
	FitText(mover, moverWidth, moverHeight, expanded, linksWidth)
	mover:ClearAllPoints()
	mover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", left + width / 2, bottom + height / 2)

	local animator = mover.animator
	if mover.expanded ~= nil and mover.expanded ~= expanded and mover:IsShown() then
		animator.fromWidth, animator.fromHeight = mover:GetSize()
		animator.toWidth, animator.toHeight = moverWidth, moverHeight
		animator.toExpanded = expanded
		animator.start = GetTime()
		mover.cog:Show()
		animator:Show()
	elseif animator:IsShown() then
		animator.toWidth, animator.toHeight = moverWidth, moverHeight
	else
		mover:SetSize(moverWidth, moverHeight)
		mover.cog:SetShown(expanded)
	end
	mover.expanded = expanded

	local centerX = left + width / 2 - UIParent:GetWidth() / 2
	local centerY = bottom + height / 2 - UIParent:GetHeight() / 2
	mover.coordinates:SetFormattedText("%d, %d", Round(centerX), Round(centerY))
end

function lib:RefreshMovers()
	local ui = self.ui
	-- While edit mode fades out the movers stay as they were; they go when it has.
	if not ui or ui.closing then
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
					local id = lib:MoverId(addonName, target.key)
					if not session.hidden[id] and target.frame:IsShown() then
						local mover = ui.movers[id] or CreateMover(ui.moverLayer)
						ui.movers[id] = mover
						mover.addonName, mover.key, mover.id, mover.target = addonName, target.key, id, target
						local pick = session.pick
						local dragging = session.drag and session.drag.started
						-- The mover whose menu is open stays expanded, since the menu hangs from its cog.
						local expanded = (session.expanded == id or lib:MenuOwner() == id) and not dragging and not pick
						if pick and pick.source == id then
							mover.name:SetText(lib.L["PICK_" .. pick.kind:upper()])
						else
							mover.name:SetText(target.label or target.key)
						end
						mover.subtitle:SetText(target.subtitle or "")
						local position = registration:Current(target)
						local linksWidth = lib:LayoutLinks(mover, target, position, expanded)
						LayoutMover(mover, target, expanded, linksWidth)

						local state = "idle"
						if session.drag and session.drag.id == id and session.drag.started then
							state = "dragging"
						elseif session.selected == id or session.pressed == id then
							state = "selected"
						end
						local snapTarget = session.drag and session.drag.started and session.drag.snapFrom == id
						PaintMover(mover, state, session.hovered == id, fill, showCoordinates, snapTarget, expanded,
							session.refused == id, position.anchor ~= nil)
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
			mover.expanded = nil
			mover.animator:Hide()
		end
	end
	if session.selected and not used[session.selected] then
		session.selected = nil
	end
	if session.expanded and not used[session.expanded] then
		session.expanded = nil
	end
	self:RefreshLines()
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

---Starts a press on a mover. A press on one of its links passes `linkAction`: it runs on release, or the press
---becomes a drag after 1 unit of movement.
function Handlers.MouseDown(mover, button, linkAction)
	local session = lib.session
	if button ~= "LeftButton" or InCombatLockdown() or not session.open or session.paused then
		return
	end
	if lib.session.pick then
		lib:PickMover(mover.id)
		return
	end
	lib:CloseMenus()
	local registration, target = TargetOf(mover)
	if not target then
		return
	end
	-- A pinned target is not dragged: a drag shakes it and says why; a click still selects it.
	local pinned = not linkAction and lib:PinnedReason(target) or nil
	Handlers.EndSettle()
	local left, bottom, width, height = FrameRect(target.frame)
	if not left then
		return
	end
	-- The mover's edges snap: where its outline sits around the frame.
	local outerLeft, outerBottom, outerWidth, outerHeight = TargetRect(target)
	if not outerLeft then
		outerLeft, outerBottom, outerWidth, outerHeight = left, bottom, width, height
	end
	local cursorX, cursorY = CursorPosition()
	lib.session.drag = {
		id = mover.id, registration = registration, target = target, started = false,
		cursorX = cursorX, cursorY = cursorY, left = left, bottom = bottom, width = width, height = height,
		insetLeft = left - outerLeft, insetBottom = bottom - outerBottom,
		extraWidth = outerWidth - width, extraHeight = outerHeight - height,
		link = linkAction, threshold = linkAction and 1 or DRAG_THRESHOLD, pinned = pinned,
		history = {}, easeX = { value = 0, velocity = 0 }, easeY = { value = 0, velocity = 0 },
	}
	mover:SetScript("OnUpdate", function(self, elapsed) Handlers.DragUpdate(self, elapsed) end)
	-- The press shows the selection at once, before any movement.
	if not linkAction then
		session.pressed = mover.id
		lib:RefreshMovers()
	end
end

-- Moves one axis's snap offset toward `target`: exactly while the frame follows the cursor, on a spring while it
-- catches a line it reached or lets go of one it left. Returns the offset.
local function EaseAxis(ease, target, snapped, elapsed)
	if snapped ~= ease.snapped then
		ease.snapped = snapped
		ease.catching = not lib:ReduceMotion()
	end
	if ease.catching then
		ease.value, ease.velocity = lib.Motion.Step(ease.value, ease.velocity, target, SNAP_RESPONSE, 1, elapsed)
		if math.abs(ease.value - target) < CAUGHT and math.abs(ease.velocity) < CAUGHT * 20 then
			ease.catching = false
		end
	end
	if not ease.catching then
		ease.value, ease.velocity = target, 0
	end

	return ease.value
end

function Handlers.DragUpdate(mover, elapsed)
	local drag = lib.session.drag
	elapsed = elapsed or 0
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
		if math.abs(dx) < drag.threshold and math.abs(dy) < drag.threshold then
			return
		end
		if drag.pinned then
			Handlers.EndDrag(mover, true)
			lib:Refuse(drag.id, drag.pinned)
			lib:Shake(mover)
			return
		end
		drag.started = true
		lib.session.selected = drag.id
		lib.session.expanded = nil
		-- Shift held as the drag starts locks it to the axis of that first movement.
		if IsShiftKeyDown() then
			drag.axis = math.abs(dx) >= math.abs(dy) and "x" or "y"
		end
		-- Movers attached to or matched with the dragged one, directly or through others, are redrawn with it on
		-- each step and are not snap candidates.
		local followers, moving = {}, { mover }
		for id, other in pairs(lib.ui.movers) do
			if id ~= drag.id and other:IsShown() and other.target and lib:DependsOn(id, drag.id) then
				followers[id] = true
				table.insert(moving, other)
			end
		end
		drag.moving = moving
		drag.xs, drag.ys = lib:SnapCandidates(drag.id, TargetRect, followers)
		drag.threshold = lib:SnapThreshold()
		drag.snap = lib:GetPreference("snap")
		drag.redraw = true
	end

	local snapMover = drag.snapFrom and lib.ui.movers[drag.snapFrom]
	if snapMover then
		local wave = (math.sin(GetTime() * SNAP_PULSE_HZ * 2 * math.pi) + 1) / 2
		snapMover.hover:SetAlpha(SNAP_PULSE_LOW + (SNAP_PULSE_HIGH - SNAP_PULSE_LOW) * wave)
	end

	-- The cursor's last tenth of a second, for the release speed.
	local now = GetTime()
	local history = drag.history
	table.insert(history, { now, cursorX, cursorY })
	while #history > 2 and now - history[1][1] > VELOCITY_WINDOW do
		table.remove(history, 1)
	end

	local altDown = IsAltKeyDown()
	local easing = drag.easeX.catching or drag.easeY.catching
	if dx == drag.lastDx and dy == drag.lastDy and altDown == drag.lastAlt and not easing then
		return
	end
	drag.lastDx, drag.lastDy, drag.lastAlt = dx, dy, altDown

	if drag.axis == "x" then
		dy = 0
	elseif drag.axis == "y" then
		dx = 0
	end
	local left, bottom, width, height = drag.left + dx, drag.bottom + dy, drag.width, drag.height
	local snapX, snapY
	if drag.snap and not altDown then
		local outerLeft, outerBottom = left - drag.insetLeft, bottom - drag.insetBottom
		local outerWidth, outerHeight = width + drag.extraWidth, height + drag.extraHeight
		if drag.axis ~= "y" then
			snapX = Geometry.NearestSnap({ outerLeft, outerLeft + outerWidth / 2, outerLeft + outerWidth }, drag.xs,
				drag.threshold)
		end
		if drag.axis ~= "x" then
			snapY = Geometry.NearestSnap({ outerBottom, outerBottom + outerHeight / 2, outerBottom + outerHeight },
				drag.ys, drag.threshold)
		end
	end
	-- Where the frame lands on release is exact; on screen it eases onto a line and off it.
	drag.finalLeft, drag.finalBottom = left + (snapX and snapX.delta or 0), bottom + (snapY and snapY.delta or 0)
	left = left + EaseAxis(drag.easeX, snapX and snapX.delta or 0, snapX ~= nil, elapsed)
	bottom = bottom + EaseAxis(drag.easeY, snapY and snapY.delta or 0, snapY ~= nil, elapsed)
	local snapFrom = (snapX and snapX.from) or (snapY and snapY.from)
	if snapFrom ~= drag.snapFrom then
		drag.snapFrom = snapFrom
		drag.redraw = true
	end
	lib:ShowGuides(snapX and snapX.value, snapY and snapY.value)
	lib:MoveTargetTo(drag.registration.addonName, drag.target, left, bottom, width, height, true)

	-- A step only moves the dragged mover and its followers; every mover is redrawn when the drag starts and when the
	-- snap target changes, since those change how movers are painted.
	if drag.redraw then
		drag.redraw = nil
		lib:RefreshMovers()
	else
		for _, moved in ipairs(drag.moving) do
			LayoutMover(moved, moved.target, false, 0)
		end
		lib:MoveLines()
	end
end

---Ends a press or drag. `refused`: a pinned target's drag, which neither moves nor selects it.
function Handlers.EndDrag(mover, refused)
	mover:SetScript("OnUpdate", nil)
	local drag = lib.session.drag
	lib.session.drag = nil
	lib.session.pressed = nil
	lib:ShowGuides(nil, nil)
	if refused then
		lib:RefreshMovers()
		return
	end
	if drag and drag.started and drag.finalLeft then
		-- A frame still easing onto its line lands on it; a fast drop then settles with a little give.
		lib:MoveTargetTo(drag.registration.addonName, drag.target, drag.finalLeft, drag.finalBottom, drag.width,
			drag.height, true)
		Handlers.StartSettle(mover, drag)
	end
	if drag and not drag.started and drag.id == mover.id then
		if drag.link then
			lib:RefreshMovers()
			drag.link()
			return
		end
		lib.session.selected = lib.session.selected ~= mover.id and mover.id or nil
	end
	lib:RefreshMovers()
end

-- The release speed across the last tenth of a second, in UI units per second, along the drag's locked axis.
local function ReleaseVelocity(drag)
	local history = drag.history
	local first, last = history[1], history[#history]
	if not first or first == last or last[1] <= first[1] then
		return 0, 0
	end
	local time = last[1] - first[1]
	local vx, vy = (last[2] - first[2]) / time, (last[3] - first[3]) / time

	return drag.axis == "y" and 0 or vx, drag.axis == "x" and 0 or vy
end

-- A fast drop carries a share of its speed past where it landed and springs back, under-damped; the pending
-- position stays where it landed.
function Handlers.StartSettle(mover, drag)
	local vx, vy = ReleaseVelocity(drag)
	if math.sqrt(vx * vx + vy * vy) < SETTLE_SPEED or lib:ReduceMotion() then
		return
	end
	local function Carry(v)
		return math.max(-SETTLE_MOST, math.min(SETTLE_MOST, v * SETTLE_SHARE))
	end
	lib.session.settle = {
		mover = mover, drag = drag, x = 0, y = 0, vx = Carry(vx), vy = Carry(vy),
	}
	mover:SetScript("OnUpdate", function(_, elapsed) Handlers.SettleStep(elapsed) end)
end

function Handlers.SettleStep(elapsed)
	local settle = lib.session.settle
	if not settle or InCombatLockdown() then
		Handlers.EndSettle()
		return
	end
	local Step = lib.Motion.Step
	settle.x, settle.vx = Step(settle.x, settle.vx, 0, SETTLE_RESPONSE, SETTLE_DAMPING, elapsed)
	settle.y, settle.vy = Step(settle.y, settle.vy, 0, SETTLE_RESPONSE, SETTLE_DAMPING, elapsed)
	local Settled = lib.Motion.Settled
	local settled = Settled(settle.x, settle.vx, 0, 0.05) and Settled(settle.y, settle.vy, 0, 0.05)
	if settled then
		settle.x, settle.y = 0, 0
	end
	local drag = settle.drag
	lib:MoveTargetTo(drag.registration.addonName, drag.target, drag.finalLeft + settle.x,
		drag.finalBottom + settle.y, drag.width, drag.height, true)
	for _, moved in ipairs(drag.moving or {}) do
		LayoutMover(moved, moved.target, false, 0)
	end
	lib:MoveLines()
	if settled then
		Handlers.EndSettle()
	end
end

---Ends a settling drop where it landed.
function Handlers.EndSettle()
	local settle = lib.session.settle
	if not settle then
		return
	end
	lib.session.settle = nil
	settle.mover:SetScript("OnUpdate", nil)
	local drag = settle.drag
	if settle.x ~= 0 or settle.y ~= 0 then
		lib:MoveTargetTo(drag.registration.addonName, drag.target, drag.finalLeft, drag.finalBottom, drag.width,
			drag.height, true)
	end
	lib:RefreshMovers()
end

function Handlers.MouseUp(mover, button)
	if button == "LeftButton" then
		Handlers.EndDrag(mover)
	elseif button == "RightButton" and not lib.session.pick then
		if IsShiftKeyDown() then
			lib:CloseMenus()
			lib.session.hidden[mover.id] = true
			lib:RefreshMovers()
		else
			lib:ToggleCogMenu(mover)
		end
	end
end

function Handlers.CogClick(mover)
	if not lib.session.pick then
		lib:ToggleCogMenu(mover)
	end
end

function Handlers.Enter(mover)
	local session = lib.session
	session.hovered = mover.id
	if session.expandTimer then
		session.expandTimer:Cancel()
	end
	session.expandTimer = C_Timer.NewTimer(HOVER_INTENT, function()
		session.expandTimer = nil
		if session.hovered == mover.id and not session.drag and not session.pick then
			session.expanded = mover.id
			lib:RefreshMovers()
		end
	end)
	lib:RefreshMovers()
end

function Handlers.Leave(mover)
	-- Moving onto the mover's own cog is not leaving it.
	if mover:IsMouseOver() then
		return
	end
	local session = lib.session
	if session.hovered == mover.id then
		session.hovered = nil
	end
	if session.expanded == mover.id and lib:MenuOwner() ~= mover.id then
		session.expanded = nil
	end
	lib:RefreshMovers()
end

local ARROWS = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }

---Moves the selected mover by whole physical pixels. Returns true when the key was used.
function lib:NudgeSelected(key)
	Handlers.EndSettle()
	local direction = ARROWS[key]
	local selected = self.session.selected
	local mover = selected and self.ui and self.ui.movers and self.ui.movers[selected]
	if not direction or not mover or not mover:IsShown() then
		return false
	end
	local registration, target = TargetOf(mover)
	local left, bottom, width, height = FrameRect(target.frame)
	if not left or lib:PinnedReason(target) then
		return false
	end
	local step = (IsShiftKeyDown() and NUDGE_SHIFT or NUDGE) * PixelSize()
	lib:MoveTargetTo(registration.addonName, target, left + direction[1] * step, bottom + direction[2] * step, width, height)

	return true
end
