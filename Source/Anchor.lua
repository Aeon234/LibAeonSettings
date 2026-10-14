-- Anchoring a target to another, matching its width or height, growth direction, the mover link row and the
-- anchor lines drawn while editing.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local L = lib.L

local LINK_COLOR = { 1, 1, 1 }
local LINK_ACTIVE = { 1, 0.7, 0.3 }
local LINK_HOVER = { 1, 0.82, 0 }
local LINE_COLOR = { 1, 0.7, 0.3, 0.9 }
local LINE_THICKNESS = 3
local PULSE_SIZE = 14
local PULSE_PERIOD = 2.5
local REFUSE_FLASH = 0.6
local REFUSE_TOOLTIP = 3
local MATCH_EXTRA_LIMIT = 100

local Handlers = {}
lib.AnchorHandlers = Handlers

-- Targets and links ----------------------------------------------------------------------------------------------

function lib:MoverId(addonName, key)
	return addonName .. "\0" .. key
end

---@return string? addonName
---@return string? key
function lib:SplitMoverId(id)
	return id:match("^(.-)%z(.*)$")
end

---The target another target's position links to, when its addon is registered and its frame exists.
---@return LibAeonSettingsTarget?
function lib:ResolveTarget(addonName, key)
	local registration = self.registrations[addonName]
	local target = registration and registration:Target(key)
	if target and target.frame then
		return target
	end
end

local function Links(position)
	return { position.anchor, position.matchWidth, position.matchHeight }
end

---True when the target `id` reaches `otherId` through anchors and matches (directly or through others).
function lib:DependsOn(id, otherId, seen)
	if id == otherId then
		return true
	end
	seen = seen or {}
	if seen[id] then
		return false
	end
	seen[id] = true
	local addonName, key = self:SplitMoverId(id)
	local registration = addonName and self.registrations[addonName]
	local target = registration and registration:Target(key)
	if not target then
		return false
	end
	for _, link in ipairs(Links(registration:Current(target))) do
		if link and self:DependsOn(self:MoverId(link.addon, link.key), otherId, seen) then
			return true
		end
	end

	return false
end

-- Sizes ----------------------------------------------------------------------------------------------------------

local function HasSize(target)
	local size = target.size

	return type(size) == "table" and type(size.get) == "function" and type(size.set) == "function"
end

---Sets a target's size (in its frame's units) through its `size.set`. While editing, the first size seen is kept
---so leaving without saving can restore it.
function lib:SetTargetSize(addonName, target, width, height)
	local size = target.size
	local session = self.session
	if session.open then
		session.sizeOriginals = session.sizeOriginals or {}
		local id = self:MoverId(addonName, target.key)
		if not session.sizeOriginals[id] then
			local originalWidth, originalHeight = size.get()
			session.sizeOriginals[id] = { addonName = addonName, key = target.key, width = originalWidth,
				height = originalHeight }
		end
	end
	local minimum = size.min or 1
	size.set(math.max(minimum, width), math.max(minimum, height))
end

---Gives a target the width or height of the targets it matches, plus each match's extra.
function lib:ApplyMatches(addonName, target, position)
	if not HasSize(target) or not (position.matchWidth or position.matchHeight) then
		return
	end
	local scale = target.frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local width, height = target.size.get()
	local newWidth, newHeight = width, height
	for dimension, match in pairs({ width = position.matchWidth, height = position.matchHeight }) do
		local other = self:ResolveTarget(match.addon, match.key)
		local _, _, otherWidth, otherHeight = other and self:FrameRect(other.frame)
		if otherWidth then
			self:WatchParent(other.frame, self.registrations[addonName], target)
			local value = ((dimension == "width" and otherWidth or otherHeight) + (match.extra or 0)) / scale
			if dimension == "width" then
				newWidth = value
			else
				newHeight = value
			end
		end
	end
	if math.abs(newWidth - width) > 0.01 or math.abs(newHeight - height) > 0.01 then
		self:SetTargetSize(addonName, target, newWidth, newHeight)
	end
end

-- A frame others are anchored to or matched with is watched for size changes, so they follow it outside edit
-- mode as well. Each watched frame keeps the targets that follow it (frame -> target -> registration), and each
-- target the frames it follows (target -> frame -> true), so a resize applies only its own followers. A hook cannot
-- be removed; a frame nothing follows any more returns at once. The apply runs once on the next frame however many
-- changes arrive, and a follower whose own size changes passes the change on through its own hook.
lib.followers = lib.followers or {}
lib.followed = lib.followed or {}

---Records that `target` follows `frame`, and watches the frame's size.
function lib:WatchParent(frame, registration, target)
	self.watched = self.watched or {}
	if registration and target then
		self.followers[frame] = self.followers[frame] or {}
		self.followers[frame][target] = registration
		self.followed[target] = self.followed[target] or {}
		self.followed[target][frame] = true
	end
	if self.watched[frame] then
		return
	end
	self.watched[frame] = true
	frame:HookScript("OnSizeChanged", function(watched) lib:OnWatchedResized(watched) end)
end

---Forgets the frames a target follows, before its position is applied again.
function lib:ForgetParents(target)
	local frames = self.followed[target]
	if not frames then
		return
	end
	for frame in pairs(frames) do
		local followers = self.followers[frame]
		if followers then
			followers[target] = nil
		end
		frames[frame] = nil
	end
end

---@param frame Frame? nil from a hook set by an older copy, which applies every target
function lib:OnWatchedResized(frame)
	if frame then
		local followers = self.followers[frame]
		if not followers or not next(followers) then
			return
		end
		self.resized = self.resized or {}
		self.resized[frame] = true
	else
		self.resizedAll = true
	end
	if self.reapplyQueued then
		return
	end
	self.reapplyQueued = true
	C_Timer.After(0, function() lib:ApplyResized() end)
end

---Applies the followers of every frame resized since the last call, each once.
function lib:ApplyResized()
	self.reapplyQueued = nil
	local frames, all = self.resized, self.resizedAll
	self.resized, self.resizedAll = nil, nil
	if all then
		self:ApplyAll()
	elseif frames then
		-- Applying a target records its frames again, so the followers are gathered before any is applied.
		local due = {}
		for frame in pairs(frames) do
			for target, registration in pairs(self.followers[frame] or {}) do
				due[target] = registration
			end
		end
		for target, registration in pairs(due) do
			-- A target dropped by its addon's latest declaration is forgotten instead.
			if registration:Target(target.key) == target then
				registration:ApplyTarget(target)
			else
				self:ForgetParents(target)
			end
		end
	end
	if self.session.open then
		self:RefreshMovers()
	end
end

-- Refusal --------------------------------------------------------------------------------------------------------

---Flashes a mover red and shows why near the cursor.
function lib:Refuse(id, reason)
	local session = self.session
	session.refused = id
	self:RefreshMovers()
	C_Timer.After(REFUSE_FLASH, function()
		if session.refused == id then
			session.refused = nil
			lib:RefreshMovers()
		end
	end)
	GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
	GameTooltip:SetText(reason, 1, 0.35, 0.3, 1, true)
	GameTooltip:Show()
	C_Timer.After(REFUSE_TOOLTIP, function()
		if GameTooltip:GetOwner() == UIParent then
			GameTooltip:Hide()
		end
	end)
end

-- Picking --------------------------------------------------------------------------------------------------------

local function Pending(id)
	local addonName, key = lib:SplitMoverId(id)
	local registration = lib.registrations[addonName]
	local target = registration and registration:Target(key)
	if target then
		return registration, target, CopyTable(registration:Current(target))
	end
end

local function SetPosition(registration, target, position)
	lib:SetPending(registration.addonName, target.key, position)
end

local SIDES = { { "LEFT", L.ANCHOR_LEFT }, { "RIGHT", L.ANCHOR_RIGHT }, { "TOP", L.ANCHOR_TOP }, { "BOTTOM", L.ANCHOR_BOTTOM } }

local function OpenAnchorMenu(sourceId, targetId)
	local otherMover = lib.ui.movers[targetId]
	local otherAddon, otherKey = lib:SplitMoverId(targetId)
	lib:OpenMenu(sourceId, otherMover, function(menu)
		for _, side in ipairs(SIDES) do
			menu:Action(side[2], function()
				local registration, target, position = Pending(sourceId)
				if not registration then
					return
				end
				position.anchor = { addon = otherAddon, key = otherKey, side = side[1], x = 0, y = 0 }
				lib:CloseMenus()
				lib:EndPick()
				SetPosition(registration, target, position)
			end)
		end
		local _, _, current = Pending(sourceId)
		if current and current.anchor then
			menu:Action(L.REMOVE_ANCHOR, function()
				lib:Detach(sourceId)
				lib:CloseMenus()
				lib:EndPick()
			end, { color = { 1, 0.35, 0.3 } })
		end
	end)
end

---Completes an anchor or match pick with the clicked mover. Returns true when the pick was one of these kinds.
function lib:CompleteLinkPick(pick, id)
	local kind = pick.kind
	if kind ~= "anchor" and kind ~= "matchWidth" and kind ~= "matchHeight" then
		return false
	end
	if id == pick.source then
		self:EndPick()
		return true
	end
	if self:DependsOn(id, pick.source) then
		self:Refuse(id, kind == "anchor" and L.REFUSE_CIRCULAR_ANCHOR or L.REFUSE_CIRCULAR_MATCH)
		return true
	end
	if kind == "anchor" then
		OpenAnchorMenu(pick.source, id)
		return true
	end

	local registration, target, position = Pending(pick.source)
	local otherAddon, otherKey = self:SplitMoverId(id)
	position[kind] = { addon = otherAddon, key = otherKey, extra = 0 }
	self:EndPick()
	SetPosition(registration, target, position)

	return true
end

---Removes a target's anchor and keeps it where it is.
function lib:Detach(id)
	local registration, target, position = Pending(id)
	if not registration or not position.anchor then
		return
	end
	local left, bottom, width, height = self:FrameRect(target.frame)
	position.anchor = nil
	self:SetPending(registration.addonName, target.key, position)
	if left then
		self:MoveTargetTo(registration.addonName, target, left, bottom, width, height)
	end
end

---Sets or clears a match's extra size, clamped to its range.
function lib:SetMatchExtra(id, kind, extra)
	local registration, target, position = Pending(id)
	if registration and position[kind] then
		position[kind].extra = math.max(-MATCH_EXTRA_LIMIT, math.min(MATCH_EXTRA_LIMIT, extra))
		SetPosition(registration, target, position)
	end
end

---Sets a target's anchor offsets.
function lib:SetAnchorOffset(id, x, y)
	local registration, target, position = Pending(id)
	if registration and position.anchor then
		position.anchor.x, position.anchor.y = x, y
		SetPosition(registration, target, position)
	end
end

local GROW_LABELS = {
	CENTER = L.GROW_CENTERED, LEFT = L.LEFT, RIGHT = L.RIGHT, UP = L.GROW_UP, DOWN = L.GROW_DOWN,
}

local function OpenGrowMenu(mover, anchor)
	lib:OpenMenu(mover.id, anchor, function(menu)
		menu:Hint(L.GROW_DIRECTION)
		local registration, target, position = Pending(mover.id)
		for _, direction in ipairs(target.grow) do
			local _, label = menu:Action(GROW_LABELS[direction] or direction, function()
				local left, bottom, width, height = lib:FrameRect(target.frame)
				position.grow = direction
				lib:SetPending(registration.addonName, target.key, position)
				if left and not position.anchor then
					lib:MoveTargetTo(registration.addonName, target, left, bottom, width, height)
				end
				lib:CloseMenus()
				lib:RefreshMovers()
			end)
			if (position.grow or target.grow[1]) == direction then
				label:SetTextColor(unpack(LINK_ACTIVE))
			end
		end
	end)
end

-- Link row -------------------------------------------------------------------------------------------------------

local LINK_KINDS = { "matchWidth", "matchHeight", "anchor", "grow" }

local function LinkAllowed(target, kind)
	if kind == "matchWidth" then
		return HasSize(target) and (target.match == "width" or target.match == "both")
	elseif kind == "matchHeight" then
		return HasSize(target) and (target.match == "height" or target.match == "both")
	elseif kind == "anchor" then
		return target.attach == true
	end

	return type(target.grow) == "table" and #target.grow > 0
end

function Handlers.LinkAction(mover, kind, button)
	local id = mover.id
	local _, _, position = Pending(id)
	if not position then
		return
	end
	if kind == "grow" then
		OpenGrowMenu(mover, button)
	elseif kind == "anchor" then
		if position.anchor then
			lib:Detach(id)
		else
			lib:StartPick("anchor", id)
		end
	elseif position[kind] then
		local registration, target = Pending(id)
		position[kind] = nil
		SetPosition(registration, target, position)
	else
		lib:StartPick(kind, id)
	end
end

---Creates a mover's link row: W Match, H Match, Anchor and Grow, separated by thin dividers.
function lib:CreateLinks(mover)
	local row = CreateFrame("Frame", nil, mover.text)
	row:SetHeight(14)
	row:SetPoint("TOPLEFT", mover.name, "BOTTOMLEFT", 0, -3)
	row.buttons, row.dividers = {}, {}
	for _, kind in ipairs(LINK_KINDS) do
		local button = CreateFrame("Button", nil, row)
		button:SetHeight(14)
		button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		lib:OutlineText(button.label)
		button.label:SetPoint("CENTER")
		button.kind = kind
		button:SetScript("OnEnter", function(self) Handlers.LinkHover(self, true) end)
		button:SetScript("OnLeave", function(self) Handlers.LinkHover(self, false) end)
		button:SetScript("OnMouseDown", function(self, mouseButton)
			if mouseButton == "LeftButton" then
				lib.MoverHandlers.MouseDown(mover, "LeftButton", function() Handlers.LinkAction(mover, self.kind, self) end)
			end
		end)
		button:SetScript("OnMouseUp", function(self, mouseButton)
			if mouseButton == "LeftButton" then
				lib.MoverHandlers.EndDrag(mover)
			end
		end)
		row.buttons[kind] = button
	end
	for index = 1, #LINK_KINDS - 1 do
		local divider = row:CreateTexture(nil, "ARTWORK")
		divider:SetColorTexture(1, 1, 1, 0.25)
		divider:SetSize(1, 10)
		row.dividers[index] = divider
	end
	row:Hide()
	mover.links = row
end

function Handlers.LinkHover(button, hovered)
	button.hovered = hovered
	local color = hovered and LINK_HOVER or button.active and LINK_ACTIVE or LINK_COLOR
	button.label:SetTextColor(unpack(color))
	if hovered then
		GameTooltip:SetOwner(button, "ANCHOR_TOP")
		GameTooltip:SetText(button.tooltip or button.label:GetText(), 1, 1, 1, 1, true)
		GameTooltip:Show()
	else
		GameTooltip:Hide()
		Handlers.Leave(button)
	end
end

function Handlers.Leave(button)
	local mover = button:GetParent():GetParent():GetParent()
	if mover and mover.id then
		lib.MoverHandlers.Leave(mover)
	end
end

local function TargetLabel(link)
	local other = link and lib:ResolveTarget(link.addon, link.key)

	return other and (other.label or other.key) or (link and link.key) or ""
end

---Fills and lays out a mover's link row for its target. Returns the row's width, or 0 when it has no links.
function lib:LayoutLinks(mover, target, position, shown)
	local row = mover.links
	local x = 0
	local visible = {}
	for _, kind in ipairs(LINK_KINDS) do
		local button = row.buttons[kind]
		local allowed = LinkAllowed(target, kind)
		button:SetShown(allowed)
		if allowed then
			local text, active, tooltip
			if kind == "matchWidth" then
				local match = position.matchWidth
				active = match ~= nil
				local extra = match and match.extra or 0
				text = match and (extra ~= 0 and L.W_MATCHED_EXTRA:format(extra > 0 and "+" or "", extra) or L.W_MATCHED) or L.W_MATCH
				tooltip = match and L.MATCHED_TO:format(TargetLabel(match)) or L.W_MATCH_TOOLTIP
			elseif kind == "matchHeight" then
				local match = position.matchHeight
				active = match ~= nil
				text = match and L.H_MATCHED or L.H_MATCH
				tooltip = match and L.MATCHED_TO:format(TargetLabel(match)) or L.H_MATCH_TOOLTIP
			elseif kind == "anchor" then
				active = position.anchor ~= nil
				text = active and L.ANCHORED or L.ANCHOR
				tooltip = active and L.ANCHORED_TO:format(TargetLabel(position.anchor)) or L.ANCHOR_TOOLTIP
			else
				text = L.GROW
				tooltip = L.GROW_TOOLTIP:format(GROW_LABELS[position.grow or target.grow[1]] or "")
			end
			button.active, button.tooltip = active, tooltip
			button.label:SetText(text)
			button.label:SetTextColor(unpack(button.hovered and LINK_HOVER or active and LINK_ACTIVE or LINK_COLOR))
			button:SetWidth(button.label:GetStringWidth() + 10)
			table.insert(visible, button)
		end
	end
	for _, divider in ipairs(row.dividers) do
		divider:Hide()
	end
	for index, button in ipairs(visible) do
		button:ClearAllPoints()
		button:SetPoint("LEFT", row, "LEFT", x, 0)
		x = x + button:GetWidth()
		if index < #visible then
			local divider = row.dividers[index]
			divider:ClearAllPoints()
			divider:SetPoint("LEFT", row, "LEFT", x, 0)
			divider:Show()
			x = x + 1
		end
	end
	row:SetWidth(math.max(x, 1))
	row:SetShown(shown and #visible > 0)

	return #visible > 0 and x or 0
end

-- Anchor lines ---------------------------------------------------------------------------------------------------

local function LineLayer()
	local ui = lib.ui
	if not ui.lineLayer then
		ui.lineLayer = CreateFrame("Frame", nil, ui.screen)
		ui.lineLayer:SetAllPoints()
		ui.lineLayer:SetFrameLevel(ui.screen:GetFrameLevel() + 8)
		ui.lineLayer.lines, ui.lineLayer.pulses = {}, {}
		ui.lineLayer:SetScript("OnUpdate", function(self) Handlers.Pulse(self) end)
		ui.lineLayer:Hide()
	end

	return ui.lineLayer
end

function Handlers.Pulse(layer)
	local progress = (GetTime() % PULSE_PERIOD) / PULSE_PERIOD
	for index = 1, layer.count do
		local line, pulse = layer.lines[index], layer.pulses[index]
		pulse:ClearAllPoints()
		pulse:SetPoint("CENTER", UIParent, "BOTTOMLEFT", line.fromX + (line.toX - line.fromX) * progress,
			line.fromY + (line.toY - line.fromY) * progress)
	end
end

local function PlaceLine(line)
	line.fromX, line.fromY = line.fromMover:GetCenter()
	line.toX, line.toY = line.toMover:GetCenter()
	line:SetStartPoint("BOTTOMLEFT", UIParent, line.fromX, line.fromY)
	line:SetEndPoint("BOTTOMLEFT", UIParent, line.toX, line.toY)
end

---Moves the shown anchor lines to their movers' current centers, without choosing the lines again.
function lib:MoveLines()
	local layer = self.ui and self.ui.lineLayer
	if not layer or not layer:IsShown() then
		return
	end
	for index = 1, layer.count do
		PlaceLine(layer.lines[index])
	end
end

---Draws a line from each anchored mover to the mover it is anchored to while either is hovered, expanded or
---dragged, with a pulse running from the anchored one to the other. The layer's OnUpdate runs only while lines show.
function lib:RefreshLines()
	if not self.ui or not self.ui.movers then
		return
	end
	local layer = LineLayer()
	local session = self.session
	local focus = {}
	for _, id in ipairs({ session.hovered, session.expanded, session.drag and session.drag.started and session.drag.id }) do
		if id then
			focus[id] = true
		end
	end
	local count = 0
	if session.open and not session.paused and next(focus) then
		for id, mover in pairs(self.ui.movers) do
			if mover:IsShown() and mover.target then
				local registration = self.registrations[mover.addonName]
				local anchor = registration and registration:Current(mover.target).anchor
				local parentId = anchor and self:MoverId(anchor.addon, anchor.key)
				local parentMover = parentId and self.ui.movers[parentId]
				if parentMover and parentMover:IsShown() and (focus[id] or focus[parentId]) then
					count = count + 1
					local line = layer.lines[count]
					if not line then
						line = layer:CreateLine(nil, "ARTWORK")
						line:SetTexture(self.mediaPath .. "Textures\\anchor-line")
						line:SetVertexColor(LINE_COLOR[1], LINE_COLOR[2], LINE_COLOR[3], LINE_COLOR[4])
						line:SetThickness(LINE_THICKNESS)
						layer.lines[count] = line
						local pulse = layer:CreateTexture(nil, "OVERLAY")
						pulse:SetTexture(self.mediaPath .. "Textures\\pulse")
						pulse:SetSize(PULSE_SIZE, PULSE_SIZE)
						pulse:SetBlendMode("ADD")
						layer.pulses[count] = pulse
					end
					line.fromMover, line.toMover = mover, parentMover
					PlaceLine(line)
					line:Show()
					layer.pulses[count]:Show()
				end
			end
		end
	end
	for index = count + 1, #layer.lines do
		layer.lines[index]:Hide()
		layer.pulses[index]:Hide()
	end
	layer.count = count
	layer:SetShown(count > 0)
end
