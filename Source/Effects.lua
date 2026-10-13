-- Edit mode's presentation: the opening sequence and emblem, Hover Top Bar, the Shift fade and the first-time tip.
-- Animations use animation groups; OnUpdate runs only for the toolbar's slide and while Hover Top Bar is on.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

local EMBLEM_SIZE = 112
local EMBLEM_OFFSET_Y = 60
local CORNER_SPREAD = 11
local HOVER_BAR_ZONE = 60    -- UI units around the toolbar within which Hover Top Bar shows it
local HOVER_BAR_SPEED = 4    -- alpha per second
local SHIFT_FADE = 0.15
local TIP_GAP, TIP_DROP = 16, 12  -- the tip's distance below the toolbar, and how far above that it starts
local TIP_FADE_IN, TIP_FADE_OUT = 0.45, 0.2
local TIP_DELAY = 0.7            -- seconds into the opening sequence, as the toolbar settles

local Handlers = {}
lib.EffectHandlers = Handlers

local function Texture(name)
	return lib.mediaPath .. "Textures\\" .. name
end

local function Alpha(group, from, to, duration, delay, order)
	local animation = group:CreateAnimation("Alpha")
	animation:SetFromAlpha(from)
	animation:SetToAlpha(to)
	animation:SetDuration(duration)
	animation:SetStartDelay(delay or 0)
	animation:SetOrder(order or 1)

	return animation
end

local function Translation(group, x, y, duration, delay, order, smoothing)
	local animation = group:CreateAnimation("Translation")
	animation:SetOffset(x, y)
	animation:SetDuration(duration)
	animation:SetStartDelay(delay or 0)
	animation:SetOrder(order or 1)
	if smoothing then
		animation:SetSmoothing(smoothing)
	end

	return animation
end

-- Emblem -------------------------------------------------------------------------------------------------------

-- Four bronze corners open around three layout tiles while a shine crosses them, then the emblem fades.
local CORNERS = {
	{ "TOPLEFT", -1, 1, 0, 1, 0, 1 },
	{ "TOPRIGHT", 1, 1, 1, 0, 0, 1 },
	{ "BOTTOMLEFT", -1, -1, 0, 1, 1, 0 },
	{ "BOTTOMRIGHT", 1, -1, 1, 0, 1, 0 },
}

local function BuildEmblem()
	local emblem = CreateFrame("Frame", nil, UIParent)
	emblem:SetFrameStrata("FULLSCREEN_DIALOG")
	emblem:SetSize(EMBLEM_SIZE, EMBLEM_SIZE)
	emblem:SetPoint("CENTER", UIParent, "CENTER", 0, EMBLEM_OFFSET_Y)
	emblem:Hide()
	local unit = EMBLEM_SIZE / 128

	emblem.corners = {}
	for _, corner in ipairs(CORNERS) do
		local point, dx, dy, left, right, top, bottom = unpack(corner)
		local texture = emblem:CreateTexture(nil, "ARTWORK")
		texture:SetTexture(Texture("emblem-corner"))
		texture:SetTexCoord(left, right, top, bottom)
		texture:SetSize(64 * unit, 64 * unit)
		texture:SetPoint(point)
		local group = texture:CreateAnimationGroup()
		Translation(group, dx * CORNER_SPREAD, dy * CORNER_SPREAD, 0.9, 0.2, 1, "OUT")
		Translation(group, 0, 0, 2.2, 0, 2) -- holds the corners open until the emblem has faded
		texture.open = group
		table.insert(emblem.corners, texture)
	end
	local function Tile(name, x, y, width, height)
		local texture = emblem:CreateTexture(nil, "ARTWORK", nil, 1)
		texture:SetTexture(Texture(name))
		texture:SetSize(width * unit, height * unit)
		texture:SetPoint("TOPLEFT", x * unit, -y * unit)
	end
	Tile("emblem-tile-h", 22, 24, 50, 25)
	Tile("emblem-tile-h", 22, 54, 50, 25)
	Tile("emblem-tile-v", 76, 24, 27, 55)

	local shine = emblem:CreateTexture(nil, "OVERLAY")
	shine:SetTexture(Texture("emblem-shine"))
	shine:SetBlendMode("ADD")
	shine:SetSize(128 * unit, 16 * unit)
	shine:SetPoint("CENTER", -60 * unit, 0)
	shine:SetRotation(math.rad(-30))
	shine:SetAlpha(0)
	local shineGroup = shine:CreateAnimationGroup()
	Alpha(shineGroup, 0, 1, 0.28, 0.4, 1)
	Translation(shineGroup, 120 * unit, 0, 0.7, 0.4, 1)
	Alpha(shineGroup, 1, 0, 0.42, 0, 2)
	emblem.shine = shineGroup

	local fade = emblem:CreateAnimationGroup()
	Alpha(fade, 1, 1, 1.2, 0, 1)
	Alpha(fade, 1, 0, 2, 0, 2)
	fade:SetScript("OnFinished", function() emblem:Hide() end)
	emblem.fade = fade

	return emblem
end

-- Opening ------------------------------------------------------------------------------------------------------

-- The opening timeline, in seconds. One driver sets every alpha and the toolbar's place each frame, so the
-- first frame is exactly what PrepareOpening set and nothing is shown before its time.
local TINT_DURATION = 0.75
local MOVERS_DELAY, MOVERS_DURATION = 0.5, 0.75
local TOOLBAR_SLIDE_DELAY, TOOLBAR_SLIDE_DURATION = 0.25, 0.6
local OPENING_LENGTH = math.max(MOVERS_DELAY + MOVERS_DURATION, TOOLBAR_SLIDE_DELAY + TOOLBAR_SLIDE_DURATION)

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

---Plays the opening sequence: the tint and grid fade in, the toolbar slides down as it fades in,
---the emblem opens and the movers fade in.
function lib:PlayOpening()
	local ui = self.ui
	C_Timer.After(TIP_DELAY, function()
		if lib.session.open and not lib.session.paused then
			lib:ShowFirstTip()
		end
	end)
	self:PrepareOpening()
	if not ui.openingDriver then
		ui.openingDriver = CreateFrame("Frame", nil, ui.screen)
		ui.openingDriver:SetScript("OnUpdate", function(self, elapsed) Handlers.Opening(self, elapsed) end)
	end
	ui.openingDriver.elapsed = 0
	ui.openingDriver:Show()

	ui.emblem = ui.emblem or BuildEmblem()
	local emblem = ui.emblem
	emblem:SetAlpha(1)
	emblem:Show()
	for _, corner in ipairs(emblem.corners) do
		corner.open:Stop()
		corner.open:Play()
	end
	emblem.shine:Stop()
	emblem.shine:Play()
	emblem.fade:Stop()
	emblem.fade:Play()
end

function lib:HideEmblem()
	local emblem = self.ui and self.ui.emblem
	if emblem then
		emblem.fade:Stop()
		emblem:Hide()
	end
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
	tip.title = tip:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	tip.title:SetPoint("TOPLEFT", 14, -12)
	tip.title:SetText(L.EDIT_MODE)
	tip.text = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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
