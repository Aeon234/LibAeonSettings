-- LibAeonSettings-1.0: library object, upgrade guard and shared state.

-- MINOR goes up by one with every tag that changes the library's code (AGENTS.md, Release): LibStub keeps the copy
-- with the highest MINOR, whatever its tag.
local MAJOR, MINOR = "LibAeonSettings-1.0", 5

local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
	return
end

---@class LibAeonSettings
---@field MINOR number
---@field loading boolean? true while this copy's files load; every other file returns at once when it is not set
lib.MINOR = MINOR
lib.loading = true

-- State that outlives an in-place upgrade: a newer copy keeps the tables an older copy filled.
lib.registrations = lib.registrations or {}
lib.order = lib.order or {}
lib.deferred = lib.deferred or {}
lib.eventFrame = lib.eventFrame or CreateFrame("Frame")
lib.reported = lib.reported or {}

-- Media lives beside this copy's files, wherever the embedding addon put them.
local function FindMediaPath()
	local trace = debugstack(1, 1, 0) or ""
	local folder = trace:match('([^"%[%]@]-)[/\\]Source[/\\]Core%.lua')
	if not folder then
		return
	end
	folder = folder:gsub("^.*[/\\][Aa]dd[Oo]ns[/\\]", ""):gsub("^[Ii]nterface[/\\][Aa]dd[Oo]ns[/\\]", "")

	return "Interface\\AddOns\\" .. folder:gsub("/", "\\") .. "\\Media\\"
end
lib.mediaPath = FindMediaPath() or "Interface\\AddOns\\LibAeonSettings\\Media\\"

---Each adopting addon's account-wide table, from its edit mode registration (in registration order), then from its
---settings window (by addon name), each table once. Account-wide preferences live in all of them, kept identical; the
---library itself has no saved variables.
---@return table[]
function lib:AccountTables()
	local tables, seen = {}, {}
	local function Add(declaration)
		local account = declaration and declaration.account
		if type(account) == "function" then
			account = account()
		end
		if type(account) == "table" and not seen[account] then
			seen[account] = true
			table.insert(tables, account)
		end
	end
	for _, addonName in ipairs(self.order) do
		Add(self.registrations[addonName].declaration)
	end
	local names = {}
	for addonName in pairs(self.windows or {}) do
		table.insert(names, addonName)
	end
	table.sort(names)
	for _, addonName in ipairs(names) do
		Add(self.windows[addonName].declaration)
	end

	return tables
end

---Reports a problem in an adopting addon's call once, without stopping the caller.
---@param addonName string
---@param message string
function lib:Report(addonName, message)
	local text = ("%s: %s: %s"):format(MAJOR, tostring(addonName), message)
	if self.reported[text] then
		return
	end
	self.reported[text] = true
	geterrorhandler()(text)
end
