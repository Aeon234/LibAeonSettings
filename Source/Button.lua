-- C-14, the action button: Blizzard's SharedButtonTemplate in a row, 26 tall, fitted to its text. It runs an action
-- instead of holding a value; destructive actions ask first. `run(setting)` returns false and a reason to fail;
-- success is the adopter's to report, usually with `window:ShowStatus`.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

local HEIGHT, PADDING, MIN_WIDTH = 26, 40, 120
local TEXT_SIZE = 14
local CLICK_SOUND = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON

lib.ActionButton = {}
local buttonMeta = { __index = function(_, name) return lib.ActionButton[name] end }
local Handlers = {}
lib.ActionButtonHandlers = Handlers

function lib:CreateActionButton(parent)
	local view = setmetatable({ width = MIN_WIDTH }, buttonMeta)
	local button = CreateFrame("Button", nil, parent, "SharedButtonTemplate")
	button:SetHeight(HEIGHT)
	-- The button has no font string until it is given text.
	button:SetText(" ")
	lib:SetFont(button:GetFontString(), "body", TEXT_SIZE)
	button:SetScript("OnClick", function() Handlers.Click(view) end)
	view.frame, view.button = button, button

	return view
end

function lib.ActionButton:Bind(setting)
	self.setting = setting
	local verb = setting.verb or setting.label or tostring(setting.id)
	self.button:SetText(verb)
	self.width = math.max(MIN_WIDTH, math.min(lib.VALUE_WIDTH, math.ceil(self.button:GetFontString():GetUnboundedStringWidth()) + PADDING))
	self.button:SetWidth(self.width)
end

function lib.ActionButton:Update(_, refused)
	if refused then
		lib:Shake(self.frame)
	end
end

-- Releasing or going inactive closes a confirmation still open.
function lib.ActionButton:Release()
	lib:CloseConfirm(self.confirming)
	self.confirming, self.setting = nil, nil
end

function lib.ActionButton:SetActive(active)
	if not active then
		lib:CloseConfirm(self.confirming)
		self.confirming = nil
	end
	self.button:SetEnabled(active)
end

function lib.ActionButton:GetWidth()
	return self.width
end

local function Run(view, setting)
	view.confirming = nil
	if view.setting ~= setting then
		return
	end
	local ok, reason = lib.CallAdopter(setting.run, setting)
	if ok == false then
		local verb = (setting.verb or setting.label or tostring(setting.id)):lower()
		local message = reason and L.COULDNT_VERB_REASON:format(verb, (reason:gsub("%.$", ""))) or L.COULDNT_VERB:format(verb)
		UIErrorsFrame:AddExternalErrorMessage(lib.TitleCase(message))
		view:Update(true, true)
		return
	end
	-- The action may have changed other settings.
	setting.window:Refresh()
end

function Handlers.Click(view)
	local setting = view.setting
	if not setting or not setting.run then
		return
	end
	PlaySound(CLICK_SOUND)
	if setting.confirm then
		local question = type(setting.confirm) == "function" and lib.CallAdopter(setting.confirm, setting) or setting.confirm
		view.confirming = lib:Confirm(question, setting.verb, function() Run(view, setting) end)
	else
		Run(view, setting)
	end
end

lib:RegisterControl("Button", {
	fields = { verb = true, confirm = true, run = true },
	noValue = true,
	Create = function(half) return lib:CreateActionButton(half) end,
})
