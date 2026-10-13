-- C-12, the color swatch: the checkbox's frame (Blizzard's `checkbox-minimal`) with the color filling the box inside
-- its border, cut to the box's chamfered shape, and a centered 3 × 3 checkerboard behind a color that is not fully
-- opaque. It opens Blizzard's color picker; the pick saves live, at
-- most once a frame, and Cancel puts the earlier color back. `classColor` pairs it with a Use Class Color checkbox.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

-- `checkbox-minimal` is 30 × 29. Measured on its Forever art: the box's alpha spans x 2 to 27 and y 2 to 26, its
-- light border is 2 wide, and the dark inside runs x 4 to 25 and y 4 to 24 (22 × 21), with chamfered corners.
local WIDTH, HEIGHT = 30, 29
local INNER_LEFT, INNER_TOP, INNER_WIDTH, INNER_HEIGHT = 4, 4, 22, 21
local BOX_LEFT, BOX_TOP, BOX_WIDTH, BOX_HEIGHT = 2, 2, 26, 25
-- The mask is the same atlas, scaled so its box lands exactly on the inside: the color keeps the chamfers and the
-- border shows all round it.
local MASK_SCALE_X, MASK_SCALE_Y = INNER_WIDTH / BOX_WIDTH, INNER_HEIGHT / BOX_HEIGHT
local MASK_LEFT, MASK_TOP = INNER_LEFT - BOX_LEFT * MASK_SCALE_X, INNER_TOP - BOX_TOP * MASK_SCALE_Y
local CHECKER = 0.75           -- the checkerboard's 3 × 3 cells in its 4 × 4 texels
local SAME = 0.0005            -- colors this close count as the same

lib.Color = {}
local colorMeta = { __index = function(_, name) return lib.Color[name] end }
local Handlers = {}
lib.ColorHandlers = Handlers

local function Texture(path)
	return lib.mediaPath .. "Textures\\" .. path
end

function lib:CreateColorSwatch(parent)
	local view = setmetatable({}, colorMeta)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(WIDTH, HEIGHT)
	button:RegisterForClicks("LeftButtonUp")

	view.border = button:CreateTexture(nil, "BACKGROUND")
	view.border:SetAtlas("checkbox-minimal")
	view.border:SetAllPoints()

	local mask = button:CreateMaskTexture()
	mask:SetAtlas("checkbox-minimal")
	mask:SetPoint("TOPLEFT", MASK_LEFT, -MASK_TOP)
	mask:SetSize(WIDTH * MASK_SCALE_X, HEIGHT * MASK_SCALE_Y)

	local function Inner(layer, sublevel)
		local texture = button:CreateTexture(nil, layer, nil, sublevel)
		texture:SetPoint("TOPLEFT", INNER_LEFT, -INNER_TOP)
		texture:SetSize(INNER_WIDTH, INNER_HEIGHT)
		texture:AddMaskTexture(mask)

		return texture
	end
	view.checker = Inner("BORDER", 0)
	view.checker:SetTexture(Texture("swatch-checker"), "CLAMP", "CLAMP", "NEAREST")
	view.checker:SetTexCoord(0, CHECKER, 0, CHECKER)
	view.color = Inner("ARTWORK", 0)
	-- Hover as the checkbox does (MinimalCheckboxArtTemplate): an ADD copy of the box over it, brightening the border.
	view.highlight = button:CreateTexture(nil, "HIGHLIGHT")
	view.highlight:SetAtlas("checkbox-minimal")
	view.highlight:SetBlendMode("ADD")
	view.highlight:SetAllPoints()

	button:SetScript("OnClick", function() Handlers.Click(view) end)
	button:SetScript("OnHide", function() view:EndPick(true) end)
	button.view = view
	view.frame, view.button = button, button

	return view
end

local function Components(color, hasOpacity)
	if type(color) ~= "table" then
		return 1, 1, 1, 1
	end
	local alpha = hasOpacity and (color.a or 1) or 1

	return color.r or 1, color.g or 1, color.b or 1, alpha
end

local function Same(r1, g1, b1, a1, r2, g2, b2, a2)
	return math.abs(r1 - r2) < SAME and math.abs(g1 - g2) < SAME and math.abs(b1 - b2) < SAME and math.abs(a1 - a2) < SAME
end

-- Paints a color, the checkerboard showing through when it is not fully opaque.
function lib.Color:Paint(r, g, b, a)
	self.color:SetColorTexture(r, g, b, a)
	self.checker:SetShown(a < 1)
end

function lib.Color:ShowValue()
	self:Paint(Components(self.setting:GetValue(), self.setting.hasOpacity))
end

function lib.Color:Bind(setting)
	self.setting = setting
	self:ShowValue()
end

function lib.Color:Update(_, refused)
	if self.picking then
		if refused then
			-- The rest of the pick only previews, so the refusal is not repeated each frame.
			self.previewOnly = true
			lib:Shake(self.frame)
		end
		return
	end
	self:ShowValue()
	if refused then
		lib:Shake(self.frame)
	end
end

-- Losing the row ends a pick as Cancel.
function lib.Color:Release()
	self:EndPick(true)
	self.setting = nil
end

function lib.Color:SetActive(active)
	if not active then
		self:EndPick(true)
	end
	self.button:SetEnabled(active)
end

-- Inactive: the frame grays; the color is the value, so it keeps its own.
function lib.Color:Desaturate(amount)
	self.border:SetDesaturation(amount)
end

function lib.Color:GetWidth()
	return WIDTH
end

-- Picking ------------------------------------------------------------------------------------------------------

local function Request(view, r, g, b, a)
	local setting = view.setting
	local sr, sg, sb, sa = Components(setting:GetValue(), setting.hasOpacity)
	if Same(r, g, b, a, sr, sg, sb, sa) then
		return
	end
	setting:Request({ r = r, g = g, b = b, a = setting.hasOpacity and a or nil })
end

---Ends this swatch's pick. As Cancel (`cancel`), the color from before the pick is asked for again and the picker
---closes if it still shows this swatch's color.
function lib.Color:EndPick(cancel)
	local pick = self.picking
	if not pick then
		return
	end
	self.frame:SetScript("OnUpdate", nil)
	-- Still picking while the earlier color is asked for, so Undo keeps the whole pick as one step.
	if cancel and self.setting then
		Request(self, pick.r, pick.g, pick.b, pick.a)
	end
	self.picking, self.previewOnly = nil, nil
	if cancel and self.setting then
		self:ShowValue()
	end
	if ColorPickerFrame:IsShown() and ColorPickerFrame.extraInfo == pick then
		ColorPickerFrame:Hide()
	end
end

-- Reads the picker into a pending color; the frame's OnUpdate saves it, at most once a frame.
function Handlers.Changed(view)
	local pick = view.picking
	if not pick or pick.opening then
		return
	end
	local r, g, b = ColorPickerFrame:GetColorRGB()
	local a = view.setting.hasOpacity and ColorPickerFrame:GetColorAlpha() or 1
	view:Paint(r, g, b, a)
	pick.pending = { r, g, b, a }
	view.frame:SetScript("OnUpdate", Handlers.Flush)
end

function Handlers.Flush(button)
	local view = button.view
	button:SetScript("OnUpdate", nil)
	local pick = view and view.picking
	if not pick or not pick.pending or view.previewOnly then
		return
	end
	local pending = pick.pending
	pick.pending = nil
	Request(view, pending[1], pending[2], pending[3], pending[4])
end

-- The picker hid: Okay if it still holds this pick (the final color is asked for once more), else someone else
-- took it and the swatch goes back to its saved color.
function Handlers.PickerHidden()
	local view = lib.colorPicking
	local pick = view and view.picking
	if not pick then
		return
	end
	lib.colorPicking = nil
	if ColorPickerFrame.extraInfo == pick then
		local r, g, b = ColorPickerFrame:GetColorRGB()
		local a = view.setting.hasOpacity and ColorPickerFrame:GetColorAlpha() or 1
		view.frame:SetScript("OnUpdate", nil)
		if not view.previewOnly then
			Request(view, r, g, b, a) -- still picking, so it joins the pick's Undo step
		end
		view.picking, view.previewOnly = nil, nil
		view:ShowValue()
	else
		view.picking, view.previewOnly = nil, nil
		view.frame:SetScript("OnUpdate", nil)
		view:ShowValue()
	end
end

function Handlers.Click(view)
	local setting = view.setting
	if not setting then
		return
	end
	-- A click while this swatch's picker is open cancels it, then opens it again, fresh.
	view:EndPick(true)
	if lib.colorPicking and lib.colorPicking ~= view then
		lib.colorPicking:EndPick(true)
	end
	if not lib.pickerHooked then
		lib.pickerHooked = true
		ColorPickerFrame:HookScript("OnHide", function() lib.ColorHandlers.PickerHidden() end)
	end
	local r, g, b, a = Components(setting:GetValue(), setting.hasOpacity)
	local pick = { r = r, g = g, b = b, a = a, opening = true }
	view.picking = pick
	lib.colorPicking = view
	ColorPickerFrame:SetupColorPickerAndShow({
		r = r, g = g, b = b, opacity = a, hasOpacity = setting.hasOpacity,
		swatchFunc = function() Handlers.Changed(view) end,
		opacityFunc = function() Handlers.Changed(view) end,
		cancelFunc = function() view:EndPick(true) end,
		extraInfo = pick,
	})
	-- The picker reports the previous user's opacity for a moment as it opens; paint the saved color again.
	pick.opening = nil
	view:Paint(r, g, b, a)
end

-- Use Class Color --------------------------------------------------------------------------------------------

---@return number r, number g, number b the player's class color
function lib:ClassColor()
	local _, class = UnitClass("player")
	local color = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS[class])
	if color then
		return color.r, color.g, color.b
	end

	return 1, 1, 1
end

-- `classColor = { path, default, get?, set? }` adds a Use Class Color checkbox in the half beside the swatch; while
-- it is on, the swatch is dimmed and takes no clicks (its label stays, with no reason line).
-- A color as text: a chip of it and its hex code, with the opacity when it has one.
local function FormatColor(setting, color)
	local r, g, b, a = Components(color, setting.hasOpacity)
	local chip = ("|TInterface\\Buttons\\WHITE8X8:10:10:0:-1:8:8:0:8:0:8:%d:%d:%d|t"):format(r * 255, g * 255, b * 255)
	local text = ("%s #%02X%02X%02X"):format(chip, r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
	if setting.hasOpacity and a < 1 then
		text = ("%s %d%%"):format(text, a * 100 + 0.5)
	end

	return text
end

lib:RegisterControl("Color", {
	fields = { hasOpacity = true, classColor = true },
	Format = FormatColor,
	Create = function(half) return lib:CreateColorSwatch(half) end,
})

-- Replaces the plain constructor RegisterControl made.
function lib.Section.Color(section, info)
	local classColor = type(info) == "table" and info.classColor
	if classColor ~= nil then
		info.classColor = nil
		local lines = section.lines
		local last = lines[#lines]
		if last and not last.wide and not last.note and last[2] == nil then
			section:Skip()
		end
	end
	local swatch = section:Add("Color", info)
	if swatch and classColor ~= nil then
		local fields = type(classColor) == "table" and classColor or {}
		fields.id = fields.id or (tostring(info.id) .. "Class")
		fields.label = fields.label or L.USE_CLASS_COLOR
		local checkbox = section:Add("Checkbox", fields)
		swatch.classSetting = checkbox
	end

	return swatch
end
