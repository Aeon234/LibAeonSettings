-- Details: a row that heads optional settings, set apart by a faint band, a heading label and a leading chevron.
-- Closed, it shows a summary of what it holds; clicked, the summary goes and its settings grow in under it, indented,
-- inside the same card, and clicked again they leave. Its settings name it with `details = "<id>"`. Open or closed
-- lasts for the session and is not saved or undone.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local SUMMARY_WIDTH = 160 -- room kept beside the label for the summary
local CHEVRON_SIZE, CHEVRON_GAP = 12, 8
local REST_ALPHA, HOVER_ALPHA, PRESSED_ALPHA = 0.03, 0.05, 0.08
local MAX_CHAIN = lib.MAX_CHAIN
local OPEN_SOUND = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
local CLOSE_SOUND = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF

lib.Details = {}
local detailsMeta = { __index = function(_, name) return lib.Details[name] end }
lib.DetailsHandlers = lib.DetailsHandlers or {}
local Handlers = lib.DetailsHandlers

-- A row's label starts one step further in than its chevron, so the rows inside line up under that label.
lib.DETAILS_STEP = CHEVRON_SIZE + CHEVRON_GAP

---@param setting table
---@return number indent how far a row sits in, one step for each details row it is inside
function lib.DetailsIndent(setting)
	local indent, depth = 0, 0
	local inside = setting.details and setting.page.settings[setting.details]
	while inside and depth < MAX_CHAIN do
		indent, depth = indent + lib.DETAILS_STEP, depth + 1
		inside = inside.details and inside.page.settings[inside.details]
	end

	return indent
end

-- The whole row is the button: a faint band at rest, a little more on hover and while pressed.
function lib:CreateDetails(parent)
	local view = setmetatable({}, detailsMeta)
	local button = CreateFrame("Button", nil, parent)
	button:RegisterForClicks("LeftButtonUp")
	view.fill = button:CreateTexture(nil, "BACKGROUND")
	view.fill:SetAllPoints()
	view.fill:SetColorTexture(1, 1, 1, 1)
	view.fill:SetAlpha(REST_ALPHA)
	view.chevron = button:CreateTexture(nil, "ARTWORK")
	view.chevron:SetTexture(lib.mediaPath .. "Textures\\chevron")
	view.chevron:SetSize(CHEVRON_SIZE, CHEVRON_SIZE)
	view.chevron:SetVertexColor(lib:GetColor("tertiary"))
	view.summary = button:CreateFontString(nil, "OVERLAY")
	lib:SetType(view.summary, "body", "secondary")
	view.summary:SetJustifyH("RIGHT")
	view.summary:SetWordWrap(false)
	view.summary:SetWidth(SUMMARY_WIDTH)
	view.summary:SetPoint("RIGHT", button, "RIGHT", -lib.ROW_INSET, 0)
	button:SetScript("OnClick", function() Handlers.Click(view) end)
	button:SetScript("OnEnter", function() Handlers.Paint(view, true, false) end)
	button:SetScript("OnLeave", function() Handlers.Paint(view, false, false) end)
	button:SetScript("OnMouseDown", function() Handlers.Paint(view, true, true) end)
	button:SetScript("OnMouseUp", function() Handlers.Paint(view, button:IsMouseOver(), false) end)
	view.frame = button

	return view
end

-- Covers the whole row, above the label's tooltip area.
function lib.Details:Place(half)
	self.frame:SetAllPoints(half)
	self.frame:SetFrameLevel(half:GetFrameLevel() + 5)
end

-- The chevron starts where the row's own inset does, before its label.
function lib.Details:Bind(setting)
	self.setting = setting
	self.chevron:ClearAllPoints()
	self.chevron:SetPoint("LEFT", self.frame, "LEFT", lib.ROW_INSET + lib.DetailsIndent(setting), 0)
	self:Update()
end

-- Open points the chevron down and hides the summary; closed, to the right. The summary is the adopter's, read on
-- every redraw.
function lib.Details:Update()
	local setting = self.setting
	if not setting then
		return
	end
	local open = setting:GetValue()
	self.chevron:SetRotation(open and 0 or math.pi / 2)
	self.summary:SetShown(not open)
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
	return SUMMARY_WIDTH + lib.ROW_INSET - lib.CONTROL_RIGHT
end

function Handlers.Paint(view, hovered, pressed)
	view.fill:SetAlpha(pressed and PRESSED_ALPHA or hovered and HOVER_ALPHA or REST_ALPHA)
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
	heads = true,
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
