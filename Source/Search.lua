-- Search (Q105): the sidebar's search box lists matching pages and settings in a popup, each with where it lives;
-- arrow keys and Enter, or a click, open the page, bring the row into view and flash it gold. The index comes from
-- the declarations, so no page is built to search it.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

-- Kit values (Bronze Hearth).
local BOX_LEFT, BOX_TOP, BOX_WIDTH, BOX_HEIGHT = 16, 34, 242, 52 -- the search box art, its 12-unit border included
local BOX_BORDER = 12
local BOX_ART = lib.mediaPath .. "Textures\\search-box"
local BOX_ART_FOCUS = lib.mediaPath .. "Textures\\search-box-focus"
local ICON_LEFT, ICON_TOP, ICON_SIZE, ICON_ALPHA = 1, 6, 18, 0.85
local INPUT_LEFT, INPUT_TOP, INPUT_HEIGHT = 22, -4, 36
local TEXT_SIZE = 18 -- the magnifier's height
local LIST_LEFT, LIST_TOP, LIST_WIDTH, LIST_PAD, LIST_MAX = 18, 84, 238, 7, 420
local RESULT_PAD_X, RESULT_PAD_Y, RESULT_SIZE, RESULT_SMALL = 10, 5, 14, 12
local RESULT_HEIGHT = RESULT_PAD_Y * 2 + 17 + 15
local RESULT_ON_ALPHA = 0.28 -- the highlighted result's bronze fill
local BACKING = { 0.043, 0.043, 0.063, 1 }
local TOOLTIP_CENTER = { 0.090, 0.090, 0.188 }
local LANDING_MARGIN = 80 -- the found row lands this far below the list's top
local FLASH_SECONDS, FLASH_HOLD, FLASH_EDGE = 2.4, 0.6, 2
local FLASH_FILL = 0.12
local CLOSE_DELAY = 0.1
local MAX_RESULTS = 50 -- the list draws at most this many matches, best first

lib.SearchHandlers = lib.SearchHandlers or {}
local Handlers = lib.SearchHandlers

-- Index ------------------------------------------------------------------------------------------------------

-- Words a search may leave out or put in: "gold and" finds "Gold & Bags", "show the clock" finds "Show Clock".
local FILLER = { a = true, an = true, ["and"] = true, the = true, of = true, to = true, ["for"] = true, ["in"] = true,
	on = true, with = true, at = true, by = true, ["or"] = true }
local SYNONYM_MIN = 3 -- a synonym engages once this many of its letters are typed
local SPELLING_MIN = 4 -- a partly typed word takes its other spelling once this many letters are typed
local FUZZY_MIN, FUZZY_SLACK = 3, 4

-- Groups of words that name the same thing; a typed word in a group also finds the others. Adopters add their own
-- with lib:AddSearchSynonyms.
local synonymGroups = {
	{ "color", "tint" },
	{ "opacity", "alpha", "transparency", "transparent" },
	{ "position", "move", "location" },
	{ "font", "typeface" },
	{ "keybind", "hotkey", "binding" },
	{ "bag", "inventory" },
	{ "gold", "money" },
	{ "cooldown", "cd" },
	{ "experience", "xp" },
	{ "health", "hp" },
	{ "sound", "audio" },
	{ "tooltip", "tip" },
}

-- American and British spellings of one word, American first, each the start its other forms share ("customiz"
-- covers customize, customized and customization). A typed word in either spelling also matches the other. Listed
-- word by word, because suffix rules (-our, -re, -ise) would also respell words such as your, fire and precise.
local SPELLINGS = {
	-- -or, -our
	{ "armor", "armour" }, { "behavior", "behaviour" }, { "color", "colour" }, { "favor", "favour" },
	{ "flavor", "flavour" }, { "harbor", "harbour" }, { "honor", "honour" }, { "humor", "humour" },
	{ "labor", "labour" }, { "neighbor", "neighbour" }, { "rumor", "rumour" }, { "savior", "saviour" },
	{ "valor", "valour" }, { "vapor", "vapour" }, { "vigor", "vigour" },
	-- -er, -re
	{ "caliber", "calibre" }, { "center", "centre" }, { "centered", "centred" }, { "centering", "centring" },
	{ "fiber", "fibre" }, { "luster", "lustre" }, { "maneuver", "manoeuvre" }, { "meter", "metre" },
	{ "saber", "sabre" }, { "scepter", "sceptre" }, { "somber", "sombre" }, { "specter", "spectre" },
	{ "theater", "theatre" },
	-- -ize, -ise; -yze, -yse
	{ "analyz", "analys" }, { "authoriz", "authoris" }, { "categoriz", "categoris" }, { "customiz", "customis" },
	{ "finaliz", "finalis" }, { "initializ", "initialis" }, { "localiz", "localis" }, { "maximiz", "maximis" },
	{ "memoriz", "memoris" }, { "minimiz", "minimis" }, { "normaliz", "normalis" }, { "optimiz", "optimis" },
	{ "organiz", "organis" }, { "paralyz", "paralys" }, { "personaliz", "personalis" }, { "prioritiz", "prioritis" },
	{ "randomiz", "randomis" }, { "realiz", "realis" }, { "recogniz", "recognis" }, { "serializ", "serialis" },
	{ "specializ", "specialis" }, { "stabiliz", "stabilis" }, { "standardiz", "standardis" },
	{ "summariz", "summaris" }, { "synchroniz", "synchronis" }, { "utiliz", "utilis" }, { "visualiz", "visualis" },
	-- -l-, -ll-
	{ "beveled", "bevelled" }, { "canceled", "cancelled" }, { "canceling", "cancelling" },
	{ "channeled", "channelled" }, { "channeling", "channelling" }, { "dueling", "duelling" },
	{ "duelist", "duellist" }, { "fueled", "fuelled" }, { "jeweler", "jeweller" }, { "jewelry", "jewellery" },
	{ "labeled", "labelled" }, { "labeling", "labelling" }, { "leveled", "levelled" }, { "leveling", "levelling" },
	{ "marvelous", "marvellous" }, { "modeled", "modelled" }, { "modeling", "modelling" },
	{ "signaled", "signalled" }, { "signaling", "signalling" }, { "traveled", "travelled" },
	{ "traveler", "traveller" }, { "traveling", "travelling" },
	-- -se, -ce; -og, -ogue; others
	{ "defense", "defence" }, { "license", "licence" }, { "offense", "offence" },
	{ "analog", "analogue" }, { "catalog", "catalogue" }, { "dialog", "dialogue" },
	{ "archeology", "archaeology" }, { "artifact", "artefact" }, { "gray", "grey" }, { "judgment", "judgement" },
}

-- The pairs by the first letter of each spelling, so a word is compared only with the pairs it can be in.
local spellingsByLetter = {}
for _, pair in ipairs(SPELLINGS) do
	for side = 1, 2 do
		local letter = pair[side]:sub(1, 1)
		local bucket = spellingsByLetter[letter] or {}
		spellingsByLetter[letter] = bucket
		if bucket[#bucket] ~= pair then
			bucket[#bucket + 1] = pair
		end
	end
end

---Adds a group of words that name the same thing, so searching for one also finds the others.
---@param ... string the words, each one plain word
function lib:AddSearchSynonyms(...)
	local group = {}
	for index = 1, select("#", ...) do
		group[#group + 1] = tostring((select(index, ...))):lower()
	end
	synonymGroups[#synonymGroups + 1] = group
end

-- Lower case, "&" read as "and", split into words on spaces and punctuation.
local function Words(text, into)
	into = into or {}
	if type(text) ~= "string" then
		return into
	end
	for word in text:lower():gsub("&", " and "):gmatch("[^%s%p]+") do
		into[#into + 1] = word
	end

	return into
end

local function Joined(words)
	return " " .. table.concat(words, " ")
end

-- An index entry with the words each tier searches: its own (label and keywords), those and where it lives, and
-- all of them with its description.
local function Entry(kind, page, label, where, searchWhere, keywords, description)
	local own = Words(keywords, Words(label))
	local near = Words(searchWhere, Words(keywords, Words(label)))

	return { kind = kind, page = page, label = label, where = where, phrase = Joined(Words(label)),
		squeezed = table.concat(Words(label)), own = own, near = near,
		all = Words(description, Words(searchWhere, Words(keywords, Words(label)))) }
end

-- Every page, every titled section and every labeled setting in a section, in declaration order. Rebuilt only after
-- the declarations change.
local function BuildIndex(window)
	local index = {}
	for _, page in ipairs(window.pageOrder) do
		index[#index + 1] = Entry("page", page, page.title, L.PAGE)
	end
	for _, page in ipairs(window.pageOrder) do
		for _, section in ipairs(page.sections or {}) do
			local where = page.title
			if section.tab then
				where = where .. " › " .. section.tab.title
			end
			-- The section itself, ahead of its settings; it lands on the first one shown.
			local sectionEntry
			if section.title then
				sectionEntry = Entry("section", page, section.title, where, where)
				sectionEntry.settings = {}
				index[#index + 1] = sectionEntry
			end
			local settingWhere = section.title and (where .. " › " .. section.title) or where
			for _, line in ipairs(section.lines) do
				for slot = 1, 2 do
					local setting = line[slot]
					if type(setting) == "table" and setting.label then
						local description = type(setting.description) == "string" and setting.description or nil
						-- A tooltip given as text is searched with the description, without its color codes.
						if type(setting.tooltip) == "string" then
							local tooltip = setting.tooltip:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
							description = description and (description .. " " .. tooltip) or tooltip
						end
						local entry = Entry("setting", page, setting.label, settingWhere, settingWhere, setting.keywords,
							description)
						entry.setting = setting
						index[#index + 1] = entry
						if sectionEntry then
							table.insert(sectionEntry.settings, setting)
						end
					end
					-- An ordered list is found by its title and by each of its items' text, landing on the list.
					if type(setting) == "table" and setting.kind == "OrderedList" then
						local listWhere = setting.title and (settingWhere .. " › " .. setting.title) or settingWhere
						if setting.title and not setting.label then
							local entry = Entry("setting", page, setting.title, settingWhere, settingWhere, setting.keywords)
							entry.setting = setting
							index[#index + 1] = entry
							if sectionEntry then
								table.insert(sectionEntry.settings, setting)
							end
						end
						for _, item in ipairs(setting:OrderedItems()) do
							local entry = Entry("setting", page, item.text, listWhere, listWhere)
							entry.setting = setting
							index[#index + 1] = entry
						end
						if sectionEntry and not setting.label and not setting.title then
							table.insert(sectionEntry.settings, setting)
						end
					end
				end
			end
			if sectionEntry and #sectionEntry.settings == 0 then
				index[#index] = nil
			end
		end
	end
	for order, entry in ipairs(index) do
		entry.order = order
	end
	window.searchIndex = index

	return index
end

-- Matching ---------------------------------------------------------------------------------------------------

-- The word in its other spelling, the rest of it kept ("colours" gives "colors"), or nil when it has none. When
-- more than one start fits ("centered" starts both center and centered), the longest is the word's.
local function OtherSpelling(word)
	local bucket = spellingsByLetter[word:sub(1, 1)]
	if not bucket then
		return nil
	end
	local other, fitted = nil, 0
	for _, pair in ipairs(bucket) do
		for side = 1, 2 do
			local start = pair[side]
			if #start > fitted and word:sub(1, #start) == start then
				other, fitted = pair[3 - side] .. word:sub(#start + 1), #start
			end
		end
	end

	return other
end

-- Adds the other spelling of each of forms[first] to forms[last]: the whole word respelled, and, for a word typed
-- past the letters both spellings share ("colou", "centr"), the other spelling's start.
local function AddSpellings(forms, first, last)
	for index = first, last do
		local form = forms[index]
		local other = OtherSpelling(form)
		if other then
			forms[#forms + 1] = other
		end
		local bucket = spellingsByLetter[form:sub(1, 1)]
		if bucket and #form >= SPELLING_MIN then
			for _, pair in ipairs(bucket) do
				for side = 1, 2 do
					local start, rival = pair[side], pair[3 - side]
					if #form < #start and start:sub(1, #form) == form and rival:sub(1, #form) ~= form then
						forms[#forms + 1] = rival
					end
				end
			end
		end
	end
end

-- The forms a typed word may take: itself, its stem ("bars", "fading"), its other spelling ("colour", "color"),
-- and every word of a synonym group it names or is starting to name, in either spelling.
local function Forms(word)
	local forms = { word }
	if #word >= 5 then
		local stem = word:match("^(.-)ing$") or word:match("^(.-)es$") or word:match("^(.-)ed$")
		if stem and #stem >= 3 then
			forms[#forms + 1] = stem
		end
	end
	if #word >= 4 and word:sub(-1) == "s" then
		forms[#forms + 1] = word:sub(1, -2)
	end
	AddSpellings(forms, 1, #forms)
	local bases = #forms
	for _, group in ipairs(synonymGroups) do
		local named
		for _, member in ipairs(group) do
			for base = 1, bases do
				local form = forms[base]
				if member == form or (#form >= math.min(SYNONYM_MIN, #member) and member:sub(1, #form) == form) then
					named = true
				end
			end
		end
		if named then
			for _, member in ipairs(group) do
				forms[#forms + 1] = member
			end
		end
	end
	AddSpellings(forms, bases + 1, #forms)
	-- Each form once, since every entry's words are tried against all of them.
	local unique, seen = {}, {}
	for _, form in ipairs(forms) do
		if not seen[form] then
			seen[form] = true
			unique[#unique + 1] = form
		end
	end

	return unique
end

-- A word of the text starts with one of the forms. Returns the word's number and the form's length.
local function Find(forms, words)
	for number, word in ipairs(words) do
		for _, form in ipairs(forms) do
			if word:sub(1, #form) == form then
				return number, #form
			end
		end
	end
end

local function AllFound(query, words)
	for _, forms in ipairs(query) do
		if not Find(forms, words) then
			return false
		end
	end

	return true
end

-- The typed letters in order, close together: "shwclk" finds "Show Clock".
local function Fuzzy(text, needle)
	local at, first = 1, nil
	for index = 1, #needle do
		local found = text:find(needle:sub(index, index), at, true)
		if not found then
			return false
		end
		first = first or found
		at = found + 1
	end

	return at - first <= #needle + FUZZY_SLACK
end

-- The query's words that must match (filler is optional unless it is all there is), each with its forms; the typed
-- words joined and squeezed; and joined in their other spellings, or nil when no word has one.
local function Query(text)
	local words = Words(text)
	local query = {}
	for _, word in ipairs(words) do
		if not FILLER[word] then
			query[#query + 1] = Forms(word)
		end
	end
	if #query == 0 then
		for _, word in ipairs(words) do
			query[#query + 1] = Forms(word)
		end
	end
	local respelled, changed = {}, false
	for index, word in ipairs(words) do
		local other = OtherSpelling(word)
		respelled[index] = other or word
		changed = changed or other ~= nil
	end

	return query, Joined(words), table.concat(words), changed and Joined(respelled) or nil
end

-- How well an entry matches, best first: the label holds the query as typed (or in its other spelling); every word
-- is in the label (or its keywords); every word is in the label or where it lives; every word is somewhere, its
-- description included; the letters in order. Nil when it does not match.
local function Score(entry, query, phrase, squeezed, respelled)
	if #query == 0 then
		return nil
	end
	if entry.phrase:find(phrase, 1, true) or (respelled and entry.phrase:find(respelled, 1, true)) then
		return 5
	elseif AllFound(query, entry.own) then
		return 4
	elseif AllFound(query, entry.near) then
		return 3
	elseif AllFound(query, entry.all) then
		return 2
	elseif #squeezed >= FUZZY_MIN and Fuzzy(entry.squeezed, squeezed) then
		return 1
	end
end

local KIND_RANK = { page = 3, section = 2, setting = 1 }

-- Best score first; at a tie pages, then sections, then settings; then declaration order.
local function Better(a, b)
	if a.score ~= b.score then
		return a.score > b.score
	elseif KIND_RANK[a.kind] ~= KIND_RANK[b.kind] then
		return KIND_RANK[a.kind] > KIND_RANK[b.kind]
	end

	return a.order < b.order
end

---Finds what the search text names, in American or British spelling, best first: pages, sections and settings, by
---how well each matches.
---@return table entries
function lib.Window:FindSettings(text)
	local query, phrase, squeezed, respelled = Query(text)
	local scored = {}
	for _, entry in ipairs(self.searchIndex or BuildIndex(self)) do
		local visible = true
		if entry.kind == "setting" then
			visible = entry.setting:IsShown() or entry.setting:Revealable()
		elseif entry.kind == "section" then
			entry.setting = nil
			for _, setting in ipairs(entry.settings) do
				if setting:IsShown() or setting:Revealable() then
					entry.setting = setting
					break
				end
			end
			visible = entry.setting ~= nil
		end
		local score = visible and Score(entry, query, phrase, squeezed, respelled)
		if score then
			entry.score = score
			scored[#scored + 1] = entry
		end
	end
	table.sort(scored, Better)

	return scored, query, phrase
end

-- The label with each matched word's typed part in gold.
local function Marked(label, query)
	local lower = label:lower()
	local marked, last = {}, 1
	for start, word, finish in lower:gmatch("()([^%s%p]+)()") do
		local best = 0
		for _, forms in ipairs(query) do
			for _, form in ipairs(forms) do
				if #form > best and word:sub(1, #form) == form then
					best = #form
				end
			end
		end
		if best > 0 then
			marked[#marked + 1] = label:sub(last, start - 1) .. "|cffffd100" .. label:sub(start, start + best - 1) .. "|r"
			last = start + best
		end
	end
	marked[#marked + 1] = label:sub(last)

	return table.concat(marked)
end

-- Building ---------------------------------------------------------------------------------------------------

local function CreateResult(window, list)
	local result = CreateFrame("Button", nil, list.scroll.child)
	result:SetHeight(RESULT_HEIGHT)
	result.fill = result:CreateTexture(nil, "BACKGROUND")
	result.fill:SetAllPoints()
	result.fill:SetColorTexture(lib:Color("bronze", RESULT_ON_ALPHA))
	result.fill:Hide()
	result.label = result:CreateFontString(nil, "OVERLAY")
	lib:SetFont(result.label, "body", RESULT_SIZE)
	result.label:SetPoint("TOPLEFT", RESULT_PAD_X, -RESULT_PAD_Y)
	result.label:SetPoint("TOPRIGHT", -RESULT_PAD_X, -RESULT_PAD_Y)
	result.label:SetJustifyH("LEFT")
	result.label:SetWordWrap(false)
	result.label:SetHeight(17)
	result.where = result:CreateFontString(nil, "OVERLAY")
	lib:SetFont(result.where, "body", RESULT_SMALL)
	result.where:SetTextColor(lib:Color("secondary"))
	result.where:SetPoint("TOPLEFT", result.label, "BOTTOMLEFT")
	result.where:SetPoint("TOPRIGHT", result.label, "BOTTOMRIGHT")
	result.where:SetJustifyH("LEFT")
	result.where:SetWordWrap(false)
	result.where:SetHeight(15)
	result:SetScript("OnMouseDown", function(self) Handlers.Choose(window, self.entry) end)
	result:SetScript("OnEnter", function(self) Handlers.Highlight(window, self.index) end)

	return result
end

---Builds the search box above the sidebar, and its results list.
function lib.Window:BuildSearch()
	local frame = self.frame
	local box = CreateFrame("Frame", nil, frame)
	box:SetPoint("TOPLEFT", BOX_LEFT, -BOX_TOP)
	box:SetSize(BOX_WIDTH, BOX_HEIGHT)
	-- A square frame drawn from the cross-section of Blizzard's `common-dropdown-textholder` edge (the atlas's own
	-- beveled lip and chamfered corners read as stray lines on this taller box). A brighter copy shows while typing;
	-- a vertex color cannot brighten past the art.
	local function Art(path, sublevel)
		local art = box:CreateTexture(nil, "BACKGROUND", nil, sublevel)
		art:SetTexture(path)
		art:SetTextureSliceMargins(24, 24, 24, 24)
		if Enum.UITextureSliceMode then
			art:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
		end
		art:SetScale(0.5)
		art:SetAllPoints()

		return art
	end
	box.art = Art(BOX_ART, 0)
	box.focusArt = Art(BOX_ART_FOCUS, 1)
	box.focusArt:Hide()
	local icon = box:CreateTexture(nil, "ARTWORK")
	icon:SetAtlas("common-search-magnifyingglass")
	icon:SetSize(ICON_SIZE, ICON_SIZE)
	icon:SetPoint("TOPLEFT", BOX_BORDER + ICON_LEFT, -(BOX_BORDER + ICON_TOP))
	icon:SetAlpha(ICON_ALPHA)

	local input = CreateFrame("EditBox", nil, box)
	input:SetPoint("TOPLEFT", BOX_BORDER + INPUT_LEFT, -(BOX_BORDER + INPUT_TOP))
	input:SetPoint("TOPRIGHT", -BOX_BORDER, -(BOX_BORDER + INPUT_TOP))
	input:SetHeight(INPUT_HEIGHT)
	input:SetAutoFocus(false)
	lib:SetFont(input, "body", TEXT_SIZE)
	input:SetTextColor(1, 1, 1)
	input.placeholder = input:CreateFontString(nil, "OVERLAY")
	lib:SetFont(input.placeholder, "body", TEXT_SIZE)
	input.placeholder:SetTextColor(lib:Color("tertiary"))
	input.placeholder:SetPoint("LEFT")
	input.placeholder:SetText(L.SEARCH_SETTINGS)
	input:SetScript("OnTextChanged", function(_, userInput) Handlers.Changed(self, userInput) end)
	input:SetScript("OnEditFocusGained", function() box.focusArt:Show(); Handlers.Changed(self, true) end)
	input:SetScript("OnEditFocusLost", function() box.focusArt:Hide(); Handlers.FocusLost(self) end)
	input:SetScript("OnEscapePressed", function() input:ClearFocus() end)
	input:SetScript("OnEnterPressed", function() Handlers.Enter(self) end)
	input:SetScript("OnArrowPressed", function(_, key) Handlers.Arrow(self, key) end)
	box.input = input

	-- The results list: GameTooltip's frame over an opaque backing (the Bronze Hearth popup frame).
	local list = CreateFrame("Frame", nil, frame)
	list:SetPoint("TOPLEFT", LIST_LEFT, -LIST_TOP)
	list:SetWidth(LIST_WIDTH)
	list:SetFrameLevel(frame:GetFrameLevel() + 50)
	list:Hide()
	local backing = list:CreateTexture(nil, "BACKGROUND", nil, -8)
	backing:SetPoint("TOPLEFT", 3, -3)
	backing:SetPoint("BOTTOMRIGHT", -3, 3)
	backing:SetColorTexture(unpack(BACKING))
	list.NineSlice = CreateFrame("Frame", nil, list, "NineSlicePanelTemplate")
	list.NineSlice:SetAllPoints()
	NineSliceUtil.ApplyLayoutByName(list.NineSlice, "TooltipDefaultLayout")
	list.NineSlice:SetCenterColor(unpack(TOOLTIP_CENTER))
	-- On the list's own level, as GameTooltip's NineSlice is (useParentLevel), so its center never draws over the
	-- results.
	list.NineSlice:SetFrameLevel(list:GetFrameLevel())
	local scrollRegion = CreateFrame("Frame", nil, list)
	scrollRegion:SetPoint("TOPLEFT", 0, -LIST_PAD)
	scrollRegion:SetPoint("BOTTOMRIGHT", 0, LIST_PAD)
	scrollRegion:SetFrameLevel(list:GetFrameLevel() + 2)
	list.scroll = lib:CreateScroll(scrollRegion, { step = RESULT_HEIGHT, row = RESULT_HEIGHT, slim = true, inside = true })
	list.empty = list:CreateFontString(nil, "OVERLAY")
	lib:SetFont(list.empty, "body", RESULT_SIZE)
	list.empty:SetTextColor(lib:Color("secondary"))
	list.empty:SetPoint("TOPLEFT", RESULT_PAD_X, -(LIST_PAD + RESULT_PAD_Y))
	list.empty:SetText(L.NO_MATCHES)
	list.results = {}

	self.search = { box = box, input = input, list = list, hits = {}, at = 1 }
end

-- Results ----------------------------------------------------------------------------------------------------

function lib.Window:CloseSearch()
	if self.search then
		self.search.list:Hide()
	end
end

-- Lists what the text names, best match first (FindSettings).
function Handlers.Changed(window, userInput)
	local search = window.search
	local text = search.input:GetText()
	search.input.placeholder:SetShown(text == "")
	if not userInput then
		return
	end
	local list, hits = search.list, search.hits
	wipe(hits)
	if strtrim(text) == "" then
		list:Hide()
		return
	end
	local found, query = window:FindSettings(text)
	for index = 1, math.min(#found, MAX_RESULTS) do
		hits[index] = found[index]
	end
	search.at = 1
	for index, entry in ipairs(hits) do
		local result = list.results[index] or CreateResult(window, list)
		list.results[index] = result
		result.entry, result.index = entry, index
		result.label:SetText(Marked(entry.label, query))
		result.where:SetText(entry.where)
		result:ClearAllPoints()
		result:SetPoint("TOPLEFT", list.scroll.child, "TOPLEFT", 0, -(index - 1) * RESULT_HEIGHT)
		result:SetPoint("RIGHT", list.scroll.child, "RIGHT")
		result:Show()
	end
	for index = #hits + 1, #list.results do
		list.results[index]:Hide()
	end
	list.empty:SetShown(#hits == 0)
	local content = math.max(1, #hits) * RESULT_HEIGHT
	list:SetHeight(math.min(LIST_MAX, content) + 2 * LIST_PAD)
	list:Show()
	list.scroll:SetContentHeight(#hits * RESULT_HEIGHT)
	list.scroll:JumpTo(0)
	Handlers.Highlight(window, 1)
end

function Handlers.Highlight(window, at)
	local search = window.search
	search.at = at
	for index, result in ipairs(search.list.results) do
		result.fill:SetShown(index == at and result:IsShown())
	end
	if search.hits[at] then
		search.list.scroll:Reveal((at - 1) * RESULT_HEIGHT, RESULT_HEIGHT)
	end
end

function Handlers.Arrow(window, key)
	local search = window.search
	local count = #search.hits
	if count == 0 or not search.list:IsShown() then
		return
	end
	if key == "DOWN" then
		Handlers.Highlight(window, search.at % count + 1)
	elseif key == "UP" then
		Handlers.Highlight(window, (search.at - 2) % count + 1)
	end
end

function Handlers.Enter(window)
	local search = window.search
	local entry = search.list:IsShown() and search.hits[search.at]
	if entry then
		Handlers.Choose(window, entry)
	else
		search.input:ClearFocus()
	end
end

-- The list closes a moment after the box loses focus, so a click on a result still lands.
function Handlers.FocusLost(window)
	C_Timer.After(CLOSE_DELAY, function()
		if not window.search.input:HasFocus() then
			window:CloseSearch()
		end
	end)
end

-- Landing ----------------------------------------------------------------------------------------------------

function Handlers.Choose(window, entry)
	window:CloseSearch()
	window.search.input:ClearFocus()
	if entry.kind == "page" then
		window:SelectPage(entry.page.id)
		return
	end
	window:LandOn(entry.setting)
end

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
	view.scroll:GlideTo(half.top - LANDING_MARGIN)
	self:Flash(half)
end

local function FlashEdge(flash, first, second, horizontal)
	local edge = flash:CreateTexture(nil, "OVERLAY")
	edge:SetColorTexture(lib:Color("accent"))
	edge:SetPoint(first)
	edge:SetPoint(second)
	if horizontal then
		edge:SetHeight(FLASH_EDGE)
	else
		edge:SetWidth(FLASH_EDGE)
	end
end

---Flashes a row half (or, with `top` and `height`, a band of the page from `top`, such as a section): a gold outline
---and wash, held, then fading out. The flash stops if `region` leaves the page.
function lib.Window:Flash(half, top, height)
	local view = self.pageView
	local flash = view.flash
	if not flash then
		flash = CreateFrame("Frame", nil, view.scroll.child)
		local fill = flash:CreateTexture(nil, "ARTWORK")
		fill:SetAllPoints()
		fill:SetColorTexture(lib:Color("accent", FLASH_FILL))
		FlashEdge(flash, "TOPLEFT", "TOPRIGHT", true)
		FlashEdge(flash, "BOTTOMLEFT", "BOTTOMRIGHT", true)
		FlashEdge(flash, "TOPLEFT", "BOTTOMLEFT", false)
		FlashEdge(flash, "TOPRIGHT", "BOTTOMRIGHT", false)
		flash:SetScript("OnUpdate", Handlers.FlashUpdate)
		view.flash = flash
	end
	flash:ClearAllPoints()
	if top then
		flash:SetPoint("TOPLEFT", view.scroll.child, "TOPLEFT", 0, -top)
		flash:SetSize(half:GetWidth(), height)
	else
		flash:SetAllPoints(half)
	end
	flash:SetFrameLevel(half:GetFrameLevel() + 20)
	flash.half, flash.elapsed = half, 0
	flash:SetAlpha(1)
	flash:Show()
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
