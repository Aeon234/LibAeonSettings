-- Settings windows: one per registered addon, built on first open. This file holds the registration and the
-- window shell (frame, title, close, footer, dragging, opening and closing, Escape, combat); the sidebar, pages and
-- controls are added by later files.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

local WINDOW_WIDTH, WINDOW_HEIGHT = 1000, 800 -- every window, every page
local OPEN_RESPONSE = 0.28 -- the opening spring; closing hides at once
local CLOSED_SCALE = 0.965 -- the scale the window grows from as it opens and shrinks to as it closes
local TITLE_SIZE = 14
local FOOTER_HEIGHT = 35
local FOOTER_BOTTOM = 11 -- centers the band between the inner frame's bottom (46) and the frame's inner edge (11)
local FOOTER_TEXT_SIZE = 14
local STATUS_SECONDS = 4
local TEXT_FADE_OUT, TEXT_FADE_IN = 0.15, 0.25 -- the footer text's crossfade when it changes
local TITLE_GOLD = { 1, 0.82, 0 } -- the title's color in Blizzard's own panels

-- Layout inside the window (from its top left): the inner frame, the sidebar column and the content fill.
local INNER_LEFT, INNER_TOP, INNER_RIGHT, INNER_BOTTOM = 10, 30, 10, 46
local SIDEBAR_WIDTH = 230
local SIDEBAR_LEFT, SIDEBAR_TOP, SIDEBAR_BOTTOM = 22, 92, 12 -- the list starts below the search box's place
local CONTENT_FILL = { 0, 0, 0, 0.45 }

-- Options_InnerFrame is drawn in pieces so its divider and corners keep their size: columns and rows as
-- { source start, source size, drawn size } in the art's 886 by 618 pixels; a drawn size of false stretches.
local INNER_ART_WIDTH, INNER_ART_HEIGHT = 886, 618
local INNER_COLUMNS = { { 0, 12, 12 }, { 12, 184, SIDEBAR_WIDTH }, { 196, 8, 8 }, { 204, 670, false }, { 874, 12, 12 } }
local INNER_ROWS = { { 0, 60, 60 }, { 60, 480, false }, { 540, 78, 78 } }

local DECLARATION_FIELDS = { title = true, version = true, store = true, write = true, account = true, width = true,
	height = true, footer = true, frameName = true, reloadNeeded = true }

lib.windows = lib.windows or {}

-- Adopters hear of their window through CallbackHandler, which every adopter ships:
-- `LibStub("LibAeonSettings-1.0").RegisterCallback(owner, event, method)`, events (each with the addon's name first)
-- "OnOpen" (addonName), "OnClose" (addonName, once the window has hidden) and "OnPageShown" (addonName, pageId,
-- tabId?), the last each time another page or tab shows, and again as the window opens.
local CallbackHandler = LibStub("CallbackHandler-1.0", true)
if CallbackHandler then
	lib.callbacks = lib.callbacks or CallbackHandler:New(lib)
end

---Fires an event to the adopters registered for it.
function lib:Fire(event, ...)
	if self.callbacks then
		self.callbacks:Fire(event, ...)
	end
end

-- Window methods are looked up on the library at call time, so windows made through an older copy use the newest
-- code after an upgrade.
lib.Window = {}
local windowMeta = { __index = function(_, name) return lib.Window[name] end }

lib.WindowHandlers = lib.WindowHandlers or {}
local Handlers = lib.WindowHandlers

---Registers an addon's settings window. Calling it again for the same addon returns the same window with the
---new declaration. Nothing is built until the window first opens. `store` (a table, or a function returning one)
---holds the values settings name by `path`; `write(path, value, setting)`, when given, makes every such write
---instead, so the addon writes its own store and hears of each change (the player's, Undo's, ↺, Clear Overrides);
---it may return false and a reason to refuse.
---@param addonName string the addon's folder name
---@param declaration table { title, version?, store?, write?, account?, width?, height?, footer?, frameName?,
---reloadNeeded? }; `reloadNeeded()` returns true while a change waits for a reload, which the footer then says
---@return table? window
function lib:Settings(addonName, declaration)
	if type(addonName) ~= "string" or type(declaration) ~= "table" then
		self:Report(addonName, "Settings(addonName, declaration) needs a name and a table")
		return
	end
	for field in pairs(declaration) do
		if not DECLARATION_FIELDS[field] then
			self:Report(addonName, ("unknown settings field %q"):format(tostring(field)))
		end
	end
	if type(declaration.title) ~= "string" then
		self:Report(addonName, "the settings declaration needs a title")
	end
	if declaration.width ~= nil or declaration.height ~= nil then
		self:Report(addonName, ("width and height are no longer used: every settings window is %d by %d")
			:format(WINDOW_WIDTH, WINDOW_HEIGHT))
	end
	if declaration.footer ~= nil then
		self:Report(addonName, "footer is no longer used: the footer shows messages only, for a few seconds")
	end

	local window = self.windows[addonName]
	if not window then
		window = setmetatable({ addonName = addonName, pages = {}, pageOrder = {}, nodes = {}, nav = {}, collapsed = {} },
			windowMeta)
		self.windows[addonName] = window
	end
	window.declaration = declaration

	return window
end

---@return table? window
function lib:GetSettings(addonName)
	return self.windows[addonName]
end

-- Building ---------------------------------------------------------------------------------------------------

local function FrameName(window)
	local name = window.declaration.frameName
	if type(name) == "string" and name ~= "" then
		return name
	end

	return "LibAeonSettingsWindow" .. window.addonName:gsub("[^%w]", "")
end

local function BuildFooter(window, frame)
	local footer = CreateFrame("Frame", nil, frame)
	footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, FOOTER_BOTTOM)
	footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, FOOTER_BOTTOM)
	footer:SetHeight(FOOTER_HEIGHT)

	footer.text = footer:CreateFontString(nil, "OVERLAY")
	lib:SetFont(footer.text, "body", FOOTER_TEXT_SIZE)
	footer.text:SetPoint("LEFT", 14, 0)
	footer.text:SetJustifyH("LEFT")

	-- Beside the reload notice; a message shown for a few seconds takes its place meanwhile.
	footer.reload = CreateFrame("Button", nil, footer, "SharedButtonTemplate")
	footer.reload:SetText(RELOADUI)
	footer.reload:SetSize(footer.reload:GetFontString():GetStringWidth() + 40, 30)
	footer.reload:SetPoint("LEFT", footer.text, "RIGHT", 12, 0)
	footer.reload:SetScript("OnClick", function() C_UI.Reload() end)
	footer.reload:Hide()

	footer.editMode = CreateFrame("Button", nil, footer, "SharedButtonTemplate")
	footer.editMode:SetText(L.OPEN_EDIT_MODE)
	footer.editMode:SetSize(footer.editMode:GetFontString():GetStringWidth() + 40, 30)
	footer.editMode:SetPoint("RIGHT", -10, 0)
	footer.editMode:SetScript("OnClick", function() Handlers.EditMode(window) end)

	return footer
end

-- Draws Blizzard's settings inner frame across `width` by `height` from (left, top) of `frame`, piece by piece.
local function DrawInnerFrame(frame, left, top, width, height)
	local info = C_Texture.GetAtlasInfo("Options_InnerFrame")
	if not info then
		return
	end
	local function Fixed(list, total)
		local fixed = 0
		for _, entry in ipairs(list) do
			fixed = fixed + (entry[3] or 0)
		end

		return total - fixed
	end
	local stretchWidth, stretchHeight = Fixed(INNER_COLUMNS, width), Fixed(INNER_ROWS, height)
	local u0, u1 = info.leftTexCoord, info.rightTexCoord
	local v0, v1 = info.topTexCoord, info.bottomTexCoord
	local y = top
	for _, rowInfo in ipairs(INNER_ROWS) do
		local rowHeight = rowInfo[3] or stretchHeight
		local x = left
		for _, column in ipairs(INNER_COLUMNS) do
			local columnWidth = column[3] or stretchWidth
			local piece = frame:CreateTexture(nil, "BORDER")
			piece:SetTexture(info.file)
			piece:SetTexCoord(u0 + (u1 - u0) * column[1] / INNER_ART_WIDTH,
				u0 + (u1 - u0) * (column[1] + column[2]) / INNER_ART_WIDTH,
				v0 + (v1 - v0) * rowInfo[1] / INNER_ART_HEIGHT,
				v0 + (v1 - v0) * (rowInfo[1] + rowInfo[2]) / INNER_ART_HEIGHT)
			piece:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
			piece:SetSize(columnWidth, rowHeight)
			x = x + columnWidth
		end
		y = y + rowHeight
	end
end

---A hidden SettingsFrameTemplate window: top level, clamped to the screen, dragged by a 22-unit bar along its top
---(short of the close button), with a gold header title (`frame.title`) in place of the template's. `onDragStop` runs
---when a drag ends; by default the frame just stops moving.
---@param onDragStop function?
---@return Frame frame with `titleBar` and `title`
function lib:CreateSettingsShell(name, parent, strata, onDragStop)
	local frame = CreateFrame("Frame", name, parent, "SettingsFrameTemplate")
	frame:SetFrameStrata(strata)
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetDontSavePosition(true)
	frame:Hide()
	frame.NineSlice.Text:SetText("")

	local titleBar = CreateFrame("Frame", nil, frame)
	titleBar:SetPoint("TOPLEFT", 0, 0)
	titleBar:SetPoint("TOPRIGHT", -28, 0)
	titleBar:SetHeight(22)
	titleBar:EnableMouse(true)
	titleBar:RegisterForDrag("LeftButton")
	titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
	titleBar:SetScript("OnDragStop", onDragStop or function() frame:StopMovingOrSizing() end)
	local title = titleBar:CreateFontString(nil, "OVERLAY")
	lib:SetFont(title, "header", TITLE_SIZE)
	title:SetTextColor(unpack(TITLE_GOLD))
	title:SetPoint("TOP", frame, "TOP", 0, -4)
	frame.titleBar, frame.title = titleBar, title

	return frame
end

local function Build(window)
	local name = FrameName(window)
	local frame = lib:CreateSettingsShell(name, UIParent, "HIGH", function() Handlers.Moved(window) end)
	frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
	frame:SetScript("OnHide", function() Handlers.Hidden(window) end)
	frame.ClosePanelButton:SetScript("OnClick", function() window:Close() end)

	local version = frame.titleBar:CreateFontString(nil, "OVERLAY")
	lib:SetType(version, "secondary", "secondary")
	version:SetPoint("LEFT", frame.title, "RIGHT", 6, 0)
	frame.version = version

	frame.footer = BuildFooter(window, frame)

	local width, height = frame:GetSize()
	local innerWidth, innerHeight = width - INNER_LEFT - INNER_RIGHT, height - INNER_TOP - INNER_BOTTOM
	DrawInnerFrame(frame, INNER_LEFT, INNER_TOP, innerWidth, innerHeight)
	local contentLeft = INNER_LEFT + 12 + SIDEBAR_WIDTH + 8
	local fill = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
	fill:SetColorTexture(unpack(CONTENT_FILL))
	fill:SetPoint("TOPLEFT", frame, "TOPLEFT", contentLeft - 2, -(INNER_TOP + 3))
	fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(INNER_RIGHT + 3), INNER_BOTTOM + 3)

	local sidebarRegion = CreateFrame("Frame", nil, frame)
	sidebarRegion:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDEBAR_LEFT, -SIDEBAR_TOP)
	sidebarRegion:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", SIDEBAR_LEFT, INNER_BOTTOM + SIDEBAR_BOTTOM)
	sidebarRegion:SetWidth(SIDEBAR_WIDTH)
	frame.sidebarRegion = sidebarRegion

	-- Escape closes the window, as it does Blizzard's panels, after any open menu: Blizzard hides the frames named in
	-- UISpecialFrames at once, so a hidden stand-in is named there instead, and its hiding closes the window.
	local escape = CreateFrame("Frame", name .. "Escape", frame)
	escape:SetScript("OnHide", function() Handlers.EscapeHidden(window) end)
	tinsert(UISpecialFrames, escape:GetName())
	frame.escape = escape

	window.frame = frame
	window:BuildSidebar(sidebarRegion)
	window:BuildSearch()
	window:BuildUndo()
	window:RefreshShell()

	return frame
end

---Fills the title, version and footer from the declaration.
function lib.Window:RefreshShell()
	local frame, declaration = self.frame, self.declaration
	if not frame then
		return
	end
	frame.title:SetText(declaration.title or self.addonName)
	frame.version:SetText(declaration.version or "")
	frame.version:SetShown(declaration.version ~= nil)
	self:SetFooterText(self:FooterText(), false)
	frame.footer.reload:SetShown(self.reloadNeeded == true and not self.statusText)
	frame.footer.editMode:SetShown(lib.registrations[self.addonName] ~= nil)
	self:PlaceUndo()
end

-- Opening and closing ----------------------------------------------------------------------------------------

---Opens the window, on the page and at the place it last had this session. Refused in combat, and while edit
---mode is open (which is asked to close first).
function lib.Window:Open()
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(L.UNAVAILABLE_IN_COMBAT, lib:GetColor("destructive"))
		return
	end
	if lib:IsEditing() then
		lib:RequestClose(false)
		if lib:IsEditing() then
			return
		end
	end
	local frame = self.frame or Build(self)
	frame:ClearAllPoints()
	if self.position then
		frame:SetPoint(unpack(self.position))
	else
		frame:SetPoint("CENTER")
	end
	self:RefreshShell()
	if self.navChanged then
		self:RefreshSidebar()
	end
	-- Pages switched on or off while the window was closed.
	self:PaintSidebar()
	if not self.page and self.pageOrder[1] then
		self.page = self.pageOrder[1].id
	end
	self:AddWindowSection()
	self:RefreshPageShows()
	self:RefreshReloadNeeded()
	local opening = not frame:IsShown() or self.closing
	self.closing = false
	local presence = Handlers.Presence(self)
	if not frame:IsShown() then
		Handlers.DrawPresence(self, presence.value)
	end
	frame:Show()
	if frame.escape then
		frame.escape:Show()
	end
	if self.page then
		self:SelectPage(self.page)
	end
	lib.combatWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
	presence:To(1)
	if opening then
		lib:Fire("OnOpen", self.addonName)
	end
end

---Closes the window at once, so a click or camera turn right after it reaches the world. An opening still running
---stops where it is.
function lib.Window:Close()
	local frame = self.frame
	if not frame or not frame:IsShown() then
		return
	end
	self.closing = true
	if frame.escape then
		frame.escape:Hide()
	end
	Handlers.Presence(self):Jump(0)
end

function lib.Window:Toggle()
	if self:IsShown() then
		self:Close()
	else
		self:Open()
	end
end

---@return boolean shown the window is open, not closing
function lib.Window:IsShown()
	return self.frame ~= nil and self.frame:IsShown() and not self.closing
end

-- The window's presence, 0 closed to 1 open, on a spring: alpha follows it, and the scale grows from CLOSED_SCALE
-- about the window's center. At rest at 0 the window hides. Made on first use: a window built by an older copy has
-- none.
function Handlers.Presence(window)
	if not window.presence then
		window.presence = lib:CreateSpring(0, function(value) Handlers.DrawPresence(window, value) end, {
			response = OPEN_RESPONSE,
			onRest = function(value)
				if value == 0 and window.closing then
					window.frame:Hide()
				end
			end,
		})
	end

	return window.presence
end

-- A scaled frame's anchor offsets count in its own scale, so they are divided by it to keep the center still.
function Handlers.DrawPresence(window, value)
	local frame = window.frame
	local scale = CLOSED_SCALE + (1 - CLOSED_SCALE) * value
	local point, relativeTo, relativePoint, x, y = unpack(window.position or { "CENTER", UIParent, "CENTER", 0, 0 })
	local width, height = frame:GetSize()
	local dx = (point:find("LEFT") and width / 2 or point:find("RIGHT") and -width / 2 or 0) * (1 - scale)
	local dy = (point:find("BOTTOM") and height / 2 or point:find("TOP") and -height / 2 or 0) * (1 - scale)
	frame:SetAlpha(math.max(0, math.min(1, value)))
	frame:SetScale(scale)
	frame:ClearAllPoints()
	frame:SetPoint(point, relativeTo, relativePoint, (x + dx) / scale, (y + dy) / scale)
end

-- The stand-in stopped being visible. Only Escape hides it while the window is open; it also stops being visible
-- when the window or the whole interface hides, and then it is still shown.
function Handlers.EscapeHidden(window)
	if window.frame.escape:IsShown() or window.closing or not window.frame:IsShown() then
		return
	end
	window:Close()
end

-- The footer text fades out, changes, and fades back in. The tween's OnUpdate runs only while it fades.
function Handlers.FooterFade(footer, elapsed)
	local fade = footer.fade
	fade.elapsed = fade.elapsed + elapsed
	if fade.phase == "out" then
		local progress = math.min(1, fade.elapsed / TEXT_FADE_OUT)
		footer.text:SetAlpha(fade.from * (1 - progress))
		if progress >= 1 then
			footer.text:SetText(fade.text)
			fade.phase, fade.elapsed = "in", 0
		end
	else
		local progress = math.min(1, fade.elapsed / TEXT_FADE_IN)
		footer.text:SetAlpha(progress)
		if progress >= 1 then
			footer.fade = nil
			footer:SetScript("OnUpdate", nil)
		end
	end
end

---Sets the footer text, crossfading when `animate` is true and the window is shown.
function lib.Window:SetFooterText(text, animate)
	local footer = self.frame and self.frame.footer
	if not footer then
		return
	end
	if footer.fade then
		footer.fade.text = text
		return
	end
	if footer.text:GetText() == text then
		return
	end
	if not animate or not self.frame:IsShown() or lib:ReduceMotion() then
		footer.text:SetText(text)
		footer.text:SetAlpha(1)
		return
	end
	footer.fade = { phase = "out", elapsed = 0, from = footer.text:GetAlpha(), text = text }
	footer:SetScript("OnUpdate", function(frame, elapsed) Handlers.FooterFade(frame, elapsed) end)
end

---@return string text the footer's text: a message being shown, else the reload notice while a change waits, else none
function lib.Window:FooterText()
	return self.statusText or self.reloadNeeded and L.RELOAD_NEEDED or ""
end

---Shows a message in the footer for a few seconds, fading in and out, then the reload notice again when one stands.
function lib.Window:ShowStatus(text)
	self.statusText = text
	self.statusToken = (self.statusToken or 0) + 1
	local token = self.statusToken
	self:SetFooterText(text, true)
	if self.frame then
		self.frame.footer.reload:Hide()
	end
	C_Timer.After(STATUS_SECONDS, function()
		if self.statusToken == token then
			self.statusText = nil
			self:SetFooterText(self:FooterText(), true)
			if self.frame then
				self.frame.footer.reload:SetShown(self.reloadNeeded == true)
			end
		end
	end)
end

---Asks the declaration's `reloadNeeded` again and shows or clears the footer's reload notice and its Reload UI button.
function lib.Window:RefreshReloadNeeded()
	local check = self.declaration.reloadNeeded
	local needed = type(check) == "function" and lib.CallAdopter(check) == true
	if needed == (self.reloadNeeded == true) then
		return
	end
	self.reloadNeeded = needed
	if not self.frame then
		return
	end
	self:SetFooterText(self:FooterText(), true)
	self.frame.footer.reload:SetShown(needed and not self.statusText)
end

function Handlers.Moved(window)
	local frame = window.frame
	frame:StopMovingOrSizing()
	-- Offsets are kept at full scale; a drag that ends while the window still grows has smaller ones.
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	local scale = frame:GetScale()
	window.position = { point, UIParent, relativePoint, x * scale, y * scale }
end

function Handlers.Hidden(window)
	window:StopPreview()
	if window.pageView then
		window.pageView.announced = nil
	end
	lib:Fire("OnClose", window.addonName)
	for _, other in pairs(lib.windows) do
		if other:IsShown() then
			return
		end
	end
	lib.combatWatch:UnregisterEvent("PLAYER_REGEN_DISABLED")
end

-- The footer's Edit Mode button closes the window and opens the library's edit mode from this addon; leaving edit
-- mode opens the window again.
function Handlers.EditMode(window)
	window:Close()
	lib:OpenEditMode(window.addonName)
	if lib:IsEditing() then
		lib.session.returnTo = window
	end
end

-- Combat closes every open window; each opens again where it was the next time.
lib.combatWatch = lib.combatWatch or CreateFrame("Frame")
lib.combatWatch:SetScript("OnEvent", function()
	for _, window in pairs(lib.windows) do
		window:Close()
	end
end)
