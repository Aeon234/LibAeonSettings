-- Landing: opening the page a setting or section is on, gliding it into view and flashing it gold, for search, Undo,
-- the edit mode link and a preview's parts. Also the flashes themselves, a pool on the page view.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local SETTING_MARGIN, SECTION_MARGIN = 80, 8 -- a row and a section land this far below the list's top
local FLASH_SECONDS, FLASH_HOLD, FLASH_EDGE = 2.4, 0.6, 2

lib.LandingHandlers = lib.LandingHandlers or {}
local Handlers = lib.LandingHandlers

---Opens a setting's page (and tab), reveals its section when search found it hidden, glides its row into view and
---flashes it gold. A row away under a parent that is off lands on that parent.
function lib.Window:LandOn(setting)
	local page = setting.page
	local tab = setting.section and setting.section.tab
	if tab then
		page.tab = tab.id
	end
	local reveal = not setting:IsShown() and setting:Revealable()
	if reveal then
		lib.CallAdopter(setting.section.reveal, setting.section)
	end
	-- A setting inside closed details opens them (and any they sit in) first.
	local inside, depth = setting.details and page.settings[setting.details], 0
	while inside and depth < 16 do
		if not inside:GetValue() then
			inside:SetValue(true)
		end
		inside, depth = inside.details and page.settings[inside.details], depth + 1
	end
	self:SelectPage(page.id)
	if reveal then
		self:Refresh()
	end
	local half = self:RowOf(setting)
	-- A row away under a parent that is off: land on the parent, whose turning on brings it in.
	local parent, depth = setting:Parent(), 0
	while half and not half:IsShown() and parent and depth < 16 do
		half = self:RowOf(parent) or half
		parent, depth = parent:Parent(), depth + 1
	end
	local view = self.pageView
	if not half or not view or not half:IsShown() then
		return
	end
	view.scroll:GlideTo(half.top - SETTING_MARGIN)
	self:Flash(half)
end

---Opens a section's page (and tab), glides the section to the top and pulses the whole section gold.
function lib.Window:LandOnSection(section)
	local page = section.page
	if section.tab then
		page.tab = section.tab.id
	end
	self:SelectPage(page.id)
	local header = self:HeaderOf(section)
	local view = self.pageView
	if not view or not header or header.section ~= section or not header:IsShown() or not header.top then
		return
	end
	view.scroll:GlideTo(math.max(0, header.top - SECTION_MARGIN))
	self:Flash(header, header.top, (header.bottom or header.top) - header.top)
end

-- Flashes ----------------------------------------------------------------------------------------------------

local function FlashEdge(flash, first, second, horizontal)
	local edge = flash:CreateTexture(nil, "OVERLAY")
	edge:SetColorTexture(lib:GetColor("accent"))
	edge:SetPoint(first)
	edge:SetPoint(second)
	if horizontal then
		edge:SetHeight(FLASH_EDGE)
	else
		edge:SetWidth(FLASH_EDGE)
	end
end

-- Starts the flash at a place in the view's pool, made the first time it is needed. It covers `region`, or with `top`
-- and `height` a band of the page from `top`.
local function StartFlash(view, index, region, top, height)
	view.flashes = view.flashes or {}
	local flash = view.flashes[index]
	if not flash then
		flash = CreateFrame("Frame", nil, view.scroll.child)
		FlashEdge(flash, "TOPLEFT", "TOPRIGHT", true)
		FlashEdge(flash, "BOTTOMLEFT", "BOTTOMRIGHT", true)
		FlashEdge(flash, "TOPLEFT", "BOTTOMLEFT", false)
		FlashEdge(flash, "TOPRIGHT", "BOTTOMRIGHT", false)
		flash:SetScript("OnUpdate", function(self, elapsed) Handlers.FlashUpdate(self, elapsed) end)
		view.flashes[index] = flash
	end
	flash:ClearAllPoints()
	if top then
		flash:SetPoint("TOPLEFT", view.scroll.child, "TOPLEFT", 0, -top)
		flash:SetSize(region:GetWidth(), height)
	else
		flash:SetAllPoints(region)
	end
	flash:SetFrameLevel(region:GetFrameLevel() + 20)
	flash.half, flash.elapsed = region, 0
	flash:SetAlpha(1)
	flash:Show()
end

-- Hides the view's flashes from a place in its pool on.
local function HideFlashes(view, from)
	for index = from, view.flashes and #view.flashes or 0 do
		view.flashes[index]:Hide()
	end
end

---Flashes a row half (or, with `top` and `height`, a band of the page from `top`, such as a section): a gold outline,
---held, then fading out. The flash stops if `half` leaves the page.
function lib.Window:Flash(half, top, height)
	local view = self.pageView
	StartFlash(view, 1, half, top, height)
	HideFlashes(view, 2)
end

---Flashes the rows of several settings together, without moving the page. A setting with no row showing is skipped.
---@param settings table[]
---@return integer flashed how many rows flashed
function lib.Window:FlashSettings(settings)
	local view = self.pageView
	local count = 0
	if not view then
		return count
	end
	for _, setting in ipairs(settings) do
		local half = self:RowOf(setting)
		if half and half:IsShown() then
			count = count + 1
			StartFlash(view, count, half)
		end
	end
	HideFlashes(view, count + 1)

	return count
end

---Ends every flash on the page view.
function lib.Window:StopFlash()
	local view = self.pageView
	if view then
		HideFlashes(view, 1)
	end
end

function Handlers.FlashUpdate(flash, elapsed)
	flash.elapsed = flash.elapsed + elapsed
	local t = flash.elapsed / FLASH_SECONDS
	-- The row moved on (a page change released it): stop.
	if t >= 1 or not flash.half:IsShown() then
		flash:Hide()
		return
	end
	flash:SetAlpha(t <= FLASH_HOLD and 1 or 1 - (t - FLASH_HOLD) / (1 - FLASH_HOLD))
end
