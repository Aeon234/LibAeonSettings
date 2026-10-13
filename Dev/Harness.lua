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
			grow = { "CENTER", "LEFT", "RIGHT" } },
		{ key = "unit", label = "Harness Unit", subtitle = "Sample while editing", frame = self.frames.unit,
			default = { point = "CENTER", x = -280, y = -120 },
			sample = function(shown) self.frames.unit.text:SetText(shown and "Harness Unit (sample)" or "Harness Unit") end,
			size = StoredSize(self.frames.unit, "unitSize", 20), attach = true, match = "both",
			settings = function(target) Print("Element Options for %s: the adopter would open its settings page here", target.key) end },
		{ key = "icon", label = "Harness Icon", frame = self.frames.icon, default = { point = "TOPRIGHT", x = -240, y = -200 },
			attach = true },
		{ key = "secure", label = "Secure Button", subtitle = "Protected", frame = self.frames.secure,
			default = { point = "LEFT", x = 240, y = -60 }, attach = true },
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
	window:Page("profiles", { title = "Profiles" })
end

-- W2 test page: notes, hidden halves, a custom row and a long section for the content scroll.
function Harness:DeclareGeneral(page)
	local intro = page:Section("intro", "Introduction")
	intro:Note("Notes run across the section.", "A smaller second part sits under the note in the description color.")
	intro:Checkbox({ id = "extras", label = "Show Extras", path = "general.extras", default = false,
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

	local texts = page:Section("texts", "Text Inputs")
	texts:TextInput({ id = "nameFormat", label = "Name Format", path = "controls.nameFormat", default = "[name]",
		validate = function(text)
			if not text:find("%[%a+%]") then
				return "It needs a tag in brackets, such as [name]."
			end
		end })
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

	local inactive = page:Section("inactive", "Inactive")
	inactive:Slider({ id = "deadSlider", label = "Slider", path = "controls.deadSlider", default = 4, min = 0, max = 10,
		depends = "active" })
	inactive:Dropdown({ id = "deadDropdown", label = "Dropdown", path = "controls.deadDropdown", default = "OUTLINE",
		options = lib.OUTLINES, depends = "active" })
	inactive:TextInput({ id = "deadText", label = "Text Input", path = "controls.deadText", default = "text",
		depends = "active" })
	inactive:Button({ id = "deadButton", label = "Button", verb = "Delete", confirm = "Close me by unticking Controls Active.",
		run = function() end, depends = "active" })
	inactive:Checkbox({ id = "deadCheck", label = "Checkbox", path = "controls.deadCheck", depends = "active" })
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
			{ key = "two", frame = scratch, default = { point = "CENTER", x = 0, y = 0 }, colour = true },
		},
	})
	Print('registered a declaration with three problems (unknown field "mystery", a bad default, unknown field "colour"); each should appear as a reported error')
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

function COMMANDS.help()
	Print("/lasdev edit [second] | hide <key> | pend <key> <dx> <dy> | move | show | set <key> <POINT> <x> <y> | reset [key] | profile <name> | off <key> | scale <key> <n> | bad | media | tip | combat [key] [dx] [dy] | settings | status [text] | block")
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
