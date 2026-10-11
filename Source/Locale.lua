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
L.MOVER_FILL = "Mover Fill"
L.COORDINATES = "Coordinates"
L.SNAP_ELEMENTS = "Snap"
L.COG_HINT = "Arrow keys move 1 px, Shift+arrow 10 px. Shift+right-click hides this overlay."
L.ELEMENT_OPTIONS = "Element Options"
L.WIDTH = "Width"
L.HEIGHT = "Height"
L.X_POSITION = "X Position"
L.Y_POSITION = "Y Position"
L.SELECT_SNAP_TARGET = "Select Snap Target"
L.SNAP_TARGET = "Snap Target: %s"
L.CENTER_ON_SCREEN = "Center on Screen"
L.RELATIVE_TO_SCREEN = "Relative to Screen"
L.RESET_POSITION = "Reset Position"
L.LEFT = "Left"
L.RIGHT = "Right"
L.TOP = "Top"
L.BOTTOM = "Bottom"
L.CENTER = "Center"
L.PICK_SNAP = "Click an element to snap to"
L.TOP_LEFT = "Top Left"
L.TOP_RIGHT = "Top Right"
L.BOTTOM_LEFT = "Bottom Left"
L.BOTTOM_RIGHT = "Bottom Right"
L.WAITING_FOR_PANELS = "Edit mode will open when the game menu and settings are closed."
