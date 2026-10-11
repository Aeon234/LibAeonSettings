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

function Harness:CreateFrames()
	self.frames = {
		bar = SampleFrame("Bar", 600, 26, "Harness Bar (fixed edge: BOTTOM)", 0.08, 0.08, 0.1),
		unit = SampleFrame("Unit", 220, 48, "Harness Unit", 0.1, 0.35, 0.12),
		icon = SampleFrame("Icon", 40, 40, "Icon", 0.45, 0.3, 0.1),
	}
	self.frames.icon:SetScale(1.5)
	local unitSize = self:Profile().unitSize
	if unitSize then
		self.frames.unit:SetSize(unitSize[1], unitSize[2])
	end
	self.targets = {
		{ key = "bar", label = "Harness Bar", frame = self.frames.bar, default = { point = "BOTTOM", x = 0, y = 120 },
			fixedEdge = "BOTTOM" },
		{ key = "unit", label = "Harness Unit", subtitle = "Sample while editing", frame = self.frames.unit,
			default = { point = "CENTER", x = -280, y = -120 },
			sample = function(shown) self.frames.unit.text:SetText(shown and "Harness Unit (sample)" or "Harness Unit") end,
			size = {
				min = 20,
				get = function() return self.frames.unit:GetSize() end,
				set = function(width, height)
					self.frames.unit:SetSize(width, height)
					local db = Harness:Profile()
					db.unitSize = { width, height }
				end,
			},
			settings = function(target) Print("Element Options for %s: the adopter would open its settings page here", target.key) end },
		{ key = "icon", label = "Harness Icon", frame = self.frames.icon, default = { point = "TOPRIGHT", x = -240, y = -200 } },
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

function COMMANDS.edit()
	lib:OpenEditMode(ADDON_NAME)
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

function COMMANDS.media()
	Print("media path: %s", lib.mediaPath)
end

function COMMANDS.help()
	Print("/lasdev edit | hide <key> | pend <key> <dx> <dy> | move | show | set <key> <POINT> <x> <y> | reset [key] | profile <name> | off <key> | scale <key> <n> | bad | media")
end

SLASH_LIBAEONSETTINGSDEV1 = "/lasdev"
SlashCmdList.LIBAEONSETTINGSDEV = function(input)
	local command, a, b, c, d = strsplit(" ", strtrim(input or ""))
	local handler = COMMANDS[(command or ""):lower()] or COMMANDS.help
	handler(a, b, c, d)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name == ADDON_NAME then
		self:UnregisterEvent("ADDON_LOADED")
		Harness:Register()
	end
end)
