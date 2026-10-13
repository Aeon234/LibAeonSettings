-- C-01, the toggle: a bronze track whose pin slides left (off) to right (on), for turning a module, feature or page
-- on and off. Controlled: a click slides the pin and asks the setting; the setting's answer is drawn back.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local WIDTH, HEIGHT = 56, 28
local CAP = HEIGHT / 2
local PIN_SIZE, PRESSED_SCALE = 23.2, 0.95
local SLIDE_SECONDS = 0.2 -- for the full distance, scaled by the distance left; out-cubic
local SHAKE_SECONDS, SHAKE_PIXELS, SHAKE_CYCLES = 0.25, 3, 3
local HOVER_ALPHA = 0.2
local OFF_DOT = { 0.6, 0.6, 0.6, 0.4 }
local ON_DOT = { 0.620, 0.459, 0.290, 1 } -- color.accent, the brightest bronze of the track's rim
local SOUND_ON = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
local SOUND_OFF = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF

lib.Toggle = {}
local toggleMeta = { __index = function(_, name) return lib.Toggle[name] end }
local Handlers = {}
lib.ToggleHandlers = Handlers

local function Track(button, left, right)
	local texture = button:CreateTexture(nil, "BACKGROUND")
	texture:SetTexture(lib.mediaPath .. "Textures\\toggle-track")
	texture:SetTexCoord(left, right, 0, 1)

	return texture
end

---Makes a toggle in `parent`.
function lib:CreateToggle(parent)
	local view = setmetatable({ position = 0, value = false }, toggleMeta)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(WIDTH, HEIGHT)
	button:RegisterForClicks("LeftButtonUp")

	view.left = Track(button, 0, 0.125)
	view.left:SetPoint("TOPLEFT")
	view.left:SetSize(CAP, HEIGHT)
	view.right = Track(button, 0.875, 1)
	view.right:SetPoint("TOPRIGHT")
	view.right:SetSize(CAP, HEIGHT)
	view.middle = Track(button, 0.125, 0.875)
	view.middle:SetPoint("TOPLEFT", view.left, "TOPRIGHT")
	view.middle:SetPoint("BOTTOMRIGHT", view.right, "BOTTOMLEFT")

	local pin = CreateFrame("Frame", nil, button)
	pin:SetSize(PIN_SIZE, PIN_SIZE)
	view.circle = pin:CreateTexture(nil, "ARTWORK")
	view.circle:SetAtlas("common-radiobutton-circle")
	view.circle:SetAllPoints()
	view.dot = pin:CreateTexture(nil, "OVERLAY")
	view.dot:SetAtlas("common-radiobutton-dot")
	view.dot:SetDesaturated(true)
	view.dot:SetAllPoints()
	view.hover = pin:CreateTexture(nil, "OVERLAY", nil, 1)
	view.hover:SetAtlas("common-radiobutton-circle")
	view.hover:SetBlendMode("ADD")
	view.hover:SetAlpha(HOVER_ALPHA)
	view.hover:SetAllPoints()
	view.hover:Hide()

	button:SetScript("OnClick", function() Handlers.Click(view) end)
	button:SetScript("OnEnter", function() view.hover:SetShown(button:IsEnabled()) end)
	button:SetScript("OnLeave", function() Handlers.Press(view, false); view.hover:Hide() end)
	button:SetScript("OnMouseDown", function(_, mouse) Handlers.Press(view, mouse == "LeftButton" and button:IsEnabled()) end)
	button:SetScript("OnMouseUp", function() Handlers.Press(view, false) end)
	button:SetScript("OnHide", function() view:Stop() end)

	view.frame, view.button, view.pin = button, button, pin
	view:Draw()

	return view
end

-- Draws the pin at its position (0 off, 1 on) plus any shake, and the dot's color between gray and bronze.
function lib.Toggle:Draw()
	local p = math.max(0, math.min(1, self.position))
	self.pin:ClearAllPoints()
	self.pin:SetPoint("CENTER", self.button, "LEFT", CAP + (WIDTH - HEIGHT) * p + (self.shakeOffset or 0), 0)
	self.dot:SetVertexColor(OFF_DOT[1] + (ON_DOT[1] - OFF_DOT[1]) * p, OFF_DOT[2] + (ON_DOT[2] - OFF_DOT[2]) * p,
		OFF_DOT[3] + (ON_DOT[3] - OFF_DOT[3]) * p)
	self.dot:SetAlpha(OFF_DOT[4] + (ON_DOT[4] - OFF_DOT[4]) * p)
end

---Draws a value: at once with `instant` (or when hidden), else sliding from where the pin is.
function lib.Toggle:SetChecked(value, instant)
	self.value = value and true or false
	local target = self.value and 1 or 0
	if instant or not self.button:IsVisible() then
		self:Stop()
		self.position = target
		self:Draw()
		return
	end
	if self.slide and self.slide.to == target then
		return
	end
	local distance = math.abs(target - self.position)
	if distance == 0 then
		return
	end
	self.slide = { from = self.position, to = target, elapsed = 0, duration = SLIDE_SECONDS * distance }
	self.button:SetScript("OnUpdate", Handlers.Update)
	self.button.view = self
end

---Shakes the pin sideways after a refused save.
function lib.Toggle:Reject()
	if not self.button:IsVisible() then
		return
	end
	self.shake = 0
	self.button:SetScript("OnUpdate", Handlers.Update)
	self.button.view = self
end

---Stops any slide or shake and draws the final state.
function lib.Toggle:Stop()
	self.slide, self.shake, self.shakeOffset = nil, nil, nil
	self.button:SetScript("OnUpdate", nil)
	self.position = self.value and 1 or 0
	self:Draw()
end

function lib.Toggle:SetActive(active)
	self.button:SetEnabled(active)
	if not active then
		Handlers.Press(self, false)
		self.hover:Hide()
	end
end

-- Inactive: the track and circle lose their color; the dot keeps its color, only dimmed with the control.
function lib.Toggle:Desaturate(amount)
	self.left:SetDesaturation(amount)
	self.middle:SetDesaturation(amount)
	self.right:SetDesaturation(amount)
	self.circle:SetDesaturation(amount)
end

function lib.Toggle:GetWidth()
	return WIDTH
end

-- Row binding (the control contract in Page.lua) ----------------------------------------------------------

function lib.Toggle:Bind(setting)
	self.setting = setting
	self:SetChecked(setting:GetValue(), true)
end

function lib.Toggle:Update(instant, refused)
	self:SetChecked(self.setting:GetValue(), instant)
	if refused then
		self:Reject()
	end
end

function lib.Toggle:Release()
	self:Stop()
	self.setting = nil
end

-- Handlers ----------------------------------------------------------------------------------------------------

function Handlers.Click(view)
	local value = not view.value
	PlaySound(value and SOUND_ON or SOUND_OFF)
	view:SetChecked(value)
	if view.setting then
		view.setting:Request(value)
	end
end

function Handlers.Press(view, pressed)
	local size = pressed and PIN_SIZE * PRESSED_SCALE or PIN_SIZE
	view.pin:SetSize(size, size)
end

function Handlers.Update(button, elapsed)
	local view = button.view
	local slide = view.slide
	if slide then
		slide.elapsed = slide.elapsed + elapsed
		local t = math.min(1, slide.elapsed / slide.duration)
		view.position = slide.from + (slide.to - slide.from) * (1 - (1 - t) ^ 3)
		if t >= 1 then
			view.slide = nil
		end
	end
	if view.shake then
		view.shake = view.shake + elapsed
		local t = math.min(1, view.shake / SHAKE_SECONDS)
		view.shakeOffset = SHAKE_PIXELS * math.sin(t * SHAKE_CYCLES * 2 * math.pi) * (1 - t)
		if t >= 1 then
			view.shake, view.shakeOffset = nil, nil
		end
	end
	view:Draw()
	if not view.slide and not view.shake then
		button:SetScript("OnUpdate", nil)
	end
end

lib:RegisterControl("Toggle", { Format = function(_, value) return value and lib.L.ON or lib.L.OFF end, Create = function(half) return lib:CreateToggle(half) end })
