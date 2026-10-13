-- The settings model: pages hold sections, sections hold settings, notes and empty places laid out two to a line.
-- Each setting is one object, made once at registration and holding no frames; its value is bound by a path in the
-- adopter's store and a default, or by `get` and `set`. Pages draw settings with pooled views (Page.lua).

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

-- Methods are looked up on the library at call time, so objects made through an older copy use the newest code.
lib.PageModel = {}
lib.Section = {}
lib.Setting = {}
lib.controls = lib.controls or {}
local pageMeta = { __index = function(_, name) return lib.PageModel[name] end }
local sectionMeta = { __index = function(_, name) return lib.Section[name] end }
local settingMeta = { __index = function(_, name) return lib.Setting[name] end }

-- An empty place in a line (`section:Skip()`).
lib.EMPTY = lib.EMPTY or { empty = true }

local SETTING_FIELDS = { id = true, label = true, description = true, path = true, default = true, get = true,
	set = true, depends = true, blocked = true, show = true, wide = true }
local MAX_CHAIN = 16

---Registers a control kind: `section:<Kind>(info)` declares a setting drawn with it. `info.fields` lists the fields
---the kind adds; `info.Create(half)` makes its view (see Page.lua for the view contract).
function lib:RegisterControl(kind, info)
	self.controls[kind] = info
	self.Section[kind] = function(section, settingInfo)
		return section:Add(kind, settingInfo)
	end
end

-- Calls an adopter's function, reporting an error instead of breaking the window.
local function Call(fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		geterrorhandler()(a)
		return
	end

	return a, b
end
lib.CallAdopter = Call

-- Pages -------------------------------------------------------------------------------------------------------

-- Called by window:Page once the navigation entry exists: gives it its sections and its switch.
function lib:InitPage(window, page, info)
	setmetatable(page, pageMeta)
	page.window = window
	page.sections = {}
	page.settings = {}
	if info.switch ~= nil then
		local switch = type(info.switch) == "table" and info.switch or {}
		switch.id = switch.id or "enabled"
		switch.label = switch.label or L.ENABLED
		page.switch = page:NewSetting("Toggle", switch)
	end
end

---Adds a section with a gold title and a rule; its settings follow it.
---@return table? section
function lib.PageModel:Section(id, title)
	local section = setmetatable({ id = id, title = title, page = self, lines = {} }, sectionMeta)
	table.insert(self.sections, section)

	return section
end

---Makes a setting object for this page (`kind` a registered control) without placing it in a section.
function lib.PageModel:NewSetting(kind, info)
	local window = self.window
	local control = lib.controls[kind]
	if not control then
		lib:Report(window.addonName, ("unknown control %q"):format(tostring(kind)))
		return
	end
	if type(info) ~= "table" or info.id == nil then
		lib:Report(window.addonName, ("page %s: a %s needs an id"):format(self.id, kind))
		return
	end
	for field in pairs(info) do
		if not SETTING_FIELDS[field] and not (control.fields and control.fields[field]) then
			lib:Report(window.addonName, ("%s/%s: unknown field %q"):format(self.id, info.id, tostring(field)))
		end
	end
	if self.settings[info.id] then
		lib:Report(window.addonName, ("%s: setting id %q is used twice"):format(self.id, info.id))
		return
	end
	local setting = setmetatable(info, settingMeta)
	setting.kind, setting.page, setting.window = kind, self, window
	if type(info.path) == "string" then
		setting.keys = { strsplit(".", info.path) }
	elseif not info.get and not control.noValue then
		lib:Report(window.addonName, ("%s/%s: needs a path, or get and set"):format(self.id, info.id))
	end
	self.settings[info.id] = setting

	return setting
end

-- Sections ----------------------------------------------------------------------------------------------------

-- Puts an entry in the section's next free half, or on a line of its own when `wide`.
local function Place(section, entry, wide)
	local lines = section.lines
	local last = lines[#lines]
	if wide or not last or last.wide or last.note or last[2] ~= nil then
		table.insert(lines, { entry, wide = wide or nil })
	else
		last[2] = entry
	end
end

---Declares a setting of a registered control kind in this section (`section:Toggle(info)` calls this).
function lib.Section:Add(kind, info)
	local setting = self.page:NewSetting(kind, info)
	if setting then
		setting.section = self
		Place(self, setting, setting.wide)
	end

	return setting
end

---Leaves the next half empty.
function lib.Section:Skip()
	Place(self, lib.EMPTY, false)
end

---Adds a line of text across the section, with an optional smaller second part.
function lib.Section:Note(text, small)
	table.insert(self.lines, { note = { text = text, small = small } })
end

-- Settings ----------------------------------------------------------------------------------------------------

local function Store(window)
	local store = window.declaration.store
	if type(store) == "function" then
		store = Call(store)
	end

	return type(store) == "table" and store or nil
end

---@return any value the stored value, or the default when nothing is stored
function lib.Setting:GetValue()
	local value
	if self.get then
		value = Call(self.get, self)
	elseif self.keys then
		value = Store(self.window)
		for index = 1, #self.keys do
			if type(value) ~= "table" then
				value = nil
				break
			end
			value = value[self.keys[index]]
		end
	end
	if value == nil then
		return self.default
	end

	return value
end

-- Writes a value; returns false and a sentence when the adopter's `set` refuses it.
local function Write(setting, value)
	if setting.set then
		local ok, reason = Call(setting.set, value, setting)
		if ok == false then
			return false, reason
		end
		return true
	end
	local store = setting.keys and Store(setting.window)
	if not store then
		return false
	end
	local keys = setting.keys
	for index = 1, #keys - 1 do
		local nextTable = store[keys[index]]
		if type(nextTable) ~= "table" then
			nextTable = {}
			store[keys[index]] = nextTable
		end
		store = nextTable
	end
	store[keys[#keys]] = value

	return true
end

-- Title Case for the refusal message (C-01): every word's first letter capitalized, the rest as written.
local function TitleCase(text)
	return (text:gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
end
lib.TitleCase = TitleCase

---Saves a value from code: the window redraws it at once. Returns false and the reason when refused.
function lib.Setting:SetValue(value)
	local ok, reason = Write(self, value)
	self.window:SettingChanged(self, true)

	return ok, reason
end

---Saves a value the user chose. A refusal shows "Couldn't save <label>: <reason>" at the top of the screen.
---@return boolean ok
function lib.Setting:Request(value)
	local ok, reason = Write(self, value)
	if not ok then
		self:ShowRefusal(reason)
	end
	self.window:SettingChanged(self, false, not ok)

	return ok
end

---Shows "Couldn't save <label>: <reason>." (or without a reason) at the top of the screen, in Title Case.
function lib.Setting:ShowRefusal(reason)
	local name = self.label or tostring(self.id)
	local message = reason and L.COULDNT_SAVE_REASON:format(name, (reason:gsub("%.$", ""))) or L.COULDNT_SAVE:format(name)
	UIErrorsFrame:AddExternalErrorMessage(TitleCase(message))
end

---Refuses a value the control itself will not take (its own rules): the message, then the saved value redrawn
---with the refusal shake.
function lib.Setting:Refuse(reason)
	self:ShowRefusal(reason)
	self.window:SettingChanged(self, true, true)
end

-- The setting this one depends on, found by id on its page, or "page/id" on another page of the window.
function lib.Setting:Parent()
	local depends = self.depends
	if depends == nil then
		return nil
	end
	if self.parentSetting == nil then
		local pageId, id = tostring(depends):match("^(.-)/(.+)$")
		local page = pageId and self.window.pages[pageId] or self.page
		local parent = page and page.settings and page.settings[id or depends]
		if not parent then
			lib:Report(self.window.addonName, ("%s/%s depends on unknown %q"):format(self.page.id, self.id, tostring(depends)))
		end
		self.parentSetting = parent or false
	end

	return self.parentSetting or nil
end

---Whether the setting can be changed now, and why not: the page's switch first, then the furthest setting up its
---`depends` chain that is off, then `blocked()` (true, or a sentence giving the reason).
---@return boolean active
---@return string? reason
---@return string? cause "page", "depends" or "blocked"
function lib.Setting:Activity()
	local switch = self.page.switch
	if switch and switch ~= self and not switch:GetValue() then
		return false, nil, "page"
	end
	local reason
	local parent, depth = self:Parent(), 0
	while parent and depth < MAX_CHAIN do
		if not parent:GetValue() then
			reason = L.REQUIRES:format(parent.label or tostring(parent.id))
		end
		parent, depth = parent:Parent(), depth + 1
	end
	if reason then
		return false, reason, "depends"
	end
	if self.blocked then
		local blocked = Call(self.blocked, self)
		if blocked then
			return false, type(blocked) == "string" and blocked or nil, "blocked"
		end
	end

	return true
end

---@return boolean shown false while the setting's `show()` hides it
function lib.Setting:IsShown()
	if not self.show then
		return true
	end

	return Call(self.show, self) and true or false
end
