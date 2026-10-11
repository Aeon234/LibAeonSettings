-- LibAeonSettings-1.0: library object, upgrade guard and shared state.

local MAJOR, MINOR = "LibAeonSettings-1.0", 1

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
	local folder = trace:match("([^\"%[%]@]-)[/\\]Source[/\\]Core%.lua")
	if not folder then
		return
	end
	folder = folder:gsub("^.*[/\\][Aa]dd[Oo]ns[/\\]", ""):gsub("^[Ii]nterface[/\\][Aa]dd[Oo]ns[/\\]", "")

	return "Interface\\AddOns\\" .. folder:gsub("/", "\\") .. "\\Media\\"
end
lib.mediaPath = FindMediaPath() or "Interface\\AddOns\\LibAeonSettings\\Media\\"

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
