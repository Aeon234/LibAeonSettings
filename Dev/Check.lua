-- Offline checks of the library's rules that need no client: positions, target lists and size matching, the
-- media pickers' choices, the type and color tokens, springs and Reduce Motion, targets that place themselves, the
-- settings model, hidden sections, Undo, search, text insertion and section menus. Loads the real source files under
-- small stand-ins for the WoW API.
-- Run from anywhere with Lua 5.1: ~/.local/lua51/bin/lua Dev/Check.lua

local root = (arg and arg[0] or ""):match("^(.*)[/\\]Dev[/\\]Check%.lua$") or "."

-- Stand-ins -------------------------------------------------------------------------------------------------------

local now = 100
local errors = {}

local function NewFrame(width, height)
	local frame = { width = width or 1, height = height or 1, left = 100, bottom = 100, hooks = {} }
	function frame:GetObjectType() return "Frame" end
	function frame:GetSize() return self.width, self.height end
	function frame:GetWidth() return self.width end
	function frame:GetHeight() return self.height end
	function frame:GetLeft() return self.left end
	function frame:GetBottom() return self.bottom end
	function frame:GetEffectiveScale() return 1 end
	function frame:SetSize(newWidth, newHeight)
		self.width, self.height = newWidth, newHeight
		for _, hook in ipairs(self.hooks) do
			hook(self)
		end
	end
	function frame:ClearAllPoints() end
	function frame:SetPoint(...) self.point = { ... } end
	function frame:IsProtected() return false end
	function frame:HookScript(_, hook) table.insert(self.hooks, hook) end
	function frame:RegisterEvent() end
	function frame:UnregisterEvent() end
	function frame:SetScript() end

	return frame
end

local libraries = {}
LibStub = setmetatable({
	NewLibrary = function(_, major)
		libraries[major] = libraries[major] or {}
		return libraries[major]
	end,
}, { __call = function(_, major) return libraries[major] end })

CreateFrame = function() return NewFrame() end
debugstack = function() return "" end
geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
GetTime = function() return now end
InCombatLockdown = function() return false end
IsLoggedIn = function() return false end
UIParent = { GetEffectiveScale = function() return 1 end, GetWidth = function() return 1920 end,
	GetHeight = function() return 1080 end }
UIErrorsFrame = { AddExternalErrorMessage = function(_, message) errors[#errors + 1] = message end }
PixelUtil = { GetNearestPixelSize = function(value) return value end }
C_Timer = { After = function(_, callback) callback() end }

function wipe(t)
	for key in pairs(t) do
		t[key] = nil
	end

	return t
end

function CopyTable(t)
	local copy = {}
	for key, value in pairs(t) do
		copy[key] = type(value) == "table" and CopyTable(value) or value
	end

	return copy
end

function strsplit(separator, text)
	local parts = {}
	for part in (text .. separator):gmatch("(.-)%" .. separator) do
		parts[#parts + 1] = part
	end

	return unpack(parts)
end

for _, file in ipairs({ "Core", "Locale", "Fonts", "Media", "Geometry", "Motion", "Placement", "Anchor" }) do
	dofile(root .. "/Source/" .. file .. ".lua")
end
local lib = LibStub("LibAeonSettings-1.0")
-- Parts of the edit mode, the mover and the window that the loaded files call.
lib.session = { open = false, pending = {} }
function lib:GetPending(addonName, key)
	local pending = self.session.pending[addonName]

	return pending and pending[key]
end
function lib:RefreshMovers() end
function lib:FrameRect(frame) return frame.left, frame.bottom, frame.width, frame.height end
lib.Window = {}
function strlenutf8(text)
	local _, count = text:gsub("[^\128-\191]", "")

	return count
end
for _, file in ipairs({ "Model", "Details", "Search", "Undo", "TextInput", "Dropdown" }) do
	dofile(root .. "/Source/" .. file .. ".lua")
end

-- Checks ----------------------------------------------------------------------------------------------------------

local passed, failed = 0, 0

local function Check(name, condition)
	if condition then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL  " .. name)
	end
end

local function Near(a, b)
	return a ~= nil and b ~= nil and math.abs(a - b) < 0.001
end

-- Geometry

do
	local Geometry = lib.Geometry
	local point, x, y = Geometry.ToStored(100, 200, 50, 20, 1920, 1080)
	local left, bottom = Geometry.FromStored(point, x, y, 50, 20, 1920, 1080)
	Check("geometry: a stored position gives back its rectangle", Near(left, 100) and Near(bottom, 200))
	left, bottom = Geometry.ClampInto(-30, 1070, 50, 20, 1920, 1080)
	Check("geometry: clamping keeps the rectangle on screen", Near(left, 0) and Near(bottom, 1060))
	local snap = Geometry.NearestSnap({ 98 }, { { value = 100, from = "a" }, { value = 110 } }, 5)
	Check("geometry: the nearest candidate in range snaps", snap and Near(snap.delta, 2) and snap.from == "a")
	Check("geometry: nothing out of range snaps", Geometry.NearestSnap({ 98 }, { { value = 120 } }, 5) == nil)
	-- At 1.25 units a pixel, the grid's 32-unit steps fall 25.6 pixels apart; each line still starts on a pixel.
	local pixel, thickness = 1.25, 1.25
	for _, center in ipairs({ 32, 64, 96, 960, 991.4 }) do
		local start = Geometry.PixelLineStart(center, thickness, pixel)
		local pixels = start / pixel
		Check("geometry: a line starts on a screen pixel (" .. center .. ")", Near(pixels, math.floor(pixels + 0.5)))
		Check("geometry: and covers its center (" .. center .. ")", start <= center and center <= start + thickness)
	end
	Check("geometry: a line already on pixels stays put", Near(Geometry.PixelLineStart(10.5, 1, 1), 10))
end

-- Placement: target lists and size matching

do
	local function Size(frame)
		return { get = function() return frame:GetSize() end, set = function(w, h) frame:SetSize(w, h) end }
	end
	local first, second = NewFrame(100, 20), NewFrame(300, 40)
	local list = {
		{ key = "first", frame = first, default = { point = "CENTER", x = 0, y = 0 }, size = Size(first), match = "both" },
		{ key = "second", frame = second, default = { point = "CENTER", x = 0, y = 0 }, size = Size(second), match = "both" },
		{ key = "second", frame = second, default = { point = "CENTER", x = 0, y = 0 } },
	}
	local reads = 0
	local registration = lib:Placement("Check", { store = {}, targets = function() reads = reads + 1; return list end })
	Check("placement: a duplicate key is left out", #registration:Targets() == 2)
	registration:Target("first")
	registration:Target("second")
	Check("placement: lookups reuse the checked list", reads == 1)
	Check("placement: a target is found by key", registration:Target("second").frame == second)
	registration:Apply()
	Check("placement: Apply reads the targets again", reads == 2)

	local firstTarget = registration:Target("first")
	lib.session.pending.Check = { first = { point = "CENTER", x = 0, y = 0,
		matchWidth = { addon = "Check", key = "second", extra = 0 } } }
	registration:ApplyTarget(firstTarget)
	Check("matching: the width follows the matched frame", first.width == 300 and first.height == 20)
	lib.session.pending.Check.first.matchHeight = { addon = "Check", key = "second", extra = 5 }
	registration:ApplyTarget(firstTarget)
	Check("matching: the height follows, with its extra", first.width == 300 and first.height == 45)
	second:SetSize(500, 60)
	Check("matching: resizing the matched frame resizes its follower", first.width == 500 and first.height == 65)
	lib.session.pending.Check.first = { point = "CENTER", x = 0, y = 0 }
	registration:ApplyTarget(firstTarget)
	second:SetSize(200, 30)
	Check("matching: a cleared match no longer follows", first.width == 500 and first.height == 65)
	lib.session.pending.Check = nil
end

-- Placement: outlines and pinned targets

do
	local frame, border = NewFrame(100, 20), NewFrame(112, 32)
	local pinned = false
	local before = #errors
	local registration = lib:Placement("CheckPin", { store = {}, targets = {
		{ key = "bar", frame = frame, default = { point = "CENTER", x = 0, y = 0 }, outline = border,
			pinned = function() return pinned and "Pinned to the top edge." or nil end },
		{ key = "bad", frame = NewFrame(), default = { point = "CENTER", x = 0, y = 0 }, outline = "border", pinned = 3 },
	} })
	local bar = registration:Target("bar")
	Check("pinned: a target is free while pinned gives no reason", lib:PinnedReason(bar) == nil)
	pinned = true
	Check("pinned: a target is pinned while pinned gives a reason", lib:PinnedReason(bar) == "Pinned to the top edge.")
	Check("pinned: a bad outline and a bad pinned are reported and dropped", #errors == before + 2
		and registration:Target("bad").outline == nil and registration:Target("bad").pinned == nil)
	Check("pinned: a fixed reason pins", lib:PinnedReason({ pinned = "Fixed." }) == "Fixed.")
end

-- Placement: targets that place themselves

do
	local frame = NewFrame(100, 20)
	local placed = {}
	local stored = {}
	local before = #errors
	local registration = lib:Placement("CheckPlace", { store = { positions = stored }, targets = {
		{ key = "bar", frame = frame, default = { point = "TOP", x = 0, y = -10 },
			place = function(position, target) placed[#placed + 1] = { position = position, target = target } end },
		{ key = "both", frame = NewFrame(), default = { point = "CENTER", x = 0, y = 0 }, attach = true,
			place = function() end },
		{ key = "bad", frame = NewFrame(), default = { point = "CENTER", x = 0, y = 0 }, place = "self" },
	} })
	local bar = registration:Target("bar")
	Check("place: a bad place, and place with attach, are reported and dropped", #errors == before + 2
		and registration:Target("bad").place == nil and registration:Target("both").attach == nil
		and registration:Target("both").place ~= nil)
	frame.point = nil
	registration:ApplyTarget(bar)
	Check("place: the target places its frame itself, with its default", #placed == 1 and frame.point == nil
		and placed[1].target == bar and placed[1].position == bar.default)
	stored.bar = { point = "BOTTOMLEFT", x = 40, y = 30 }
	registration:ApplyTarget(bar)
	Check("place: a stored position is handed over", placed[2].position == stored.bar)
	lib.session.pending.CheckPlace = { bar = { point = "LEFT", x = 5, y = 0 } }
	registration:ApplyTarget(bar)
	Check("place: a pending position wins", placed[3].position.point == "LEFT" and placed[3].position.x == 5)
	lib.session.pending.CheckPlace = nil
	stored.bar = { point = "BOTTOMLEFT", x = -500, y = 30 }
	registration:ApplyTarget(bar)
	local left = lib.Geometry.FromStored(placed[4].position.point, placed[4].position.x, placed[4].position.y, 100,
		20, 1920, 1080)
	Check("place: an off-screen position is moved in view first, and the store is untouched",
		placed[4].position ~= stored.bar and Near(left, 0) and stored.bar.x == -500)
	stored.bar = { point = "CENTER", x = 0, y = 0, anchor = { addon = "Check", key = "first", side = "TOP", x = 0, y = 0 } }
	registration:ApplyTarget(bar)
	Check("place: an anchor is left out of the position handed over",
		placed[5].position.anchor == nil and placed[5].position.point == "CENTER" and stored.bar.anchor ~= nil)
	registration:Apply()
	Check("place: Apply places every target that has place", #placed == 6)
	bar.place = function() error("boom") end
	before = #errors
	registration:ApplyTarget(bar)
	Check("place: an error in place is reported", #errors == before + 1)
end

-- The settings model

local function Register(kind, fields)
	lib:RegisterControl(kind, { fields = fields, Create = function() end })
end
Register("Toggle")
Register("Slider", { min = true, max = true, step = true })
Register("Color", { hasOpacity = true })
Register("Checkbox")

local function NewWindow(store)
	local window = setmetatable({ addonName = "Check", declaration = { store = store }, pages = {}, pageOrder = {} },
		{ __index = function(_, name) return lib.Window[name] end })
	window.IsShown = function() return true end
	window.SettingChanged = function() end
	window.Refresh = function() end
	window.LandOn = function() end

	return window
end

local function NewPage(window, id, title, info)
	local page = { id = id, title = title }
	lib:InitPage(window, page, info or {})
	window.pages[id] = page
	table.insert(window.pageOrder, page)

	return page
end

do
	local store = {}
	local window = NewWindow(store)
	local page = NewPage(window, "bars", "Bars", { switch = { path = "bars.enabled", default = true } })
	local section = page:Section("look", "Look")
	local shown = section:Toggle({ id = "shown", label = "Show Bars", path = "bars.shown", default = true })
	local scale = section:Slider({ id = "scale", label = "Scale", path = "bars.scale", default = 1, depends = "shown" })
	local font = section:Slider({ id = "font", label = "Font Size", path = "bars.font", default = 12,
		inherits = "shared.font" })
	local shared = section:Slider({ id = "sharedFont", label = "Shared Font Size", path = "shared.font", default = 14,
		wide = true })
	local guarded = section:Toggle({ id = "guarded", label = "Guarded", path = "bars.guarded",
		blocked = function() return "Needs a target." end })

	Check("model: two settings share a line", section.lines[1][1] == shown and section.lines[1][2] == scale)
	Check("model: a wide setting takes its own line", section.lines[3][1] == shared and section.lines[3].wide)
	Check("model: an unset value is its default", scale:GetValue() == 1)
	scale:Request(1.5)
	Check("model: a saved value is written at its path", store.bars.scale == 1.5 and scale:GetValue() == 1.5)

	Check("model: an inheriting setting follows the shared default", font:GetValue() == 14 and not font:IsOverridden())
	store.shared = { font = 16 }
	Check("model: an inheriting setting follows the shared value", font:GetValue() == 16)
	font:Request(10)
	Check("model: its own value overrides", font:GetValue() == 10 and font:IsOverridden())
	font:Reset()
	Check("model: Reset returns it to the shared value", font:GetValue() == 16 and not font:IsOverridden())

	Check("model: a setting is active by default", (scale:Activity()))
	shown:Request(false)
	local active, reason, cause = scale:Activity()
	Check("model: turning off its parent makes it inactive", not active and cause == "depends" and reason ~= nil)
	shown:Request(true)
	page.switch:Request(false)
	local _
	active, _, cause = scale:Activity()
	Check("model: the page's switch comes first", not active and cause == "page")
	page.switch:Request(true)
	active, reason, cause = guarded:Activity()
	Check("model: blocked gives its reason", not active and cause == "blocked" and reason == "Needs a target.")
	Check("model: an unknown field is reported", (function()
		local before = #errors
		section:Toggle({ id = "odd", label = "Odd", path = "odd", colour = true })
		return #errors == before + 1
	end)())
end

-- Type and color tokens

do
	local roles = 0
	for _, entry in pairs(lib.TYPE) do
		roles = roles + 1
		Check("type: each role names a library font and a size", (entry[1] == "body" or entry[1] == "header")
			and type(entry[2]) == "number" and entry[2] > 0)
	end
	Check("type: the scale has its six roles", roles == 6)
	local r, g, b, a = lib:GetColor("accent")
	Check("color: accent is Blizzard's gold", r == 1 and Near(g, 0.82) and b == 0 and a == 1)
	Check("color: an alpha given replaces the color's own", select(4, lib:GetColor("bronze", 0.2)) == 0.2)
	Check("color: an unknown name falls back to white",
		lib:GetColor("missing") == 1 and select(4, lib:GetColor("missing")) == 1)
	Check("color: destructive without the client's red keeps its own value",
		Near(select(2, lib:GetColor("destructive")), 0.125))
	RED_FONT_COLOR = { GetRGB = function() return 0.9, 0.1, 0.2 end }
	r, g, b, a = lib:GetColor("destructive")
	Check("color: destructive reads the client's red at each call", r == 0.9 and g == 0.1 and b == 0.2 and a == 1)
	RED_FONT_COLOR = nil
end

-- Names on the library: a method defined as `function lib:X` and a table assigned as `lib.X =` in another file
-- would replace each other by load order.

do
	local methods, tables, clashes = {}, {}, {}
	for line in io.lines(root .. "/LibAeonSettings.xml") do
		local file = line:match('Script file="([^"]+)"')
		if file then
			for code in io.lines(root .. "/" .. file:gsub("\\", "/")) do
				local method = code:match("^function lib:([%w_]+)%(")
				local field = code:match("^lib%.([%w_]+) = ")
				if method then
					methods[method] = file
				end
				if field then
					tables[field] = file
				end
			end
		end
	end
	for name, file in pairs(methods) do
		if tables[name] then
			clashes[#clashes + 1] = ("%s (%s, %s)"):format(name, file, tables[name])
		end
	end
	table.sort(clashes)
	Check("library names: no method shares its name with a table (" .. table.concat(clashes, ", ") .. ")", #clashes == 0)
end

-- Springs and Reduce Motion

do
	local Motion = lib.Motion
	local function Run(response, damping, seconds)
		local value, velocity, peak = 0, 0, 0
		for _ = 1, math.floor(seconds * 60) do
			value, velocity = Motion.Step(value, velocity, 1, response, damping, 1 / 60)
			peak = math.max(peak, value)
		end
		return value, peak
	end
	local value, peak = Run(0.3, 1, 2)
	Check("spring: critically damped, it settles on the target", math.abs(value - 1) < 0.001)
	Check("spring: critically damped, it never passes the target", peak <= 1 + 1e-6)
	Check("spring: by its response time it is most of the way there", (Run(0.3, 1, 0.3)) > 0.95)
	Check("spring: under-damped, it overshoots", select(2, Run(0.3, 0.8, 2)) > 1.01)
	Check("spring: under-damped, it overshoots as its damping says", math.abs(select(2, Run(0.3, 0.8, 2)) - 1
		- math.exp(-math.pi * 0.8 / math.sqrt(1 - 0.64))) < 0.002)
	for _, damping in ipairs({ 0.8, 1, 1.4 }) do
		local big = { Motion.Step(0, 2, 1, 0.3, damping, 0.25) }
		local small = { 0, 2 }
		for _ = 1, 25 do
			small = { Motion.Step(small[1], small[2], 1, 0.3, damping, 0.01) }
		end
		Check(("spring: one long frame lands where many short ones do (damping %.1f)"):format(damping),
			math.abs(big[1] - small[1]) < 1e-9 and math.abs(big[2] - small[2]) < 1e-7)
	end

	local savedWindows = lib.windows
	local first, second = {}, {}
	lib.windows = {
		A = { declaration = { account = first } },
		B = { declaration = { account = function() return second end } },
		C = { declaration = { account = first } },
	}
	local reports, rests = {}, 0
	local spring = lib:CreateSpring(0, function(v) reports[#reports + 1] = v end,
		{ onRest = function() rests = rests + 1 end })
	spring:To(1)
	Check("spring: a new target starts it moving", spring:IsMoving())
	for _ = 1, 10 do
		lib.MotionHandlers.Update(1 / 60)
	end
	local speed = spring.velocity
	spring:To(0)
	Check("spring: turning back keeps its speed", speed > 0 and spring.velocity == speed and spring:IsMoving())
	for _ = 1, 120 do
		lib.MotionHandlers.Update(1 / 60)
	end
	Check("spring: it comes to rest on the new target and reports it once", spring.value == 0 and not spring:IsMoving()
		and rests == 1 and reports[#reports] == 0)

	Check("reduce motion: off by default", lib:ReduceMotion() == false)
	spring:To(1)
	lib:SetReduceMotion(true)
	Check("reduce motion: turning it on ends a moving spring at its target",
		spring.value == 1 and not spring:IsMoving())
	Check("reduce motion: stored in every account table, each once", #lib:AccountTables() >= 2
		and first.settingsWindow.reduceMotion == true and second.settingsWindow.reduceMotion == true)
	spring:To(0)
	Check("reduce motion: a spring jumps to its target", spring.value == 0 and not spring:IsMoving())
	lib:SetReduceMotion(false)
	Check("reduce motion: off again", lib:ReduceMotion() == false)
	lib.windows = savedWindows
end

-- The library's Settings Window section

do
	local account = {}
	local window = NewWindow({})
	window.declaration.account = account
	local first = NewPage(window, "first", "First")
	first:Section("own", "Own"):Toggle({ id = "on", label = "On", path = "on", default = true })
	NewPage(window, "second", "Second")
	local savedWindows = lib.windows
	lib.windows = { Check = window }
	window:AddWindowSection()
	window:AddWindowSection()
	local last = first.sections[#first.sections]
	Check("window section: added once, at the end of the first page only", #first.sections == 2
		and last.title == lib.L.SETTINGS_WINDOW and #window.pages.second.sections == 0)
	local setting = last.lines[1][1]
	Check("window section: Reduce Motion starts off",
		setting.label == lib.L.REDUCE_MOTION and setting:GetValue() == false)
	setting:Request(true)
	Check("window section: its checkbox turns Reduce Motion on account-wide",
		lib:ReduceMotion() and account.settingsWindow.reduceMotion == true and setting:GetValue() == true)
	setting:Request(false)
	Check("window section: and off", not lib:ReduceMotion() and setting:GetValue() == false)
	lib.windows = savedWindows
end

-- Cards: rows under their parents, choice cards

do
	local window = NewWindow({ show = true, a = false })
	local page = NewPage(window, "cards", "Cards")
	local section = page:Section("rows", "Rows")
	section:Toggle({ id = "first", label = "First", path = "first", default = true })
	section:Toggle({ id = "child", label = "Child", path = "child", default = true, depends = "show" })
	section:Toggle({ id = "show", label = "Show", path = "show", default = true })
	section:Toggle({ id = "grandchild", label = "Grandchild", path = "grandchild", default = true, depends = "child" })
	section:Toggle({ id = "last", label = "Last", path = "last", default = true })
	local other = page:Section("other", "Other")
	local outside = other:Toggle({ id = "outside", label = "Outside", path = "outside", default = true, depends = "a" })
	section:Toggle({ id = "a", label = "A", path = "a", default = false })
	local rows = {}
	for _, id in ipairs({ "first", "child", "show", "grandchild", "last", "a" }) do
		rows[#rows + 1] = { setting = page.settings[id] }
	end
	lib.OrderUnderParents(rows)
	local order = {}
	for _, row in ipairs(rows) do
		order[#order + 1] = row.setting.id
	end
	Check("cards: a row moves directly under the row it depends on, its own dependents under it",
		table.concat(order, ",") == "first,show,child,grandchild,last,a")
	local loop = { { setting = { Parent = function() return nil end } } }
	loop[2] = { setting = { Parent = function() return loop[3].setting end } }
	loop[3] = { setting = { Parent = function() return loop[2].setting end } }
	lib.OrderUnderParents(loop)
	Check("cards: rows in a dependency loop keep their place", #loop == 3)

	page.settings.show:SetValue(false)
	Check("cards: a row whose parent in its section is off leaves", lib.ParentOffInSection(page.settings.child)
		and lib.ParentOffInSection(page.settings.grandchild))
	Check("cards: a row whose parent is in another section stays, dimmed", not lib.ParentOffInSection(outside)
		and select(3, outside:Activity()) == "depends")

	local before = #errors
	local choices = page:Section("choices", "Choices", { columns = 2 })
	choices:Checkbox({ id = "c1", label = "One", path = "c1" })
	choices:Checkbox({ id = "c2", label = "Two", path = "c2" })
	Check("choice card: two checkboxes draw two to a line", lib.ChoiceGrid(window, choices) and #errors == before)
	local mixed = page:Section("mixed", "Mixed", { columns = 2 })
	mixed:Checkbox({ id = "m1", label = "One", path = "m1" })
	mixed:Toggle({ id = "m2", label = "Two", path = "m2" })
	Check("choice card: a non-checkbox draws one to a line and is reported",
		not lib.ChoiceGrid(window, mixed) and #errors == before + 1)
	local described = page:Section("described", "Described", { columns = 2 })
	described:Checkbox({ id = "d1", label = "One", path = "d1", description = "Words." })
	described:Checkbox({ id = "d2", label = "Two", path = "d2" })
	Check("choice card: a description draws one to a line", not lib.ChoiceGrid(window, described))
	local single = page:Section("single", "Single", { columns = 2 })
	single:Checkbox({ id = "s1", label = "One", path = "s1" })
	Check("choice card: one checkbox draws one to a line", not lib.ChoiceGrid(window, single))
	page:Section("three", "Three", { columns = 3 })
	Check("choice card: columns other than 1 or 2 are reported", errors[#errors]:find("columns must be 1 or 2") ~= nil)

	local module = NewPage(window, "clock", "Clock", { switch = { path = "clock.on" } })
	local named = NewPage(window, "broker", "DataBroker", { switch = { path = "broker.on", label = "Broker Hosting" } })
	Check("page switch: named after its page unless it has a label of its own",
		module.switch.label == "Clock" and named.switch.label == "Broker Hosting")

	local store = {}
	local detailsWindow = NewWindow(store)
	local clock = NewPage(detailsWindow, "clock", "Clock")
	local more = clock:Section("more", "More")
	more:Toggle({ id = "rest", label = "Resting Glyph", path = "rest", default = true })
	local text = more:Details({ id = "text", label = "Text", summary = function() return "Bar Style" end })
	local font = more:Dropdown({ id = "font", label = "Font", path = "font", default = "A", details = "text",
		choices = { { value = "A", text = "A" } } })
	local classColor = more:Checkbox({ id = "class", label = "Class Color", path = "class", details = "text" })
	local hover = more:Checkbox({ id = "hover", label = "Hover Class Color", path = "hover", depends = "class",
		details = "text" })
	Check("details: closed at first, holding its settings away", text:GetValue() == false
		and lib.ParentOffInSection(font) and lib.ParentOffInSection(hover))
	local rows = {}
	for _, setting in ipairs({ font, more.lines[1][1], classColor, text, hover }) do
		rows[#rows + 1] = { setting = setting }
	end
	lib.OrderUnderParents(rows)
	Check("details: its settings sit under it", rows[2].setting == text and rows[3].setting == font
		and rows[4].setting == classColor and rows[5].setting == hover)
	text:SetValue(true)
	Check("details: opened, its settings are there; one depending on another inside follows that one",
		not lib.ParentOffInSection(font) and lib.ParentOffInSection(hover))
	Check("details: open or closed lives in the window for the session, not in the store",
		detailsWindow.openDetails["clock/text"] == true and store.text == nil and next(store) == nil)
end

-- Media pickers

do
	Check("media: without LibSharedMedia, Blizzard's bar textures are listed",
		#lib:TextureChoices() == 3 and lib:TextureFile("Blizzard") == "Interface\\TargetingFrame\\UI-StatusBar")
	local own = { { value = "none", text = "None" }, { value = "alarm", text = "Alarm", soundKit = 12889 } }
	Check("media: without LibSharedMedia, a sound picker lists only its own", #lib:SoundChoices(own) == 2)

	local registry = {
		statusbar = { Flat = "Interface\\Flat", Empty = "" },
		sound = { None = 1, Alarm = "Interface\\alarm.ogg", Bell = "Interface\\bell.ogg" },
	}
	local media = LibStub:NewLibrary("LibSharedMedia-3.0")
	function media:HashTable(kind) return registry[kind] end
	function media:List(kind)
		local names = {}
		for name in pairs(registry[kind]) do
			names[#names + 1] = name
		end
		table.sort(names)
		return names
	end
	local textures = lib:TextureChoices()
	Check("media: an empty texture file is left out", #textures == 1 and textures[1].value == "Flat")
	Check("media: an unknown texture name has no file", lib:TextureFile("Missing") == nil)
	local sounds = lib:SoundChoices(own)
	Check("media: the setting's own sounds come first, its None replacing LibSharedMedia's, its names winning",
		#sounds == 3 and sounds[1] == own[1] and sounds[2] == own[2] and sounds[3].value == "Bell"
		and sounds[3].soundFile == "Interface\\bell.ogg")
	libraries["LibSharedMedia-3.0"] = nil
end

-- The text cursor

do
	local store = {}
	local window = NewWindow(store)
	window.RecordUndo = function() end
	local page = NewPage(window, "text", "Text")
	local section = page:Section("slot", "Slot")
	local input = section:TextInput({ id = "text", label = "Text", path = "slot.text", default = "", allowEmpty = true })
	local short = section:TextInput({ id = "short", label = "Short", path = "slot.short", default = "ab", maxLetters = 4 })
	Check("cursor: without a cursor, text goes at the end", input:InsertText("[name]") and store.slot.text == "[name]")
	input:SetTextCursor(0)
	input:InsertText("Lv ")
	Check("cursor: text goes where the cursor was, and the cursor follows it",
		store.slot.text == "Lv [name]" and input:TextCursor() == 3)
	store.slot.text = "Ñö [x]"
	input:SetTextCursor(2)
	input:InsertText("é")
	Check("cursor: positions count UTF-8 characters", store.slot.text == "Ñöé [x]" and input:TextCursor() == 3)
	input:SetTextCursor(99)
	input:InsertText("!")
	Check("cursor: a position past the end inserts at the end", store.slot.text == "Ñöé [x]!")
	Check("cursor: an insertion the input's rules refuse is not saved", not short:InsertText("cde") and store.slot.short == nil)
	local before = #errors
	section:Toggle({ id = "plain", label = "Plain", path = "slot.plain" }):InsertText("x")
	Check("cursor: InsertText on another control is reported", #errors == before + 1)
end

-- Action dropdowns and section menus

do
	local store = {}
	local window = NewWindow(store)
	local page = NewPage(window, "copy", "Copy")
	local section = page:Section("look", "Look")
	local picked
	local copy = section:Menu({ id = "copy", placeholder = "Copy From", action = true,
		options = { { value = "other", text = "Other" } }, set = function(value) picked = value end })
	Check("menu: a section menu belongs to its section and takes no row",
		section.menu == copy and copy.section == section and #section.lines == 0)
	Check("menu: an action dropdown reads as no choice and is left out of Undo",
		copy:GetValue() == nil and copy.noUndo == true)
	local before = #errors
	section:Menu({ id = "second", action = true, set = function() end })
	Check("menu: a second menu on a section is reported", #errors == before + 1 and page.settings.second == nil)
	before = #errors
	section:Dropdown({ id = "noSet", action = true, options = {} })
	Check("menu: an action dropdown without set is reported", #errors == before + 1)
	window.RefreshUndo = function() end
	copy:Request("other")
	Check("menu: picking an action runs set without recording Undo",
		picked == "other" and #(window.undoHistory or {}) == 0)
end

-- Resettable settings

do
	local store = {}
	local window = NewWindow(store)
	window.RefreshUndo = function() end
	local page = NewPage(window, "reset", "Reset")
	local section = page:Section("look", "Look")
	local color = section:Color({ id = "color", label = "Color", path = "color", resettable = true,
		default = { r = 0, g = 0, b = 0, a = 0.618 }, hasOpacity = true })
	local plain = section:Slider({ id = "plain", label = "Plain", path = "plain", default = 4 })
	local shared = section:Slider({ id = "shared", label = "Shared", path = "shared", default = 1, resettable = true,
		inherits = "base" })
	Check("resettable: nothing stored is not changed", not color:IsChangedFromDefault())
	color:Request({ r = 0, g = 0, b = 0, a = 0.6182 })
	Check("resettable: a value within rounding of the default is not changed", not color:IsChangedFromDefault())
	color:Request({ r = 1, g = 0, b = 0, a = 0.618 })
	Check("resettable: another value is changed", color:IsChangedFromDefault())
	color:ResetToDefault()
	Check("resettable: reset writes a copy of the default", store.color and store.color.r == 0
		and store.color ~= color.default and not color:IsChangedFromDefault())
	Check("resettable: the reset is recorded for Undo", window:CanUndo())
	plain:Request(8)
	Check("resettable: a setting without the field never shows it", not plain:IsChangedFromDefault())
	shared:Request(3)
	Check("resettable: an inheriting setting keeps its override marker instead",
		not shared:IsChangedFromDefault() and shared:IsOverridden())
end

-- The declaration's write hook

do
	local store = {}
	local window = NewWindow(store)
	window.RefreshUndo = function() end
	local writes = {}
	window.declaration.write = function(path, value)
		if path == "locked" then
			return false, "Locked."
		end
		writes[#writes + 1] = path
		store[path] = value
	end
	local page = NewPage(window, "hook", "Hook")
	local section = page:Section("one", "One")
	local size = section:Slider({ id = "size", label = "Size", path = "size", default = 10 })
	local font = section:Slider({ id = "font", label = "Font", path = "font", inherits = "shared" })
	local locked = section:Slider({ id = "locked", label = "Locked", path = "locked", default = 1 })
	local own = 0
	section:Slider({ id = "own", label = "Own", get = function() return own end, set = function(value) own = value end })
		:Request(5)
	size:Request(12)
	Check("write: a path write goes through the declaration's write", writes[1] == "size" and store.size == 12)
	Check("write: a setting with its own set does not", #writes == 1 and own == 5)
	Check("write: write may refuse", not locked:Request(2) and store.locked == nil)
	window:Undo()
	Check("write: Undo writes through it", writes[2] == "size" and store.size == nil)
	font:Request(14)
	window:ClearOverrides()
	Check("write: Clear Overrides writes through it", writes[#writes] == "font" and store.font == nil)
end

-- Undo

do
	local store = {}
	local window = NewWindow(store)
	local page = NewPage(window, "main", "Main")
	local section = page:Section("one", "One")
	local slider = section:Slider({ id = "size", label = "Size", path = "size", default = 10 })
	local color = section:Color({ id = "tint", label = "Tint", path = "tint" })
	local toggle = section:Toggle({ id = "on", label = "On", path = "on", default = false })

	slider:Request(11)
	now = now + 0.5
	slider:Request(12)
	Check("undo: quick slider saves are one step", #window.undoHistory == 1)
	now = now + 5
	slider:Request(13)
	Check("undo: a later save is a new step", #window.undoHistory == 2)
	now = now + 0.5
	slider:Request(12)
	Check("undo: a step that ends where it began is dropped", #window.undoHistory == 1)

	local pick = {}
	color:Request({ r = 1, g = 0, b = 0 }, pick)
	now = now + 10
	color:Request({ r = 0, g = 1, b = 0 }, pick)
	Check("undo: saves of one gesture are one step, however far apart", #window.undoHistory == 2)
	color:Request({ r = 0, g = 0, b = 1 }, {})
	Check("undo: another gesture is a new step", #window.undoHistory == 3)

	toggle:Request(true)
	window:Undo()
	Check("undo: Undo puts the earlier value back", store.on == nil and toggle:GetValue() == false)
	window:Undo()
	window:Undo()
	Check("undo: a whole pick is undone at once", store.tint == nil)
	window:Undo()
	Check("undo: the merged slider steps go back to the start", store.size == nil and #window.undoHistory == 0)
end

-- Undo of a change made outside a setting

do
	local store = { order = { "a", "b" }, gaps = {} }
	local window = NewWindow(store)
	window.declaration.write = function(path, value)
		store[path] = value
	end
	local before = store.order
	store.order = { "b", "a" }
	window:RecordChange({ path = "order", before = before, text = "Order back." })
	before[1] = "changed"
	Check("change: the earlier value is copied", window.undoHistory[1].before[1] == "a")
	window:RecordChange({ path = "gaps", before = {}, merge = "x" })
	now = now + 0.5
	window:RecordChange({ path = "gaps", before = { x = 4 }, merge = "x" })
	Check("change: the same path and merge moments later join one step", #window.undoHistory == 2)
	window:RecordChange({ path = "gaps", before = {}, merge = "y" })
	Check("change: another merge value is a new step", #window.undoHistory == 3)
	local page = NewPage(window, "after", "After")
	local slider = page:Section("one", "One"):Slider({ id = "size", label = "Size", path = "size", default = 1 })
	slider:Request(2)
	Check("change: a setting saved after one is its own step", #window.undoHistory == 4)
	window:Undo()
	window:Undo()
	window:Undo()
	Check("change: Undo writes the first earlier value back", next(store.gaps) == nil)
	window:Undo()
	Check("change: through the declaration's write", store.order[1] == "a" and store.order[2] == "b"
		and #window.undoHistory == 0)
	store.order, store.gaps = { "c" }, { x = 1 }
	window:RecordChange({ paths = { { path = "order", before = { "a", "b" } }, { path = "gaps", before = {} } },
		text = "Both back." })
	Check("change: several paths are one step", #window.undoHistory == 1)
	window:Undo()
	Check("change: Undo writes each path back", store.order[2] == "b" and next(store.gaps) == nil
		and #window.undoHistory == 0)
end

-- Search

do
	local window = NewWindow({})
	local page = NewPage(window, "bars", "Action Bars")
	local section = page:Section("look", "Appearance")
	section:Color({ id = "color", label = "Bar Color", path = "color" })
	section:Toggle({ id = "clock", label = "Show Clock", path = "clock", keywords = "time" })
	section:Toggle({ id = "centered", label = "Centered Text", path = "centered",
		description = "Puts the label in the middle." })
	local hidden = section:Toggle({ id = "hidden", label = "Hidden Thing", path = "hidden",
		show = function() return false end })
	section:Toggle({ id = "channels", label = "Announce", path = "announce",
		tooltip = "Posts to |cff40c0ffParty|r and |cff40ff40Guild|r chat." })
	section:Toggle({ id = "live", label = "Live Tip", path = "live", tooltip = function() return "Zeppelin" end })

	local function First(text)
		local found = window:FindSettings(text)

		return found[1] and found[1].label
	end
	local function Finds(text, label)
		for _, entry in ipairs((window:FindSettings(text))) do
			if entry.label == label then
				return true
			end
		end

		return false
	end

	Check("search: a page is found by its title", First("action") == "Action Bars")
	Check("search: a British spelling finds the American one", First("colour") == "Bar Color")
	Check("search: a synonym finds the setting", Finds("tint", "Bar Color"))
	Check("search: filler words may be left out", First("show the clock") == "Show Clock")
	Check("search: keywords are searched", Finds("time", "Show Clock"))
	Check("search: letters in order find the label", Finds("shwclk", "Show Clock"))
	Check("search: a typed British stem finds the word", Finds("centr", "Centered Text"))
	Check("search: descriptions are searched", Finds("middle", "Centered Text"))
	Check("search: a section is found", Finds("appearance", "Appearance"))
	Check("search: a hidden setting is not listed", not Finds("hidden", hidden.label))
	Check("search: nothing matches nonsense", First("zzqx") == nil)
	Check("search: a tooltip given as text is searched without its color codes",
		Finds("guild", "Announce") and not Finds("cff40ff40", "Announce"))
	Check("search: a tooltip given as a function is not searched", not Finds("zeppelin", "Live Tip"))

	local mode = "markers"
	local markers = page:Section("markers", "Markers", { show = function() return mode == "markers" end })
	local markerSize = markers:Slider({ id = "markerSize", label = "Marker Size", path = "markerSize" })
	local party = page:Section("party", "Party Bars", { show = function() return mode == "party" end })
	local partyHeight = party:Slider({ id = "partyHeight", label = "Party Height", path = "partyHeight" })
	Check("section show: settings follow their section's show",
		markerSize:IsShown() and not partyHeight:IsShown() and markers:IsShown() and not party:IsShown())
	Check("section show: a hidden section and its settings are not searched",
		Finds("marker", "Marker Size") and Finds("markers", "Markers")
		and not Finds("party", "Party Height") and not Finds("party", "Party Bars"))
	mode = "party"
	Check("section show: changing the mode swaps what search finds",
		not Finds("marker", "Marker Size") and Finds("party", "Party Height") and Finds("party", "Party Bars"))
	Check("section show: a section without show is shown", section:IsShown())
	local before = #errors
	local odd = page:Section("odd", "Odd", { show = true, hidden = true })
	Check("section show: an unknown field and a show that is not a function are reported",
		#errors == before + 2 and odd.show == nil and odd:IsShown())

	local chosen
	local panel = page:Section("panel", "Panel", { show = function() return chosen ~= nil end,
		reveal = function() chosen = "left" end })
	local panelGap = panel:Slider({ id = "panelGap", label = "Panel Gap", path = "panelGap" })
	local panelOnly = panel:Slider({ id = "panelOnly", label = "Panel Only", path = "panelOnly",
		show = function() return false end })
	Check("section reveal: a revealable section's hidden rows are searched",
		not panelGap:IsShown() and panelGap:Revealable() and Finds("panel gap", "Panel Gap"))
	Check("section reveal: a row its own show hides is not", not panelOnly:Revealable()
		and not Finds("panel only", "Panel Only"))
	Check("section reveal: a section without reveal stays out of search", not partyHeight:Revealable()
		or mode == "party")
	window.SelectPage = function() end
	window.Refresh = function() end
	window.RowOf = function() end
	lib.Window.LandOn(window, panelGap)
	Check("section reveal: landing reveals the section first", chosen == "left" and panelGap:IsShown())
end

-- Translations: every locale file names only keys Locale.lua has, keeps their format specifiers in order, and
-- translates every key the client does not translate itself (those take a Blizzard global).

do
	local english, blizzard = {}, {}
	for line in io.lines(root .. "/Source/Locale.lua") do
		local key, rest = line:match("^L%.([%w_]+) = (.*)$")
		if key then
			english[key] = lib.L[key]
			blizzard[key] = not rest:match('^"') or nil
		end
	end
	local function Specifiers(text)
		local list = {}
		for specifier in tostring(text):gmatch("%%[%%%a]") do
			list[#list + 1] = specifier
		end

		return table.concat(list, " ")
	end
	local saved = lib.L
	for _, code in ipairs({ "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
		lib.L = {}
		GetLocale = function() return code end
		local loaded = pcall(dofile, root .. "/Source/Locale/" .. code .. ".lua")
		local unknown, mismatched, missing = {}, {}, {}
		for key, text in pairs(lib.L) do
			if english[key] == nil then
				unknown[#unknown + 1] = key
			elseif Specifiers(text) ~= Specifiers(english[key]) then
				mismatched[#mismatched + 1] = key
			end
		end
		for key in pairs(english) do
			if not blizzard[key] and lib.L[key] == nil then
				missing[#missing + 1] = key
			end
		end
		Check(("locale %s: loads"):format(code), loaded)
		Check(("locale %s: names only English keys (%s)"):format(code, table.concat(unknown, ", ")), #unknown == 0)
		Check(("locale %s: keeps the format specifiers (%s)"):format(code, table.concat(mismatched, ", ")),
			#mismatched == 0)
		Check(("locale %s: translates every key (%d missing: %s)"):format(code, #missing,
			table.concat(missing, ", ")), #missing == 0)
	end
	lib.L, GetLocale = saved, nil
end

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	os.exit(1)
end
