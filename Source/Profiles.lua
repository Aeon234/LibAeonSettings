-- C-17, the Profiles page: which profile is active, managing profiles and sharing them, drawn by the library from
-- an adapter the addon passes; the profiles and their data stay the addon's. Profile actions are not undoable and
-- empty the window's Undo history (Q86). The dialogs are C-18 (ProfileDialog.lua).

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

lib.DEFAULT_PROFILE = "Default" -- the built-in profile's saved key; it shows as Blizzard's DEFAULT string
local MAX_NAME = 32

local ADAPTER_REQUIRED = { "List", "Active", "Switch", "New", "Copy", "Rename", "Delete", "Reset", "Export", "Decode",
	"Import" }
local ADAPTER_FIELDS = { IsEditing = true, UsesCharacterProfile = true, SetUseCharacterProfile = true }
for _, name in ipairs(ADAPTER_REQUIRED) do
	ADAPTER_FIELDS[name] = true
end
local PROFILES_FIELDS = { adapter = true, sections = true }

lib.Profiles = {}
local Profiles = lib.Profiles

-- Names ------------------------------------------------------------------------------------------------------

---@return string shown a profile's name as players see it: the built-in profile as DEFAULT
function lib:ProfileName(name)
	if name == lib.DEFAULT_PROFILE then
		return DEFAULT or name
	end

	return tostring(name)
end

local function Trim(text)
	return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

---Checks a profile name: unique case-insensitively, the built-in profile's names reserved, at most 32 letters.
---`current` is the name being renamed, which may keep its own name.
---@return string? name the trimmed name when it can be used
---@return string? reason why not (nil for an empty or unchanged name, which is simply not ready)
function lib:CheckProfileName(list, text, current)
	local name = Trim(text)
	if name == "" then
		return nil
	end
	local lower = name:lower()
	if current and lower == lib:ProfileName(current):lower() then
		return nil
	end
	if strlenutf8(name) > MAX_NAME then
		return nil, L.MAX_LETTERS:format(MAX_NAME)
	end
	if lower == lib.DEFAULT_PROFILE:lower() or lower == lib:ProfileName(lib.DEFAULT_PROFILE):lower() then
		return nil, L.PROFILE_RESERVED:format(lib:ProfileName(lib.DEFAULT_PROFILE))
	end
	for _, other in ipairs(list) do
		if tostring(other):lower() == lower then
			return nil, L.PROFILE_TAKEN:format(name)
		end
	end

	return name
end

-- The page ---------------------------------------------------------------------------------------------------

local function Call(adapter, name, ...)
	local fn = adapter[name]
	if type(fn) ~= "function" then
		return
	end

	return lib.CallAdopter(fn, ...)
end
Profiles.Call = Call

---Every profile, the built-in one first, then alphabetical without regard to case.
function Profiles.List(adapter)
	local list = {}
	local names = Call(adapter, "List")
	for _, name in ipairs(type(names) == "table" and names or {}) do
		list[#list + 1] = name
	end
	table.sort(list, function(a, b)
		if (a == lib.DEFAULT_PROFILE) ~= (b == lib.DEFAULT_PROFILE) then
			return a == lib.DEFAULT_PROFILE
		end

		return tostring(a):lower() < tostring(b):lower()
	end)

	return list
end

-- While the addon's layout is being edited, every row but Export is inactive.
local function Editing(adapter)
	if adapter.IsEditing then
		return Call(adapter, "IsEditing") and true or false
	end

	return lib:IsEditing()
end

local function Locked(adapter)
	return Editing(adapter) and L.UNAVAILABLE_EDITING or nil
end

---Finishes a profile action: the history empties (profile actions are not undoable), every value is read again,
---and the status line says what happened.
function Profiles.Finish(window, status)
	window:ClearUndo()
	window:Refresh()
	if status then
		window:ShowStatus(status)
	end
end

local function Fail(verb, reason)
	local message = reason and L.COULDNT_VERB_REASON:format(verb:lower(), (tostring(reason):gsub("%.$", "")))
		or L.COULDNT_VERB:format(verb:lower())
	UIErrorsFrame:AddExternalErrorMessage(lib.TitleCase(message))
end
Profiles.Fail = Fail

-- Settings on this page change the profile, not a value in it: none is recorded for Undo.
local function NoUndo(setting)
	if setting then
		setting.noUndo = true
	end

	return setting
end

local function Delete(window, adapter)
	local name = Call(adapter, "Active")
	local list = Profiles.List(adapter)
	local hasDefault = false
	for _, other in ipairs(list) do
		hasDefault = hasDefault or other == lib.DEFAULT_PROFILE
	end
	if name ~= lib.DEFAULT_PROFILE and hasDefault then
		local question = L.DELETE_TO_DEFAULT:format(lib:ProfileName(name), lib:ProfileName(lib.DEFAULT_PROFILE))
		window.profileConfirm = lib:Confirm(question, L.DELETE, function()
			local ok, reason = Call(adapter, "Delete", name, lib.DEFAULT_PROFILE)
			if ok == false then
				Fail(L.DELETE, reason)
				return
			end
			Profiles.Finish(window, L.PROFILE_DELETED:format(lib:ProfileName(name), lib:ProfileName(lib.DEFAULT_PROFILE)))
		end)
		return
	end
	window:OpenProfileDialog("replace", adapter)
end

local function Reset(window, adapter)
	local name = Call(adapter, "Active")
	window.profileConfirm = lib:Confirm(L.RESET_PROFILE_QUESTION:format(lib:ProfileName(name)), L.RESET, function()
		local ok, reason = Call(adapter, "Reset")
		if ok == false then
			Fail(L.RESET, reason)
			return
		end
		Profiles.Finish(window, L.PROFILE_RESET:format(lib:ProfileName(name)))
	end)
end

---Adds the Profiles page (C-17): Active Profile, the addon's own sections (`sections(page)`), Manage and Share. Takes
---a page's fields plus `adapter`; sections the addon adds to the returned page afterwards follow Share.
---@param info table { title?, description?, under?, icon?, adapter, sections? }
---@return table? page
function lib.Window:ProfilesPage(id, info)
	info = info or {}
	local adapter = info.adapter
	if type(adapter) ~= "table" then
		lib:Report(self.addonName, ("profiles page %s needs an adapter"):format(tostring(id)))
		return
	end
	for _, name in ipairs(ADAPTER_REQUIRED) do
		if type(adapter[name]) ~= "function" then
			lib:Report(self.addonName, ("profiles page %s: the adapter has no %s"):format(tostring(id), name))
			return
		end
	end
	for field in pairs(adapter) do
		if not ADAPTER_FIELDS[field] then
			lib:Report(self.addonName, ("profiles page %s: unknown adapter field %q"):format(tostring(id), tostring(field)))
		end
	end
	local pageInfo = {}
	for field, value in pairs(info) do
		if not PROFILES_FIELDS[field] then
			pageInfo[field] = value
		end
	end
	pageInfo.title = pageInfo.title or L.PROFILES
	local page = self:Page(id, pageInfo)
	if not page then
		return
	end
	page.profileAdapter = adapter
	local window = self
	local blocked = function() return Locked(adapter) end

	local active = page:Section("active", L.ACTIVE_PROFILE)
	NoUndo(active:Dropdown({ id = "profile", label = L.ACTIVE_PROFILE, titleCase = false,
		options = function()
			local options = {}
			for _, name in ipairs(Profiles.List(adapter)) do
				options[#options + 1] = { value = name, text = lib:ProfileName(name) }
			end
			return options
		end,
		get = function() return Call(adapter, "Active") end,
		set = function(name)
			local ok, reason = Call(adapter, "Switch", name)
			if ok == false then
				return false, reason
			end
			Profiles.Finish(window)
		end,
		blocked = blocked }))
	if adapter.UsesCharacterProfile and adapter.SetUseCharacterProfile then
		NoUndo(active:Checkbox({ id = "character", label = L.CHARACTER_PROFILE, description = L.CHARACTER_PROFILE_DESC,
			get = function() return Call(adapter, "UsesCharacterProfile") and true or false end,
			set = function(on)
				local ok, reason = Call(adapter, "SetUseCharacterProfile", on)
				if ok == false then
					return false, reason
				end
				Profiles.Finish(window)
			end,
			blocked = blocked }))
	end

	if info.sections then
		lib.CallAdopter(info.sections, page)
	end

	local manage = page:Section("manage", L.MANAGE)
	manage:Button({ id = "new", label = L.NEW_PROFILE, verb = L.NEW, blocked = blocked,
		run = function() window:OpenProfileDialog("new", adapter) end })
	manage:Button({ id = "copy", label = L.COPY_PROFILE, verb = L.COPY, blocked = blocked,
		run = function() window:OpenProfileDialog("copy", adapter) end })
	manage:Button({ id = "rename", label = L.RENAME_PROFILE, verb = L.RENAME, blocked = blocked,
		run = function() window:OpenProfileDialog("rename", adapter) end })
	manage:Button({ id = "delete", label = L.DELETE_PROFILE, verb = L.DELETE,
		blocked = function()
			return Locked(adapter) or (#Profiles.List(adapter) <= 1 and L.LAST_PROFILE) or nil
		end,
		run = function() Delete(window, adapter) end })
	manage:Button({ id = "reset", label = L.RESET_PROFILE, verb = L.RESET, description = L.RESET_PROFILE_DESC,
		blocked = blocked, run = function() Reset(window, adapter) end })

	local share = page:Section("share", L.SHARE)
	share:Button({ id = "export", label = L.EXPORT_PROFILE, verb = L.EXPORT,
		run = function() window:OpenProfileDialog("export", adapter) end })
	share:Button({ id = "import", label = L.IMPORT_PROFILE, verb = L.IMPORT, description = L.IMPORT_PROFILE_DESC,
		blocked = blocked, run = function() window:OpenProfileDialog("import", adapter) end })

	return page
end
