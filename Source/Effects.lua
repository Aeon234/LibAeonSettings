-- Edit mode's presentation: the opening sequence and the closing that runs it backward, Hover Top Bar, the Shift
-- fade and the first-time tip.
-- Animations use animation groups; OnUpdate runs only for the toolbar's slide and while Hover Top Bar is on.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

local HOVER_BAR_ZONE = 60    -- UI units around the toolbar within which Hover Top Bar shows it
local HOVER_BAR_SPEED = 4    -- alpha per second
local SHIFT_FADE = 0.15
local TIP_GAP, TIP_DROP = 16, 12  -- the tip's distance below the toolbar, and how far above that it starts
local TIP_FADE_IN, TIP_FADE_OUT = 0.45, 0.2
local TIP_DELAY = 0.5            -- seconds into the opening sequence, as the toolbar settles

lib.EffectHandlers = lib.EffectHandlers or {}
local Handlers = lib.EffectHandlers

local function Alpha(group, from, to, duration, delay, order)
	local animation = group:CreateAnimation("Alpha")
	animation:SetFromAlpha(from)
	animation:SetToAlpha(to)
	animation:SetDuration(duration)
	animation:SetStartDelay(delay or 0)
	animation:SetOrder(order or 1)

	return animation
end

-- Opening ------------------------------------------------------------------------------------------------------

-- The opening timeline, in seconds. One driver sets every alpha and the toolbar's place each frame, so the
-- first frame is exactly what PrepareOpening set and nothing is shown before its time.
local TINT_DURATION = 0.5
local MOVERS_DELAY, MOVERS_DURATION = 0, 0.5
local TOOLBAR_SLIDE_DELAY, TOOLBAR_SLIDE_DURATION = 0, 0.5
local OPENING_LENGTH = math.max(MOVERS_DELAY + MOVERS_DURATION, TOOLBAR_SLIDE_DELAY + TOOLBAR_SLIDE_DURATION)
local CLOSING_SPEED = 2 -- the closing runs the opening backward this many times faster

local function EaseOut(t)
	return 1 - (1 - t) * (1 - t)
end

local function Clamp01(value)
	return math.max(0, math.min(1, value))
end

---Applies the opening sequence's state at `t` seconds.
local function ApplyOpening(ui, t)
	ui.tint:SetAlpha(Clamp01(t / TINT_DURATION))
	ui.grid:SetAlpha(Clamp01(t / TINT_DURATION))
	ui.moverLayer:SetAlpha(Clamp01((t - MOVERS_DELAY) / MOVERS_DURATION))
	local progress = Clamp01((t - TOOLBAR_SLIDE_DELAY) / TOOLBAR_SLIDE_DURATION)
	ui.toolbar:SetAlpha(progress)
	ui.toolbarSlide = (ui.openingDistance or 0) * (1 - EaseOut(progress))
	lib:PlaceToolbar()
end

function Handlers.Opening(driver, elapsed)
	driver.elapsed = driver.elapsed + elapsed
	local ui = lib.ui
	if driver.elapsed >= OPENING_LENGTH then
		lib:StopOpening()
		return
	end
	ApplyOpening(ui, driver.elapsed)
end

---Sets the opening sequence's first frame before anything is shown: the tint, grid, movers and toolbar
---transparent, and the toolbar wholly out of view above its place when it opens docked. Clamping is off meanwhile,
---since a clamped toolbar cannot start above the screen.
function lib:PrepareOpening()
	local ui = self.ui
	ui.openingActive = true
	ui.toolbar:SetClampedToScreen(false)
	ui.openingDistance = ui.toolbarSpot and 0 or self:ToolbarHiddenOffset()
	ApplyOpening(ui, 0)
end

---Plays the opening sequence: the tint and grid fade in, the toolbar slides down as it fades in and the movers
---fade in. `from` (seconds) picks it up where a closing left off; `quiet` skips the first-time tip. With Reduce
---Motion everything shows at once.
function lib:PlayOpening(from, quiet)
	local ui = self.ui
	if not quiet then
		C_Timer.After(TIP_DELAY, function()
			if lib.session.open and not lib.session.paused then
				lib:ShowFirstTip()
			end
		end)
	end
	self:PrepareOpening()
	if self:ReduceMotion() then
		self:StopOpening()
		return
	end
	if not ui.openingDriver then
		ui.openingDriver = CreateFrame("Frame", nil, ui.screen)
		ui.openingDriver:SetScript("OnUpdate", function(self, elapsed) Handlers.Opening(self, elapsed) end)
	end
	ui.openingDriver.elapsed = from or 0
	ApplyOpening(ui, ui.openingDriver.elapsed)
	ui.openingDriver:Show()
end

---Plays the opening sequence backward, faster, from where it is (from its end once it has finished), then runs `done`.
---Reduce Motion runs `done` at once.
function lib:PlayClosing(done)
	local ui = self.ui
	local from = ui.openingActive and ui.openingDriver and ui.openingDriver.elapsed or OPENING_LENGTH
	if ui.openingDriver then
		ui.openingDriver:Hide()
	end
	ui.openingActive = nil
	ui.closingDone = done
	if self:ReduceMotion() then
		Handlers.FinishClosing(ui)
		return
	end
	ui.toolbar:SetClampedToScreen(false)
	ui.openingDistance = ui.toolbarSpot and 0 or self:ToolbarHiddenOffset()
	if not ui.closingDriver then
		ui.closingDriver = CreateFrame("Frame", nil, ui.screen)
		ui.closingDriver:SetScript("OnUpdate", function(self, elapsed) Handlers.Closing(self, elapsed) end)
	end
	ui.closingDriver.elapsed = from
	ui.closing = true
	ui.closingDriver:Show()
end

function Handlers.Closing(driver, elapsed)
	driver.elapsed = driver.elapsed - elapsed * CLOSING_SPEED
	if driver.elapsed <= 0 then
		Handlers.FinishClosing(lib.ui)
		return
	end
	ApplyOpening(lib.ui, driver.elapsed)
end

function Handlers.FinishClosing(ui)
	if ui.closingDriver then
		ui.closingDriver:Hide()
	end
	ui.closing = nil
	local done = ui.closingDone
	ui.closingDone = nil
	if done then
		done()
	end
end

---Stops a closing where it is, without running its `done`.
---@return number? from the point in the opening sequence it had reached, or nil when none was running
function lib:StopClosing()
	local ui = self.ui
	if not ui or not ui.closing then
		return nil
	end
	ui.closingDriver:Hide()
	ui.closing, ui.closingDone = nil, nil

	return math.max(0, ui.closingDriver.elapsed)
end

---Ends the opening sequence at once, everything in its final state.
function lib:StopOpening()
	local ui = self.ui
	if not ui then
		return
	end
	if ui.openingDriver then
		ui.openingDriver:Hide()
	end
	ui.openingActive = nil
	ui.openingDistance = 0
	ui.tint:SetAlpha(1)
	ui.grid:SetAlpha(1)
	ui.moverLayer:SetAlpha(1)
	ui.toolbar:SetAlpha(1)
	ui.toolbarSlide = 0
	ui.toolbar:SetClampedToScreen(true)
	self:PlaceToolbar()
	self:RefreshEffects()
end

-- Hover Top Bar -----------------------------------------------------------------------------------------------

local function Driver(ui)
	if not ui.effects then
		local driver = CreateFrame("Frame", nil, ui.screen)
		driver:SetScript("OnUpdate", function(self, elapsed) Handlers.Update(self, elapsed) end)
		driver:Hide()
		ui.effects = driver
	end

	return ui.effects
end

-- The toolbar fades out unless the cursor is within reach of it.
function Handlers.Update(driver, elapsed)
	if lib.shiftHidden or lib.ui.openingActive then
		return
	end
	local toolbar = lib.ui.toolbar
	local x, y = GetCursorPosition()
	-- Nothing to do while the cursor rests and the toolbar already shows the alpha this spot gave it.
	if x == driver.cursorX and y == driver.cursorY and toolbar:GetAlpha() == driver.settled then
		return
	end
	driver.cursorX, driver.cursorY = x, y
	local cursorScale = UIParent:GetEffectiveScale()
	x, y = x / cursorScale, y / cursorScale
	local scale = toolbar:GetScale()
	local left, bottom = toolbar:GetLeft(), toolbar:GetBottom()
	local near = toolbar:IsMouseOver()
	if left and not near then
		left, bottom = left * scale, bottom * scale
		local right, top = left + toolbar:GetWidth() * scale, bottom + toolbar:GetHeight() * scale
		near = x > left - HOVER_BAR_ZONE and x < right + HOVER_BAR_ZONE and y > bottom - HOVER_BAR_ZONE
			and y < top + HOVER_BAR_ZONE
	end
	local wanted = near and 1 or 0
	local alpha = toolbar:GetAlpha()
	if alpha ~= wanted then
		local step = HOVER_BAR_SPEED * elapsed
		alpha = wanted > alpha and math.min(wanted, alpha + step) or math.max(wanted, alpha - step)
		toolbar:SetAlpha(alpha)
	end
	driver.settled = alpha == wanted and alpha or nil
end

---Starts or stops Hover Top Bar to match its preference and the session.
function lib:RefreshEffects()
	local ui = self.ui
	if not ui then
		return
	end
	local driver = Driver(ui)
	local hoverBar = self.session.open and not self.session.paused and self:GetPreference("hoverBar")
	driver:SetShown(hoverBar)
	if not hoverBar and not self.shiftHidden and not ui.openingActive then
		ui.toolbar:SetAlpha(1)
	end
end

-- Shift ------------------------------------------------------------------------------------------------------

-- Holding Shift fades the toolbar away and lets clicks through it, so whatever lies under it can be reached.
function lib:SetShiftHidden(hidden)
	local ui = self.ui
	if not ui or self.shiftHidden == hidden then
		return
	end
	self.shiftHidden = hidden
	local toolbar = ui.toolbar
	toolbar.shiftFade = toolbar.shiftFade or toolbar:CreateAnimationGroup()
	toolbar.shiftFade:Stop()
	if hidden then
		toolbar.shiftAlpha = toolbar.shiftAlpha or Alpha(toolbar.shiftFade, 1, 0, SHIFT_FADE)
		toolbar.shiftAlpha:SetFromAlpha(toolbar:GetAlpha())
		toolbar.shiftFade:SetToFinalAlpha(true)
		toolbar.shiftFade:Play()
		toolbar:EnableMouse(false)
		for _, child in ipairs({ toolbar:GetChildren() }) do
			child:EnableMouse(false)
		end
	else
		toolbar:SetAlpha(1)
		toolbar:EnableMouse(true)
		for _, child in ipairs({ toolbar:GetChildren() }) do
			child:EnableMouse(true)
		end
		self:RefreshEffects()
	end
end

lib.shiftEvents = lib.shiftEvents or CreateFrame("Frame")
lib.shiftEvents:SetScript("OnEvent", function()
	lib:SetShiftHidden(lib.session.open and not lib.session.paused and IsShiftKeyDown() or false)
end)

function lib:WatchShift(watch)
	if watch then
		self.shiftEvents:RegisterEvent("MODIFIER_STATE_CHANGED")
	else
		self.shiftEvents:UnregisterEvent("MODIFIER_STATE_CHANGED")
		self:SetShiftHidden(false)
	end
end

-- First-time tip -----------------------------------------------------------------------------------------------

local function StartTipTween(tip, showing, duration)
	tip.tween = { elapsed = 0, duration = duration, showing = showing }
	tip:SetScript("OnUpdate", function(self, elapsed) Handlers.TipUpdate(self, elapsed) end)
end

local function BuildTip(ui)
	local tip = CreateFrame("Frame", nil, UIParent)
	tip:SetFrameStrata("FULLSCREEN_DIALOG")
	tip:SetWidth(380)
	tip:EnableMouse(true)
	lib:ApplyPanelArt(tip)
	tip.title = tip:CreateFontString(nil, "OVERLAY")
	lib:SetType(tip.title, "body", "cream")
	tip.title:SetPoint("TOPLEFT", 14, -12)
	tip.title:SetText(L.EDIT_MODE)
	tip.text = tip:CreateFontString(nil, "OVERLAY")
	lib:SetType(tip.text, "secondary")
	tip.text:SetPoint("TOPLEFT", tip.title, "BOTTOMLEFT", 0, -8)
	tip.text:SetWidth(352)
	tip.text:SetJustifyH("LEFT")
	tip.text:SetSpacing(3)
	tip.text:SetText(L.FIRST_TIP)
	tip.close = CreateFrame("Button", nil, tip, "UIPanelCloseButton")
	tip.close:SetSize(24, 24)
	tip.close:SetPoint("TOPRIGHT", -5, -5)
	tip.close:SetScript("OnClick", function() lib:HideFirstTip(true) end)
	tip:SetHeight(12 + tip.title:GetStringHeight() + 8 + tip.text:GetStringHeight() + 14)
	tip:SetClampedToScreen(true)
	tip:SetPoint("TOP", ui.toolbar, "BOTTOM", 0, -TIP_GAP)
	tip:Hide()

	return tip
end

-- The tip eases in, fading in as it drops into place below the toolbar, and fades out when closed.
function Handlers.TipUpdate(tip, elapsed)
	if not tip.tween then
		return
	end
	tip.tween.elapsed = tip.tween.elapsed + elapsed
	local progress = Clamp01(tip.tween.elapsed / tip.tween.duration)
	if tip.tween.showing then
		local eased = EaseOut(progress)
		tip:SetAlpha(eased)
		tip:SetPoint("TOP", lib.ui.toolbar, "BOTTOM", 0, -TIP_GAP + TIP_DROP * (1 - eased))
	else
		tip:SetAlpha(1 - progress)
	end
	if progress >= 1 then
		if not tip.tween.showing then
			tip:Hide()
		end
		tip.tween = nil
		tip:SetScript("OnUpdate", nil)
	end
end

---Shows the tip once per account, the first time edit mode opens.
function lib:ShowFirstTip()
	if self:GetPreference("tipSeen") then
		return
	end
	self:SetPreference("tipSeen", true)
	local tip = self.ui.tip or BuildTip(self.ui)
	self.ui.tip = tip
	tip:SetAlpha(0)
	tip:SetPoint("TOP", self.ui.toolbar, "BOTTOM", 0, -TIP_GAP + TIP_DROP)
	StartTipTween(tip, true, TIP_FADE_IN)
	tip:Show()
end

---Hides the tip; `fade` fades it out first.
function lib:HideFirstTip(fade)
	local tip = self.ui and self.ui.tip
	if not tip or not tip:IsShown() then
		return
	end
	if fade then
		StartTipTween(tip, false, TIP_FADE_OUT)
	else
		tip.tween = nil
		tip:SetScript("OnUpdate", nil)
		tip:Hide()
	end
end
