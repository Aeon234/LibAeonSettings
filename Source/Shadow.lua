-- Shadows: a soft glow outside a frame, for an addon's own frames and Blizzard's (decided 2026-10-13, from ElvUI
-- WindTools' shadows), drawn as eight edge textures made directly. WindTools' way, a BackdropTemplate frame whose edge
-- file is the glow, was built beside it for comparison and removed (Alex, 2026-10-13): the backdrop runs Lua on every
-- resize, Retail's needs a patch ElvUI applies, and it cannot leave out a side. A round frame takes the round glow. The module keeps its own weak-keyed table of shadows: it writes nothing into
-- the frames it shadows and hooks none of them, so it does not follow their border colors or frame levels.
-- `below` puts a shadow one level under its frame, as WindTools' lower shadow does for rows of closely spaced
-- buttons and bars (action buttons, the micro menu, cooldown and timer bars): no glow draws over a neighbor, and the
-- frame's fill covers the glow's inner unit, so there is no dark line along its edge. WindTools keeps it there with
-- permanent hooks on the frame; none are needed here: on Forever (1.60.1.70338) a child keeps its offset when its
-- frame's level or strata changes. `shadow:Restack()` is only for a frame that was at level 0 (its shadow could not
-- go lower, so it sits level with it) and has since been raised.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local GLOW = lib.mediaPath .. "Textures\\shadow-glow"   -- Alex's GlowTex.tga: 128 × 16, eight 16-texel segments
local ROUND = lib.mediaPath .. "Textures\\shadow-round" -- the same glow as a ring, matched at the 198-unit minimap
local DEFAULT_SIZE = 4
lib.SHADOW_COLOR = { 0, 0, 0, 0.618 } -- WindTools' black at its border alpha
local OPTION_FIELDS = { size = true, color = true, round = true, below = true, extend = true, shape = true }

-- Shaped glows for Blizzard art that is not a rectangle (Dev/make_shadow_shapes.py, from Blizzard's art exported at 2x,
-- half a unit per texel), with the same glow profile as the square shadow.
-- "frame": a frame drawn with Blizzard's metal NineSlice (its portrait ring, its chamfered corners). Each piece of the
-- frame's own NineSlice whose atlas is known gets the glow made from that piece's art, laid over it and reaching
-- `size + 2` units past its outer sides, so the glow follows the art wherever and however large it is drawn. Pieces
-- with other art get none.
-- Each shape exists for the sizes in SHAPE_SIZES (one texel per unit); a shadow takes the nearest to its `size`.
local SHAPE_SIZES = { 2, 4, 6, 8, 10 }
local NINE_PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge",
	"BottomEdge", "LeftEdge", "RightEdge" }
local NINE_SIDES = { -- the outward sides of each piece: { left, top, right, bottom }
	TopLeftCorner = { 1, 1, 0, 0 }, TopRightCorner = { 0, 1, 1, 0 }, BottomLeftCorner = { 1, 0, 0, 1 },
	BottomRightCorner = { 0, 0, 1, 1 }, TopEdge = { 0, 1, 0, 0 }, BottomEdge = { 0, 0, 0, 1 }, LeftEdge = { 1, 0, 0, 0 },
	RightEdge = { 0, 0, 1, 0 },
}
-- Lower-case atlas name: the glow made from it, and the piece it was made for (a layout that mirrors an atlas onto
-- another piece gets no glow there, rather than one facing the wrong way).
local NINE_GLOWS = {
	["ui-frame-metal-cornertopleft"] = { "cornertopleft", "TopLeftCorner" },
	["ui-frame-portraitmetal-cornertopleft"] = { "portraitcornertopleft", "TopLeftCorner" },
	["ui-frame-portraitmetal-cornertopleftsmall"] = { "portraitcornertopleftsmall", "TopLeftCorner" },
	["ui-frame-metal-cornertopright"] = { "cornertopright", "TopRightCorner" },
	["ui-frame-metal-cornertoprightdouble"] = { "cornertoprightdouble", "TopRightCorner" },
	["ui-frame-metal-cornerbottomleft"] = { "cornerbottomleft", "BottomLeftCorner" },
	["ui-frame-metal-cornerbottomright"] = { "cornerbottomright", "BottomRightCorner" },
	["_ui-frame-metal-edgetop"] = { "edgetop", "TopEdge" },
	["_ui-frame-metal-edgebottom"] = { "edgebottom", "BottomEdge" },
	["!ui-frame-metal-edgeleft"] = { "edgeleft", "LeftEdge" },
	["!ui-frame-metal-edgeright"] = { "edgeright", "RightEdge" },
}
-- "sidetab": a side tab (`LargeSideTabButtonTemplate`), around its `Background` art; Forever's tab art is wider than
-- Retail's, which tells the two apart.
local SHAPES = { frame = true, sidetab = true }
local SIDETAB_FOREVER_WIDTH = 55
local SIDES = { left = true, top = true, right = true, bottom = true }

-- The glow's eight segments in the backdrop edge layout, as Blizzard's Backdrop.lua reads them (texture
-- coordinates in eighths, one texel in from each side; the edges' along-the-edge coordinate stretched, since the
-- glow does not change along an edge).
local IN, OUT = 0.0625, 0.9375
local PIECES = {
	TopLeft = { 0.5078125, IN, 0.5078125, OUT, 0.6171875, IN, 0.6171875, OUT },
	TopRight = { 0.6328125, IN, 0.6328125, OUT, 0.7421875, IN, 0.7421875, OUT },
	BottomLeft = { 0.7578125, IN, 0.7578125, OUT, 0.8671875, IN, 0.8671875, OUT },
	BottomRight = { 0.8828125, IN, 0.8828125, OUT, 0.9921875, IN, 0.9921875, OUT },
	Top = { 0.2578125, OUT, 0.3671875, OUT, 0.2578125, IN, 0.3671875, IN },
	Bottom = { 0.3828125, OUT, 0.4921875, OUT, 0.3828125, IN, 0.4921875, IN },
	Left = { 0.0078125, IN, 0.0078125, OUT, 0.1171875, IN, 0.1171875, OUT },
	Right = { 0.1328125, IN, 0.1328125, OUT, 0.2421875, IN, 0.2421875, OUT },
}

lib.shadows = lib.shadows or setmetatable({}, { __mode = "k" })
lib.Shadow = {}
local shadowMeta = { __index = function(_, name) return lib.Shadow[name] end }

-- Waiting for the end of combat (protected frames) and for load-on-demand Blizzard addons.
lib.shadowEvents = lib.shadowEvents or CreateFrame("Frame")
lib.shadowQueue = lib.shadowQueue or {}
lib.shadowWaiting = lib.shadowWaiting or {}

local function Report(message)
	lib:Report("LibAeonSettings", message)
end

-- The frame a shadow hangs from: the region itself, or a texture's or font string's parent frame.
local function Host(region)
	if region.CreateTexture then
		return region
	end

	return region.GetParent and region:GetParent()
end

local function Edge(shadow)
	return shadow.size + 1
end

-- Drawing ------------------------------------------------------------------------------------------------------

-- A texture on the shadow's frame for a build: one an earlier build left spare, reset, or a new one.
local function NewTexture(shadow)
	local texture = shadow.spare and table.remove(shadow.spare)
	if texture then
		texture:ClearAllPoints()
		texture:SetTexCoord(0, 1, 0, 1)
		texture:Show()
	else
		texture = shadow.frame:CreateTexture(nil, "BORDER")
	end

	return texture
end

local function BuildTextures(shadow)
	local pieces = {}
	-- BORDER, as the backdrop's edge pieces (NineSlice's default layer): the glow's inner unit then draws over the
	-- frame's own fill, the dark line along its edge that WindTools' shadow has.
	for name, coords in pairs(PIECES) do
		local piece = NewTexture(shadow)
		piece:SetTexture(GLOW)
		piece:SetTexCoord(unpack(coords))
		pieces[name] = piece
	end
	local p = pieces
	p.TopLeft:SetPoint("TOPLEFT")
	p.TopRight:SetPoint("TOPRIGHT")
	p.BottomLeft:SetPoint("BOTTOMLEFT")
	p.BottomRight:SetPoint("BOTTOMRIGHT")
	p.Top:SetPoint("TOPLEFT", p.TopLeft, "TOPRIGHT")
	p.Top:SetPoint("BOTTOMRIGHT", p.TopRight, "BOTTOMLEFT")
	p.Bottom:SetPoint("TOPLEFT", p.BottomLeft, "TOPRIGHT")
	p.Bottom:SetPoint("BOTTOMRIGHT", p.BottomRight, "BOTTOMLEFT")
	p.Left:SetPoint("TOPLEFT", p.TopLeft, "BOTTOMLEFT")
	p.Left:SetPoint("BOTTOMRIGHT", p.BottomLeft, "TOPRIGHT")
	p.Right:SetPoint("TOPLEFT", p.TopRight, "BOTTOMLEFT")
	p.Right:SetPoint("BOTTOMRIGHT", p.BottomRight, "TOPRIGHT")
	shadow.pieces = pieces
end

local function Texture(name)
	return lib.mediaPath .. "Textures\\" .. name
end

-- The built size nearest to `size` (the larger on a tie).
local function ShapeSize(size)
	local best
	for _, built in ipairs(SHAPE_SIZES) do
		if not best or math.abs(built - size) <= math.abs(best - size) then
			best = built
		end
	end

	return best
end

-- One glow per known piece of the frame's NineSlice, each anchored to its piece.
local function BuildFrameShape(shadow)
	local nine = type(shadow.region.NineSlice) == "table" and shadow.region.NineSlice or shadow.region
	local size = ShapeSize(shadow.size)
	local pad = size + 2
	shadow.pieces = {}
	for _, name in ipairs(NINE_PIECES) do
		local piece = nine[name]
		local atlas = type(piece) == "table" and piece.GetAtlas and piece:GetAtlas()
		local glow = atlas and NINE_GLOWS[atlas:lower()]
		if glow and glow[2] == name then
			local texture = NewTexture(shadow)
			texture:SetTexture(Texture(("shadow-metal-%s-%d"):format(glow[1], size)))
			local sides = NINE_SIDES[name]
			texture:SetPoint("TOPLEFT", piece, "TOPLEFT", -pad * sides[1], pad * sides[2])
			texture:SetPoint("BOTTOMRIGHT", piece, "BOTTOMRIGHT", pad * sides[3], -pad * sides[4])
			shadow.pieces[name] = texture
		end
	end
	if not next(shadow.pieces) then
		Report("AddShadow: shape \"frame\", but the frame has no known NineSlice art")
	end
end

local function BuildTabShape(shadow)
	local art = shadow.region.Background or shadow.region
	local info = C_Texture.GetAtlasInfo("common-sidetab")
	local forever = not info or info.width >= SIDETAB_FOREVER_WIDTH
	local size = ShapeSize(shadow.size)
	local pad = size + 2
	local texture = NewTexture(shadow)
	texture:SetTexture(Texture(("%s-%d"):format(forever and "shadow-shape-sidetab" or "shadow-shape-sidetab-retail", size)))
	texture:SetPoint("TOPLEFT", art, "TOPLEFT", -pad, pad)
	texture:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", pad, -pad)
	shadow.pieces = { Tab = texture }
end

local function BuildRound(shadow)
	local ring = NewTexture(shadow)
	ring:SetTexture(ROUND)
	ring:SetAllPoints()
	shadow.ring = ring
end

-- Makes the shadow's frame around its region, or remakes its textures when the shape changed: the frame is kept, and
-- the earlier build's textures wait hidden for the new one to reuse.
local function Build(shadow)
	local host = Host(shadow.region)
	if shadow.frame then
		shadow.frame:SetParent(host)
		shadow.spare = shadow.spare or {}
		for _, texture in pairs(shadow.pieces or {}) do
			texture:Hide()
			table.insert(shadow.spare, texture)
		end
		if shadow.ring then
			shadow.ring:Hide()
			table.insert(shadow.spare, shadow.ring)
		end
	else
		shadow.frame = CreateFrame("Frame", nil, host)
	end
	shadow.pieces, shadow.ring = nil, nil
	shadow.built = { round = shadow.round, shape = shadow.shape,
		shapeSize = shadow.shape and ShapeSize(shadow.size) }
	if shadow.shape == "frame" then
		BuildFrameShape(shadow)
	elseif shadow.shape == "sidetab" then
		BuildTabShape(shadow)
	elseif shadow.round then
		BuildRound(shadow)
	else
		BuildTextures(shadow)
	end
end

local function Snap(value, region)
	if PixelUtil and PixelUtil.GetNearestPixelSize then
		return PixelUtil.GetNearestPixelSize(value, region:GetEffectiveScale())
	end

	return value
end

-- Places, sizes and colors the shadow: `size` outside the region on every side, the glow `size + 1` wide (one unit
-- under the region's edge), both on whole pixels.
local function Draw(shadow)
	local built = shadow.built
	if not shadow.frame or built.round ~= shadow.round or built.shape ~= shadow.shape
		or (shadow.shape and built.shapeSize ~= ShapeSize(shadow.size)) then
		Build(shadow)
	end
	local frame, region = shadow.frame, shadow.region
	shadow:Stack()
	local size = Snap(shadow.size, frame)
	local edge = Snap(Edge(shadow), frame)
	frame:ClearAllPoints()
	if shadow.shape then
		-- The glow textures are anchored to the art itself; the frame only holds them.
		frame:SetAllPoints(region)
	else
		-- `extend` moves each side further out (or, negative, in) to follow art that reaches past the frame.
		local extend = shadow.extend or {}
		frame:SetPoint("TOPLEFT", region, "TOPLEFT", -size - (extend.left or 0), size + (extend.top or 0))
		frame:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", size + (extend.right or 0), -size - (extend.bottom or 0))
	end
	local r, g, b, a = unpack(shadow.color)
	if shadow.shape then
		for _, piece in pairs(shadow.pieces) do
			piece:SetVertexColor(r, g, b, a)
		end
	elseif shadow.round then
		shadow.ring:SetVertexColor(r, g, b, a)
	else
		for name, piece in pairs(shadow.pieces) do
			if name == "Top" or name == "Bottom" then
				piece:SetHeight(edge)
			elseif name == "Left" or name == "Right" then
				piece:SetWidth(edge)
			else
				piece:SetSize(edge, edge)
			end
			piece:SetVertexColor(r, g, b, a)
		end
	end
	frame:SetShown(shadow.shown)
end

-- The shadow object ------------------------------------------------------------------------------------------

local function Apply(shadow, options)
	if options.size ~= nil then
		shadow.size = tonumber(options.size) or DEFAULT_SIZE
	end
	if options.color ~= nil then
		shadow:SetColor(options.color, true)
	end
	if options.round ~= nil then
		shadow.round = options.round and true or false
	end
	if options.below ~= nil then
		shadow.below = options.below and true or false
	end
	if options.extend ~= nil then
		shadow.extend = type(options.extend) == "table" and options.extend or nil
	end
	if options.shape ~= nil then
		local shape = options.shape
		if shape == true then
			shape = type(shadow.region.NineSlice) == "table" and "frame" or nil
			if not shape then
				Report("AddShadow: shape = true, but the frame has no NineSlice")
			end
		end
		shadow.shape = SHAPES[shape] and shape or nil
	end
end

-- A protected frame in combat waits for the end of combat: making and placing a frame on it is restricted then.
local function Restricted(region)
	local host = Host(region)

	return InCombatLockdown() and host and host.IsProtected and host:IsProtected()
end

---Gives a frame (or a texture, around which its parent frame's shadow is placed) a shadow, or updates its
---shadow. Options: `size` (units outside the frame, default 4), `color` ({ r, g, b, a }, default black at 0.618;
---the caller may pass a border color), `round` (the round glow, matched at Blizzard's 198-unit minimap), `below`
---(one level under the frame, for rows of closely spaced buttons
---or bars; call `Restack` if the frame was at level 0 and has been raised). A protected frame in combat gets its
---shadow when combat ends. `extend` ({ left?, top?, right?, bottom? }) moves sides further out (negative: in) for art
---that reaches past the frame. `shape` draws a shaped glow instead of the square one: "frame" (a frame drawn with
---Blizzard's metal NineSlice, ring and chamfers included: each known piece gets its own glow), "sidetab" (a side tab,
---around its art), or true (the frame's NineSlice). A shape takes the nearest of the sizes it is built in (2, 4, 6, 8,
---10); `extend` does not apply to it.
---@return table? shadow with Show, Hide, SetShown, SetColor, SetSize, SetBelow, Restack
function lib:AddShadow(region, options)
	options = options or {}
	if type(region) ~= "table" or type(region.GetObjectType) ~= "function" then
		Report("AddShadow needs a frame or texture")
		return
	end
	if region.IsForbidden and region:IsForbidden() then
		Report("AddShadow: the frame is forbidden")
		return
	end
	for field in pairs(options) do
		if not OPTION_FIELDS[field] then
			Report(("AddShadow: unknown option %q"):format(tostring(field)))
		end
	end
	if options.shape ~= nil and options.shape ~= true and options.shape ~= false and not SHAPES[options.shape] then
		Report(("AddShadow: unknown shape %q"):format(tostring(options.shape)))
	end
	if type(options.extend) == "table" then
		for side in pairs(options.extend) do
			if not SIDES[side] then
				Report(("AddShadow: unknown extend side %q"):format(tostring(side)))
			end
		end
	end
	if not Host(region) then
		Report("AddShadow: the region has no parent frame")
		return
	end
	local shadow = self.shadows[region]
	if not shadow then
		shadow = setmetatable({ region = region, size = DEFAULT_SIZE, color = { unpack(self.SHADOW_COLOR) },
			round = false, below = false, shown = true }, shadowMeta)
		self.shadows[region] = shadow
	end
	Apply(shadow, options)
	shadow:Refresh()

	return shadow
end

---@return table? shadow the frame's shadow, if it has one
function lib:GetShadow(region)
	return self.shadows[region]
end

---Gives a frame from a load-on-demand Blizzard addon its shadow once that addon has loaded (at once if it has).
---`frameOrGetter` is the frame's global name or a function returning the frame.
function lib:AddShadowWhenLoaded(addonName, frameOrGetter, options)
	local function Add()
		local frame = type(frameOrGetter) == "function" and lib.CallAdopter(frameOrGetter) or _G[frameOrGetter]
		if frame then
			lib:AddShadow(frame, options)
		else
			Report(("AddShadowWhenLoaded: %s loaded without the frame"):format(addonName))
		end
	end
	if C_AddOns.IsAddOnLoaded(addonName) then
		Add()
		return
	end
	local waiting = self.shadowWaiting[addonName] or {}
	waiting[#waiting + 1] = Add
	self.shadowWaiting[addonName] = waiting
	self.shadowEvents:RegisterEvent("ADDON_LOADED")
end

-- Redraws the shadow now, or once combat ends when its frame is protected.
function lib.Shadow:Refresh()
	if Restricted(self.region) then
		lib.shadowQueue[self] = true
		lib.shadowEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	Draw(self)
end

-- Puts the shadow frame at its frame's strata and level, or one level under it when `below`.
function lib.Shadow:Stack()
	local frame, host = self.frame, Host(self.region)
	if not frame or not host then
		return
	end
	frame:SetFrameStrata(host:GetFrameStrata())
	local level = host:GetFrameLevel()
	frame:SetFrameLevel(self.below and math.max(level - 1, 0) or level)
end

---Puts the shadow back at (or under) its frame's level. Level and strata changes keep the offset on their own; this is
---for a frame raised from level 0, where a lower shadow could not go below it. Waits for the end of combat on a
---protected frame.
function lib.Shadow:Restack()
	if Restricted(self.region) then
		self:Refresh()
		return
	end
	self:Stack()
end

---One level under the frame (true) or at its level (false).
function lib.Shadow:SetBelow(below)
	self.below = below and true or false
	self:Restack()
end

---@return integer? level the shadow frame's level, for checks
function lib.Shadow:GetFrameLevel()
	return self.frame and self.frame:GetFrameLevel()
end

function lib.Shadow:SetShown(shown)
	self.shown = shown and true or false
	if self.frame and not Restricted(self.region) then
		self.frame:SetShown(self.shown)
	else
		self:Refresh()
	end
end

function lib.Shadow:Show()
	self:SetShown(true)
end

function lib.Shadow:Hide()
	self:SetShown(false)
end

---@return boolean shown
function lib.Shadow:IsShown()
	return self.shown
end

---Sets the color, or back to the default with nil. A table { r, g, b, a } or r, g, b, a.
function lib.Shadow:SetColor(r, g, b, a, quiet)
	if type(r) == "table" then
		quiet = g
		r, g, b, a = r.r or r[1], r.g or r[2], r.b or r[3], r.a or r[4]
	end
	local default = lib.SHADOW_COLOR
	if r == nil then
		self.color = { unpack(default) }
	else
		self.color = { r, g or 0, b or 0, a or default[4] }
	end
	if not quiet then
		self:Refresh()
	end
end

function lib.Shadow:SetSize(size)
	self.size = tonumber(size) or DEFAULT_SIZE
	self:Refresh()
end

lib.shadowEvents:SetScript("OnEvent", function(frame, event, addonName)
	if event == "PLAYER_REGEN_ENABLED" then
		frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
		local queue = lib.shadowQueue
		lib.shadowQueue = {}
		for shadow in pairs(queue) do
			shadow:Refresh()
		end
	elseif event == "ADDON_LOADED" then
		local waiting = lib.shadowWaiting[addonName]
		if waiting then
			lib.shadowWaiting[addonName] = nil
			for _, add in ipairs(waiting) do
				add()
			end
		end
		if not next(lib.shadowWaiting) then
			frame:UnregisterEvent("ADDON_LOADED")
		end
	end
end)
