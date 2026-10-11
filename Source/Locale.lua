-- Player-facing strings, keyed by their English text. Blizzard's global strings are used where the client has them.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = setmetatable({}, { __index = function(_, key) return key end })
lib.L = L

L.EXIT = EXIT or "Exit"
L.OFF = OFF or "Off"
L.ON = "On"
L.SAVE_AND_EXIT = "Save & Exit"
L.EXIT_WITHOUT_SAVING = "Exit Without Saving"
L.UNSAVED_CHANGES = "You have unsaved position changes.\nWhat would you like to do?"
L.COMBAT_REFUSED = "Cannot enter edit mode during combat."
L.GRID_LINES = "Grid Lines"
L.DIMMED = "Dimmed"
L.BRIGHT = "Bright"
