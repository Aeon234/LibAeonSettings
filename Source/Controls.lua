-- What the controls share: their sizes, the refused-save shake, and the one confirmation popup.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

-- Kit values: every value control is 220 in all (slider 168 + gap + number box 44), 64 from the half's right edge.
lib.VALUE_WIDTH = 220
lib.CONTROL_HEIGHT = 29
-- A row's geometry: its label starts ROW_INSET in; its control ends CONTROL_RIGHT from the right, past the ◆/↺ gutter.
lib.ROW_INSET, lib.CONTROL_RIGHT = 16, 64

local SHAKE_SECONDS, SHAKE_PIXELS, SHAKE_CYCLES = 0.25, 3, 3 -- motion.reject

lib.ControlHandlers = lib.ControlHandlers or {}
local Handlers = lib.ControlHandlers

---Shakes a control sideways around its first anchor (`motion.reject`), the label staying still. Skipped while
---hidden, and with Reduce Motion.
function lib:Shake(frame)
	if not frame:IsVisible() or frame:GetNumPoints() ~= 1 or self:ReduceMotion() then
		return
	end
	local shaker = frame.libShaker
	if not shaker then
		shaker = CreateFrame("Frame", nil, frame)
		shaker:SetScript("OnUpdate", Handlers.Shake)
		shaker:SetScript("OnHide", function(self) Handlers.StopShake(self) end)
		shaker.target = frame
		frame.libShaker = shaker
	end
	if not shaker.point then
		shaker.point = { frame:GetPoint(1) }
	end
	shaker.elapsed = 0
	shaker:Show()
end

function Handlers.Shake(shaker, elapsed)
	shaker.elapsed = shaker.elapsed + elapsed
	local t = math.min(1, shaker.elapsed / SHAKE_SECONDS)
	local point = shaker.point
	local offset = SHAKE_PIXELS * math.sin(t * SHAKE_CYCLES * 2 * math.pi) * (1 - t)
	shaker.target:SetPoint(point[1], point[2], point[3], point[4] + offset, point[5])
	if t >= 1 then
		Handlers.StopShake(shaker)
	end
end

function Handlers.StopShake(shaker)
	local point = shaker.point
	if point then
		shaker.point = nil
		shaker.target:ClearAllPoints()
		shaker.target:SetPoint(point[1], point[2], point[3], point[4], point[5])
	end
	shaker:Hide()
end

-- Confirmation (C-14): Blizzard's static popup with the alert icon, the action's own verb on the accept button.
StaticPopupDialogs.LIBAEONSETTINGS_CONFIRM = StaticPopupDialogs.LIBAEONSETTINGS_CONFIRM or {}
local confirm = StaticPopupDialogs.LIBAEONSETTINGS_CONFIRM
confirm.text = "%s"
confirm.button1 = ACCEPT
confirm.button2 = CANCEL
confirm.showAlert = 1
confirm.hideOnEscape = 1
confirm.timeout = 0
confirm.whileDead = 1
confirm.OnShow = function(dialog, data)
	local accept = dialog.GetButton1 and dialog:GetButton1() or dialog.button1
	if accept and data then
		accept:SetText(data.verb)
	end
end
confirm.OnAccept = function(_, data)
	if data and data.accept then
		data.accept()
	end
end

---Asks `question` before running `accept`, with `verb` on the accept button. Returns the popup's data, so the
---caller can close it if the action goes inactive meanwhile.
function lib:Confirm(question, verb, accept)
	local data = { verb = verb or L.ACCEPT, accept = accept }
	self.confirming = data
	StaticPopup_Show("LIBAEONSETTINGS_CONFIRM", question, nil, data)

	return data
end

---Closes the confirmation if it is still the one `data` opened.
function lib:CloseConfirm(data)
	if data and self.confirming == data then
		self.confirming = nil
		StaticPopup_Hide("LIBAEONSETTINGS_CONFIRM", data)
	end
end
