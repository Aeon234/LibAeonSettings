-- Development harness: sample frames registered through the library, driven by /lasdev. Not packaged.

local ADDON_NAME = ...
local lib = LibStub("LibAeonSettings-1.0")

local Harness = {}

local function Print(message, ...)
	print("|cff9e754aLibAeonSettings dev:|r " .. message:format(...))
end

local function SampleFrame(name, width, height, label, r, g, b)
	local frame = CreateFrame("Frame", "LibAeonSettingsDev" .. name, UIParent)
	frame:SetSize(width, height)
	frame:SetClampedToScreen(false)
	local background = frame:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(r, g, b, 0.75)
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("CENTER")
	text:SetText(label)
	frame.text = text

	return frame
end

-- A size the harness keeps in the active profile, as an adopter would.
local function StoredSize(frame, name, minimum)
	return {
		min = minimum,
		get = function() return frame:GetSize() end,
		set = function(width, height)
			frame:SetSize(width, height)
			Harness:Profile()[name] = { width, height }
		end,
	}
end

local function RestoreSize(frame, name)
	local size = Harness:Profile()[name]
	if size then
		frame:SetSize(size[1], size[2])
	end
end

function Harness:CreateFrames()
	self.frames = {
		bar = SampleFrame("Bar", 600, 26, "Harness Bar (fixed edge: BOTTOM)", 0.08, 0.08, 0.1),
		unit = SampleFrame("Unit", 220, 48, "Harness Unit", 0.1, 0.35, 0.12),
		icon = SampleFrame("Icon", 40, 40, "Icon", 0.45, 0.3, 0.1),
	}
	self.frames.icon:SetScale(1.5)
	-- A border drawn 6 outside the unit frame, as Levelbound's bar border is: its mover covers the border.
	local border = CreateFrame("Frame", nil, self.frames.unit, "BackdropTemplate")
	border:SetPoint("TOPLEFT", -6, 6)
	border:SetPoint("BOTTOMRIGHT", 6, -6)
	border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
	border:SetBackdropBorderColor(0.9, 0.75, 0.3, 0.9)
	self.frames.unit.border = border
	-- A protected frame: a secure action button that targets the player when clicked.
	local secure = CreateFrame("Button", "LibAeonSettingsDevSecure", UIParent, "SecureActionButtonTemplate")
	secure:SetSize(140, 32)
	secure:RegisterForClicks("AnyUp", "AnyDown")
	secure:SetAttribute("type", "target")
	secure:SetAttribute("unit", "player")
	local secureBackground = secure:CreateTexture(nil, "BACKGROUND")
	secureBackground:SetAllPoints()
	secureBackground:SetColorTexture(0.45, 0.1, 0.1, 0.8)
	secure.text = secure:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	secure.text:SetPoint("CENTER")
	secure.text:SetText("Secure: target self")
	self.frames.secure = secure
	RestoreSize(self.frames.bar, "barSize")
	RestoreSize(self.frames.unit, "unitSize")
	self.targets = {
		{ key = "bar", label = "Harness Bar", frame = self.frames.bar, default = { point = "BOTTOM", x = 0, y = 120 },
			fixedEdge = "BOTTOM", size = StoredSize(self.frames.bar, "barSize", 40), attach = true, match = "width",
			grow = { "CENTER", "LEFT", "RIGHT" }, settings = { page = "bar" } },
		{ key = "unit", label = "Harness Unit", subtitle = "Sample while editing", frame = self.frames.unit,
			default = { point = "CENTER", x = -280, y = -120 },
			sample = function(shown) self.frames.unit.text:SetText(shown and "Harness Unit (sample)" or "Harness Unit") end,
			size = StoredSize(self.frames.unit, "unitSize", 20), attach = true, match = "both",
			outline = self.frames.unit.border, settings = { page = "controls", section = "sliders" } },
		{ key = "icon", label = "Harness Icon", frame = self.frames.icon, default = { point = "TOPRIGHT", x = -240, y = -200 },
			attach = true, settings = { page = "appearance", section = "look" },
			pinned = function() return Harness.pinIcon and "Pinned: /lasdev pin frees it." or nil end },
		{ key = "secure", label = "Secure Button", subtitle = "Protected", frame = self.frames.secure,
			default = { point = "LEFT", x = 240, y = -60 }, attach = true,
			settings = function(target) Print("Element Options for %s: an addon's own function runs instead", target.key) end },
	}
end

function Harness:Profile()
	local db = LibAeonSettingsDevDB
	db.profiles[db.profile] = db.profiles[db.profile] or {}

	return db.profiles[db.profile]
end

function Harness:Register()
	LibAeonSettingsDevDB = LibAeonSettingsDevDB or {}
	local db = LibAeonSettingsDevDB
	db.profile = db.profile or "Default"
	db.profiles = db.profiles or {}

	self:CreateFrames()
	self.registration = lib:Placement(ADDON_NAME, {
		title = "LibAeonSettings Harness",
		store = function() return Harness:Profile() end,
		account = function() return LibAeonSettingsDevDB end,
		targets = self.targets,
	})
	self:RegisterSecond()
	self.settings = lib:Settings(ADDON_NAME, {
		title = "LibAeonSettings Harness",
		version = "dev",
		store = function() return Harness:Profile() end,
		write = function(path, value) Harness:Write(path, value) end,
		account = function() return LibAeonSettingsDevDB end,
		footer = "|cffffd100Changes|r apply immediately",
	})
	self:DeclarePages()
end

-- Navigation shaped like Hearthline's, long enough to scroll: top-level pages, a header with groups of pages (some
-- with icons), a page directly under the header, dividers and pages after them.
function Harness:DeclarePages()
	local window = self.settings
	self:DeclareGeneral(window:Page("general", { title = "General",
		description = "A page without a switch: sections, notes, a custom row and enough lines to scroll." }))
	self:DeclareControls(window:Page("controls", { title = "Controls",
		description = "W3: every basic control, with refusals and a checkbox that makes the rest inactive." }))
	self:DeclareOverrides(window:Page("overrides", { title = "Overrides",
		description = "W5: Clock follows the Whole Bar until a setting is changed here." }))
	self:DeclareAppearance(window:Page("appearance", { title = "Appearance", switch = { path = "look.enabled", default = true },
		description = "W6: a preview shared by tabs that set the same things for different panels; its parts find their settings." }))
	self:DeclareBar(window:Page("bar", { title = "Bar", switch = { path = "bar.enabled", default = true },
		description = "A page with a switch: turning it off dims and desaturates everything below the header." }))
	window:Divider()
	window:Header("modules", "Modules")
	local groups = {
		{ "status", "Status", { "Clock", "System", "Durability & Item Level" } },
		{ "economy", "Economy", { "Gold & Bags", "Currencies" } },
		{ "character", "Character", { "Professions", "Specialization", "Great Vault" } },
		{ "shortcuts", "Shortcuts", { "Micro-Menu & Social", "Volume" } },
		{ "extra", "Extra (to scroll)", { "Test One", "Test Two", "Test Three", "Test Four", "Test Five" } },
	}
	for _, group in ipairs(groups) do
		window:Group(group[1], group[2], "modules")
		for index, title in ipairs(group[3]) do
			window:Page(group[1] .. index, { title = title, under = group[1],
				icon = index == 1 and "Interface\\Icons\\INV_Misc_PocketWatch_01" or nil, slot = true })
		end
	end
	window:Page("travel", { title = "Travel", under = "modules", icon = "Interface\\Icons\\INV_Misc_Rune_01" })
	window:Divider()
	window:Page("databroker", { title = "DataBroker" })
	self:DeclareProfiles(window)
end

-- W9: the Profiles page over the harness's own profiles, exported as CBOR, compressed and in base64.
local EXPORT_PREFIX, EXPORT_FORMAT = "!LAS", 1
local REPORT_ADDONS = { "Broker_Everything", "SavedInstances" } -- named in every export, for the import report

local function CharacterProfile()
	return ("%s - %s"):format(UnitName("player"), GetRealmName())
end

function Harness:UseProfile(name)
	LibAeonSettingsDevDB.profile = name
	self:Profile()
	self.registration:Apply()
end

function Harness:ProfileAdapter()
	local db = LibAeonSettingsDevDB
	local adapter = {}
	function adapter.List()
		Harness:Profile()
		local names = {}
		for name in pairs(db.profiles) do
			names[#names + 1] = name
		end
		return names
	end
	function adapter.Active() return db.profile end
	function adapter.Switch(name) Harness:UseProfile(name) end
	function adapter.New(name)
		db.profiles[name] = {}
		Harness:UseProfile(name)
	end
	function adapter.Copy(name)
		db.profiles[name] = CopyTable(Harness:Profile())
		Harness:UseProfile(name)
	end
	function adapter.Rename(name)
		db.profiles[name], db.profiles[db.profile] = db.profiles[db.profile], nil
		Harness:UseProfile(name)
	end
	function adapter.Delete(name, replacement)
		db.profiles[name] = nil
		Harness:UseProfile(replacement)
	end
	function adapter.Reset()
		wipe(Harness:Profile())
		Harness.registration:Apply()
	end
	function adapter.Export()
		local payload = { name = db.profile, profile = Harness:Profile(), addons = REPORT_ADDONS }
		local packed = C_EncodingUtil.CompressString(C_EncodingUtil.SerializeCBOR(payload))
		return ("%s%d!%s"):format(EXPORT_PREFIX, EXPORT_FORMAT, C_EncodingUtil.EncodeBase64(packed))
	end
	function adapter.Decode(text)
		local format, body = text:match("^" .. EXPORT_PREFIX .. "(%d+)!(.+)$")
		if not format then
			return nil, "This isn't a profile string."
		end
		if tonumber(format) > EXPORT_FORMAT then
			return nil, "This profile was made by a newer version of the harness."
		end
		local ok, payload = pcall(function()
			return C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecompressString(C_EncodingUtil.DecodeBase64(body)))
		end)
		if not ok or type(payload) ~= "table" or type(payload.profile) ~= "table" then
			return nil, "This profile string is damaged."
		end
		local missing = {}
		for _, addon in ipairs(type(payload.addons) == "table" and payload.addons or {}) do
			if not C_AddOns.IsAddOnLoaded(addon) then
				missing[#missing + 1] = tostring(addon)
			end
		end
		local report
		if #missing > 0 then
			local names = #missing == 1 and missing[1]
				or table.concat(missing, ", ", 1, #missing - 1) .. " and " .. missing[#missing]
			report = { ("%s %s installed or enabled here. %s settings come with the profile and work once %s enabled."):format(
				names, #missing == 1 and "isn't" or "aren't", #missing == 1 and "Its" or "Their",
				#missing == 1 and "it is" or "they are") }
		end
		return { name = tostring(payload.name or "Imported"), profile = payload.profile, report = report,
			summary = ("Harness profile \"%s\", format %s."):format(tostring(payload.name or ""), format) }
	end
	function adapter.Import(info, name)
		db.profiles[name] = CopyTable(info.profile)
		Harness:UseProfile(name)
	end
	function adapter.IsEditing() return Harness.layoutLock end
	function adapter.UsesCharacterProfile() return db.profile == CharacterProfile() end
	function adapter.SetUseCharacterProfile(on)
		Harness:UseProfile(on and CharacterProfile() or lib.DEFAULT_PROFILE)
	end
	return adapter
end

function Harness:DeclareProfiles(window)
	local page = window:ProfilesPage("profiles", { adapter = self:ProfileAdapter(),
		description = "W9: the harness's profiles. /lasdev lock stands in for editing the layout.",
		sections = function(profiles)
			profiles:Section("extra", "Harness Section"):Note("The addon's own sections sit between Active Profile and Manage.")
		end })
	local holds = page:Section("holds", "What a Profile Holds")
	holds:Note("In the profile, and in its export: every page's settings and the sample frames' positions.",
		"Not in profiles: the edit mode's grid and toolbar preferences, saved for the account.")
end

-- W2 test page: notes, hidden halves, a custom row and a long section for the content scroll.
function Harness:DeclareGeneral(page)
	local intro = page:Section("intro", "Introduction")
	intro:Note("Notes run across the section.", "A smaller second part sits under the note in the description color.")
	intro:Checkbox({ id = "extras", label = "Show Extras", path = "general.extras", default = false, keywords = "reveal hidden",
		description = "Shows the hidden settings below." })
	intro:Checkbox({ id = "plain", label = "Plain Setting", path = "general.plain", default = true })
	local extras = function() return Harness:Profile().general and Harness:Profile().general.extras end
	intro:Checkbox({ id = "extraLeft", label = "Extra Left (hidden half)", path = "general.extraLeft", show = extras })
	intro:Checkbox({ id = "visible", label = "Always Shown", path = "general.visible" })
	intro:Checkbox({ id = "extraA", label = "Extra A (whole line hidden)", path = "general.extraA", show = extras })
	intro:Checkbox({ id = "extraB", label = "Extra B (whole line hidden)", path = "general.extraB", show = extras })
	intro:Checkbox({ id = "after", label = "After the Hidden Line", path = "general.after" })

	local custom = page:Section("custom", "Custom Rows")
	custom:Custom({ id = "swatch", label = "Custom in a Half", width = 120, height = 24,
		create = function(area)
			area.texture = area:CreateTexture(nil, "ARTWORK")
			area.texture:SetAllPoints()
		end,
		refresh = function(area)
			local on = Harness:Profile().general and Harness:Profile().general.plain ~= false
			area.texture:SetColorTexture(on and 0.62 or 0.3, on and 0.46 or 0.3, on and 0.29 or 0.3, 1)
		end })
	custom:Skip()
	custom:Custom({ id = "wide", wide = true, height = 60,
		create = function(area)
			local background = area:CreateTexture(nil, "BACKGROUND")
			background:SetAllPoints()
			background:SetColorTexture(1, 1, 1, 0.05)
			local text = area:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			text:SetPoint("CENTER")
			text:SetText("A wide custom row with no label: the adopter draws across the line")
		end })

	local long = page:Section("long", "A Long Section")
	for index = 1, 24 do
		long:Checkbox({ id = "long" .. index, label = "Filler Setting " .. index, path = "general.long" .. index,
			description = index % 5 == 0 and "Every fifth one has a description." or nil })
	end
end

-- W5 test page: shared values and settings that follow them until overridden (◆/↺).
function Harness:DeclareOverrides(page)
	local shared = page:Section("shared", "Whole Bar")
	shared:Slider({ id = "size", label = "Font Size", path = "shared.size", default = 12, min = 8, max = 24 })
	shared:Dropdown({ id = "font", label = "Font", path = "shared.font", default = "Expressway", picker = "font" })
	shared:Dropdown({ id = "outline", label = "Outline", path = "shared.outline", default = "NONE", options = lib.OUTLINES })
	shared:Color({ id = "color", label = "Text Color", path = "shared.color", default = { r = 1, g = 1, b = 1 } })
	shared:Checkbox({ id = "labels", label = "Show Labels", path = "shared.labels", default = true })

	local function From(path)
		return { path = path, from = "Whole Bar" }
	end
	local clock = page:Section("clock", "Clock")
	clock:Slider({ id = "clockSize", label = "Font Size", path = "clock.size", min = 8, max = 24,
		inherits = From("shared.size") })
	clock:Dropdown({ id = "clockFont", label = "Font", path = "clock.font", picker = "font", inherits = From("shared.font") })
	clock:Dropdown({ id = "clockOutline", label = "Outline", path = "clock.outline", options = lib.OUTLINES,
		inherits = From("shared.outline"), description = "The six outline choices." })
	clock:Color({ id = "clockColor", label = "Text Color", path = "clock.color", inherits = From("shared.color") })
	clock:Checkbox({ id = "clockLabels", label = "Show Labels", path = "clock.labels", inherits = From("shared.labels") })
	clock:TextInput({ id = "clockFormat", label = "Time Format", path = "clock.format", default = "%H:%M",
		inherits = { path = "shared.format", from = "Whole Bar", default = "%H:%M" } })

	local actions = page:Section("actions", "Overrides")
	actions:Button({ id = "count", label = "Count Overrides", verb = "Count",
		run = function(setting)
			setting.window:ShowStatus(("%d overridden on this page."):format(setting.window:CountOverrides("overrides")))
		end })
	actions:Button({ id = "clear", label = "Clear Overrides", verb = "Clear",
		confirm = "Return every Clock setting to the Whole Bar's value?",
		run = function(setting)
			setting.window:ShowStatus(("%d overrides cleared."):format(setting.window:ClearOverrides("overrides")))
		end })
end

-- W6 test page: a preview (state pills, shrinking to fit with its caption) over tabs for Shared, Left and Right. Its
-- parts find their settings: a panel finds its tab's Color, a label its tab's Width and chooses that panel. A tick
-- counter runs while the preview shows and the page is on, so `stop` can be seen ending it.
function Harness:DeclareAppearance(page)
	local function Get(path)
		local value = Harness:Profile()
		for key in path:gmatch("[^.]+") do
			value = type(value) == "table" and value[key] or nil
		end
		return value
	end
	local function Panel(side)
		return {
			width = Get("look." .. side .. ".width") or Get("look.shared.width") or 240,
			color = Get("look." .. side .. ".color") or Get("look.shared.color") or { r = 0.62, g = 0.46, b = 0.29 },
		}
	end
	page:Preview({
		height = 84,
		states = function()
			local states = { "Normal" }
			if Get("look.fade") then
				states[#states + 1] = "Faded"
			end
			states[#states + 1] = "In Combat"
			return states
		end,
		create = function(canvas)
			canvas.panels = {}
			for index, side in ipairs({ "left", "right" }) do
				local panel = canvas:CreateTexture(nil, "ARTWORK")
				local text = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				text:SetPoint("CENTER", panel)
				text:SetText(side == "left" and "Left" or "Right")
				canvas.panels[index] = { texture = panel, text = text, side = side }
			end
			canvas.ticks = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			canvas.ticks:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 0, -2)
			canvas.tickCount = 0
		end,
		refresh = function(canvas, state, preview)
			local x, height, gap = 0, 32, 12
			for _, entry in ipairs(canvas.panels) do
				local panel = Panel(entry.side)
				entry.texture:ClearAllPoints()
				entry.texture:SetPoint("LEFT", canvas, "LEFT", x, 0)
				entry.texture:SetSize(panel.width, height)
				entry.texture:SetColorTexture(panel.color.r, panel.color.g, panel.color.b, state == "Faded" and 0.3 or 0.9)
				entry.texture:SetShown(state ~= "In Combat")
				entry.text:SetShown(state ~= "In Combat")
				preview:Part(entry.texture, entry.side .. "Color")
				preview:Part(entry.text, entry.side .. "Width", { text = true, key = entry.side })
				x = x + panel.width + gap
			end
			if not canvas.ticker then
				canvas.ticker = C_Timer.NewTicker(0.5, function()
					canvas.tickCount = canvas.tickCount + 1
					canvas.ticks:SetFormattedText("Ticks: %d", canvas.tickCount)
				end)
			end
			canvas.ticks:SetFormattedText("Ticks: %d", canvas.tickCount)
			return x - gap, height
		end,
		stop = function(canvas)
			if canvas.ticker then
				canvas.ticker:Cancel()
				canvas.ticker = nil
			end
		end,
		pick = function(key, preview)
			preview.page.window:ShowStatus(("Chose the %s panel."):format(key))
		end,
		caption = function(state, scale)
			if state == "In Combat" then
				return "Hidden in combat; it returns when combat ends."
			elseif scale < 0.999 then
				return ("Shown at %d%% to fit; on screen it is 100%%."):format(scale * 100 + 0.5)
			end
		end,
	})

	local shared = page:Tab("shared", "Shared")
	local look = shared:Section("look", "Panels")
	look:Slider({ id = "width", label = "Width", path = "look.shared.width", default = 240, min = 60, max = 900, step = 10,
		description = "Past about 480 each, the preview shrinks to fit." })
	look:Color({ id = "color", label = "Color", path = "look.shared.color", default = { r = 0.62, g = 0.46, b = 0.29 } })
	look:Checkbox({ id = "fade", label = "Fade Out", path = "look.fade", description = "Adds a Faded pill to the preview." })
	for _, side in ipairs({ { "left", "Left" }, { "right", "Right" } }) do
		local tab = page:Tab(side[1], side[2], { countOverrides = true })
		local section = tab:Section(side[1] .. "Look", side[2] .. " Panel")
		section:Slider({ id = side[1] .. "Width", label = "Width", path = "look." .. side[1] .. ".width", min = 60,
			max = 900, step = 10, inherits = { path = "look.shared.width", from = "Shared" } })
		section:Color({ id = side[1] .. "Color", label = "Color", path = "look." .. side[1] .. ".color",
			inherits = { path = "look.shared.color", from = "Shared" } })
		-- A section menu: copies the other panel's own settings over this one's, after asking.
		local other = side[1] == "left" and { "right", "Right Panel" } or { "left", "Left Panel" }
		section:Menu({ id = side[1] .. "Copy", placeholder = "Copy From", width = 170, action = true, verb = "Copy",
			titleCase = false,
			options = { { value = other[1], text = other[2] },
				{ value = "hidden", text = "Hidden Panel", blocked = "It has no settings to copy." } },
			blocked = function()
				local look = Harness:Profile().look
				if not (look and look[other[1]] and next(look[other[1]])) then
					return ("The %s has no settings of its own."):format(other[2])
				end
			end,
			confirm = function(value)
				return ("Replace the %s Panel's settings with the %s's?"):format(side[2], other[2])
			end,
			set = function(value, setting)
				local look = Harness:Profile().look
				look[side[1]] = CopyTable(look[value])
				setting.window:Refresh()
				setting.window:ShowStatus(("Copied the %s's settings."):format(other[2]))
			end })
	end
end

-- W2 test page (checkboxes since W3): the page switch, a depends chain, blocked() and a refused save.
function Harness:DeclareBar(page)
	local behavior = page:Section("behavior", "Behavior")
	behavior:Checkbox({ id = "fade", label = "Fade Out", path = "bar.fade", default = false,
		description = "The next two depend on this one, the second through the first." })
	behavior:Checkbox({ id = "fadeDelay", label = "Delay the Fade", path = "bar.fadeDelay", default = false,
		depends = "fade" })
	behavior:Checkbox({ id = "fadeInstant", label = "Fade Instantly", path = "bar.fadeInstant", depends = "fadeDelay" })
	behavior:Checkbox({ id = "locked", label = "Locked", path = "bar.locked",
		blocked = function() return Harness.blocked and "Blocked by the harness (/lasdev block)." end })
	behavior:Checkbox({ id = "refuses", label = "Refuses to Save", wide = true,
		get = function() return false end,
		set = function() return false, "The harness refuses this one." end })
	behavior:Checkbox({ id = "otherPage", label = "Follows General", path = "bar.otherPage",
		depends = "general/plain" })
end

-- A sound picker's own sounds, Blizzard sound kits; LibSharedMedia's sounds follow them in the list.
local SAMPLE_SOUNDS = {
	{ value = "none", text = "None" },
	{ value = "raidWarning", text = "Raid Warning", soundKit = SOUNDKIT.RAID_WARNING },
	{ value = "readyCheck", text = "Ready Check", soundKit = SOUNDKIT.READY_CHECK },
	{ value = "whisper", text = "Whisper", soundKit = SOUNDKIT.TELL_MESSAGE },
	{ value = "alarmClock", text = "Alarm Clock", soundKit = SOUNDKIT.ALARM_CLOCK_WARNING_3 },
	{ value = "questComplete", text = "Quest Complete", soundKit = SOUNDKIT.IG_QUEST_LIST_COMPLETE },
}

-- W3 test page: checkboxes, sliders, dropdowns, text inputs and buttons.
function Harness:DeclareControls(page)
	local function Value(key)
		local controls = Harness:Profile().controls
		return controls and controls[key]
	end

	local checkboxes = page:Section("checkboxes", "Checkboxes")
	checkboxes:Checkbox({ id = "active", label = "Controls Active", path = "controls.active", default = true,
		description = "Everything in the Inactive section depends on this." })
	checkboxes:Checkbox({ id = "refuseCheck", label = "Refuses to Save", get = function() return false end,
		set = function() return false, "The harness refuses this one." end })
	-- Tooltips on the label: text with line breaks and colors, one worked out on each hover, and cut-off lines.
	checkboxes:Checkbox({ id = "announce", label = "Announce Level-Ups", path = "controls.announce",
		tooltip = "Posts your level-ups to chat.\nChannels: |cffaaaaffParty|r, |cff40ff40Guild|r.", keywords = "chat" })
	checkboxes:Checkbox({ id = "liveTip", label = "Live Tooltip", path = "controls.liveTip",
		tooltip = function(setting)
			return ("Built on hover: it is %s, and the box is %s."):format(date("%H:%M:%S"),
				setting:GetValue() and "ticked" or "unticked")
		end })
	checkboxes:Checkbox({ id = "longLabel", label = "A Label Long Enough That The Row Has To Cut It Off Somewhere",
		path = "controls.longLabel",
		description = "A description long enough that the line under the label is cut off too, so hovering shows it whole." })
	checkboxes:Checkbox({ id = "longReason", label = "Long Reason", path = "controls.longReason",
		blocked = function()
			return "Unavailable while the harness pretends something long and complicated is going on somewhere."
		end })

	local sliders = page:Section("sliders", "Sliders")
	sliders:Slider({ id = "size", label = "Font Size", path = "controls.size", default = 12, min = 8, max = 32 })
	sliders:Slider({ id = "scale", label = "Scale", path = "controls.scale", default = 1, min = 0.5, max = 2,
		step = 0.1, format = "decimal" })
	sliders:Slider({ id = "alpha", label = "Opacity", path = "controls.alpha", default = 80, min = 0, max = 100,
		step = 5, format = "percent", description = "Typed as 55 or 55%." })
	sliders:Slider({ id = "capped", label = "Refuses Above 50", path = "controls.capped", default = 20, min = 0,
		max = 100, set = function(value)
			if value > 50 then
				return false, "It can't go above 50."
			end
			Harness:Profile().controls = Harness:Profile().controls or {}
			Harness:Profile().controls.capped = value
		end, get = function() return Value("capped") or 20 end })

	sliders:Slider({ id = "screenWidth", label = "Bar Width", path = "controls.screenWidth", default = 400, min = 100,
		max = function() return math.floor(UIParent:GetWidth()) end, step = 10,
		description = "Up to the screen's width, worked out on each redraw." })

	-- One set of rows for whichever slot is picked: the Slot dropdown is session state marked `redraws`, so picking
	-- a slot redraws the rows below with that slot's values.
	local slots = page:Section("slots", "Picked Slot")
	local function SlotValues()
		local controls = Harness:Profile().controls or {}
		Harness:Profile().controls = controls
		controls.slots = controls.slots or {}
		local key = Harness.pickedSlot or "left"
		controls.slots[key] = controls.slots[key] or {}
		return controls.slots[key]
	end
	slots:Dropdown({ id = "slot", label = "Slot", redraws = true, titleCase = false,
		options = function()
			local list = {}
			for _, key in ipairs({ "left", "center", "right" }) do
				local values = (Harness:Profile().controls or {}).slots
				local text = values and values[key] and values[key].text
				list[#list + 1] = { value = key, text = ("%s: %s"):format(key:gsub("^%l", string.upper), text or "empty") }
			end
			return list
		end,
		get = function() return Harness.pickedSlot or "left" end,
		set = function(value) Harness.pickedSlot = value end })
	slots:TextInput({ id = "slotText", label = "Text", default = "", allowEmpty = true,
		get = function() return SlotValues().text end, set = function(value) SlotValues().text = value end })
	slots:Slider({ id = "slotSize", label = "Size", default = 12, min = 6, max = 32,
		get = function() return SlotValues().size end, set = function(value) SlotValues().size = value end })

	local dropdowns = page:Section("dropdowns", "Dropdowns")
	dropdowns:Dropdown({ id = "format", label = "Text Format", path = "controls.format", default = "current",
		description = "Choices written in lower case show in Title Case.",
		options = {
			{ value = "current", text = "current" },
			{ value = "currentMax", text = "current / max" },
			{ value = "percent", text = "percent of max" },
			{ value = "hidden", text = "hidden", blocked = "Requires a text slot to be free." },
		} })
	dropdowns:Dropdown({ id = "long", label = "Long List", path = "controls.long", default = 15,
		description = "Scrolls past 20, opening on the saved choice.",
		options = function()
			local list = { { title = true, text = "Numbers" } }
			for index = 1, 40 do
				list[#list + 1] = { value = index, text = "choice number " .. index }
			end
			return list
		end })
	dropdowns:Dropdown({ id = "font", label = "Font", path = "controls.font", default = "Expressway", picker = "font" })
	dropdowns:Dropdown({ id = "outline", label = "Outline", path = "controls.outline", default = "SLUG_OUTLINE",
		options = lib.OUTLINES })
	dropdowns:Dropdown({ id = "texture", label = "Bar Texture", path = "controls.texture", default = "Blizzard",
		picker = "texture" })
	dropdowns:Dropdown({ id = "sound", label = "Alert Sound", path = "controls.sound", default = "raidWarning",
		picker = "sound", options = SAMPLE_SOUNDS })
	dropdowns:Dropdown({ id = "growth", label = "Growth", path = "controls.growth", default = "up", width = "fit",
		description = "Fits its two choices.", options = { { value = "up", text = "up" }, { value = "down", text = "down" } } })

	local texts = page:Section("texts", "Text Inputs")
	local nameFormat = texts:TextInput({ id = "nameFormat", label = "Name Format", path = "controls.nameFormat",
		default = "[name]",
		validate = function(text)
			if not text:find("%[%a+%]") then
				return "It needs a tag in brackets, such as [name]."
			end
		end })
	-- An action: puts the tag where Name Format's cursor last was. Undo records the insertion on Name Format.
	texts:Dropdown({ id = "insertTag", label = "Insert Tag", placeholder = "Insert Tag", titleCase = false, action = true,
		options = {
			{ title = true, text = "Unit" },
			{ value = "[name]", text = "[name]", tooltip = "The unit's name." },
			{ value = "[level]", text = "[level]", tooltip = "The unit's level." },
			{ title = true, text = "Text" },
			{ value = "[Ñame]", text = "[Ñame]", tooltip = "A tag with a two-byte letter, for counting characters." },
		},
		set = function(tag) nameFormat:InsertText(tag) end })
	texts:TextInput({ id = "welcome", label = "Welcome Message", path = "controls.welcome",
		default = "Welcome back!", allowEmpty = true, description = "May be empty: the default shows gray." })
	texts:TextInput({ id = "profileName", label = "Profile Name", path = "controls.profileName", default = "Default",
		maxLetters = 24 })

	local buttons = page:Section("buttons", "Buttons")
	buttons:Button({ id = "test", label = "Test Message", verb = "Show Test",
		run = function(setting) setting.window:ShowStatus("Test message shown.") end })
	buttons:Button({ id = "delete", label = "Delete Profile", verb = "Delete",
		confirm = "Delete the profile \"Default\"? Its settings will be lost.",
		run = function(setting) setting.window:ShowStatus("Nothing was really deleted.") end })
	buttons:Button({ id = "fail", label = "Failing Action", verb = "Reset Position",
		run = function() return false, "The harness frame is missing." end })

	local colors = page:Section("colors", "Colors & Swatches")
	colors:Color({ id = "textColor", label = "Text Color", path = "controls.textColor",
		default = { r = 1, g = 0.82, b = 0 }, classColor = { path = "controls.textClass", default = false } })
	colors:Color({ id = "background", label = "Background", path = "controls.background", hasOpacity = true,
		default = { r = 0, g = 0, b = 0, a = 0.5 }, description = "With opacity: the checkerboard shows through." })
	colors:Color({ id = "noRed", label = "Refuses Red", path = "controls.noRed", default = { r = 0.2, g = 0.6, b = 1 },
		set = function(value)
			if value.r > 0.6 and value.g < 0.4 then
				return false, "Red is not allowed here."
			end
			Harness:Profile().controls = Harness:Profile().controls or {}
			Harness:Profile().controls.noRed = value
		end, get = function() return Value("noRed") end })
	colors:Note("The class color here: " .. ("|cff%02x%02x%02x%s|r"):format(
		math.floor(select(1, lib:ClassColor()) * 255), math.floor(select(2, lib:ClassColor()) * 255),
		math.floor(select(3, lib:ClassColor()) * 255), UnitClass("player") or "?"))

	local inactive = page:Section("inactive", "Inactive")
	inactive:Slider({ id = "deadSlider", label = "Slider", path = "controls.deadSlider", default = 4, min = 0, max = 10,
		depends = "active" })
	inactive:Dropdown({ id = "deadDropdown", label = "Dropdown", path = "controls.deadDropdown", default = "OUTLINE",
		options = lib.OUTLINES, depends = "active" })
	inactive:Dropdown({ id = "deadSound", label = "Sound", path = "controls.deadSound", default = "readyCheck",
		picker = "sound", options = SAMPLE_SOUNDS, depends = "active" })
	inactive:TextInput({ id = "deadText", label = "Text Input", path = "controls.deadText", default = "text",
		depends = "active" })
	inactive:Button({ id = "deadButton", label = "Button", verb = "Delete", confirm = "Close me by unchecking Controls Active.",
		run = function() end, depends = "active" })
	inactive:Checkbox({ id = "deadCheck", label = "Checkbox", path = "controls.deadCheck", depends = "active" })
	inactive:Color({ id = "deadColor", label = "Color", path = "controls.deadColor", hasOpacity = true,
		default = { r = 0.62, g = 0.46, b = 0.29, a = 0.7 }, depends = "active" })
end

-- A second registration under its own name stands in for another adopting addon: its own frames, its own saved
-- table, and the same account preferences.
local SECOND_NAME = "LibAeonSettingsDevSecond"

function Harness:RegisterSecond()
	local db = LibAeonSettingsDevDB
	db.second = db.second or {}
	local panel = SampleFrame("SecondPanel", 260, 60, "Second Addon Panel", 0.3, 0.12, 0.35)
	local tag = SampleFrame("SecondTag", 120, 24, "Second Tag", 0.12, 0.2, 0.4)
	local function Size(frame, name)
		return {
			min = 20,
			get = function() return frame:GetSize() end,
			set = function(width, height) frame:SetSize(width, height); db.second[name] = { width, height } end,
		}
	end
	for frame, name in pairs({ [panel] = "panelSize", [tag] = "tagSize" }) do
		local size = db.second[name]
		if size then
			frame:SetSize(size[1], size[2])
		end
	end
	self.second = lib:Placement(SECOND_NAME, {
		title = "Second Harness",
		store = db.second,
		account = function() return LibAeonSettingsDevDB end,
		targets = {
			{ key = "panel", label = "Second Panel", frame = panel, default = { point = "TOP", x = 0, y = -260 },
				size = Size(panel, "panelSize"), attach = true, match = "both" },
			{ key = "tag", label = "Second Tag", frame = tag, default = { point = "LEFT", x = 120, y = 60 },
				size = Size(tag, "tagSize"), attach = true, match = "width" },
		},
	})
end

-- Dragging the sample frames directly stands in for the mover until the edit mode exists; each drop stores the
-- frame through Capture, which is what this slice checks.
function Harness:SetDragging(enabled)
	self.dragging = enabled
	for key, frame in pairs(self.frames) do
		frame:SetMovable(enabled)
		frame:EnableMouse(enabled)
		if enabled then
			frame:RegisterForDrag("LeftButton")
			frame:SetScript("OnDragStart", function(f) f:SetDontSavePosition(true); f:StartMoving() end)
			frame:SetScript("OnDragStop", function(f)
				f:StopMovingOrSizing()
				local position = Harness.registration:Capture(key)
				if position then
					Print("%s stored %s %.1f %.1f", key, position.point, position.x, position.y)
				end
			end)
		else
			frame:SetScript("OnDragStart", nil)
			frame:SetScript("OnDragStop", nil)
		end
	end
end

function Harness:Show()
	Print("profile %s", LibAeonSettingsDevDB.profile)
	for _, target in ipairs(self.targets) do
		local stored = self.registration:Read(target.key)
		local point, _, relativePoint, x, y = target.frame:GetPoint(1)
		Print("%s: stored %s | anchored %s %s %.1f %.1f | scale %.2f", target.key,
			stored and ("%s %.1f %.1f"):format(stored.point, stored.x, stored.y) or "default",
			tostring(point), tostring(relativePoint), x or 0, y or 0, target.frame:GetScale())
	end
end

local COMMANDS = {}

function COMMANDS.move()
	Harness:SetDragging(not Harness.dragging)
	Print("dragging %s", Harness.dragging and "on: drag a sample frame, its position is captured on release" or "off")
end

function COMMANDS.show()
	Harness:Show()
end

function COMMANDS.set(key, point, x, y)
	x, y = tonumber(x), tonumber(y)
	if not Harness.registration:Target(key or "") or not point or not x or not y then
		Print("usage: /lasdev set <bar|unit|icon> <POINT> <x> <y>")
		return
	end
	Harness.registration:Write(key, { point = point:upper(), x = x, y = y })
	Harness.registration:Apply()
	Harness:Show()
end

function COMMANDS.reset(key)
	for _, target in ipairs(Harness.targets) do
		if not key or key == "" or key == target.key then
			Harness.registration:Reset(target.key)
		end
	end
	Harness:Show()
end

function COMMANDS.profile(name)
	if not name or name == "" then
		Print("usage: /lasdev profile <name>")
		return
	end
	LibAeonSettingsDevDB.profile = name
	Harness.registration:Apply()
	-- A profile switch is not undoable and empties the settings window's Undo history.
	Harness.settings:ClearUndo()
	Harness.settings:Refresh()
	Harness:Show()
end

function COMMANDS.off(key)
	if not Harness.registration:Target(key or "") then
		Print("usage: /lasdev off <bar|unit|icon>")
		return
	end
	Harness.registration:Write(key, { point = "CENTER", x = 5000, y = 0 })
	Harness.registration:Apply()
	Print("%s stored off-screen; it should be drawn in view and keep that stored value:", key)
	Harness:Show()
end

function COMMANDS.scale(key, value)
	local target = Harness.registration:Target(key or "")
	value = tonumber(value)
	if not target or not value or value <= 0 then
		Print("usage: /lasdev scale <bar|unit|icon> <scale>")
		return
	end
	target.frame:SetScale(value)
	Harness.registration:ApplyTarget(target)
	Harness:Show()
end

function COMMANDS.bad()
	local scratch = Harness.scratch or SampleFrame("Scratch", 30, 30, "", 0.6, 0.1, 0.1)
	Harness.scratch = scratch
	scratch:Hide()
	lib:Placement("LibAeonSettingsBadExample", {
		title = "Bad example",
		store = {},
		mystery = true,
		targets = {
			{ key = "one", frame = scratch, default = { point = "MIDDLE", x = 0, y = 0 } },
			{ key = "two", frame = scratch, default = { point = "CENTER", x = 0, y = 0 }, shade = true },
		},
	})
	Print('registered a declaration with three problems (unknown field "mystery", a bad default, unknown field "shade"); each should appear as a reported error')
end

function COMMANDS.edit(which)
	lib:OpenEditMode(which == "second" and SECOND_NAME or ADDON_NAME)
end

-- Stands in for dragging until movers exist: shifts a frame by a pending (unsaved) offset during edit mode.
function COMMANDS.pend(key, dx, dy)
	local target = Harness.registration:Target(key or "")
	dx, dy = tonumber(dx), tonumber(dy)
	if not target or not dx or not dy then
		Print("usage: /lasdev pend <bar|unit|icon> <dx> <dy> (during edit mode)")
		return
	end
	if not lib:IsEditing() then
		Print("open edit mode first: /lasdev edit")
		return
	end
	local position = Harness.registration:Measure(target)
	position.x, position.y = position.x + dx, position.y + dy
	lib:SetPending(ADDON_NAME, key, position)
	Print("%s pending %s %.1f %.1f (unsaved: %s)", key, position.point, position.x, position.y, tostring(lib:IsDirty()))
end

function COMMANDS.hide(key)
	local target = Harness.registration:Target(key or "")
	if not target then
		Print("usage: /lasdev hide <bar|unit|icon> (toggles the frame; hidden frames get no mover)")
		return
	end
	target.frame:SetShown(not target.frame:IsShown())
	if lib.RefreshMovers then
		lib:RefreshMovers()
	end
	Print("%s %s", key, target.frame:IsShown() and "shown" or "hidden")
end

-- Protected-frame checks: in combat a change to the secure button (or to a frame attached to it) waits, and
-- lands when combat ends.
function COMMANDS.combat(key, dx, dy)
	key = key or "secure"
	local target = Harness.registration:Target(key)
	dx, dy = tonumber(dx) or 40, tonumber(dy) or 0
	if not target then
		Print("usage: /lasdev combat [key] [dx] [dy] (default: secure 40 0)")
		return
	end
	local position = Harness.registration:Measure(target)
	position.x, position.y = position.x + dx, position.y + dy
	Harness.registration:Write(key, position)
	Harness.registration:Apply()
	Print("%s moved by %d, %d; in combat: %s; waiting for the end of combat: %d", key, dx, dy,
		tostring(InCombatLockdown()), lib:DeferredCount())
end

-- The sound round: plays a sound kit by its SOUNDKIT name or number, on the Master channel as EllesmereUI's unlock
-- sound plays, to audition candidates for the edit mode's sounds.
function COMMANDS.sound(which)
	local kit = which and (tonumber(which) or SOUNDKIT[which:upper()])
	if not kit then
		Print("usage: /lasdev sound <SOUNDKIT name or number>, e.g. UI_DRAGONRIDING_FULL_NODE or 856")
		return
	end
	PlaySound(kit, "Master")
	Print("played %s (%d)", which, kit)
end

-- Icon pass: every atlas and file the library draws, checked in this client, and its own art laid out on one sheet.
local ICON_ATLASES = {
	"checkbox-minimal", "common-button-list-small-selected", "common-icon-undo", "common-radiobutton-circle",
	"common-radiobutton-dot", "common-search-magnifyingglass", "common-sidetab", "Options_HorizontalDivider",
	"Options_InnerFrame",
}
for _, prefix in ipairs({ "Options_Tab_", "Options_Tab_Active_" }) do
	for _, part in ipairs({ "Left", "Middle", "Right" }) do
		table.insert(ICON_ATLASES, prefix .. part)
	end
end
for _, kit in ipairs({ "editmode-actionbar-highlight", "editmode-actionbar-selected" }) do
	for _, piece in ipairs({ "%s-NineSlice-Corner", "_%s-NineSlice-EdgeTop", "_%s-NineSlice-EdgeBottom",
		"!%s-NineSlice-EdgeLeft", "!%s-NineSlice-EdgeRight", "%s-NineSlice-Center" }) do
		table.insert(ICON_ATLASES, piece:format(kit))
	end
end
-- The metal pieces the frame shadows recognize (they are only compared, never drawn).
for _, piece in ipairs({ "ui-frame-metal-cornertopleft", "ui-frame-portraitmetal-cornertopleft",
	"ui-frame-portraitmetal-cornertopleftsmall", "ui-frame-metal-cornertopright", "ui-frame-metal-cornertoprightdouble",
	"ui-frame-metal-cornerbottomleft", "ui-frame-metal-cornerbottomright", "_ui-frame-metal-edgetop",
	"_ui-frame-metal-edgebottom", "!ui-frame-metal-edgeleft", "!ui-frame-metal-edgeright" }) do
	table.insert(ICON_ATLASES, piece)
end
local ICON_FILES = {
	"Interface\\QuestFrame\\UI-QuestTitleHighlight", "Interface\\ChatFrame\\ChatFrameExpandArrow",
	"Interface\\Buttons\\WHITE8X8",
}
-- The library's own art, as shown on the sheet.
local ICON_MEDIA = {
	{ "icon-grid-dim" }, { "icon-grid-bright" }, { "icon-grid-off" }, { "icon-dark-overlays-on" }, { "icon-dark-overlays-off" },
	{ "icon-snap-on" }, { "icon-snap-off" }, { "icon-coordinates-on" }, { "icon-coordinates-off" },
	{ "icon-hover-top-bar-on" }, { "icon-hover-top-bar-off" }, { "icon-addons-on" }, { "icon-addons-off" },
	{ "icon-cog-on" }, { "chevron" }, { "override-diamond" }, { "nav-hover" },
	{ "swatch-checker" }, { "toggle-track" }, { "search-box" }, { "search-box-focus" }, { "mover-fill" },
	{ "mover-frame" }, { "anchor-line" }, { "pulse" }, { "shadow-glow" }, { "shadow-round" },
}
for _, size in ipairs({ 2, 4, 6, 8, 10 }) do
	for _, piece in ipairs({ "cornertopleft", "portraitcornertopleft", "portraitcornertopleftsmall", "cornertopright",
		"cornertoprightdouble", "cornerbottomleft", "cornerbottomright", "edgetop", "edgebottom", "edgeleft", "edgeright" }) do
		table.insert(ICON_MEDIA, { ("shadow-metal-%s-%d"):format(piece, size), nil, true })
	end
	table.insert(ICON_MEDIA, { ("shadow-shape-sidetab-%d"):format(size), nil, true })
	table.insert(ICON_MEDIA, { ("shadow-shape-sidetab-retail-%d"):format(size), nil, true })
end

local function IconSheet()
	if Harness.iconSheet then
		return Harness.iconSheet
	end
	local sheet = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	sheet:SetFrameStrata("DIALOG")
	sheet:SetPoint("CENTER")
	sheet:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	sheet:SetBackdropColor(0.08, 0.07, 0.06, 0.95)
	sheet:SetBackdropBorderColor(0.52, 0.41, 0.32)
	sheet:EnableMouse(true)
	sheet:SetMovable(true)
	sheet:RegisterForDrag("LeftButton")
	sheet:SetScript("OnDragStart", sheet.StartMoving)
	sheet:SetScript("OnDragStop", sheet.StopMovingOrSizing)
	local close = CreateFrame("Button", nil, sheet, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	local title = sheet:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText("LibAeonSettings art")
	local columns, cell, gap = 6, 96, 6
	local index = 0
	for _, entry in ipairs(ICON_MEDIA) do
		if not entry[3] then
			local column, row = index % columns, math.floor(index / columns)
			index = index + 1
			local swatch = sheet:CreateTexture(nil, "BACKGROUND", nil, 1)
			swatch:SetColorTexture(0.2, 0.2, 0.2, 1)
			swatch:SetSize(48, 48)
			swatch:SetPoint("TOPLEFT", 12 + column * (cell + gap) + (cell - 48) / 2, -34 - row * (cell - 20 + gap))
			local art = sheet:CreateTexture(nil, "ARTWORK")
			art:SetAllPoints(swatch)
			art:SetTexture(lib.mediaPath .. "Textures\\" .. entry[1])
			local label = sheet:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			label:SetPoint("TOP", swatch, "BOTTOM", 0, -2)
			label:SetWidth(cell)
			label:SetText(entry[1])
		end
	end
	local rows = math.ceil(index / columns)
	sheet:SetSize(24 + columns * (cell + gap) - gap, 44 + rows * (cell - 20 + gap))
	Harness.iconSheet = sheet

	return sheet
end

function COMMANDS.icons()
	local probe = Harness.iconProbe or UIParent:CreateTexture()
	Harness.iconProbe = probe
	local missing, atlases, files = {}, 0, 0
	for _, atlas in ipairs(ICON_ATLASES) do
		atlases = atlases + 1
		if not C_Texture.GetAtlasInfo(atlas) then
			table.insert(missing, "atlas " .. atlas)
		end
	end
	local function File(path, label)
		files = files + 1
		probe:SetTexture(nil)
		if not probe:SetTexture(path) then
			table.insert(missing, "file " .. label)
		end
	end
	for _, path in ipairs(ICON_FILES) do
		File(path, path)
	end
	for _, entry in ipairs(ICON_MEDIA) do
		File(lib.mediaPath .. "Textures\\" .. entry[1], entry[1])
	end
	Print("icons: %d atlases and %d files checked, %d missing (client %s)", atlases, files, #missing,
		(GetBuildInfo()) .. "." .. select(2, GetBuildInfo()))
	for _, line in ipairs(missing) do
		Print("  missing %s", line)
	end
	local sheet = IconSheet()
	sheet:SetShown(not sheet:IsShown())
end

-- Edit mode's screen tint at another strength, to compare (the library's is 25 %). Lasts until /reload.
function COMMANDS.tint(percent)
	local tint = lib.ui and lib.ui.tint
	if not tint then
		Print("open edit mode once first (/lasdev edit), then /lasdev tint <percent>")
		return
	end
	percent = tonumber(percent)
	if not percent then
		Print("usage: /lasdev tint <0-100>, e.g. 25 (the library's), 20, 30")
		return
	end
	percent = math.floor(math.max(0, math.min(100, percent)) + 0.5)
	tint:SetColorTexture(0.03, 0.023, 0.018, percent / 100) -- the library's TINT color
	Print("edit mode tint: %d%%%s", percent, lib:IsEditing() and "" or " (shows the next time edit mode opens)")
end

function COMMANDS.lock()
	Harness.layoutLock = not Harness.layoutLock
	Print("the Profiles page's layout lock is now %s", Harness.layoutLock and "on" or "off")
	Harness.settings:Refresh()
end

-- The Shadow module: the harness frames, the Secure Button (protected), the
-- character frame, the minimap (round) and the macro frame (load on demand).
local SHADOW_RED = { 0.9, 0.2, 0.1, 0.8 }
local function ShadowTargets()
	local targets = {
		{ Harness.frames.bar }, { Harness.frames.unit }, { Harness.frames.icon }, { Harness.frames.secure },
		{ CharacterFrame, { shape = true } }, { Minimap, { round = true } },
	}
	-- The character frame's side tabs: the tab-shaped glow, below each tab (a tight stack, as WindTools' lower shadow).
	for index = 1, 6 do
		local tab = _G["CharacterFrameModeTab" .. index]
		if tab then
			targets[#targets + 1] = { tab, { shape = "sidetab", below = true } }
		end
	end
	return targets
end

local function EachShadow(fn)
	for _, entry in ipairs(ShadowTargets()) do
		local shadow = entry[1] and lib:GetShadow(entry[1])
		if shadow then
			fn(shadow)
		end
	end
	local macro = MacroFrame and lib:GetShadow(MacroFrame)
	if macro then
		fn(macro)
	end
end

function COMMANDS.shadow(what, value)
	what = (what or "on"):lower()
	local state = Harness.shadowState or { size = 4, red = false, below = false }
	Harness.shadowState = state
	if what == "size" then
		state.size = tonumber(value) or 4
	elseif what == "red" then
		state.red = not state.red
	elseif what == "below" then
		state.below = not state.below
	elseif what == "probe" then
		Harness:ShadowProbe()
		return
	elseif what == "off" then
		EachShadow(function(shadow) shadow:Hide() end)
		Print("shadows hidden")
		return
	elseif what ~= "on" then
		Print("usage: /lasdev shadow [on | off | size <n> | red | below | probe]")
		return
	end
	local color = state.red and SHADOW_RED or false
	for _, entry in ipairs(ShadowTargets()) do
		if entry[1] then
			local own = entry[2] or {}
			local below = state.below
			if own.below ~= nil then
				below = own.below
			end
			local shadow = lib:AddShadow(entry[1], { size = state.size, below = below,
				round = own.round, shape = own.shape })
			if shadow then
				shadow:SetColor(color or nil)
				shadow:Show()
			end
		end
	end
	lib:AddShadowWhenLoaded("Blizzard_MacroUI", "MacroFrame", { size = state.size, below = state.below })
	local macro = MacroFrame and lib:GetShadow(MacroFrame)
	if macro then
		macro:SetSize(state.size)
		macro:SetColor(color or nil)
		macro:SetBelow(state.below)
		macro:Show()
	end
	Print("shadows: size %d, %s, %s", state.size, state.red and "red" or "default black",
		state.below and "below their frames" or "at their frames' level")
end

-- Whether a shadow kept one level under its frame keeps that offset when the frame's level changes (WindTools hooks
-- the frame because, per its comment, the level is reset). First run (Alex, 2026-10-13, Forever 70338): raising the
-- icon's level by 5 moved its shadow by 5 too, keeping the offset; Raise left the character frame's level as it was.
-- Second run (same day): changing the icon's strata to HIGH and back kept the shadow's strata with it and its level
-- one under. So a child keeps its offset; Restack is only for a frame raised from level 0.
function Harness:ShadowProbe()
	local function Probe(name, frame, change)
		local shadow = frame and lib:GetShadow(frame)
		if not shadow or not shadow:GetFrameLevel() then
			Print("%s: no shadow yet (/lasdev shadow below first)", name)
			return
		end
		local function Levels()
			return ("frame %s %d, shadow %s %d"):format(frame:GetFrameStrata(), frame:GetFrameLevel(),
				shadow.frame:GetFrameStrata(), shadow:GetFrameLevel())
		end
		local before = Levels()
		change(frame)
		local after = Levels()
		shadow:Restack()
		Print("%s (below %s): before %s; after the change %s; after Restack %s", name, tostring(shadow.below),
			before, after, Levels())
	end
	local icon = self.frames.icon
	local strata = icon:GetFrameStrata()
	Probe("Harness Icon, SetFrameStrata HIGH", icon, function(frame) frame:SetFrameStrata("HIGH") end)
	Probe("Harness Icon, SetFrameStrata back to " .. strata, icon, function(frame) frame:SetFrameStrata(strata) end)
	Probe("Harness Icon, SetFrameLevel +5", icon, function(frame) frame:SetFrameLevel(frame:GetFrameLevel() + 5) end)
end

function COMMANDS.block()
	Harness.blocked = not Harness.blocked
	Print("blocked() now returns %s", Harness.blocked and "a reason" or "nothing")
	Harness.settings:Refresh()
end

function COMMANDS.settings()
	Harness.settings:Toggle()
end

function COMMANDS.status(_, _, _, _, rest)
	local text = rest or ""
	Harness.settings:ShowStatus(text ~= "" and text or "A status message for six seconds")
end

function COMMANDS.tip()
	local editMode = LibAeonSettingsDevDB.editMode
	if editMode then
		editMode.tipSeen = nil
	end
	Print("the first-time tip will show the next time edit mode opens")
end

function COMMANDS.media()
	Print("media path: %s", lib.mediaPath)
end

-- Writes a setting's value into the profile by its path, as an adopter's own store would (Levelbound's Profile:Set),
-- and tells anyone listening: `/lasdev writes` echoes each one to chat.
function Harness:Write(path, value)
	local node = self:Profile()
	local keys = { strsplit(".", path) }
	for index = 1, #keys - 1 do
		if type(node[keys[index]]) ~= "table" then
			node[keys[index]] = {}
		end
		node = node[keys[index]]
	end
	node[keys[#keys]] = value
	self.writeCount = (self.writeCount or 0) + 1
	if self.echoWrites then
		Print("write %d: %s = %s", self.writeCount, path, type(value) == "table" and "{...}" or tostring(value))
	end
end

function COMMANDS.pin()
	Harness.pinIcon = not Harness.pinIcon
	Print("Harness Icon is %s.", Harness.pinIcon and "pinned" or "free")
	lib:RefreshMovers()
end

function COMMANDS.writes()
	Harness.echoWrites = not Harness.echoWrites
	Print("Echoing writes %s (%d so far).", Harness.echoWrites and "on" or "off", Harness.writeCount or 0)
end

function COMMANDS.help()
	Print("/lasdev edit [second] | hide <key> | pend <key> <dx> <dy> | move | show | set <key> <POINT> <x> <y> | reset [key] | profile <name> | off <key> | scale <key> <n> | bad | media | tip | combat [key] [dx] [dy] | settings | status [text] | block | lock | shadow [on|off|size n|red|below|probe] | sound <kit> | icons | tint <percent> | writes | pin")
end

SLASH_LIBAEONSETTINGSDEV1 = "/lasdev"
SlashCmdList.LIBAEONSETTINGSDEV = function(input)
	input = strtrim(input or "")
	local command, a, b, c, d = strsplit(" ", input)
	local rest = input:match("^%S+%s+(.+)$")
	local handler = COMMANDS[(command or ""):lower()] or COMMANDS.help
	handler(a, b, c, d, rest)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name == ADDON_NAME then
		self:UnregisterEvent("ADDON_LOADED")
		Harness:Register()
	end
end)
