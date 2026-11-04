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
for _, file in ipairs({ "Model", "RowLook", "PageLayout", "Details", "Search", "Undo", "TextInput", "Dropdown" }) do
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

-- Whether a row not yet drawn belongs on the page.
local function Wanted(setting)
	local look = {}
	lib.RowLook(setting, look)

	return look.wanted
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
	Check("cards: a row whose parent in its section is off leaves", not Wanted(page.settings.child)
		and not Wanted(page.settings.grandchild))
	Check("cards: a row whose parent is in another section stays, dimmed", Wanted(outside)
		and select(3, outside:Activity()) == "depends")

	local before = #errors
	local choices = page:Section("choices", "Choices", { columns = 2 })
	choices:Checkbox({ id = "c1", label = "One", path = "c1" })
	choices:Checkbox({ id = "c2", label = "Two", path = "c2" })
	Check("choice card: two checkboxes draw two to a line", lib.ChoiceGrid(window, choices) and #errors == before)
	local swatches = page:Section("swatches", "Swatches", { columns = 2 })
	swatches:Checkbox({ id = "w1", label = "One", path = "w1" })
	swatches:Color({ id = "w2", label = "Two", path = "w2" })
	Check("choice card: a color swatch draws two to a line", lib.ChoiceGrid(window, swatches) and #errors == before)
	local mixed = page:Section("mixed", "Mixed", { columns = 2 })
	mixed:Checkbox({ id = "m1", label = "One", path = "m1" })
	mixed:Toggle({ id = "m2", label = "Two", path = "m2" })
	Check("choice card: a non-checkbox draws one to a line and is reported",
		not lib.ChoiceGrid(window, mixed) and #errors == before + 1)
	local described = page:Section("described", "Described", { columns = 2 })
	described:Checkbox({ id = "d1", label = "One", path = "d1", description = "Words." })
	described:Checkbox({ id = "d2", label = "Two", path = "d2" })
	Check("choice card: a description draws one to a line", not lib.ChoiceGrid(window, described))
	local reported = #errors
	local tail = page:Section("tail", "Tail", { columns = 2 })
	tail:Checkbox({ id = "t1", label = "One", path = "t1" })
	tail:Checkbox({ id = "t2", label = "Two", path = "t2" })
	tail:Color({ id = "t3", label = "Three", path = "t3", depends = "t1" })
	tail:Checkbox({ id = "t4", label = "Four", path = "t4", depends = "t1" })
	tail:Color({ id = "t5", label = "Five", path = "t5", depends = "t4" })
	Check("choice card: dependents at the card's end draw two to a line",
		lib.ChoiceGrid(window, tail) and #errors == reported)
	local early = page:Section("early", "Early", { columns = 2 })
	early:Color({ id = "e1", label = "One", path = "e1", depends = "e2" })
	early:Checkbox({ id = "e2", label = "Two", path = "e2" })
	Check("choice card: a dependent before its parent draws one to a line and is reported",
		not lib.ChoiceGrid(window, early) and errors[#errors]:find("comes before") ~= nil)
	local after = page:Section("after", "After", { columns = 2 })
	after:Checkbox({ id = "a1", label = "One", path = "a1" })
	after:Color({ id = "a2", label = "Two", path = "a2", depends = "a1" })
	after:Checkbox({ id = "a3", label = "Three", path = "a3" })
	Check("choice card: an independent row after a dependent draws one to a line and is reported",
		not lib.ChoiceGrid(window, after) and errors[#errors]:find("does not depend") ~= nil)
	local crossed = page:Section("crossed", "Crossed", { columns = 2 })
	crossed:Checkbox({ id = "x1", label = "One", path = "x1" })
	crossed:Checkbox({ id = "x2", label = "Two", path = "x2" })
	crossed:Color({ id = "x3", label = "Three", path = "x3", depends = "x1" })
	crossed:Color({ id = "x4", label = "Four", path = "x4", depends = "x2" })
	Check("choice card: another parent's dependent after a dependent draws one to a line and is reported",
		not lib.ChoiceGrid(window, crossed) and errors[#errors]:find("does not depend") ~= nil)
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
		and not Wanted(font) and not Wanted(hover))
	local rows = {}
	for _, setting in ipairs({ font, more.lines[1][1], classColor, text, hover }) do
		rows[#rows + 1] = { setting = setting }
	end
	lib.OrderUnderParents(rows)
	Check("details: its settings sit under it", rows[2].setting == text and rows[3].setting == font
		and rows[4].setting == classColor and rows[5].setting == hover)
	text:SetValue(true)
	Check("details: opened, its settings are there; one depending on another inside follows that one",
		Wanted(font) and not Wanted(hover))
	Check("details: open or closed lives in the window for the session, not in the store",
		detailsWindow.openDetails["clock/text"] == true and store.text == nil and next(store) == nil)
	Check("details: a row sits in one step for each details row it is inside, whatever it depends on",
		lib.DetailsIndent(text) == 0 and lib.DetailsIndent(more.lines[1][1]) == 0
		and lib.DetailsIndent(font) == lib.DETAILS_STEP and lib.DetailsIndent(hover) == lib.DETAILS_STEP)
	local inner = more:Details({ id = "inner", label = "Inner", details = "text" })
	local nested = more:Checkbox({ id = "nested", label = "Nested", path = "nested", details = "inner" })
	Check("details: rows inside nested details sit in further", lib.DetailsIndent(inner) == lib.DETAILS_STEP
		and lib.DetailsIndent(nested) == 2 * lib.DETAILS_STEP)
	local loopA = more:Details({ id = "loopA", label = "A", details = "loopB" })
	more:Details({ id = "loopB", label = "B", details = "loopA" })
	Check("details: rows naming each other still give an indent", type(lib.DetailsIndent(loopA)) == "number")
	Check("details: only the details row heads what is under it", lib.controls.Details.heads == true
		and not lib.controls.Checkbox.heads)
end

-- Row looks

do
	local store = { useClass = true, gate = true, flip = true }
	local window = NewWindow(store)
	local page = NewPage(window, "looks", "Looks")
	local section = page:Section("rows", "Rows")
	local other = page:Section("other", "Other")
	local function Look(setting, inGrid, revealed)
		local look = {}
		local changed = lib.RowLook(setting, look, inGrid, revealed)

		return look, changed
	end
	section:Toggle({ id = "parent", label = "Parent", path = "parent", default = false })

	local look = Look(section:Toggle({ id = "plain", label = "Plain", path = "plain", default = true }))
	Check("row look: a plain row is active and wanted, with nothing marked or under its label", look.active
		and look.wanted and not look.labelDimmed and not look.controlDimmed and not look.pageOff and look.marker == nil
		and look.inheritedLine == nil and look.secondLine == nil and look.lines == 0 and look.reason == nil
		and look.tooltipReason == nil)

	local offPage = NewPage(window, "off", "Off", { switch = { path = "offPage", default = false } })
	local offSection = offPage:Section("rows", "Rows")
	look = Look(offSection:Toggle({ id = "row", label = "Row", path = "offRow" }))
	Check("row look: under a page switch that is off, a row loses its color only, with no reason", not look.active
		and look.wanted and look.pageOff and not look.labelDimmed and not look.controlDimmed and look.reason == nil
		and look.secondLine == nil and look.tooltipReason == nil)

	look = Look(section:Toggle({ id = "inside", label = "Inside", path = "inside", depends = "parent" }))
	Check("row look: a row whose parent in its section is off is not wanted", not look.active and not look.wanted)

	look = Look(other:Toggle({ id = "across", label = "Across", path = "across", depends = "looks/parent" }))
	Check("row look: a row whose parent is in another section stays, dimmed with the reason", not look.active
		and look.wanted and look.labelDimmed and look.controlDimmed and not look.pageOff and look.secondLine == "reason"
		and look.reason ~= nil and look.tooltipReason == look.reason and look.lines == 1)

	local swatch = section:Color({ id = "swatch", label = "Swatch", path = "swatch" })
	swatch.classSetting = section:Checkbox({ id = "useClass", label = "Use Class Color", path = "useClass" })
	look = Look(swatch)
	Check("row look: a swatch following the class color dims only its control, with no reason", not look.active
		and look.wanted and look.controlDimmed and not look.labelDimmed and not look.pageOff and look.reason == nil
		and look.secondLine == nil and look.tooltipReason == nil)

	look = Look(section:Toggle({ id = "blocked", label = "Blocked", path = "blocked",
		blocked = function() return true end }))
	Check("row look: blocked with no sentence dims with no reason", not look.active and look.labelDimmed
		and look.reason == nil and look.secondLine == nil and look.lines == 0)
	look = Look(section:Toggle({ id = "blockedWhy", label = "Blocked", path = "blockedWhy",
		blocked = function() return "In combat." end }))
	Check("row look: blocked with a sentence shows it", look.labelDimmed and look.reason == "In combat."
		and look.secondLine == "reason" and look.tooltipReason == "In combat." and look.lines == 1)
	look = Look(section:Toggle({ id = "blockedSaid", label = "Blocked", path = "blockedSaid", description = "Words.",
		blocked = function() return true end }))
	Check("row look: blocked with no sentence keeps its description", look.labelDimmed
		and look.secondLine == "description" and look.lines == 1)

	section:Toggle({ id = "gate", label = "Gate", path = "gate" })
	local leaver = section:Toggle({ id = "leaver", label = "Leaver", path = "leaver", depends = "gate" })
	look = Look(leaver)
	store.gate = false
	lib.RowLook(leaver, look, false, 0.5)
	Check("row look: a row leaving keeps its undimmed look while its control stops answering", not look.wanted
		and not look.active and not look.labelDimmed and not look.controlDimmed and look.reason == nil
		and look.secondLine == nil and not look.pageOff)
	Check("row look: and a choice card's tooltip still reads why now", look.tooltipReason ~= nil)
	look = Look(leaver, false, 0)
	Check("row look: a row already gone takes the look of its state", not look.wanted and look.labelDimmed
		and look.reason ~= nil and look.secondLine == "reason")

	local sentence, shown = "In combat.", true
	local fading = section:Toggle({ id = "fading", label = "Fading", path = "fading",
		show = function() return shown end, blocked = function() return sentence end })
	look = Look(fading)
	shown, sentence = false, "Later."
	lib.RowLook(fading, look, false, 1)
	Check("row look: a dimmed row leaving keeps its dimming and its reason", look.labelDimmed and look.controlDimmed
		and look.reason == "In combat." and look.secondLine == "reason" and look.tooltipReason == "Later.")

	local offShown = true
	local offLeaver = offSection:Toggle({ id = "leaver", label = "Leaver", path = "offLeaver",
		show = function() return offShown end })
	look = Look(offLeaver)
	offShown = false
	lib.RowLook(offLeaver, look, false, 1)
	Check("row look: under a switch that is off, a row leaving keeps its color", not look.wanted and not look.active
		and not look.pageOff)
	look = Look(offLeaver, false, 0)
	Check("row look: and one already gone has lost it", look.pageOff)

	local following = section:Toggle({ id = "following", label = "Following", path = "own", inherits = "base" })
	look = Look(following)
	Check("row look: a row following a shared value names it and reserves its line", look.marker == nil
		and look.inheritedLine == "follows" and look.lines == 1)
	store.own = true
	look = Look(following)
	Check("row look: overridden, it is marked and takes the same room", look.marker == "overridden"
		and look.inheritedLine == "overridden" and look.lines == 1)
	local resettable = section:Toggle({ id = "resettable", label = "Resettable", path = "resettable", default = true,
		resettable = true })
	Check("row look: a resettable row at its default has no marker", Look(resettable).marker == nil)
	store.resettable = false
	look = Look(resettable)
	Check("row look: changed from its default, it is marked with no inherited line", look.marker == "changed"
		and look.inheritedLine == nil and look.lines == 0)
	store.resettable = true
	Check("row look: picked back to its default, the mark goes", Look(resettable).marker == nil)

	look = Look(section:Toggle({ id = "said", label = "Said", path = "said", description = "Words." }))
	Check("row look: a description takes a line", look.secondLine == "description" and look.lines == 1)
	look = Look(section:Toggle({ id = "both", label = "Both", path = "both", description = "Words.", inherits = "base" }))
	Check("row look: a description and a shared value take two", look.secondLine == "description"
		and look.inheritedLine == "follows" and look.lines == 2)
	look = Look(other:Toggle({ id = "replaced", label = "Replaced", path = "replaced", description = "Words.",
		depends = "looks/parent" }))
	Check("row look: a reason takes the description's place", look.secondLine == "reason" and look.lines == 1)

	store.overriddenChoice = true
	look = Look(other:Checkbox({ id = "choice", label = "Choice", path = "overriddenChoice", inherits = "base",
		depends = "looks/parent" }), true)
	Check("row look: a choice card's row has no lines, keeps its marker and leaves its reason to the tooltip",
		look.lines == 0 and look.secondLine == nil and look.inheritedLine == nil and look.marker == "overridden"
		and look.labelDimmed and look.tooltipReason ~= nil)

	local changer = section:Toggle({ id = "changer", label = "Changer", path = "changer", depends = "flip",
		blocked = function() return store.changerWhy end })
	section:Toggle({ id = "flip", label = "Flip", path = "flip" })
	local changed
	look, changed = Look(changer)
	Check("row look: a row's first look lays the page out", changed)
	Check("row look: the same look again does not", not lib.RowLook(changer, look))
	store.changerWhy = "No."
	Check("row look: a line more lays the page out", lib.RowLook(changer, look))
	Check("row look: and the same again does not", not lib.RowLook(changer, look))
	store.flip = false
	Check("row look: a row no longer wanted lays the page out", lib.RowLook(changer, look))

	wipe(look)
	Check("row look: a wiped look counts as a first look", lib.RowLook(changer, look))
	store.flip, store.changerWhy = true, nil
	lib.RowLook(changer, look)
	store.flip = false
	wipe(look)
	lib.RowLook(changer, look, false, 0.5)
	Check("row look: a wiped look keeps no old dimming or reason from before", not look.labelDimmed
		and look.reason == nil and look.secondLine == nil)
end

-- Page layout

do
	lib.ROW_INSET = 16
	local ROW, TALL, TITLE = lib.ROW_HEIGHT, lib.TALL_ROW_HEIGHT, lib.SECTION_TITLE_HEIGHT
	local WIDTH = 600
	local function Row(revealed, lines, indent, height)
		return { revealed = revealed, look = { lines = lines or 0 }, indent = indent or 0, setting = { height = height } }
	end
	local function Block(rows, info)
		info = info or {}

		return { header = { shown = info.shown }, rows = rows, notes = info.notes or {}, grid = info.grid }
	end
	-- Runs the layout through a sink that records each call by name, and all of them in order.
	local function Layout(blocks, width)
		local log = { order = {} }
		local sink = {}
		for _, name in ipairs({ "Hidden", "Header", "Row", "Gone", "Rule", "Fill", "Note" }) do
			log[name] = {}
			sink[name] = function(_, ...)
				table.insert(log[name], { ... })
				table.insert(log.order, name)
			end
		end
		sink.Note = function(_, note, top, noteWidth)
			table.insert(log.Note, { note, top, noteWidth })
			table.insert(log.order, "Note")

			return note.height
		end
		local total = lib.PageLayout(blocks, width or WIDTH, sink)

		return log, total
	end
	local function Separators(log)
		local rules = {}
		for _, rule in ipairs(log.Rule) do
			if rule[1] == "separator" then
				rules[#rules + 1] = rule
			end
		end

		return rules
	end

	local log, padding = Layout({})
	Check("page layout: an empty page is its padding alone", #log.order == 0 and padding > 0)

	local half = Row(1)
	local total
	log, total = Layout({ Block({ half }) })
	local header, row, fill = log.Header[1], log.Row[1], log.Fill[1]
	local gap = header[2]
	local cardTop = gap + TITLE
	Check("page layout: a row sits under its section's gap and title, full width and opaque", gap > 0 and row[1] == half
		and row[2] == 0 and Near(row[3], cardTop) and row[4] == WIDTH and Near(row[5], ROW) and row[6] == 1)
	Check("page layout: the header runs to the card's end and the content past it", header[1] ~= nil
		and Near(header[3], cardTop + ROW) and header[4] == WIDTH and Near(total, cardTop + ROW + padding))
	Check("page layout: the card's fill covers its rows", Near(fill[1], cardTop) and fill[2] == WIDTH and Near(fill[3], ROW))
	local top, bottom, leftEdge, rightEdge = log.Rule[1], log.Rule[2], log.Rule[3], log.Rule[4]
	Check("page layout: the card's top edge", top[1] == "cardEdge" and top[2] == 0 and Near(top[3], cardTop)
		and top[4] == WIDTH and top[5] == 1)
	Check("page layout: the card's bottom edge lies inside it", bottom[2] == 0 and Near(bottom[3], cardTop + ROW - 1)
		and bottom[4] == WIDTH and bottom[5] == 1)
	Check("page layout: the card's side edges fit between the others", leftEdge[2] == 0 and Near(leftEdge[3], cardTop + 1)
		and leftEdge[4] == 1 and Near(leftEdge[5], ROW - 2) and rightEdge[2] == WIDTH - 1 and Near(rightEdge[3], cardTop + 1)
		and rightEdge[4] == 1 and Near(rightEdge[5], ROW - 2))

	log = Layout({ Block({ Row(1, 1) }) })
	Check("page layout: a row with lines under its label is tall", Near(log.Row[1][5], TALL))
	log = Layout({ Block({ Row(1, 0, 0, 100) }) })
	Check("page layout: a setting's larger height wins, with its margin", Near(log.Row[1][5], 116))
	log = Layout({ Block({ Row(1, 1, 0, 1) }) })
	Check("page layout: a setting's smaller height does not", Near(log.Row[1][5], TALL))

	log = Layout({ Block({ Row(1), Row(1, 0, 12) }) })
	local separators = Separators(log)
	Check("page layout: a separator between two rows starts at the lower row's indent", #separators == 1
		and separators[1][2] == 28 and Near(separators[1][3], cardTop + ROW) and separators[1][4] == WIDTH - 28
		and separators[1][5] == 1 and separators[1][6] == 1)
	Check("page layout: and takes a unit of height", Near(log.Row[2][3], cardTop + ROW + 1))

	log = Layout({ Block({ Row(1), Row(0.5) }) })
	separators = Separators(log)
	Check("page layout: a row in motion takes its share of its height, its separator fading and shrinking with it",
		Near(log.Row[2][5], ROW * 0.5) and Near(log.Row[2][3], cardTop + ROW + 0.5) and separators[1][5] == 1
		and Near(separators[1][6], 0.5))
	Check("page layout: and fades by the square of its share", Near(log.Row[2][6], 0.25))

	local gone = Row(0)
	log = Layout({ Block({ gone, Row(1), { indent = 0, setting = {} }, Row(1) }) })
	separators = Separators(log)
	Check("page layout: a row gone takes no height or separator", #log.Gone == 2 and log.Gone[1][1] == gone
		and #log.Row == 2 and #separators == 1 and Near(log.Row[1][3], cardTop) and Near(log.Row[2][3], cardTop + ROW + 1))

	log, total = Layout({ Block({ Row(0) }) })
	Check("page layout: a section with every row gone has a heading and no card", #log.Fill == 0 and #log.Rule == 0
		and Near(log.Header[1][3], log.Header[1][2] + TITLE) and Near(total, gap + TITLE + padding))

	local hidden = Block({ Row(1) }, { shown = false, notes = { { height = 20 } } })
	log, total = Layout({ hidden })
	Check("page layout: a hidden section takes no room and draws nothing", #log.order == 1 and log.Hidden[1][1] == hidden
		and Near(total, padding))
	log = Layout({ Block({}, { shown = nil }) })
	Check("page layout: a section not yet told shows", #log.Hidden == 0 and #log.Header == 1)

	local first, second = { height = 20 }, { height = 5 }
	log, total = Layout({ Block({ Row(1) }, { notes = { first, second } }) })
	Check("page layout: notes sit under the card, each below the last", log.Note[1][1] == first
		and Near(log.Note[1][2], cardTop + ROW) and log.Note[1][3] == WIDTH and Near(log.Note[2][2], cardTop + ROW + 20))
	Check("page layout: a note's height counts in the content but not in its section's bottom",
		Near(log.Header[1][3], cardTop + ROW) and Near(total, cardTop + ROW + 25 + padding))

	local a, b, c, d = Row(1, 1), Row(1), Row(1), Row(1)
	log = Layout({ Block({ a, b, c, d }, { grid = true }) }, 601)
	separators = Separators(log)
	Check("page layout: a choice card draws two to a line, the left column rounded down", #log.Row == 4
		and log.Row[1][1] == a and log.Row[1][2] == 0 and log.Row[1][4] == 300 and log.Row[2][1] == b
		and log.Row[2][2] == 300 and log.Row[2][4] == 301)
	Check("page layout: a choice card's rows stay short whatever they hold", Near(log.Row[1][5], ROW))
	Check("page layout: a choice card's lines have a rule between their columns and one between them", #separators == 3
		and separators[1][2] == 300 and Near(separators[1][3], cardTop) and separators[1][4] == 1
		and Near(separators[1][5], ROW) and separators[2][2] == 16 and Near(separators[2][3], cardTop + ROW)
		and separators[2][4] == 601 - 16 and separators[2][5] == 1 and separators[3][2] == 300
		and Near(separators[3][3], cardTop + ROW + 1))
	Check("page layout: a choice card's next line sits below its rule", Near(log.Row[3][3], cardTop + ROW + 1)
		and log.Row[3][1] == c and log.Row[4][1] == d)

	local last = Row(1)
	log = Layout({ Block({ Row(1), Row(1), last }, { grid = true }) })
	separators = Separators(log)
	Check("page layout: an odd row out sits alone at the left, with no rule beside it", #log.Row == 3
		and log.Row[3][1] == last and log.Row[3][2] == 0 and log.Row[3][4] == WIDTH / 2 and #separators == 2)

	local away, closes = Row(0), Row(1)
	log = Layout({ Block({ Row(1), away, closes }, { grid = true }) })
	Check("page layout: a row gone gives up its place in a choice card", #log.Gone == 1 and log.Gone[1][1] == away
		and log.Row[2][1] == closes and log.Row[2][2] == WIDTH / 2 and Near(log.Row[2][3], cardTop))

	log = Layout({ Block({ Row(1), Row(0.5), Row(0.25), Row(0.5) }, { grid = true }) })
	separators = Separators(log)
	Check("page layout: a choice card's line takes its larger share", Near(log.Row[1][5], ROW)
		and Near(log.Row[3][5], ROW * 0.5))
	Check("page layout: each row fades by its own", log.Row[1][6] == 1 and Near(log.Row[2][6], 0.25)
		and Near(log.Row[3][6], 0.0625) and Near(log.Row[4][6], 0.25))
	Check("page layout: the rule beside a row fades with it, and the rule above a line with the line",
		Near(separators[1][6], 0.5) and Near(separators[2][6], 0.5) and Near(separators[3][6], 0.5)
		and Near(log.Row[3][3], cardTop + ROW + 0.5))

	log = Layout({ Block({ { revealed = 1, indent = 0, setting = {} } }) })
	Check("page layout: a row with no look yet counts as having no lines", Near(log.Row[1][5], ROW))

	log = Layout({ Block({ Row(1) }), Block({ Row(1) }) })
	Check("page layout: a later section starts its gap below the one before", Near(log.Header[2][2], log.Header[1][3] + gap))
	Check("page layout: each section's calls come in order, its header after its rows",
		table.concat(log.order, " ") == "Row Fill Rule Rule Rule Rule Header Row Fill Rule Rule Rule Rule Header")
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
	local link = section:LinkMenu({ text = "Copy", build = function() end })
	Check("link menu: belongs to its section and takes no row", section.linkMenu == link and section.lines[#section.lines].setting ~= link)
	before = #errors
	section:LinkMenu({ text = "Again", build = function() end })
	Check("link menu: a second on a section is reported", #errors == before + 1 and section.linkMenu == link)
	before = #errors
	page:Section("noBuild", "No Build"):LinkMenu({ text = "Copy" })
	Check("link menu: one without build is reported", #errors == before + 1)
	before = #errors
	page:Section("extra", "Extra"):LinkMenu({ text = "Copy", build = function() end, odd = true })
	Check("link menu: an unknown field is reported", #errors == before + 1)
	window.RefreshUndo = function() end
	copy:Request("other")
	Check("menu: picking an action runs set without recording Undo",
		picked == "other" and #(window.undoSteps or {}) == 0)
end

-- Dropdowns with several choices

do
	local store = {}
	local window = NewWindow(store)
	window.RefreshUndo = function() end
	local recorded = {}
	window.RecordChange = function(_, change) recorded[#recorded + 1] = change end
	window.SettingChanged = function() end
	local page = NewPage(window, "effects", "Effects")
	local section = page:Section("look", "Look")
	local effects = section:Dropdown({ id = "effects", label = "Effects", path = "look.effects", multiple = true,
		default = { grow = true, edge = false },
		options = { { value = "edge", text = "Highlight Border" }, { value = "grow", text = "Grow" } } })
	Check("multiple: each choice reads its default until stored",
		effects:ItemEnabled("grow") and not effects:ItemEnabled("edge"))
	Check("multiple: the closed text names the choices on", effects:FormatValue({}) == "Grow")
	effects:SetItemEnabled({ value = "edge", text = "Highlight Border" }, true)
	Check("multiple: a choice is stored at its own path, one Undo step",
		store.look.effects.edge == true and #recorded == 1 and recorded[1].path == "look.effects.edge")
	Check("multiple: in the list's order", effects:FormatValue(store.look.effects) == "Highlight Border, Grow")
	Check("multiple: none on reads None", effects:FormatValue({ grow = false }) == (NONE or "None"))
	Check("multiple: its picks are left out of the setting's own Undo", effects.noUndo == true)
	local before = #errors
	section:Dropdown({ id = "noPath", multiple = true, options = {} })
	Check("multiple: a dropdown with several choices without a path is reported", #errors > before)
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
	Check("undo: quick slider saves are one step", #window.undoSteps == 1)
	now = now + 5
	slider:Request(13)
	Check("undo: a later save is a new step", #window.undoSteps == 2)
	now = now + 0.5
	slider:Request(12)
	Check("undo: a step that ends where it began is dropped", #window.undoSteps == 1)

	local pick = {}
	color:Request({ r = 1, g = 0, b = 0 }, pick)
	now = now + 10
	color:Request({ r = 0, g = 1, b = 0 }, pick)
	Check("undo: saves of one gesture are one step, however far apart", #window.undoSteps == 2)
	color:Request({ r = 0, g = 0, b = 1 }, {})
	Check("undo: another gesture is a new step", #window.undoSteps == 3)

	toggle:Request(true)
	window:Undo()
	Check("undo: Undo puts the earlier value back", store.on == nil and toggle:GetValue() == false)
	window:Undo()
	window:Undo()
	Check("undo: a whole pick is undone at once", store.tint == nil)
	window:Undo()
	Check("undo: the merged slider steps go back to the start", store.size == nil and #window.undoSteps == 0)
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
	window:RecordChange({ path = "gaps", before = {}, merge = "x" })
	now = now + 0.5
	window:RecordChange({ path = "gaps", before = { x = 4 }, merge = "x" })
	Check("change: the same path and merge moments later join one step", #window.undoSteps == 2)
	window:RecordChange({ path = "gaps", before = {}, merge = "y" })
	Check("change: another merge value is a new step", #window.undoSteps == 3)
	local page = NewPage(window, "after", "After")
	local slider = page:Section("one", "One"):Slider({ id = "size", label = "Size", path = "size", default = 1 })
	slider:Request(2)
	Check("change: a setting saved after one is its own step", #window.undoSteps == 4)
	window:Undo()
	window:Undo()
	window:Undo()
	Check("change: Undo writes the first earlier value back", next(store.gaps) == nil)
	window:Undo()
	Check("change: through the declaration's write, as the value was when recorded", store.order[1] == "a"
		and store.order[2] == "b"
		and #window.undoSteps == 0)
	store.order, store.gaps = { "c" }, { x = 1 }
	window:RecordChange({ paths = { { path = "order", before = { "a", "b" } }, { path = "gaps", before = {} } },
		text = "Both back." })
	Check("change: several paths are one step", #window.undoSteps == 1)
	window:Undo()
	Check("change: Undo writes each path back", store.order[2] == "b" and next(store.gaps) == nil
		and #window.undoSteps == 0)

	local written, refused = {}, {}
	window.declaration.write = function(path, value)
		written[#written + 1] = path
		if refused[path] ~= nil then
			return false, refused[path] or nil
		end
		store[path] = value
	end
	local shown = #errors
	window:RecordChange({ path = "order", before = { "a" } })
	window:Undo()
	Check("change: a path put back shows no refusal", #errors == shown and store.order[1] == "a")
	refused.order = "Locked."
	store.order = { "kept" }
	window:RecordChange({ path = "order", before = { "a" } })
	window:Undo()
	Check("change: a refused path shows the reason", #errors == shown + 1 and errors[#errors]:find("Locked") ~= nil)
	Check("change: without a doubled period", errors[#errors]:find("%.%.") == nil)
	Check("change: a refused path keeps its value and leaves the history", store.order[1] == "kept"
		and #window.undoSteps == 0)
	refused.order = false
	window:RecordChange({ path = "order", before = { "a" } })
	window:Undo()
	Check("change: a path refused with no reason still says so", #errors == shown + 2
		and errors[#errors]:find("Undo", 1, true) ~= nil and store.order[1] == "kept")
	refused.order, refused.gaps = "Locked.", nil
	store.gaps = { x = 1 }
	wipe(written)
	window:RecordChange({ paths = { { path = "gaps", before = {} }, { path = "order", before = { "a" } } } })
	window:Undo()
	Check("change: one refused path of several shows, and the rest are still put back, last first",
		#errors == shown + 3 and next(store.gaps) == nil and store.order[1] == "kept" and written[1] == "order"
		and written[2] == "gaps" and #window.undoSteps == 0)
end

-- Path writes

do
	local store = {}
	local window = NewWindow(store)
	local page = NewPage(window, "paths", "Paths")
	local section = page:Section("one", "One")
	local bound = section:Slider({ id = "bound", label = "Bound", path = "deep.bound", default = 1 })
	local ok, reason = lib.WritePath(window, "a.b.c", 5)
	Check("path write: with no hook it writes the store, making tables on the way", ok and store.a.b.c == 5)
	Check("path write: and overwrites what is not a table", lib.WritePath(window, "a.b.c.d", 6) and store.a.b.c.d == 6)
	local storeless = NewWindow(nil)
	Check("path write: with no store it says so", lib.WritePath(storeless, "a", 1) == false)

	local calls = {}
	window.declaration.write = function(path, value, setting)
		calls[#calls + 1] = { path = path, value = value, setting = setting }
		if path:find("^locked") then
			return false, "Locked."
		end
	end
	Check("path write: through a hook, which counts any other answer as written", lib.WritePath(window, "open", 1)
		and calls[1].path == "open" and calls[1].value == 1)
	Check("path write: the hook gets no setting", calls[1].setting == nil)
	ok, reason = lib.WritePath(window, "locked", 1)
	Check("path write: a refusal comes back with its reason", ok == false and reason == "Locked.")
	bound:Request(2)
	Check("path write: a setting bound by a path passes itself", calls[#calls].path == "deep.bound"
		and calls[#calls].setting == bound)

	wipe(calls)
	window:ClearUndo()
	window.SelectPage = function() end
	local list = section:Toggle({ id = "list", label = "List", path = "list" })
	list.enabled = { path = "list.on", default = { a = true } }
	local item = { value = "b", text = "B" }
	Check("items: one off by default is off", not list:ItemEnabled("b") and list:ItemEnabled("a"))
	list:SetItemEnabled(item, true)
	Check("items: turning one on writes its path with no setting", calls[1].path == "list.on.b" and calls[1].value == true
		and calls[1].setting == nil)
	Check("items: and is one step", #window.undoSteps == 1)
	window:Undo()
	Check("items: Undo puts its path back", calls[2].path == "list.on.b" and calls[2].value == nil
		and #window.undoSteps == 0)
	local shown = #errors
	local locked = section:Toggle({ id = "lockedList", label = "Locked List", path = "lockedList" })
	locked.enabled = { path = "locked" }
	locked:SetItemEnabled(item, true)
	Check("items: a refusal names the setting and records nothing", #errors == shown + 1
		and errors[#errors]:find("Locked List", 1, true) ~= nil and #window.undoSteps == 0)
end

-- Undo: merging, landing, the tooltip and what counts as the same value

do
	local store = {}
	local window = NewWindow(store)
	local page = NewPage(window, "main", "Main")
	local section = page:Section("one", "One")
	local size = section:Slider({ id = "size", label = "Size", path = "size", default = 1 })
	local shown = true
	local hidden = section:Toggle({ id = "hidden", label = "Hidden", path = "hidden", default = false,
		show = function() return shown end })
	local landed, selected = {}, {}
	window.LandOn = function(_, setting) landed[#landed + 1] = setting end
	window.SelectPage = function(_, id) selected[#selected + 1] = id end

	window:RecordChange({ paths = { { path = "x", before = 1 } }, merge = "m" })
	now = now + 0.1
	window:RecordChange({ path = "x", before = 2, merge = "m" })
	Check("undo merge: a step of several paths never merges", #window.undoSteps == 2)
	window:ClearUndo()
	window:RecordUndoGroup({ { setting = size, before = 1 } })
	now = now + 0.1
	size:Request(5)
	Check("undo merge: a group never merges", #window.undoSteps == 2)
	window:ClearUndo()
	window:RecordChange({ path = "x", before = 1, merge = "m" })
	now = now + 0.1
	size:Request(6)
	Check("undo merge: a setting does not join a path before it", #window.undoSteps == 2)
	window:ClearUndo()

	size:Request(7)
	window:Undo()
	Check("undo landing: a setting's step lands on it", landed[1] == size and #selected == 0)
	wipe(landed)
	window:RecordChange({ path = "x", before = 1, page = "main" })
	window:Undo()
	Check("undo landing: a path's step shows its page", selected[1] == "main" and #landed == 0)
	wipe(selected)
	window:RecordChange({ path = "x", before = 1 })
	window:Undo()
	Check("undo landing: a path's step with no page stays", #selected == 0 and #landed == 0)
	hidden:Request(true)
	shown = false
	window:Undo()
	Check("undo landing: a setting now hidden is not landed on", #landed == 0)
	shown = true

	local lines = {}
	GameTooltip = {
		SetOwner = function() end, SetText = function() end, Show = function() end, IsOwned = function() return false end,
		AddLine = function(_, text) lines[#lines + 1] = text end,
	}
	local function Line()
		wipe(lines)
		window.frame = { footer = { undo = {} } }
		lib.UndoHandlers.Enter(window)
		window.frame = nil

		return lines[1]
	end
	window:ClearUndo()
	Check("undo tooltip: with nothing to undo it says so", Line() == lib.L.NOTHING_TO_UNDO)
	store.size = 6
	size:Request(8)
	Check("undo tooltip: a setting's step names it and its earlier value", Line() == lib.L.UNDO_TO:format("Size", "6"))
	window:ClearUndo()
	window:RecordUndoGroup({ { setting = size, before = 1 }, { setting = hidden, before = false } })
	Check("undo tooltip: a group counts its settings", Line() == lib.L.UNDO_SETTINGS:format(2))
	window:ClearUndo()
	window:RecordChange({ path = "x", before = 1, text = "Back." })
	Check("undo tooltip: a path's step says its text", Line() == "Back.")
	window:ClearUndo()
	window:RecordChange({ paths = { { path = "x", before = 1 } } })
	Check("undo tooltip: and without one, the general line", Line() == lib.L.UNDO_CHANGE)
	GameTooltip = nil

	window:ClearUndo()
	store.size = 1
	size:Request(1.0003)
	Check("undo same: a value this close is no change", #window.undoSteps == 0)
	store.size = 1
	size:Request(1.01)
	Check("undo same: a value further off is", #window.undoSteps == 1)
	window:ClearUndo()
	store.size = 1
	size:Request(2)
	now = now + 0.1
	size:Request(1.0003)
	Check("undo same: a step that ends this close to where it began is dropped", #window.undoSteps == 0)
	Check("same value: tables compare by their numbers' closeness", lib.SameValue({ r = 0.5 }, { r = 0.5003 })
		and not lib.SameValue({ r = 0.5 }, { r = 0.51 }) and not lib.SameValue({ r = 0.5 }, { r = 0.5, g = 1 }))
	local original = { a = { 1 } }
	local copy = lib.CopyValue(original)
	Check("copy value: a copy shares nothing", copy ~= original and copy.a ~= original.a and copy.a[1] == 1)
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

	local unitsShown = false
	local units = NewPage(window, "units", "Unit Tooltips")
	units.show = function() return unitsShown end
	local names = units:Section("names", "Names")
	names:Toggle({ id = "rank", label = "Guild Rank", path = "rank" })
	window.searchIndex = nil
	Check("search: a page its show hides is left out, with its settings",
		not Finds("unit tooltips", "Unit Tooltips") and not Finds("rank", "Guild Rank"))
	unitsShown = true
	Check("search: shown again, it is found", Finds("unit tooltips", "Unit Tooltips") and Finds("rank", "Guild Rank"))
	units.show = function() error("broken show") end
	local handler = geterrorhandler
	geterrorhandler = function() return function() end end
	Check("page show: an error hides the page instead of breaking search", not lib.PageShown(units)
		and not Finds("rank", "Guild Rank"))
	geterrorhandler = handler
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
