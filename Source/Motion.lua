-- Springs: every animated value in the library moves on one model, set by a response (seconds, how quickly it gets
-- there) and a damping ratio (1 settles without overshoot, below 1 overshoots). A spring keeps its value and
-- velocity, so a new target mid-way carries on from where it is. One shared frame steps the moving springs and has
-- no OnUpdate while none moves. With Reduce Motion on, springs jump to their targets.

local lib = LibStub("LibAeonSettings-1.0")
if not lib.loading then
	return
end

local DEFAULT_RESPONSE, DEFAULT_DAMPING, DEFAULT_EPSILON = 0.3, 1, 0.001

---@class LibAeonSettingsMotion
local Motion = {}
lib.Motion = Motion

-- Moving springs, shared by every copy: a newer copy steps the springs an older copy started.
lib.motion = lib.motion or { moving = {} }
lib.MotionHandlers = lib.MotionHandlers or {}
local Handlers = lib.MotionHandlers

---Advances a spring by `elapsed` seconds with the exact solution of its motion, so any frame length gives the same
---path: pure, no frame access.
---@param value number
---@param velocity number per second
---@param target number
---@param response number seconds
---@param damping number ratio
---@param elapsed number seconds
---@return number value
---@return number velocity
function Motion.Step(value, velocity, target, response, damping, elapsed)
	local omega = 2 * math.pi / response
	local x, v, t = value - target, velocity, elapsed
	if math.abs(damping - 1) < 1e-4 then
		local decay = math.exp(-omega * t)
		local slope = v + omega * x

		return target + decay * (x + slope * t), decay * (v - omega * t * slope)
	elseif damping < 1 then
		local wd = omega * math.sqrt(1 - damping * damping)
		local decay = math.exp(-damping * omega * t)
		local b = (v + damping * omega * x) / wd
		local cos, sin = math.cos(wd * t), math.sin(wd * t)

		return target + decay * (x * cos + b * sin),
			decay * ((wd * b - damping * omega * x) * cos - (damping * omega * b + wd * x) * sin)
	end
	local root = math.sqrt(damping * damping - 1)
	local r1, r2 = -omega * (damping - root), -omega * (damping + root)
	local c1 = (v - r2 * x) / (r1 - r2)
	local c2 = x - c1
	local e1, e2 = math.exp(r1 * t), math.exp(r2 * t)

	return target + c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2
end

---@return boolean settled the value is within `epsilon` of the target and nearly still
function Motion.Settled(value, velocity, target, epsilon)
	return math.abs(value - target) < epsilon and math.abs(velocity) < epsilon * 10
end

-- Reduce Motion -----------------------------------------------------------------------------------------------

---@return boolean on Reduce Motion, account-wide: read from the first adopting addon's account table that has it
function lib:ReduceMotion()
	for _, account in ipairs(self:AccountTables()) do
		local saved = account.settingsWindow
		if saved and saved.reduceMotion ~= nil then
			return saved.reduceMotion == true
		end
	end

	return false
end

---Turns Reduce Motion on or off in every adopting addon's account table; turning it on ends every moving spring.
---@param on boolean
function lib:SetReduceMotion(on)
	on = on == true
	for _, account in ipairs(self:AccountTables()) do
		account.settingsWindow = account.settingsWindow or {}
		account.settingsWindow.reduceMotion = on
	end
	if on then
		for _, spring in ipairs(Handlers.Moving()) do
			spring:Jump(spring.target)
		end
	end
end

-- Springs -----------------------------------------------------------------------------------------------------

lib.Spring = {}
local springMeta = { __index = function(_, name) return lib.Spring[name] end }

---Makes a spring at rest at `value`. `onUpdate(value)` runs on every step and on a jump.
---@param value number
---@param onUpdate fun(value: number)
---@param options { response: number?, damping: number?, epsilon: number?, onRest: fun(value: number)? }?
---@return table spring
function lib:CreateSpring(value, onUpdate, options)
	options = options or {}

	return setmetatable({
		value = value, velocity = 0, target = value, onUpdate = onUpdate, onRest = options.onRest,
		response = options.response or DEFAULT_RESPONSE, damping = options.damping or DEFAULT_DAMPING,
		epsilon = options.epsilon or DEFAULT_EPSILON,
	}, springMeta)
end

---Moves toward `target`, keeping the current value and velocity; `velocity` replaces the velocity when given.
---@param target number
---@param velocity number?
function lib.Spring:To(target, velocity)
	self.target = target
	if velocity then
		self.velocity = velocity
	end
	if lib:ReduceMotion() then
		self:Jump(target)
		return
	end
	if Motion.Settled(self.value, self.velocity, target, self.epsilon) then
		self:Jump(target)
		return
	end
	lib.motion.moving[self] = true
	Handlers.Start()
end

---Sets the value at once, at rest, and reports it.
---@param value number
function lib.Spring:Jump(value)
	lib.motion.moving[self] = nil
	self.value, self.target, self.velocity = value, value, 0
	self.onUpdate(value)
	if self.onRest then
		self.onRest(value)
	end
end

---Stops where it is, without reporting.
function lib.Spring:Stop()
	lib.motion.moving[self] = nil
	self.velocity = 0
end

---@return boolean
function lib.Spring:IsMoving()
	return lib.motion.moving[self] == true
end

function Handlers.Start()
	local frame = lib.motion.frame
	if not frame then
		frame = CreateFrame("Frame")
		lib.motion.frame = frame
	end
	frame:SetScript("OnUpdate", function(_, elapsed) lib.MotionHandlers.Update(elapsed) end)
end

-- A list of the moving springs, so callbacks may start or end springs while they are stepped.
function Handlers.Moving()
	local list = {}
	for spring in pairs(lib.motion.moving) do
		table.insert(list, spring)
	end

	return list
end

function Handlers.Update(elapsed)
	for _, spring in ipairs(Handlers.Moving()) do
		spring.value, spring.velocity = Motion.Step(spring.value, spring.velocity, spring.target, spring.response,
			spring.damping, elapsed)
		if Motion.Settled(spring.value, spring.velocity, spring.target, spring.epsilon) then
			spring:Jump(spring.target)
		else
			spring.onUpdate(spring.value)
		end
	end
	if next(lib.motion.moving) == nil then
		lib.motion.frame:SetScript("OnUpdate", nil)
	end
end
