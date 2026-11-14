-- Tamer: shows what your Hunter pet should learn next, and where to get it.
-- For now it loads, keeps its saved data, and answers /tamer.
local ADDON, ns = ...

local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
ns.Version = getMetadata and getMetadata(ADDON, "Version") or nil

local db

local function say(msg)
	print("|cffabd473Tamer:|r " .. msg)
end

ns.Say = say

function ns.GetDB()
	return db
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local handlers = {}

function handlers.ADDON_LOADED(name)
	if name ~= ADDON then return end
	TamerDB = TamerDB or {}
	db = TamerDB
end

function handlers.PLAYER_LOGIN()
	say("loaded. Type /tamer.")
end

local events = CreateFrame("Frame")
for event in pairs(handlers) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)

-------------------------------------------------------------------------------
-- Slash command
-------------------------------------------------------------------------------

local commands = {}

function commands.help()
	say("commands:")
	print("  /tamer: show your pet's next step")
	print("  /tamer help: list the commands")
end

function commands.show()
	say("no pet dashboard yet. Nothing to see yet.")
end

SLASH_TAMER1 = "/tamer"
SlashCmdList.TAMER = function(input)
	local command = (input or ""):match("^%s*(%S*)"):lower()
	local run = commands[command == "" and "show" or command]
	if run then
		run()
	else
		say("unknown command. Type /tamer help.")
	end
end
