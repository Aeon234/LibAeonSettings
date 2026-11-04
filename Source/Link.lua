-- The edit mode link, both ways. A target's `settings = { page, section?, setting?, select? }` lets the cog
-- menu's Element Options save, leave edit mode and open the window on that section (or row), pulsing gold. A section
-- that a target names shows Edit Position on its title line, which opens edit mode with that mover selected; edit
-- mode then returns to the window when it closes.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

local LINK_HEIGHT, LINK_PADDING, LINK_MIN = 26, 40, 120 -- the action button's size, fitted to its text
local LINK_TEXT_SIZE = 14
local TITLE_CENTER = 15 -- the section title's center line, from the header's top
local LINK_GAP = 8
local CLICK_SOUND = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON

lib.LinkHandlers = lib.LinkHandlers or {}
local Handlers = lib.LinkHandlers

local function FindSection(page, id)
	for _, section in ipairs(page.sections or {}) do
		if section.id == id then
			return section
		end
	end
end

local function SettingSection(page, settingId)
	local setting = page.settings and page.settings[settingId]

	return setting and setting.section
end

-- The first target of this window's addon whose settings name this section: by its id, by a setting in it, or,
-- naming only the page, the page's first section.
function lib.Window:SectionTarget(section)
	local registration = lib.registrations and lib.registrations[self.addonName]
	if not registration then
		return nil
	end
	local page = section.page
	for _, target in ipairs(registration:Targets()) do
		local link = target.settings
		if type(link) == "table" and link.page == page.id then
			local named = link.section and FindSection(page, link.section)
				or link.setting and SettingSection(page, link.setting)
				or (not link.section and not link.setting and page.sections[1])
			if named == section then
				return target
			end
		end
	end
end

-- Edit Position --------------------------------------------------------------------------------------------------

local function CreateLink(window, header)
	local button = CreateFrame("Button", nil, header, "SharedButtonTemplate")
	button:SetHeight(LINK_HEIGHT)
	button:SetText(" ")
	lib:SetFont(button:GetFontString(), "body", LINK_TEXT_SIZE)
	button:SetText(L.EDIT_POSITION)
	button:SetWidth(math.max(LINK_MIN, math.ceil(button:GetFontString():GetUnboundedStringWidth()) + LINK_PADDING))
	button:SetScript("OnClick", function() Handlers.EditPosition(window, header.linkTarget) end)
	button:SetScript("OnEnter", function() Handlers.LinkEnter(button, header.linkTarget) end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	header.link = button

	return button
end

---Shows Edit Position on a section's title line when a target's settings name the section (Page.lua calls it).
function lib.Window:RefreshSectionLink(header, section)
	local target = self:SectionTarget(section)
	header.linkTarget = target
	if target then
		local link = header.link or CreateLink(self, header)
		-- Left of the section's menu when it has one.
		link:ClearAllPoints()
		if header.menuSetting then
			link:SetPoint("RIGHT", header.menu.frame, "LEFT", -LINK_GAP, 0)
		else
			link:SetPoint("RIGHT", header, "TOPRIGHT", 0, -TITLE_CENTER)
		end
		link:Show()
	elseif header.link then
		header.link:Hide()
	end
	self:RefreshSectionLinkMenu(header, section)
end

-- Link menu ----------------------------------------------------------------------------------------------------

local function CreateLinkMenu(header)
	local button = CreateFrame("Button", nil, header)
	local text = button:CreateFontString(nil, "OVERLAY")

	button:SetHeight(LINK_HEIGHT)
	lib:SetFont(text, "body", LINK_TEXT_SIZE)
	text:SetPoint("RIGHT")
	text:SetTextColor(lib:GetColor("accent"))
	button.text = text
	button:SetScript("OnClick", function() Handlers.LinkMenuClick(header) end)
	button:SetScript("OnEnter", function() Handlers.LinkMenuEnter(header) end)
	button:SetScript("OnLeave", function() Handlers.LinkMenuLeave(header) end)
	header.linkMenu = button

	return button
end

---Shows a section's link menu on its title line, left of whatever else the line holds.
---@param header table
---@param section table
function lib.Window:RefreshSectionLinkMenu(header, section)
	local info = section.linkMenu
	local shown = info ~= nil

	if shown and info.show then
		shown = lib.CallAdopter(info.show) == true
	end

	if not shown then
		if header.linkMenu then
			header.linkMenu:Hide()
		end

		return
	end

	local button = header.linkMenu or CreateLinkMenu(header)
	local neighbor = header.linkTarget and header.link or (header.menuSetting and header.menu.frame)

	button.info = info
	button.text:SetText(info.text)
	button:SetWidth(math.ceil(button.text:GetUnboundedStringWidth()))
	button:ClearAllPoints()
	if neighbor then
		button:SetPoint("RIGHT", neighbor, "LEFT", -LINK_GAP, 0)
	else
		button:SetPoint("RIGHT", header, "TOPRIGHT", 0, -TITLE_CENTER)
	end
	button:Show()
end

function Handlers.LinkMenuClick(header)
	local button = header.linkMenu
	local info = button and button.info

	if not info then
		return
	end

	local owner = "linkMenu:" .. tostring(header.section and header.section.id)

	if lib:MenuOwner() == owner then
		lib:CloseMenus()

		return
	end

	PlaySound(CLICK_SOUND)
	lib:OpenMenu(owner, button, info.build)
end

function Handlers.LinkMenuEnter(header)
	header.linkMenu.text:SetTextColor(lib:GetColor("cream"))
end

function Handlers.LinkMenuLeave(header)
	header.linkMenu.text:SetTextColor(lib:GetColor("accent"))
end

function Handlers.LinkEnter(button, target)
	if not target then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	GameTooltip:SetText(L.EDIT_POSITION, 1, 1, 1)
	GameTooltip:AddLine(L.EDIT_POSITION_TIP:format(target.label or target.key), 1, 0.82, 0, true)
	GameTooltip:Show()
end

-- Opens edit mode with the target's mover selected; closing edit mode comes back to this window.
function Handlers.EditPosition(window, target)
	if not target then
		return
	end
	PlaySound(CLICK_SOUND)
	window:Close()
	lib:OpenEditMode(window.addonName)
	if lib:IsEditing() then
		lib.session.returnTo = window
		lib:SelectMover(lib:MoverId(window.addonName, target.key))
	end
end

-- Element Options ------------------------------------------------------------------------------------------------

---Opens the window where a target's settings are (`link` is the target's `settings` table): its `select(window,
---target)` runs first (to pick what a page shows, such as a part of a preview), then the window lands on the
---setting's row or the section, pulsing gold.
function lib.Window:OpenAt(link, target)
	local page = self.pages[link.page]
	if not page then
		lib:Report(self.addonName, ("settings for %s: no page %q"):format(tostring(target and target.key), tostring(link.page)))
		return
	end
	self:Open()
	if not self:IsShown() then
		return
	end
	if link.select then
		lib.CallAdopter(link.select, self, target)
	end
	if link.setting then
		local setting = page.settings[link.setting]
		if setting then
			self:LandOn(setting)
			return
		end
		lib:Report(self.addonName, ("settings for %s: no setting %q on %s"):format(tostring(target and target.key),
			tostring(link.setting), page.id))
	end
	local section = link.section and FindSection(page, link.section)
	if link.section and not section then
		lib:Report(self.addonName, ("settings for %s: no section %q on %s"):format(tostring(target and target.key),
			tostring(link.section), page.id))
	end
	if section then
		self:LandOnSection(section)
	else
		self:SelectPage(page.id)
	end
end
