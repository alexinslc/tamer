-- Headless smoke test for Tamer: stubs the WoW API, loads the addon the way the
-- client does (TOC order, missing files skipped), and drives its flows.
-- It proves the addon's Lua logic, NOT that the stubbed APIs exist in the client.
--
-- Run it with LuaJIT or any Lua 5.1:
--   luajit tools/harness/harness.lua [addon folder]
-- The addon folder defaults to addon/Tamer next to this tools folder.
local scriptDir = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local ADDON_DIR = ADDON_DIR or (arg and arg[1]) or (scriptDir .. "/../../addon/Tamer")
local ADDON = "Tamer"
local realG = _G
local stdPrint = print

local passed, failed = 0, 0
local failures = {}
local function check(name, cond, detail)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		failures[#failures + 1] = name .. (detail and (" -- " .. tostring(detail)) or "")
		stdPrint("  FAIL " .. name .. (detail and (" -- " .. tostring(detail)) or ""))
	end
end

-- What the addon printed to chat.
local chatOut = {}
local unknownGlobals = {}

-------------------------------------------------------------------------------
-- Frames
-------------------------------------------------------------------------------

local eventFrames = {}

local frameMethods = {}
frameMethods.__index = function(self, key)
	local method = rawget(frameMethods, key)
	if method then return method end
	-- Unmodelled API methods (always capitalized) are no-ops; data fields are nil.
	if type(key) == "string" and key:find("^%u") then
		return function() end
	end
	return nil
end

function frameMethods:SetScript(what, fn) self._scripts[what] = fn end
function frameMethods:GetScript(what) return self._scripts[what] end
function frameMethods:RegisterEvent(event)
	self._events[event] = true
	eventFrames[#eventFrames + 1] = self
end

local function newFrame()
	return setmetatable({ _scripts = {}, _events = {} }, frameMethods)
end

local function fire(event, ...)
	for _, f in ipairs(eventFrames) do
		if f._events[event] and f._scripts.OnEvent then
			f._scripts.OnEvent(f, event, ...)
		end
	end
end

-------------------------------------------------------------------------------
-- The game's globals
-------------------------------------------------------------------------------

local stubs = {
	CreateFrame = function() return newFrame() end,
	print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
		chatOut[#chatOut + 1] = table.concat(parts, " ")
	end,
	C_AddOns = {
		GetAddOnMetadata = function(name, field)
			if name == ADDON and field == "Version" then return "0.0.0-test" end
		end,
	},
	SlashCmdList = {},
}

local env = setmetatable({}, {
	__index = function(_, key)
		local value = stubs[key]
		if value ~= nil then return value end
		value = realG[key]
		if value == nil then unknownGlobals[key] = true end
		return value
	end,
})
for k, v in pairs(stubs) do env[k] = v end

-------------------------------------------------------------------------------
-- Loading
-------------------------------------------------------------------------------

local function tocFiles()
	local files = {}
	local toc = assert(io.open(ADDON_DIR .. "/" .. ADDON .. ".toc"), "no TOC in " .. ADDON_DIR)
	for line in toc:lines() do
		line = line:gsub("\r$", "")
		if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = line end
	end
	toc:close()
	return files
end

local ns = {}
for _, file in ipairs(tocFiles()) do
	local chunk = loadfile(ADDON_DIR .. "/" .. file)
	if chunk then
		setfenv(chunk, env)
		local ok, err = pcall(chunk, ADDON, ns)
		check("loads " .. file, ok, err)
	end
end

local function slash(input)
	env.SlashCmdList.TAMER(input)
	return chatOut[#chatOut]
end

local function printedSince(n, text)
	for i = n + 1, #chatOut do
		if chatOut[i]:find(text, 1, true) then return true end
	end
	return false
end

-------------------------------------------------------------------------------
-- Checks
-------------------------------------------------------------------------------

check("reads its version from the TOC", ns.Version == "0.0.0-test", ns.Version)

fire("ADDON_LOADED", "SomeOtherAddon")
check("ignores other addons loading", env.TamerDB == nil)
fire("ADDON_LOADED", ADDON)
check("creates its saved data", type(env.TamerDB) == "table")
check("shares its saved data", ns.GetDB() == env.TamerDB)

local n = #chatOut
fire("PLAYER_LOGIN")
check("says hello at login", printedSince(n, "Type /tamer"))

check("registers /tamer", env.SLASH_TAMER1 == "/tamer")
check("/tamer answers", slash("") ~= nil)
n = #chatOut
slash("help")
check("/tamer help lists the commands", printedSince(n, "/tamer help"))
check("an unknown command points to help", (slash("nonsense") or ""):find("/tamer help", 1, true))

stdPrint("")
stdPrint(("RESULT: %d passed, %d failed"):format(passed, failed))
for _, f in ipairs(failures) do stdPrint("  - " .. f) end
local names = {}
for name in pairs(unknownGlobals) do names[#names + 1] = name end
table.sort(names)
stdPrint("Globals read but not stubbed: " .. (#names > 0 and table.concat(names, ", ") or "none"))
os.exit(failed == 0 and 0 or 1)
