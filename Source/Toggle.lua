-- C-01, the toggle: a slim track whose diamond knob slides left (off) to right (on), for turning a module, feature or
-- page on and off. Controlled: a click slides the knob and asks the setting; the setting's answer is drawn back. A
-- settings row draws the slim size; a page's switch draws the large one. Retail draws Plumber's steel art, Forever
-- the same art in the bronze of its settings controls.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local SLIDE_SECONDS = 0.2 -- for the full distance, scaled by the distance left; out-cubic
local SHAKE_SECONDS, SHAKE_PIXELS, SHAKE_CYCLES = 0.25, 3, 3
local PRESSED_SCALE = 0.95
local SOUND_ON = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
local SOUND_OFF = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF

-- Sizes in units; the art is 2 texels per unit. `off` and `on` are the knob's center at each stop, from the frame's
-- left edge. `body`: the track's size when it is narrower than the frame (centered in it), so the knob's tips, which
-- overhang the track's ends, stay inside the frame. The large size's stops, 9 units in from the track's ends, line the
-- diamond's flanks up with the track's chamfered corners.
local SIZES = {
	slim = { art = "", width = 40, height = 20, knob = 38, off = 9.5, on = 30.5 },
	large = { art = "-large", width = 65, height = 30, body = { 56, 30 }, knob = 57, off = 13.5, on = 51.5 },
}

lib.Toggle = {}
local toggleMeta = { __index = function(_, name) return lib.Toggle[name] end }
lib.ToggleHandlers = lib.ToggleHandlers or {}
local Handlers = lib.ToggleHandlers

local function Art(size, piece)
	local client = WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT and "forever" or "retail"

	return ("%sTextures\\toggle-%s%s-%s"):format(lib.mediaPath, client, size.art, piece)
end

---Makes a toggle in `parent`: the slim size for a settings row, or the large size for a page's switch with `large`.
---@param parent Frame
---@param large boolean?
function lib:CreateToggle(parent, large)
	local size = large and SIZES.large or SIZES.slim
	local view = setmetatable({ size = size, position = 0, value = false }, toggleMeta)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size.width, size.height)
	button:RegisterForClicks("LeftButtonUp")

	view.bodyOff = button:CreateTexture(nil, "BACKGROUND", nil, 0)
	view.bodyOff:SetTexture(Art(size, "body-off"))
	view.bodyOn = button:CreateTexture(nil, "BACKGROUND", nil, 1)
	view.bodyOn:SetTexture(Art(size, "body-on"))
	for _, body in ipairs({ view.bodyOff, view.bodyOn }) do
		if size.body then
			body:SetSize(size.body[1], size.body[2])
			body:SetPoint("CENTER")
		else
			body:SetAllPoints()
		end
	end

	-- The knob is the parent's child, not the button's: the page dims an inactive control through its frame's alpha,
	-- which would let the track show through the knob. Window fades still reach it through the parent.
	local knob = CreateFrame("Frame", nil, parent)
	knob:SetFrameLevel(button:GetFrameLevel() + 1)
	knob:SetSize(size.knob, size.knob)
	view.knobOff = knob:CreateTexture(nil, "ARTWORK", nil, 0)
	view.knobOff:SetAllPoints()
	view.knobOn = knob:CreateTexture(nil, "ARTWORK", nil, 1)
	view.knobOn:SetAllPoints()

	button:SetScript("OnClick", function() Handlers.Click(view) end)
	button:SetScript("OnEnter", function() Handlers.Hover(view, true) end)
	button:SetScript("OnLeave", function() Handlers.Press(view, false); Handlers.Hover(view, false) end)
	button:SetScript("OnMouseDown", function(_, mouse) Handlers.Press(view, mouse == "LeftButton" and button:IsEnabled()) end)
	button:SetScript("OnMouseUp", function() Handlers.Press(view, false) end)
	button:SetScript("OnShow", function() Handlers.Show(view, true) end)
	button:SetScript("OnHide", function() Handlers.Show(view, false) end)

	view.frame, view.button, view.knob = button, button, knob
	view:Paint()
	view:Draw()

	return view
end

-- Draws the knob at its position (0 off, 1 on) plus any shake; the on track and knob fade in with the position.
function lib.Toggle:Draw()
	local size = self.size
	local p = math.max(0, math.min(1, self.position))
	self.knob:ClearAllPoints()
	self.knob:SetPoint("CENTER", self.button, "LEFT", size.off + (size.on - size.off) * p + (self.shakeOffset or 0), 0)
	self.bodyOn:SetAlpha(p)
	self.knobOn:SetAlpha(p)
	self.knobOff:SetAlpha(1 - p)
end

-- Picks the knob art for the hover and active state; an inactive toggle draws the dark knob at either stop.
function lib.Toggle:Paint()
	if not self.button:IsEnabled() then
		local art = Art(self.size, "knob-disabled")
		self.knobOff:SetTexture(art)
		self.knobOn:SetTexture(art)
		return
	end
	self.knobOff:SetTexture(Art(self.size, self.hovered and "knob-hover" or "knob"))
	self.knobOn:SetTexture(Art(self.size, self.hovered and "knob-on-hover" or "knob-on"))
end

---Draws a value: at once with `instant` (or when hidden), else sliding from where the knob is.
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
		-- A refusal answered before the first frame: the knob never left, so the slide just ends.
		self.slide = nil
		return
	end
	self.slide = { from = self.position, to = target, elapsed = 0, duration = SLIDE_SECONDS * distance }
	self.button:SetScript("OnUpdate", Handlers.Update)
	self.button.view = self
end

---Shakes the knob sideways after a refused save.
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
		self.hovered = false
	end
	self:Paint()
end

-- Inactive: every piece loses its color; the knob stays opaque (see CreateToggle).
function lib.Toggle:Desaturate(amount)
	self.bodyOff:SetDesaturation(amount)
	self.bodyOn:SetDesaturation(amount)
	self.knobOff:SetDesaturation(amount)
	self.knobOn:SetDesaturation(amount)
end

function lib.Toggle:GetWidth()
	return self.size.width
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

function Handlers.Hover(view, hovered)
	view.hovered = hovered and view.button:IsEnabled()
	view:Paint()
end

function Handlers.Press(view, pressed)
	local size = pressed and view.size.knob * PRESSED_SCALE or view.size.knob
	view.knob:SetSize(size, size)
end

-- The knob is not the button's child, so it follows the button's visibility here.
function Handlers.Show(view, shown)
	if shown then
		view.knob:SetFrameLevel(view.button:GetFrameLevel() + 1)
		view.knob:Show()
	else
		view.knob:Hide()
		view:Stop()
	end
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
