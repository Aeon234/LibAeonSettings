-- The custom row (Q147): the library sizes and places an area in a half (or across a line), and the adopter draws
-- inside it. `create(area, setting)` runs once, the first time the row is shown; `refresh(area, setting)` runs
-- each time it is shown and whenever the page redraws its states.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local DEFAULT_WIDTH, DEFAULT_HEIGHT = 220, 28
local INSET = 20

lib.Custom = {}
local customMeta = { __index = function(_, name) return lib.Custom[name] end }

function lib:CreateCustom(parent)
	local view = setmetatable({}, customMeta)
	view.frame = CreateFrame("Frame", nil, parent)
	view.frame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)

	return view
end

-- Without a label, a wide custom row spans the line between the insets; otherwise the area sits where controls do.
function lib.Custom:Place(half)
	local setting = half.setting
	if setting.wide and not setting.label then
		self.frame:SetPoint("LEFT", half, "LEFT", INSET, 0)
		self.frame:SetPoint("RIGHT", half, "RIGHT", -INSET, 0)
	else
		self.frame:SetPoint("RIGHT", half, "RIGHT", -64, 0)
	end
end

function lib.Custom:Bind(setting)
	self.setting = setting
	self.frame:SetSize(setting.width or DEFAULT_WIDTH, setting.height or DEFAULT_HEIGHT)
	local area = setting.area
	if not area then
		area = CreateFrame("Frame", nil, self.frame)
		setting.area = area
		if setting.create then
			lib.CallAdopter(setting.create, area, setting)
		end
	end
	area:SetParent(self.frame)
	area:ClearAllPoints()
	area:SetAllPoints(self.frame)
	area:Show()
	self:Update()
end

-- An adopter whose area grows or shrinks changes `setting.height` in its refresh and lays the page out again; the
-- frame follows, so it stays the row's height rather than centered in it.
function lib.Custom:Update()
	local setting = self.setting
	if setting and setting.refresh then
		lib.CallAdopter(setting.refresh, setting.area, setting)
	end
	if setting then
		self.frame:SetHeight(setting.height or DEFAULT_HEIGHT)
	end
end

function lib.Custom:Release()
	if self.setting and self.setting.area then
		self.setting.area:Hide()
	end
	self.setting = nil
end

-- The page redraws states after every change; the adopter's refresh runs with it.
function lib.Custom:SetActive()
	self:Update()
end

function lib.Custom:GetWidth()
	local setting = self.setting
	if setting and setting.wide and not setting.label then
		return 0
	end

	return setting and setting.width or DEFAULT_WIDTH
end

lib:RegisterControl("Custom", {
	fields = { width = true, height = true, create = true, refresh = true },
	noValue = true,
	Create = function(half) return lib:CreateCustom(half) end,
})
