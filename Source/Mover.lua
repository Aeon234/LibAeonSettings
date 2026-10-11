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
local TEXT_PLATE_ALPHA = 0.7
local TEXT_PLATE_PADDING_X, TEXT_PLATE_PADDING_Y = 8, 3
local TEXT_INSET_X, TEXT_INSET_Y = 10, 6 -- the label's offset from the mover's top left
local REFUSED = { 1, 0.25, 0.2 }
local HOVER_INTENT = 0.12   -- seconds the cursor rests on a mover before it expands
local COG_SIZE = 22
local COG_ALPHA = 0.9
-- Cog states: normal white, hover gold, pressed darker gold, open (its menu showing) gold.
local COG_NORMAL = { 1, 1, 1 }
local COG_HOVER = { 1, 0.82, 0 }
local COG_PRESSED = { 0.8, 0.62, 0.1 }
local EXPAND_DURATION = 0.15 -- seconds the mover takes to grow or shrink
local DRAG_THRESHOLD = 3    -- UI units the cursor moves before a press becomes a drag
local NUDGE, NUDGE_SHIFT = 1, 10 -- physical pixels per arrow key press
local HOVER_ALPHA = 0.4
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

local Handlers = {}
lib.MoverHandlers = Handlers

---Gives a font string its font object's face and size with a thin outline, for text drawn over any background.
function lib:OutlineText(fontString)
	local face, size = fontString:GetFont()
	if face then
		fontString:SetFont(face, size, "OUTLINE")
	end
	fontString:SetShadowOffset(0, 0)
end

local function MoverId(addonName, key)  -- also lib:MoverId
	return addonName .. "\0" .. key
end

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
	mover.name = mover.text:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	lib:OutlineText(mover.name)
	mover.name:SetPoint("TOPLEFT", mover, "TOPLEFT", TEXT_INSET_X, -TEXT_INSET_Y)
	mover.name:SetJustifyH("LEFT")
	mover.subtitle = mover.text:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	lib:OutlineText(mover.subtitle)
	mover.subtitle:SetPoint("TOPLEFT", mover.name, "BOTTOMLEFT", 0, -2)
	mover.coordinates = mover.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
	mover.name:SetTextColor(unpack(anchored and ANCHORED_NAME or { 1, 1, 1 }))
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

---Centers a mover on its target's frame and sizes it, growing or shrinking over EXPAND_DURATION when its
---expansion changes; any other change applies at once.
local function LayoutMover(mover, target, expanded, linksWidth)
	local left, bottom, width, height = FrameRect(target.frame)
	if not left then
		mover:Hide()
		return
	end
	local moverWidth, moverHeight = math.max(width, MIN_SIZE), math.max(height, MIN_SIZE)
	if expanded then
		local expandedHeight = EXPANDED_HEIGHT + (linksWidth > 0 and LINKS_HEIGHT or 0)
		-- Room for the label or link row from the left inset, and for the cog on the right.
		local textWidth = math.max(linksWidth, mover.name:GetStringWidth())
		moverWidth = math.max(moverWidth, EXPANDED_WIDTH, TEXT_INSET_X + textWidth + COG_SIZE + 10)
		moverHeight = math.max(moverHeight, expandedHeight)
	end
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
						-- The name moves up to make room for the link row.
						local showLinks = expanded and linksWidth > 0
						local textWidth = math.max(mover.name:GetStringWidth(), showLinks and linksWidth or 0)
						local textHeight = mover.name:GetStringHeight() + (showLinks and 17 or 0)
						mover.plate:ClearAllPoints()
						mover.plate:SetPoint("TOPLEFT", mover.name, "TOPLEFT", -TEXT_PLATE_PADDING_X, TEXT_PLATE_PADDING_Y)
						mover.plate:SetSize(textWidth + 2 * TEXT_PLATE_PADDING_X, textHeight + 2 * TEXT_PLATE_PADDING_Y)
						mover.subtitle:SetShown(not showLinks)
						LayoutMover(mover, target, expanded, linksWidth)

						local state = "idle"
						if session.drag and session.drag.id == id and session.drag.started then
							state = "dragging"
						elseif session.selected == id then
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
	if button ~= "LeftButton" or InCombatLockdown() then
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
	local left, bottom, width, height = FrameRect(target.frame)
	local cursorX, cursorY = CursorPosition()
	lib.session.drag = {
		id = mover.id, registration = registration, target = target, started = false,
		cursorX = cursorX, cursorY = cursorY, left = left, bottom = bottom, width = width, height = height,
		link = linkAction, threshold = linkAction and 1 or DRAG_THRESHOLD,
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
		if math.abs(dx) < drag.threshold and math.abs(dy) < drag.threshold then
			return
		end
		drag.started = true
		lib.session.selected = drag.id
		lib.session.expanded = nil
		-- Shift held as the drag starts locks it to the axis of that first movement.
		if IsShiftKeyDown() then
			drag.axis = math.abs(dx) >= math.abs(dy) and "x" or "y"
		end
		drag.xs, drag.ys = lib:SnapCandidates(drag.id, FrameRect)
		drag.threshold = lib:SnapThreshold()
	end

	local snapMover = drag.snapFrom and lib.ui.movers[drag.snapFrom]
	if snapMover then
		local wave = (math.sin(GetTime() * SNAP_PULSE_HZ * 2 * math.pi) + 1) / 2
		snapMover.hover:SetAlpha(SNAP_PULSE_LOW + (SNAP_PULSE_HIGH - SNAP_PULSE_LOW) * wave)
	end

	local altDown = IsAltKeyDown()
	if dx == drag.lastDx and dy == drag.lastDy and altDown == drag.lastAlt then
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
	if lib:GetPreference("snap") and not altDown then
		if drag.axis ~= "y" then
			snapX = Geometry.NearestSnap({ left, left + width / 2, left + width }, drag.xs, drag.threshold)
		end
		if drag.axis ~= "x" then
			snapY = Geometry.NearestSnap({ bottom, bottom + height / 2, bottom + height }, drag.ys, drag.threshold)
		end
	end
	left = left + (snapX and snapX.delta or 0)
	bottom = bottom + (snapY and snapY.delta or 0)
	drag.snapFrom = (snapX and snapX.from) or (snapY and snapY.from)
	lib:ShowGuides(snapX and snapX.value, snapY and snapY.value)
	lib:MoveTargetTo(drag.registration.addonName, drag.target, left, bottom, width, height)
end

function Handlers.EndDrag(mover)
	mover:SetScript("OnUpdate", nil)
	local drag = lib.session.drag
	lib.session.drag = nil
	lib:ShowGuides(nil, nil)
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
	lib:MoveTargetTo(registration.addonName, target, left + direction[1] * step, bottom + direction[2] * step, width, height)

	return true
end
