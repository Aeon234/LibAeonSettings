-- Placement registrations: what each addon can move, where its positions are stored, and applying them.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local Geometry = lib.Geometry

---@class LibAeonSettingsLink
---@field addon string the other target's addon
---@field key string the other target's key

---@class LibAeonSettingsAnchor : LibAeonSettingsLink
---@field side string "TOP", "BOTTOM", "LEFT" or "RIGHT" of the other target's frame
---@field x number offset in UIParent units
---@field y number offset in UIParent units

---@class LibAeonSettingsMatch : LibAeonSettingsLink
---@field extra number added to the other target's size, in UIParent units

---@class LibAeonSettingsPosition
---@field point string
---@field x number parent units, measured at scale 1
---@field y number parent units, measured at scale 1
---@field anchor LibAeonSettingsAnchor? attached to another target; point, x and y keep the last place, used while
---the other target is missing
---@field matchWidth LibAeonSettingsMatch?
---@field matchHeight LibAeonSettingsMatch?
---@field grow string? "LEFT", "RIGHT", "CENTER", "UP" or "DOWN"

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
-- `settings` is a function, or where the target's settings are: { page, section?, setting?, select? }.
local LINK_FIELDS = { page = true, section = true, setting = true, select = true }

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
	local settings = target.settings
	if type(settings) == "table" then
		for field in pairs(settings) do
			if not LINK_FIELDS[field] then
				lib:Report(addonName, ("target %s: unknown settings field %q"):format(target.key, tostring(field)))
			end
		end
		if type(settings.page) ~= "string" then
			lib:Report(addonName, ("target %s: settings needs a page"):format(target.key))
			target.settings = nil
		end
	elseif settings ~= nil and type(settings) ~= "function" then
		lib:Report(addonName, ("target %s: settings must be a function or { page, section? }"):format(target.key))
		target.settings = nil
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

---The position in force for a target: pending, else stored, else its default.
---@return LibAeonSettingsPosition
function lib.Registration:Current(target)
	return lib:GetPending(self.addonName, target.key) or self:Read(target.key) or target.default
end

---Anchors a target's frame to its position in force: attached to another target's frame when the position says so
---and that frame exists, else to the screen. A frame that would lie wholly off-screen is drawn in view instead,
---without changing what is stored. Matched sizes are applied first. A protected frame waits until combat ends.
---@param target LibAeonSettingsTarget
function lib.Registration:ApplyTarget(target)
	local frame = target.frame
	local position = self:Current(target)
	-- In combat a protected frame cannot be moved or sized, and a frame is not attached to a protected one either:
	-- both wait for the end of combat.
	if InCombatLockdown() then
		local anchor = position.anchor
		local parent = anchor and lib.ResolveTarget and lib:ResolveTarget(anchor.addon, anchor.key)
		if frame:IsProtected() or (parent and parent.frame:IsProtected()) then
			lib:Defer(self, target.key)
			return
		end
	end

	if lib.ApplyMatches then
		lib:ApplyMatches(self.addonName, target, position)
	end
	local scale = ScaleOf(frame)

	local anchor = position.anchor
	local parent = anchor and lib.ResolveTarget and lib:ResolveTarget(anchor.addon, anchor.key)
	if parent and parent.frame ~= frame then
		local childPoint, parentPoint = Geometry.SidePoints(anchor.side)
		if childPoint then
			frame:ClearAllPoints()
			frame:SetPoint(childPoint, parent.frame, parentPoint, anchor.x / scale, anchor.y / scale)
			if lib.WatchParent then
				lib:WatchParent(parent.frame)
			end
			return
		end
	end

	local width, height = frame:GetWidth() * scale, frame:GetHeight() * scale
	local parentWidth, parentHeight = UIParent:GetWidth(), UIParent:GetHeight()
	local point, x, y = position.point, position.x, position.y

	local left, bottom = Geometry.FromStored(point, x, y, width, height, parentWidth, parentHeight)
	if Geometry.IsOffScreen(left, bottom, width, height, parentWidth, parentHeight) then
		left, bottom = Geometry.ClampInto(left, bottom, width, height, parentWidth, parentHeight)
		point, x, y = Geometry.ToStored(left, bottom, width, height, parentWidth, parentHeight, target.fixedEdge,
			position.grow)
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

---Measures a target's current on-screen position in the stored form, offsets rounded to physical pixels. The
---position in force keeps its anchor, matches and growth; an anchor's offsets are measured again.
---@param target LibAeonSettingsTarget
---@return LibAeonSettingsPosition?
function lib.Registration:Measure(target)
	local frame = target.frame
	local left, bottom = frame:GetLeft(), frame:GetBottom()
	if not left or not bottom then
		return
	end
	local scale = ScaleOf(frame)

	return lib:PositionForRect(self.addonName, target, left * scale, bottom * scale, frame:GetWidth() * scale,
		frame:GetHeight() * scale)
end

---The stored form of a target placed at a rectangle (UIParent units), keeping the anchor, matches and growth of
---its position in force and measuring the anchor's offsets from the rectangle.
---@return LibAeonSettingsPosition
function lib:PositionForRect(addonName, target, left, bottom, width, height)
	local registration = self.registrations[addonName]
	local current = registration:Current(target)
	local point, x, y = Geometry.ToStored(left, bottom, width, height, UIParent:GetWidth(), UIParent:GetHeight(),
		target.fixedEdge, current.grow)
	local layoutScale = UIParent:GetEffectiveScale()
	local position = CopyTable(current)
	position.point = point
	position.x = PixelUtil.GetNearestPixelSize(x, layoutScale)
	position.y = PixelUtil.GetNearestPixelSize(y, layoutScale)

	local anchor = position.anchor
	local parent = anchor and self.ResolveTarget and self:ResolveTarget(anchor.addon, anchor.key)
	if parent then
		local parentLeft, parentBottom, parentWidth, parentHeight = self:FrameRect(parent.frame)
		if parentLeft then
			local offsetX, offsetY = Geometry.AnchorOffset(anchor.side, left, bottom, width, height, parentLeft,
				parentBottom, parentWidth, parentHeight)
			anchor.x = PixelUtil.GetNearestPixelSize(offsetX, layoutScale)
			anchor.y = PixelUtil.GetNearestPixelSize(offsetY, layoutScale)
		end
	end

	return position
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

---@return number count of applies waiting for the end of combat
function lib:DeferredCount()
	local count = 0
	for _ in pairs(self.deferred) do
		count = count + 1
	end

	return count
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

