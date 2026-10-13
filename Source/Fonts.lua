-- The suite's fonts: Expressway for body text, Gilroy Bold for headings. Clients whose language needs other glyphs
-- (Korean, Russian, Chinese) use the game's own font at the same sizes.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local NATIVE_FONT_LOCALES = { koKR = true, ruRU = true, zhCN = true, zhTW = true }
local FILES = { body = "Expressway.ttf", header = "GilroyBold.ttf" }

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
