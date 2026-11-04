-- Where a shown page's sections go, worked out with no frames. y runs down from the top of the scrolling list. Rows and
-- headers are read for plain fields only; everything drawn goes through a sink (Page.lua), whose calls are the answer.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local SECTION_GAP = 18
local BOTTOM_PADDING = 14
local HEIGHT_MARGIN = 16 -- a row sized by its setting's height keeps this much beyond it

lib.ROW_HEIGHT, lib.TALL_ROW_HEIGHT = 44, 52
lib.SECTION_TITLE_HEIGHT = 30 -- the heading's line also holds a section's menu and link
lib.HEADING_INSET, lib.HEADING_BOTTOM = 14, 6 -- the heading's text: in from the card's edge, above the card

---@class LibAeonSettingsPageSink
---@field Hidden fun(self, block: table) a hidden section: its header, rows and notes leave
---@field Header fun(self, header: table, top: number, bottom: number, width: number) `bottom` is below the section's card
---@field Row fun(self, half: table, left: number, top: number, width: number, height: number, alpha: number)
---@field Gone fun(self, half: table) a row with no share of its height
---@field Rule fun(self, colorName: string, left: number, top: number, width: number, height: number, alpha: number?)
---@field Fill fun(self, top: number, width: number, height: number) a card's background, drawn under its edges
---@field Note fun(self, note: table, top: number, width: number): number places a note and returns its height

local function RowHeight(half)
	local height = half.look.lines > 0 and lib.TALL_ROW_HEIGHT or lib.ROW_HEIGHT
	if half.setting.height then
		height = math.max(height, half.setting.height + HEIGHT_MARGIN)
	end

	return height
end

-- Rows one to a line. Returns the y below the last.
local function LayoutRows(rows, width, y, sink)
	local previous = false
	for _, half in ipairs(rows) do
		local share = half.revealed or 0
		if share <= 0 then
			sink:Gone(half)
		else
			-- The separator above and the row shrink together, unrounded, so a row ends without a step.
			if previous then
				local ruleLeft = lib.ROW_INSET + half.indent
				sink:Rule("separator", ruleLeft, y, width - ruleLeft, 1, share)
				y = y + share
			end
			local height = RowHeight(half) * share
			-- Not clipped: a row clipping its children while it grows in from nothing draws none of them until it is
			-- whole. Its content fades with the square of its share instead, so it stays faint while the row is too
			-- short to hold it.
			sink:Row(half, 0, y, width, height, share * share)
			y = y + height
			previous = true
		end
	end

	return y
end

-- One line of a choice card. A line takes the larger share of its two rows' heights, and each row fades by its own share.
-- Returns the y below it.
local function LayoutGridLine(left, right, width, y, ruled, sink)
	local columnWidth = math.floor(width / 2)
	local share = math.max(left.revealed, right and right.revealed or 0)
	if ruled then
		sink:Rule("separator", lib.ROW_INSET, y, width - lib.ROW_INSET, 1, share)
		y = y + share
	end
	local height = lib.ROW_HEIGHT * share
	sink:Row(left, 0, y, columnWidth, height, left.revealed * left.revealed)
	if right then
		sink:Rule("separator", columnWidth, y, 1, height, right.revealed)
		sink:Row(right, columnWidth, y, width - columnWidth, height, right.revealed * right.revealed)
	end

	return y + height
end

-- A choice card's rows, two to a line, left to right then down; a row gone gives up its place, one in motion keeps it.
-- Returns the y below the last line.
local function LayoutGrid(rows, width, y, sink)
	local left, ruled = nil, false
	for _, half in ipairs(rows) do
		if (half.revealed or 0) <= 0 then
			sink:Gone(half)
		elseif left then
			y = LayoutGridLine(left, half, width, y, ruled, sink)
			left, ruled = nil, true
		else
			left = half
		end
	end
	if left then
		y = LayoutGridLine(left, nil, width, y, ruled, sink)
	end

	return y
end

-- A card behind a section's rows: a faint fill inside a 1-unit edge.
local function LayoutCard(top, width, height, sink)
	sink:Fill(top, width, height)
	sink:Rule("cardEdge", 0, top, width, 1)
	sink:Rule("cardEdge", 0, top + height - 1, width, 1)
	sink:Rule("cardEdge", 0, top + 1, 1, height - 2)
	sink:Rule("cardEdge", width - 1, top + 1, 1, height - 2)
end

---Lays out a page's sections: each a heading, a card holding its rows one to a line (two in a choice card), then its
---notes under the card. A hidden section is left out with its rows and notes; a row growing in or leaving takes its
---share of its height, faded by as much.
---@param blocks table[] { header = { shown? }, rows = { { revealed?, look, indent, setting } }, notes, grid? }
---@param width number
---@param sink LibAeonSettingsPageSink
---@return number contentHeight
function lib.PageLayout(blocks, width, sink)
	local y = 0
	for _, block in ipairs(blocks) do
		if block.header.shown == false then
			sink:Hidden(block)
		else
			y = y + SECTION_GAP
			local top = y
			y = y + lib.SECTION_TITLE_HEIGHT
			local cardTop = y
			if block.grid then
				y = LayoutGrid(block.rows, width, y, sink)
			else
				y = LayoutRows(block.rows, width, y, sink)
			end
			if y > cardTop then
				LayoutCard(cardTop, width, y - cardTop, sink)
			end
			sink:Header(block.header, top, y, width)
			for _, note in ipairs(block.notes) do
				y = y + sink:Note(note, y, width)
			end
		end
	end

	return y + BOTTOM_PADDING
end
