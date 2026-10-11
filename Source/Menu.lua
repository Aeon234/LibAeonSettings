-- Menus for edit mode: a panel of 24-unit rows (hint text, actions, number boxes, separators) and one flyout.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local ROW_HEIGHT = 24
local MENU_WIDTH = 230
local PADDING = 8
-- Blizzard's own menu art: the row highlight and the submenu arrow of its dropdown menus.
local ROW_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local SUBMENU_ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local BORDER_OUTSET = 3     -- the frame art reaches this far outside the panel
local PANEL_FILL = { 0.122, 0.118, 0.129, 0.92 }
local PANEL_BORDER = { 0.52, 0.41, 0.32 }
local SLICE, SLICE_SCALE = 18, 0.5 -- texels per corner on the 110-texel frame textures, drawn at 2x

local Handlers = {}
lib.MenuHandlers = Handlers

local function FrameTexture(panel, layer, name, color, topExtra)
	local texture = panel:CreateTexture(nil, layer)
	texture:SetTexture(lib.mediaPath .. "Textures\\" .. name)
	texture:SetTextureSliceMargins(SLICE, SLICE, SLICE, SLICE)
	if Enum.UITextureSliceMode then
		texture:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
	end
	texture:SetScale(SLICE_SCALE)
	-- A scaled region's offsets are in its own units.
	local outset = BORDER_OUTSET / SLICE_SCALE
	texture:SetPoint("TOPLEFT", panel, "TOPLEFT", -outset, outset + (topExtra or 0) / SLICE_SCALE)
	texture.outset = outset
	texture:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", outset, -outset)
	texture:SetVertexColor(color[1], color[2], color[3])
	texture:SetAlpha(color[4] or 1)

	return texture
end

---Draws the edit mode panel art on a frame: a fill and a bronze border sharing one chamfered outline, so the fill
---meets the border at every corner. `topExtra` raises the top edge by that many units (to hide it off-screen).
function lib:ApplyPanelArt(frame, topExtra)
	frame.panelArt = {
		FrameTexture(frame, "BACKGROUND", "mover-fill", PANEL_FILL, topExtra),
		FrameTexture(frame, "BORDER", "mover-frame", PANEL_BORDER, topExtra),
	}
end

---Moves the top edge of a frame's panel art `topExtra` units above the frame.
function lib:SetPanelTopExtra(frame, topExtra)
	for _, texture in ipairs(frame.panelArt or {}) do
		texture:SetPoint("TOPLEFT", frame, "TOPLEFT", -texture.outset, texture.outset + topExtra / SLICE_SCALE)
	end
end

local function CreatePanel()
	local panel = CreateFrame("Frame", nil, UIParent)
	panel:SetFrameStrata("FULLSCREEN_DIALOG")
	panel:SetToplevel(true)
	panel:EnableMouse(true)
	panel:SetClampedToScreen(true)
	-- Clamp the art, not just the panel, so no edge is cut off at the screen's border.
	panel:SetClampRectInsets(-BORDER_OUTSET, BORDER_OUTSET, BORDER_OUTSET, -BORDER_OUTSET)
	lib:ApplyPanelArt(panel)
	panel.rows = {}

	return panel
end

local function ClearRows(panel)
	for _, row in ipairs(panel.rows) do
		row:Hide()
	end
	panel.rows = {}
	panel.height = PADDING
end

local function NewRow(panel, height)
	local row = CreateFrame("Button", nil, panel)
	row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -panel.height)
	row:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
	row:SetHeight(height)
	panel.height = panel.height + height
	table.insert(panel.rows, row)

	return row
end

---@class LibAeonSettingsMenuBuilder
local Builder = {}
local builderMeta = { __index = Builder }

function Builder:Hint(text)
	local row = NewRow(self.panel, 10)
	local label = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	label:SetPoint("TOPLEFT", 10, 0)
	label:SetPoint("RIGHT", -10, 0)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	row:SetHeight(label:GetStringHeight() + 8)
	self.panel.height = self.panel.height - 10 + row:GetHeight()
end

function Builder:Separator()
	local row = NewRow(self.panel, 7)
	local line = row:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(0.62, 0.46, 0.29, 0.5)
	line:SetHeight(1)
	line:SetPoint("LEFT", 8, 0)
	line:SetPoint("RIGHT", -8, 0)
end

---A row of text; `onClick` makes it an action. `options.color` colors it; `options.arrow` marks a flyout.
function Builder:Action(text, onClick, options)
	options = options or {}
	local row = NewRow(self.panel, ROW_HEIGHT)
	local label = row:CreateFontString(nil, "OVERLAY", onClick and "GameFontHighlight" or "GameFontDisable")
	label:SetPoint("LEFT", 10, 0)
	label:SetText(text)
	if options.color then
		label:SetTextColor(unpack(options.color))
	end
	if options.arrow then
		local arrow = row:CreateTexture(nil, "ARTWORK")
		arrow:SetSize(16, 16)
		arrow:SetPoint("RIGHT", -6, 0)
		arrow:SetTexture(SUBMENU_ARROW)
	end
	if onClick then
		local hover = row:CreateTexture(nil, "BACKGROUND")
		hover:SetPoint("TOPLEFT", 2, 0)
		hover:SetPoint("BOTTOMRIGHT", -2, 0)
		hover:SetTexture(ROW_HIGHLIGHT)
		hover:SetBlendMode("ADD")
		hover:Hide()
		row:SetScript("OnEnter", function(self) hover:Show(); if options.onEnter then options.onEnter(self) end end)
		row:SetScript("OnLeave", function(self) hover:Hide(); if options.onLeave then options.onLeave(self) end end)
		row:SetScript("OnClick", function(self) onClick(self) end)
	end

	return row, label
end

---A labeled number box: Enter applies the typed value, Escape restores the shown one.
function Builder:Number(text, value, onSet, disabledReason)
	local row, label = self:Action(text)
	label:SetFontObject(disabledReason and "GameFontDisable" or "GameFontHighlight")
	local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	box:SetSize(64, 18)
	box:SetPoint("RIGHT", -10, 0)
	box:SetAutoFocus(false)
	box:SetJustifyH("CENTER")
	box:SetTextInsets(0, 5, 0, 0) -- the template's border starts 5 units left of the box and ends at its right edge
	box:SetText(tostring(value))
	box.value = value
	if disabledReason then
		box:Disable()
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(disabledReason, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	box:SetScript("OnEnterPressed", function(self)
		local number = tonumber(self:GetText())
		self:ClearFocus()
		if number then
			onSet(number)
		else
			self:SetText(tostring(self.value))
		end
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(tostring(self.value))
		self:ClearFocus()
	end)

	return box
end

local function Finish(panel)
	panel:SetSize(panel.width or MENU_WIDTH, panel.height + PADDING)
	panel:Show()
end

local function Build(panel, build)
	ClearRows(panel)
	build(setmetatable({ panel = panel }, builderMeta))
	Finish(panel)
end

---Opens the menu beside `anchor` (owned by `owner`, used to toggle and to keep the owner's state), replacing any
---open menu. `build(builder)` adds the rows.
function lib:OpenMenu(owner, anchor, build)
	local ui = self.ui
	ui.menu = ui.menu or CreatePanel()
	self:CloseFlyout()
	ui.menu.owner = owner
	ui.menu.anchor, ui.menu.build = anchor, build
	ui.menu.width = MENU_WIDTH
	Build(ui.menu, build)
	-- Open toward the middle of the screen, so a mover against an edge keeps its menu in view.
	local anchorX, anchorY = anchor:GetCenter()
	local scale = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local right = anchorX and anchorX * scale > UIParent:GetWidth() / 2
	local up = anchorY and anchorY * scale < UIParent:GetHeight() / 2
	local gap = 4 + BORDER_OUTSET
	ui.menu:ClearAllPoints()
	ui.menu:SetPoint((up and "BOTTOM" or "TOP") .. (right and "RIGHT" or "LEFT"), anchor,
		(up and "TOP" or "BOTTOM") .. (right and "LEFT" or "RIGHT"), right and -gap or gap, up and gap or -gap)
	ui.menuEvents = ui.menuEvents or CreateFrame("Frame")
	ui.menuEvents:SetScript("OnEvent", function() Handlers.GlobalMouseDown() end)
	ui.menuEvents:RegisterEvent("GLOBAL_MOUSE_DOWN")
end

---Rebuilds the open menu in place, keeping its position.
function lib:RefreshMenu()
	local menu = self.ui and self.ui.menu
	if menu and menu:IsShown() then
		self:CloseFlyout()
		Build(menu, menu.build)
	end
end

---Opens a flyout to the right of a menu row.
function lib:OpenFlyout(row, width, build)
	local ui = self.ui
	ui.flyout = ui.flyout or CreatePanel()
	ui.flyout.width = width
	Build(ui.flyout, build)
	-- Beside the menu on the side with more room.
	local menuLeft = ui.menu:GetLeft() or 0
	local scale = ui.menu:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local toLeft = menuLeft * scale > UIParent:GetWidth() / 2
	local gap = 2 * BORDER_OUTSET + 2
	ui.flyout:ClearAllPoints()
	if toLeft then
		ui.flyout:SetPoint("TOPRIGHT", row, "TOPLEFT", -gap, PADDING)
	else
		ui.flyout:SetPoint("TOPLEFT", row, "TOPRIGHT", gap, PADDING)
	end
end

function lib:CloseFlyout()
	if self.ui and self.ui.flyout then
		self.ui.flyout:Hide()
	end
end

---@return string? owner of the open menu
function lib:MenuOwner()
	local menu = self.ui and self.ui.menu

	return menu and menu:IsShown() and menu.owner or nil
end

---Closes the menu and its flyout. Returns true when something was open.
function lib:CloseMenus()
	local ui = self.ui
	local wasOpen = ui and ui.menu and ui.menu:IsShown() or false
	if ui and ui.menu then
		ui.menu:Hide()
		ui.menu.owner = nil
	end
	self:CloseFlyout()
	if ui and ui.menuEvents then
		ui.menuEvents:UnregisterEvent("GLOBAL_MOUSE_DOWN")
	end

	return wasOpen
end

-- A click anywhere outside the menu, its flyout and the owner's cog closes it.
function Handlers.GlobalMouseDown()
	local ui = lib.ui
	if not ui or not ui.menu or not ui.menu:IsShown() then
		return
	end
	if ui.menu:IsMouseOver() or (ui.flyout and ui.flyout:IsShown() and ui.flyout:IsMouseOver()) then
		return
	end
	if ui.menu.anchor and ui.menu.anchor:IsMouseOver() then
		return
	end
	lib:CloseMenus()
	lib:RefreshMovers()
end
