-- Details: a row that holds optional settings. Closed, it shows its label, a summary of what it holds and a chevron;
-- clicked, its settings grow in under it inside the same card, and clicked again they leave. Its settings name it
-- with `details = "<id>"`. Open or closed lasts for the session and is not saved or undone.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local SUMMARY_WIDTH = 160 -- room kept beside the label for the summary
local CHEVRON_SIZE, CHEVRON_GAP = 12, 8
local HOVER_ALPHA, PRESSED_ALPHA = 0.025, 0.06
local OPEN_SOUND = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
local CLOSE_SOUND = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF

lib.Details = {}
local detailsMeta = { __index = function(_, name) return lib.Details[name] end }
lib.DetailsHandlers = lib.DetailsHandlers or {}
local Handlers = lib.DetailsHandlers

-- The whole row is the button: a faint fill on hover, a little more while pressed.
function lib:CreateDetails(parent)
	local view = setmetatable({}, detailsMeta)
	local button = CreateFrame("Button", nil, parent)
	button:RegisterForClicks("LeftButtonUp")
	view.fill = button:CreateTexture(nil, "BACKGROUND")
	view.fill:SetAllPoints()
	view.fill:SetColorTexture(1, 1, 1, 1)
	view.fill:SetAlpha(0)
	view.chevron = button:CreateTexture(nil, "ARTWORK")
	view.chevron:SetTexture(lib.mediaPath .. "Textures\\chevron")
	view.chevron:SetSize(CHEVRON_SIZE, CHEVRON_SIZE)
	view.chevron:SetVertexColor(lib:GetColor("tertiary"))
	view.summary = button:CreateFontString(nil, "OVERLAY")
	lib:SetType(view.summary, "body", "secondary")
	view.summary:SetJustifyH("RIGHT")
	view.summary:SetWordWrap(false)
	view.summary:SetWidth(SUMMARY_WIDTH)
	view.summary:SetPoint("RIGHT", view.chevron, "LEFT", -CHEVRON_GAP, 0)
	button:SetScript("OnClick", function() Handlers.Click(view) end)
	button:SetScript("OnEnter", function() Handlers.Paint(view, true, false) end)
	button:SetScript("OnLeave", function() Handlers.Paint(view, false, false) end)
	button:SetScript("OnMouseDown", function() Handlers.Paint(view, true, true) end)
	button:SetScript("OnMouseUp", function() Handlers.Paint(view, button:IsMouseOver(), false) end)
	view.frame = button

	return view
end

-- Covers the whole row, above the label's tooltip area; the chevron sits at the row's right inset.
function lib.Details:Place(half)
	self.frame:SetAllPoints(half)
	self.frame:SetFrameLevel(half:GetFrameLevel() + 5)
	self.chevron:ClearAllPoints()
	self.chevron:SetPoint("RIGHT", half, "RIGHT", -lib.ROW_INSET, 0)
end

function lib.Details:Bind(setting)
	self.setting = setting
	self:Update()
end

-- Open points the chevron down; closed, to the right. The summary is the adopter's, read on every redraw.
function lib.Details:Update()
	local setting = self.setting
	if not setting then
		return
	end
	self.chevron:SetRotation(setting:GetValue() and 0 or math.pi / 2)
	local summary = setting.summary and lib.CallAdopter(setting.summary, setting)
	self.summary:SetText(type(summary) == "string" and summary or "")
end

function lib.Details:Release()
	self.setting = nil
	Handlers.Paint(self, false, false)
end

-- The page redraws states after every change, which may change what the summary says.
function lib.Details:SetActive(active)
	self.frame:SetEnabled(active)
	self:Update()
end

-- What the row keeps clear of its label, counted from where other controls end.
function lib.Details:GetWidth()
	return SUMMARY_WIDTH + CHEVRON_GAP + CHEVRON_SIZE + lib.ROW_INSET - lib.CONTROL_RIGHT
end

function Handlers.Paint(view, hovered, pressed)
	view.fill:SetAlpha(pressed and PRESSED_ALPHA or hovered and HOVER_ALPHA or 0)
end

function Handlers.Click(view)
	local setting = view.setting
	if not setting then
		return
	end
	local open = not setting:GetValue()
	PlaySound(open and OPEN_SOUND or CLOSE_SOUND)
	setting:SetValue(open)
end

lib:RegisterControl("Details", {
	fields = { summary = true },
	-- Open or closed is the window's for the session, by page and id.
	Init = function(setting)
		local key = setting.page.id .. "/" .. tostring(setting.id)
		setting.default = false
		setting.get = function(self)
			local open = self.window.openDetails

			return open ~= nil and open[key] == true
		end
		setting.set = function(value, self)
			self.window.openDetails = self.window.openDetails or {}
			self.window.openDetails[key] = value and true or nil
		end
	end,
	Create = function(half) return lib:CreateDetails(half) end,
})
