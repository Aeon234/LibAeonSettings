-- The settings model: pages hold sections, sections hold settings, notes and empty places, declared two to a line
-- and drawn one to a line, or two to a line in a section declared with `columns = 2` (a choice card).
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
	set = true, depends = true, blocked = true, show = true, wide = true, inherits = true, keywords = true,
	tooltip = true, redraws = true, resettable = true, details = true }
local SECTION_FIELDS = { show = true, reveal = true, columns = true }
local MAX_CHAIN = 16

---Registers a control kind: `section:<Kind>(info)` declares a setting drawn with it. `info.fields` lists the fields
---the kind adds; `info.Create(half)` makes its view (see Page.lua for the view contract); `info.Init(setting)`, if
---given, runs on each new setting before its value binding is checked.
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
		switch.label = switch.label or page.title
		page.switch = page:NewSetting("Toggle", switch)
	end
end

---Adds a section: a heading over a card of its settings, its notes under the card. `info.show(section)`, when given,
---hides the whole section (heading, rows, notes and menu) and leaves it out of search while it returns false.
---`info.columns = 2` asks for a choice card (see `lib.ChoiceGrid`).
---`info.reveal(section)`, with `show`, keeps a hidden section's rows in search: landing on one calls it first, to
---make the section show (selecting what it edits).
---@param info table? { show?, reveal?, columns? }
---@return table? section
function lib.PageModel:Section(id, title, info)
	local section = setmetatable({ id = id, title = title, page = self, lines = {} }, sectionMeta)
	if info ~= nil then
		local addonName = self.window.addonName
		if type(info) ~= "table" then
			lib:Report(addonName, ("%s/%s: section info must be a table"):format(self.id, tostring(id)))
		else
			for field in pairs(info) do
				if not SECTION_FIELDS[field] then
					lib:Report(addonName, ("%s/%s: unknown section field %q"):format(self.id, tostring(id),
						tostring(field)))
				end
			end
			if type(info.show) == "function" then
				section.show = info.show
			elseif info.show ~= nil then
				lib:Report(addonName, ("%s/%s: section show must be a function"):format(self.id, tostring(id)))
			end
			if type(info.reveal) == "function" then
				section.reveal = info.reveal
			elseif info.reveal ~= nil then
				lib:Report(addonName, ("%s/%s: section reveal must be a function"):format(self.id, tostring(id)))
			end
			if info.columns == 1 or info.columns == 2 then
				section.columns = info.columns
			elseif info.columns ~= nil then
				lib:Report(addonName, ("%s/%s: section columns must be 1 or 2"):format(self.id, tostring(id)))
			end
		end
	end
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
	if control.Init then
		control.Init(setting)
	end
	if info.inherits ~= nil then
		local inherits = type(info.inherits) == "table" and info.inherits or { path = info.inherits }
		if type(inherits.path) == "string" then
			inherits.keys = { strsplit(".", inherits.path) }
		elseif not inherits.get then
			lib:Report(window.addonName, ("%s/%s: inherits needs a path or get"):format(self.id, info.id))
		end
		inherits.from = inherits.from or L.SHARED
		setting.inherits = inherits
	end
	-- A setting inside a details row is there while the row is open: it depends on the row unless it depends on
	-- another setting inside it.
	if info.details ~= nil and info.depends == nil then
		setting.depends = info.details
	end
	if type(info.path) == "string" then
		setting.keys = { strsplit(".", info.path) }
	elseif not info.get and not control.noValue then
		lib:Report(window.addonName, ("%s/%s: needs a path, or get and set"):format(self.id, info.id))
	end
	self.settings[info.id] = setting
	window.searchIndex = nil

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

---Puts a dropdown on the section's title line, right-aligned, for something done to the whole section (such as
---Copy Settings From). `info` takes a Dropdown's fields; it is not searched and takes no row.
---@return table? setting
function lib.Section:Menu(info)
	if self.menu then
		lib:Report(self.page.window.addonName, ("%s/%s: a section has one menu"):format(self.page.id, tostring(self.id)))
		return
	end
	local setting = self.page:NewSetting("Dropdown", info)
	if setting then
		setting.section = self
		self.menu = setting
	end

	return setting
end

---Whether a section draws as a choice card, two checkboxes to a line: it asks for `columns = 2`, and every setting in
---it is a checkbox with no description, two or more of them. A section that asks but breaks a rule is reported once
---and drawn one to a line.
---@return boolean
function lib.ChoiceGrid(window, section)
	if section.columns ~= 2 then
		return false
	end
	local count, problem = 0, nil
	for _, line in ipairs(section.lines) do
		for index = 1, 2 do
			local setting = not line.note and line[index]
			if setting and setting ~= lib.EMPTY then
				count = count + 1
				if setting.kind ~= "Checkbox" then
					problem = problem or ("%s is a %s, not a checkbox"):format(tostring(setting.id), setting.kind)
				elseif setting.description then
					problem = problem or ("%s has a description"):format(tostring(setting.id))
				end
			end
		end
	end
	if count < 2 then
		problem = problem or "fewer than two settings"
	end
	if problem then
		lib:Report(window.addonName, ("%s/%s: columns = 2, but %s; drawn one to a line"):format(section.page.id,
			tostring(section.id), problem))
		return false
	end

	return true
end

---@return boolean shown false while the section's `show()` hides it
function lib.Section:IsShown()
	if not self.show then
		return true
	end

	return Call(self.show, self) and true or false
end

---Adds a line of text across the section, with an optional smaller second part.
function lib.Section:Note(text, small)
	table.insert(self.lines, { note = { text = text, small = small } })
end

---Adds the library's own section at the end of the addon's first page, once per page: Reduce Motion, which is
---account-wide and the same in every addon on the library.
function lib.Window:AddWindowSection()
	local first = self.pageOrder[1]
	if not first or not first.Section or first.windowSection then
		return
	end
	local section = first:Section("libAeonSettings", L.SETTINGS_WINDOW)
	section:Checkbox({
		id = "reduceMotion", label = L.REDUCE_MOTION, description = L.REDUCE_MOTION_DESCRIPTION, default = false,
		get = function() return lib:ReduceMotion() end,
		set = function(value) lib:SetReduceMotion(value) end,
	})
	first.windowSection = section
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
local function ReadPath(window, keys)
	local value = Store(window)
	for index = 1, #keys do
		if type(value) ~= "table" then
			return nil
		end
		value = value[keys[index]]
	end

	return value
end

---@return any value what the store holds at a dot-separated path, or nil
function lib.ReadStorePath(window, path)
	return ReadPath(window, { strsplit(".", path) })
end

-- What the setting holds itself: nil when nothing is stored (a setting that inherits then follows the shared value).
function lib.Setting:StoredValue()
	if self.get then
		return Call(self.get, self)
	elseif self.keys then
		return ReadPath(self.window, self.keys)
	end
end

---The shared value an overridable setting follows until it is changed (`inherits`), or nil for other settings.
function lib.Setting:InheritedValue()
	local inherits = self.inherits
	if not inherits then
		return nil
	end
	local value
	if inherits.get then
		value = Call(inherits.get, self)
	elseif inherits.keys then
		value = ReadPath(self.window, inherits.keys)
	end
	if value == nil then
		value = inherits.default
	end
	if value == nil and inherits.path then
		-- Nothing stored for the shared value yet: the default of the setting that edits it.
		if inherits.source == nil then
			inherits.source = false
			for _, page in ipairs(self.window.pageOrder) do
				for _, other in pairs(page.settings or {}) do
					if other.path == inherits.path and other ~= self then
						inherits.source = other
					end
				end
			end
		end
		value = inherits.source and inherits.source.default
	end
	if value == nil then
		return self.default
	end

	return value
end

---@return boolean overridden true while a setting that inherits holds its own value (◆)
function lib.Setting:IsOverridden()
	return self.inherits ~= nil and self:StoredValue() ~= nil
end

-- Numbers this close count as the same, so a color picked back to its default is the default.
local SAME = 0.0005

local function SameValue(a, b)
	if type(a) == "number" and type(b) == "number" then
		return math.abs(a - b) <= SAME
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, inner in pairs(a) do
		if not SameValue(inner, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end

	return true
end

local function CopyValue(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in pairs(value) do
		copy[key] = CopyValue(inner)
	end

	return copy
end

---@return boolean changed true while a `resettable` setting that does not inherit holds a value other than its
---default (↺ without ◆)
function lib.Setting:IsChangedFromDefault()
	if not self.resettable or self.inherits then
		return false
	end
	local value = self:StoredValue()

	return value ~= nil and not SameValue(value, self.default)
end

---Saves a copy of the default as the user's choice (↺ on a `resettable` setting), recorded for Undo. The default is
---written rather than cleared, so a store that fills in defaults still holds a value.
function lib.Setting:ResetToDefault()
	return self:Request(CopyValue(self.default))
end

---@return any value the stored value; else, for a setting that inherits, the shared value; else the default
function lib.Setting:GetValue()
	local value = self:StoredValue()
	if value == nil and self.inherits then
		return self:InheritedValue()
	end
	if value == nil then
		return self.default
	end

	return value
end

-- Writes a value through the setting's `set`, the declaration's `write`, or into the store by its path; returns false
-- and a sentence when the adopter refuses it. Every write of a value goes through here.
local function Write(setting, value)
	local write = setting.window.declaration.write
	if setting.set or (write and setting.keys) then
		local ok, reason
		if setting.set then
			ok, reason = Call(setting.set, value, setting)
		else
			ok, reason = Call(write, setting.path, value, setting)
		end
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
lib.WriteSetting = Write

-- Title Case (C-01): every word's first letter capitalized, the rest as written. It is an English convention, so other
-- client languages keep their text as written.
local ENGLISH = not GetLocale or GetLocale():sub(1, 2) == "en"
local function TitleCase(text)
	if not ENGLISH then
		return text
	end

	return (text:gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
end
lib.TitleCase = TitleCase

---Clears the setting's own value: a setting that inherits follows the shared value again (↺); another goes back to
---its default.
function lib.Setting:Reset()
	return self:Request(nil)
end

---Saves a value from code: the window redraws it at once. Returns false and the reason when refused.
function lib.Setting:SetValue(value)
	local ok, reason = Write(self, value)
	self.window:SettingChanged(self, true)

	return ok, reason
end

---Saves a value the user chose, recorded for Undo. A refusal shows "Couldn't save <label>: <reason>" at the top of
---the screen.
---@param gesture any? the same value for every save of one continuous gesture (a color pick), kept as one Undo step
---@return boolean ok
function lib.Setting:Request(value, gesture)
	local before = self:StoredValue()
	local ok, reason = Write(self, value)
	if ok then
		self.window:RecordUndo(self, before, value, gesture)
	else
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

-- Items: a setting whose `enabled = { path, default }` keeps one item on or off at `path .. "." .. value` each (the
-- ordered list's checkboxes, a dropdown with several choices); `default` is a table of each item's state.
local function ItemPath(setting, value)
	return setting.enabled.path .. "." .. tostring(value)
end

---@return boolean on whether the item is on; true for a setting without items to turn on and off
function lib.Setting:ItemEnabled(value)
	local enabled = self.enabled
	if not enabled then
		return true
	end
	local stored = lib.ReadStorePath(self.window, ItemPath(self, value))
	if stored == nil and type(enabled.default) == "table" then
		stored = enabled.default[value]
	end

	return stored and true or false
end

---Turns an item on or off, recorded for Undo.
function lib.Setting:SetItemEnabled(item, on)
	local path = ItemPath(self, item.value)
	local before = lib.ReadStorePath(self.window, path)
	local ok, reason = Write({ window = self.window, path = path, keys = { strsplit(".", path) } }, on)
	if not ok then
		self:ShowRefusal(reason)
	else
		self.window:RecordChange({ path = path, before = before, page = self.page.id,
			text = L.UNDO_TO:format(item.text, before and L.ON or L.OFF) })
	end
	self.window:SettingChanged(self, true, not ok)
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
---`depends` chain that is off, then a paired Use Class Color that is on, then `blocked()` (true, or a sentence
---giving the reason).
---@return boolean active
---@return string? reason
---@return string? cause "page", "depends", "class" or "blocked"
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
	if self.classSetting and self.classSetting:GetValue() then
		return false, nil, "class"
	end
	if self.blocked then
		local blocked = Call(self.blocked, self)
		if blocked then
			return false, type(blocked) == "string" and blocked or nil, "blocked"
		end
	end

	return true
end

---@return boolean off a setting up this one's `depends` chain, in its own section, is off
function lib.ParentOffInSection(setting)
	local parent, depth = setting:Parent(), 0
	while parent and depth < 16 do
		if parent.section == setting.section and not parent:GetValue() then
			return true
		end
		parent, depth = parent:Parent(), depth + 1
	end

	return false
end

---Puts each row (anything with a `setting`) that depends on another row of its section directly under it, after any
---earlier ones, keeping the declared order otherwise. Rows in a dependency loop keep their place.
---@param rows table[] reordered in place
function lib.OrderUnderParents(rows)
	local rowOf, children, roots, placed = {}, {}, {}, {}
	for _, half in ipairs(rows) do
		rowOf[half.setting] = half
	end
	for _, half in ipairs(rows) do
		local parent = half.setting:Parent()
		local parentRow = parent and rowOf[parent]
		if parentRow and parentRow ~= half then
			children[parentRow] = children[parentRow] or {}
			table.insert(children[parentRow], half)
		else
			table.insert(roots, half)
		end
	end
	local declared = { unpack(rows) }
	wipe(rows)
	local function Add(half)
		if placed[half] then
			return
		end
		placed[half] = true
		table.insert(rows, half)
		for _, child in ipairs(children[half] or {}) do
			Add(child)
		end
	end
	for _, half in ipairs(roots) do
		Add(half)
	end
	for _, half in ipairs(declared) do
		Add(half)
	end
end

---@return boolean shown false while the setting's `show()` or its section's hides it
function lib.Setting:IsShown()
	local section = self.section
	if section and section.show and not section:IsShown() then
		return false
	end
	if not self.show then
		return true
	end

	return Call(self.show, self) and true or false
end

---@return boolean revealable hidden only by its section, which can be revealed (`reveal`) for search to land on it
function lib.Setting:Revealable()
	local section = self.section
	if not (section and section.reveal and not section:IsShown()) then
		return false
	end
	if not self.show then
		return true
	end

	return Call(self.show, self) and true or false
end

---The value as text, for the inherited line under an overridden row's label (each control kind formats its own).
function lib.Setting:FormatValue(value)
	local control = lib.controls[self.kind]
	if control and control.Format then
		return control.Format(self, value) or ""
	end

	return value ~= nil and tostring(value) or ""
end

-- Overrides ---------------------------------------------------------------------------------------------------

local function EachPage(window, pageId)
	if pageId then
		local page = window.pages[pageId]
		return page and { page } or {}
	end

	return window.pageOrder
end

---@return integer count settings holding their own value instead of the shared one, on a page or the whole window
function lib.Window:CountOverrides(pageId)
	local count = 0
	for _, page in ipairs(EachPage(self, pageId)) do
		for _, setting in pairs(page.settings or {}) do
			if setting:IsOverridden() then
				count = count + 1
			end
		end
	end

	return count
end

---Returns every overridden setting on a page (or the whole window) to the shared value, for an adopter's Clear
---Overrides action; one Undo puts them all back. Settings whose `set` refuses keep their value.
---@return integer cleared
function lib.Window:ClearOverrides(pageId)
	local cleared, changes = 0, {}
	for _, page in ipairs(EachPage(self, pageId)) do
		for _, setting in pairs(page.settings or {}) do
			local before = setting:StoredValue()
			if setting:IsOverridden() and Write(setting, nil) then
				cleared = cleared + 1
				changes[#changes + 1] = { setting = setting, before = before }
			end
		end
	end
	self:RecordUndoGroup(changes)
	self:Refresh()

	return cleared
end
