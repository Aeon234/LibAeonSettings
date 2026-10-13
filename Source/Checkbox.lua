-- C-09, the checkbox: Blizzard's minimal checkbox as it is, for every on/off option that is not a whole module or
-- page (those take the toggle). Controlled like the toggle; no animation but the refused-save shake.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local SOUND_ON = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
local SOUND_OFF = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF

lib.Checkbox = {}
local checkboxMeta = { __index = function(_, name) return lib.Checkbox[name] end }

function lib:CreateCheckbox(parent)
	local view = setmetatable({}, checkboxMeta)
	local button = CreateFrame("CheckButton", nil, parent, "MinimalCheckboxTemplate")
	button:SetSize(30, 29)
	button:SetScript("OnClick", function()
		local value = button:GetChecked()
		PlaySound(value and SOUND_ON or SOUND_OFF)
		if view.setting then
			view.setting:Request(value)
		end
	end)
	view.frame = button

	return view
end

function lib.Checkbox:Bind(setting)
	self.setting = setting
	self.frame:SetChecked(setting:GetValue() and true or false)
end

function lib.Checkbox:Update(_, refused)
	self.frame:SetChecked(self.setting:GetValue() and true or false)
	if refused then
		lib:Shake(self.frame)
	end
end

function lib.Checkbox:Release()
	self.setting = nil
end

function lib.Checkbox:SetActive(active)
	self.frame:SetEnabled(active)
end

function lib.Checkbox:GetWidth()
	return 30
end

lib:RegisterControl("Checkbox", { Create = function(half) return lib:CreateCheckbox(half) end })
