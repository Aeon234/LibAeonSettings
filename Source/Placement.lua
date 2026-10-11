-- Placement registrations: what each addon can move, where its positions are stored, and applying them.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local Geometry = lib.Geometry

---@class LibAeonSettingsPosition
---@field point string
---@field x number parent units, measured at scale 1
---@field y number parent units, measured at scale 1

---@class LibAeonSettingsTarget
---@field key string stable identifier, unique within the addon
---@field label string
---@field frame Frame
---@field default LibAeonSettingsPosition
---@field fixedEdge string? "TOP", "BOTTOM", "LEFT" or "RIGHT"

local DECLARATION_FIELDS = { title = true, store = true, get = true, set = true, targets = true, account = true }
local TARGET_FIELDS = {
	key = true, label = true, subtitle = true, frame = true, default = true, fixedEdge = true, sample = true,
	settings = true, size = true, attach = true, match = true, grow = true,
}
local FIXED_EDGES = { TOP = true, BOTTOM = true, LEFT = true, RIGHT = true }

-- Registration methods are looked up on the library at call time, so registrations made through an older copy
-- use the newest code after an upgrade.
lib.Registration = {}
local registrationMeta = { __index = function(_, name) return lib.Registration[name] end }

local function ValidPosition(position)
	return type(position) == "table" and Geometry.IsPoint(position.point)
		and type(position.x) == "number" and type(position.y) == "number"
end

---Checks one target declaration; reports each problem and returns false when the target cannot be used.
local function CheckTarget(addonName, target, seen)
	if type(target) ~= "table" then
		lib:Report(addonName, "a target is not a table")
		return false
	end
	for field in pairs(target) do
		if not TARGET_FIELDS[field] then
			lib:Report(addonName, ("target %s: unknown field %q"):format(tostring(target.key), tostring(field)))
		end
	end
	if type(target.key) ~= "string" or target.key == "" then
		lib:Report(addonName, "a target has no key")
		return false
	end
	if seen[target.key] then
		lib:Report(addonName, ("target %s: duplicate key"):format(target.key))
		return false
	end
	if type(target.frame) ~= "table" or type(target.frame.GetObjectType) ~= "function" then
		lib:Report(addonName, ("target %s: frame is not a frame"):format(target.key))
		return false
	end
	if not ValidPosition(target.default) then
		lib:Report(addonName, ("target %s: default must be { point, x, y }"):format(target.key))
		return false
	end
	if target.fixedEdge ~= nil and not FIXED_EDGES[target.fixedEdge] then
		lib:Report(addonName, ("target %s: fixedEdge must be TOP, BOTTOM, LEFT or RIGHT"):format(target.key))
	end
	seen[target.key] = true

	return true
end

---Registers what an addon can move. Calling it again for the same addon replaces the earlier registration.
---@param addonName string the adopting addon's folder name
---@param declaration table { title, targets, store or get and set, account? (account-wide table for edit mode preferences) }
---@return table? registration
function lib:Placement(addonName, declaration)
	if type(addonName) ~= "string" or type(declaration) ~= "table" then
		self:Report(addonName, "Placement(addonName, declaration) needs a name and a table")
		return
	end
	for field in pairs(declaration) do
		if not DECLARATION_FIELDS[field] then
			self:Report(addonName, ("unknown declaration field %q"):format(tostring(field)))
		end
	end
	local hasStore = type(declaration.store) == "table" or type(declaration.store) == "function"
	local hasAccessors = type(declaration.get) == "function" and type(declaration.set) == "function"
	if not hasStore and not hasAccessors then
		self:Report(addonName, "the declaration needs store, or get and set")
		return
	end
	local targets = declaration.targets
	if type(targets) ~= "table" and type(targets) ~= "function" then
		self:Report(addonName, "the declaration needs targets (a list, or a function returning one)")
		return
	end

	local registration = self.registrations[addonName]
	if not registration then
		registration = setmetatable({}, registrationMeta)
		self.registrations[addonName] = registration
		table.insert(self.order, addonName)
	end
	registration.addonName = addonName
	registration.title = declaration.title or addonName
	registration.declaration = declaration

	if self.loggedIn then
		registration:Apply()
	end

	return registration
end

---@return table? registration
function lib:GetRegistration(addonName)
	return self.registrations[addonName]
end

---The registration's checked targets, read fresh from the declaration.
---@return LibAeonSettingsTarget[]
function lib.Registration:Targets()
	local source = self.declaration.targets
	if type(source) == "function" then
		source = source()
	end
	local targets, seen = {}, {}
	if type(source) ~= "table" then
		lib:Report(self.addonName, "targets did not return a list")
		return targets
	end
	for _, target in ipairs(source) do
		if CheckTarget(self.addonName, target, seen) then
			table.insert(targets, target)
		end
	end

	return targets
end

---@return LibAeonSettingsTarget?
function lib.Registration:Target(key)
	for _, target in ipairs(self:Targets()) do
		if target.key == key then
			return target
		end
	end
end

local function PositionTable(registration)
	local store = registration.declaration.store
	if type(store) == "function" then
		store = store()
	end
	if type(store) ~= "table" then
		lib:Report(registration.addonName, "store did not return a table")
		return
	end
	store.positions = store.positions or {}

	return store.positions
end

---The stored position for a key, or nil when the default applies.
---@return LibAeonSettingsPosition?
function lib.Registration:Read(key)
	local declaration = self.declaration
	local position
	if declaration.get then
		position = declaration.get(key)
	else
		local positions = PositionTable(self)
		position = positions and positions[key]
	end
	if position ~= nil and not ValidPosition(position) then
		lib:Report(self.addonName, ("stored position for %s is not { point, x, y }; using the default"):format(key))
		return
	end

	return position
end

---Stores a position for a key; nil returns it to its default.
---@param position LibAeonSettingsPosition?
function lib.Registration:Write(key, position)
	local declaration = self.declaration
	if declaration.set then
		declaration.set(key, position)
		return
	end
	local positions = PositionTable(self)
	if positions then
		positions[key] = position
	end
end

---Ratio of a frame's units to UIParent's.
local function ScaleOf(frame)
	return frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

---Anchors a target's frame to its pending, stored or default position. A frame that would lie wholly off-screen is drawn
---in view instead, without changing what is stored. A protected frame waits until combat ends.
---@param target LibAeonSettingsTarget
function lib.Registration:ApplyTarget(target)
	local frame = target.frame
	if InCombatLockdown() and frame:IsProtected() then
		lib:Defer(self, target.key)
		return
	end

	local position = lib:GetPending(self.addonName, target.key) or self:Read(target.key) or target.default
	local scale = ScaleOf(frame)
	local width, height = frame:GetWidth() * scale, frame:GetHeight() * scale
	local parentWidth, parentHeight = UIParent:GetWidth(), UIParent:GetHeight()
	local point, x, y = position.point, position.x, position.y

	local left, bottom = Geometry.FromStored(point, x, y, width, height, parentWidth, parentHeight)
	if Geometry.IsOffScreen(left, bottom, width, height, parentWidth, parentHeight) then
		left, bottom = Geometry.ClampInto(left, bottom, width, height, parentWidth, parentHeight)
		point, x, y = Geometry.ToStored(left, bottom, width, height, parentWidth, parentHeight, target.fixedEdge)
	end

	frame:ClearAllPoints()
	frame:SetPoint(point, UIParent, point, x / scale, y / scale)
end

---Applies every target's position. Adopters call it after their active profile changes.
function lib.Registration:Apply()
	for _, target in ipairs(self:Targets()) do
		self:ApplyTarget(target)
	end
end

---Measures a target's current on-screen position in the stored form, offsets rounded to physical pixels.
---@param target LibAeonSettingsTarget
---@return LibAeonSettingsPosition?
function lib.Registration:Measure(target)
	local frame = target.frame
	local left, bottom = frame:GetLeft(), frame:GetBottom()
	if not left or not bottom then
		return
	end

	local scale = ScaleOf(frame)
	local point, x, y = Geometry.ToStored(left * scale, bottom * scale, frame:GetWidth() * scale,
		frame:GetHeight() * scale, UIParent:GetWidth(), UIParent:GetHeight(), target.fixedEdge)
	local layoutScale = UIParent:GetEffectiveScale()

	return {
		point = point,
		x = PixelUtil.GetNearestPixelSize(x, layoutScale),
		y = PixelUtil.GetNearestPixelSize(y, layoutScale),
	}
end

---Stores a target's current on-screen position and re-anchors the frame to it.
---@return LibAeonSettingsPosition?
function lib.Registration:Capture(key)
	local target = self:Target(key)
	if not target then
		lib:Report(self.addonName, ("Capture: no target %s"):format(tostring(key)))
		return
	end
	local position = self:Measure(target)
	if position then
		self:Write(key, position)
		self:ApplyTarget(target)
	end

	return position
end

---Returns a target to its default position.
function lib.Registration:Reset(key)
	local target = self:Target(key)
	if target then
		self:Write(key, nil)
		self:ApplyTarget(target)
	end
end

-- Protected frames cannot be anchored in combat; the latest request per target runs when combat ends.
function lib:Defer(registration, key)
	self.deferred[registration.addonName .. "\0" .. key] = { registration = registration, key = key }
	self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function lib:RunDeferred()
	self.eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
	local pending = self.deferred
	self.deferred = {}
	for _, entry in pairs(pending) do
		local target = entry.registration:Target(entry.key)
		if target then
			entry.registration:ApplyTarget(target)
		end
	end
end

function lib:ApplyAll()
	for _, addonName in ipairs(self.order) do
		self.registrations[addonName]:Apply()
	end
end

function lib:OnEvent(event)
	if event == "PLAYER_LOGIN" then
		self.loggedIn = true
		self:ApplyAll()
	elseif event == "PLAYER_REGEN_ENABLED" then
		self:RunDeferred()
	elseif self.loggedIn then
		self:ApplyAll()
	end
end

local eventFrame = lib.eventFrame
eventFrame:SetScript("OnEvent", function(_, event, ...) lib:OnEvent(event, ...) end)
if not IsLoggedIn() then
	eventFrame:RegisterEvent("PLAYER_LOGIN")
else
	lib.loggedIn = true
end
eventFrame:RegisterEvent("UI_SCALE_CHANGED")
eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
if next(lib.deferred) then
	eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

