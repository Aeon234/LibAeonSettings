-- The suite's fonts: Expressway for body text, Gilroy Bold for headings. Clients whose language needs other glyphs
-- (Korean, Russian, Chinese) use the game's own font at the same sizes. Also the outline choices, and the fonts a font
-- picker offers.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

local NATIVE_FONT_LOCALES = { koKR = true, ruRU = true, zhCN = true, zhTW = true }
local FILES = { body = "Expressway.ttf", header = "GilroyBold.ttf" }
local PICKER_FONT_SIZE = 14

-- Blizzard's own fonts under LibSharedMedia's names, plus the library's, for a font picker without LibSharedMedia.
local FALLBACK_FONTS = {
	{ "Arial Narrow", "Fonts\\ARIALN.TTF" },
	{ "Friz Quadrata TT", "Fonts\\FRIZQT__.TTF" },
	{ "Morpheus", "Fonts\\MORPHEUS.TTF" },
	{ "Skurri", "Fonts\\SKURRI.TTF" },
}
local LIBRARY_FONTS = { { "Expressway", FILES.body }, { "Gilroy Bold", FILES.header } }

-- The suite's six outline choices (Alex, 2026-10-07), always with the Slug variants. `SLUG` is a `SetFont` flag,
-- comma-joined with the outline.
lib.OUTLINES = {
	{ value = "NONE", text = L.OUTLINE_NONE },
	{ value = "OUTLINE", text = L.OUTLINE_OUTLINE },
	{ value = "THICKOUTLINE", text = L.OUTLINE_THICK },
	{ value = "SLUG", text = L.OUTLINE_SLUG },
	{ value = "SLUG_OUTLINE", text = L.OUTLINE_SLUG_OUTLINE },
	{ value = "SLUG_THICKOUTLINE", text = L.OUTLINE_SLUG_THICK },
}
local OUTLINE_FLAGS = { NONE = "", OUTLINE = "OUTLINE", THICKOUTLINE = "THICKOUTLINE", SLUG = "SLUG",
	SLUG_OUTLINE = "SLUG, OUTLINE", SLUG_THICKOUTLINE = "SLUG, THICKOUTLINE" }

---Sets a font string to one of the library's fonts, with the suite's black shadow.
---@param fontString FontString
---@param kind string "body" or "header"
---@param size number
---@param flags string? font flags such as "OUTLINE"
function lib:SetFont(fontString, kind, size, flags)
	local file = NATIVE_FONT_LOCALES[GetLocale()] and STANDARD_TEXT_FONT
		or self.mediaPath .. "Fonts\\" .. (FILES[kind] or FILES.body)
	fontString:SetFont(file, size, flags or "")
	fontString:SetShadowColor(0, 0, 0, 1)
	fontString:SetShadowOffset(1, -1)
end

---Gives a font string its font object's face and size with a thin outline, for text drawn over any background.
function lib:OutlineText(fontString)
	local face, size = fontString:GetFont()
	if face then
		fontString:SetFont(face, size, "OUTLINE")
	end
	fontString:SetShadowOffset(0, 0)
end

---@return string flags for `SetFont`, from one of the six outline values
function lib:OutlineFlags(value)
	return OUTLINE_FLAGS[value] or ""
end

---The choices of a font picker, by name: LibSharedMedia's fonts, read at each call, or Blizzard's and the library's.
---@return { value: string, text: string, font: string }[]
function lib:FontChoices()
	local choices = {}
	local media = LibStub("LibSharedMedia-3.0", true)
	if media then
		local files = media:HashTable("font")
		for _, name in ipairs(media:List("font")) do
			table.insert(choices, { value = name, text = name, font = files[name] })
		end
	else
		for _, entry in ipairs(FALLBACK_FONTS) do
			table.insert(choices, { value = entry[1], text = entry[1], font = entry[2] })
		end
		for _, entry in ipairs(LIBRARY_FONTS) do
			table.insert(choices, { value = entry[1], text = entry[1], font = self.mediaPath .. "Fonts\\" .. entry[2] })
		end
		table.sort(choices, function(a, b) return a.value < b.value end)
	end

	return choices
end

---One font object per file, for drawing a font picker's choices. Font objects are named globals.
function lib:PickerFont(file)
	self.pickerFonts = self.pickerFonts or {}
	local font = self.pickerFonts[file]
	if not font then
		self.pickerFontCount = (self.pickerFontCount or 0) + 1
		font = CreateFont("LibAeonSettingsPickerFont" .. self.pickerFontCount)
		font:SetFont(file, PICKER_FONT_SIZE, "")
		font:SetTextColor(1, 1, 1)
		self.pickerFonts[file] = font
	end

	return font
end
