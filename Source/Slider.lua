-- C-10, the slider: Blizzard's MinimalSliderWithSteppersTemplate (168 with its step arrows) and a 44-wide number
-- box beside it, 220 in all. A drag saves at every step it passes; the step arrows and Enter in the box save at once.
-- `min`, `max` and `step` may be functions of the setting, worked out whenever the slider draws (a screen-wide range).

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local SLIDER_WIDTH, SLIDER_HEIGHT = 168, 40
local BOX_WIDTH, BOX_HEIGHT, BOX_RIGHT = 44, 22, 2
local TEXT_SIZE = 14
local FORMATS = {
	integer = function(value) return ("%d"):format(value) end,
	decimal = function(value) return ("%.1f"):format(value) end,
	percent = function(value) return ("%d%%"):format(value) end,
}

lib.Slider = {}
local sliderMeta = { __index = function(_, name) return lib.Slider[name] end }
lib.SliderHandlers = lib.SliderHandlers or {}
local Handlers = lib.SliderHandlers

function lib:CreateSlider(parent)
	local view = setmetatable({}, sliderMeta)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(lib.VALUE_WIDTH, lib.CONTROL_HEIGHT)

	local slider = CreateFrame("Frame", nil, frame, "MinimalSliderWithSteppersTemplate")
	slider:SetSize(SLIDER_WIDTH, SLIDER_HEIGHT)
	slider:SetPoint("LEFT")
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		Handlers.Moved(view, value)
	end, view)
	slider.Slider:HookScript("OnMouseDown", function() view.dragging = true end)
	slider.Slider:HookScript("OnMouseUp", function() Handlers.Released(view) end)

	local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	box:SetSize(BOX_WIDTH, BOX_HEIGHT)
	box:SetPoint("RIGHT", -BOX_RIGHT, 0)
	box:SetAutoFocus(false)
	box:SetJustifyH("CENTER")
	lib:SetFont(box, "body", TEXT_SIZE)
	box:SetScript("OnEnterPressed", function() Handlers.Typed(view) end)
	box:SetScript("OnEscapePressed", function() box:ClearFocus() end)
	box:HookScript("OnEditFocusLost", function() view:ShowValue() end)

	view.frame, view.slider, view.box = frame, slider, box

	return view
end

-- A range field: a number, or a function of the setting worked out now; `fallback` when it gives no number.
local function Field(setting, name, fallback)
	local value = setting[name]
	if type(value) == "function" then
		value = lib.CallAdopter(value, setting)
	end

	return tonumber(value) or fallback
end

---@return number minimum
---@return number maximum
---@return number step
local function Range(setting)
	local minimum = Field(setting, "min", 0)
	local maximum = math.max(minimum, Field(setting, "max", 100))
	local step = Field(setting, "step", 1)

	return minimum, maximum, step > 0 and step or 1
end

local function Format(setting, value)
	local format = setting.format
	value = tonumber(value) or (Range(setting))

	return type(format) == "function" and format(value) or (FORMATS[format] or FORMATS.integer)(value)
end

local function Round(setting, value)
	local minimum, _, step = Range(setting)
	value = minimum + math.floor((value - minimum) / step + 0.5) * step

	return tonumber(("%.4f"):format(value))
end

-- Draws the saved value on the bar (unless it is being dragged) and in the box (unless it is being typed in).
function lib.Slider:ShowValue()
	local setting = self.setting
	if not setting then
		return
	end
	local value = tonumber(setting:GetValue()) or (Range(setting))
	self.saved = value
	if not self.dragging then
		self.updating = true
		self.slider:SetValue(value)
		self.updating = nil
	end
	if not self.box:HasFocus() then
		self.box:SetText(Format(setting, value))
		self.box:SetCursorPosition(0)
	end
end

-- Sets the bar's range when it differs from the one it has.
local function ApplyRange(view)
	local setting = view.setting
	local minimum, maximum, step = Range(setting)
	if view.range and view.range[1] == minimum and view.range[2] == maximum and view.range[3] == step then
		return
	end
	view.range = { minimum, maximum, step }
	local value = tonumber(setting:GetValue()) or minimum
	view.updating = true
	view.slider:Init(value, minimum, maximum, math.max(1, math.floor((maximum - minimum) / step + 0.5)))
	view.updating = nil
end

function lib.Slider:Bind(setting)
	self.setting = setting
	self.dragging, self.dragRefused, self.range = nil, nil, nil
	ApplyRange(self)
	self:ShowValue()
end

-- A range worked out by functions is checked again on each redraw, except mid-drag.
function lib.Slider:Update(_, refused)
	if not self.dragging then
		ApplyRange(self)
	end
	self:ShowValue()
	if refused then
		lib:Shake(self.frame)
	end
end

function lib.Slider:Release()
	self.box:ClearFocus()
	self.setting, self.dragging, self.dragRefused = nil, nil, nil
end

function lib.Slider:SetActive(active)
	self.slider:SetEnabled(active)
	self.box:SetEnabled(active)
	if not active then
		self.box:ClearFocus()
	end
end

function lib.Slider:GetWidth()
	return lib.VALUE_WIDTH
end

-- A drag or a step arrow: saves each new step; after a refusal the rest of the drag asks nothing.
function Handlers.Moved(view, value)
	local setting = view.setting
	if view.updating or not setting or view.dragRefused then
		return
	end
	value = Round(setting, value)
	if value == view.saved then
		return
	end
	if not setting:Request(value) and view.dragging then
		view.dragRefused = true
	end
end

-- The release puts the thumb back on the saved value.
function Handlers.Released(view)
	view.dragging, view.dragRefused = nil, nil
	view:ShowValue()
end

-- Enter: a number within the range ("%" allowed) is rounded to the step and saved; anything else puts the saved
-- value back, silently.
function Handlers.Typed(view)
	local setting = view.setting
	local text = view.box:GetText():gsub("%%", ""):gsub("^%s+", ""):gsub("%s+$", "")
	local value = tonumber(text)
	view.box:ClearFocus()
	local minimum, maximum = 0, 100
	if setting then
		minimum, maximum = Range(setting)
	end
	if not setting or not value or value < minimum or value > maximum then
		view:ShowValue()
		return
	end
	value = Round(setting, value)
	if value ~= view.saved then
		setting:Request(value)
	else
		view:ShowValue()
	end
end

lib:RegisterControl("Slider", {
	fields = { min = true, max = true, step = true, format = true },
	Format = Format,
	Create = function(half) return lib:CreateSlider(half) end,
})
