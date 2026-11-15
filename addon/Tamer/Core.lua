-- Tamer: shows what your Hunter pet should learn next, and where to get it.
-- Core holds the saved data, the slash command, and helpers the other files share.
local ADDON, ns = ...

local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
ns.Version = getMetadata and getMetadata(ADDON, "Version") or nil

ns.Icon = "Interface\\AddOns\\Tamer\\Textures\\Icon"
ns.MinimapIcon = "Interface\\AddOns\\Tamer\\Textures\\MinimapIcon"

local db, char

local function say(msg)
	print("|cffabd473Tamer:|r " .. msg)
end

ns.Say = say

-- Some APIs can return secret values, which error on string operations.
local function plain(value)
	if value ~= nil and issecretvalue and issecretvalue(value) then
		return nil
	end
	return value
end

ns.Plain = plain

function ns.GetDB()
	return db
end

-- What this character's Hunter knows, saved separately for each character.
function ns.CharData()
	return char
end

function ns.IsHunter()
	local _, class = UnitClass("player")
	return class == "HUNTER"
end

-------------------------------------------------------------------------------
-- Frames
-------------------------------------------------------------------------------

-- Saves a frame's position in db[key] whenever it's dragged.
function ns.MakeDraggable(target, key)
	target:SetClampedToScreen(true)
	target:SetMovable(true)
	target:EnableMouse(true)
	target:RegisterForDrag("LeftButton")
	target:SetScript("OnDragStart", target.StartMoving)
	target:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, x, y = self:GetPoint()
		db[key] = { point = point, relativePoint = relativePoint, x = x, y = y }
	end)
end

function ns.PlaceFrame(target, key, ...)
	local position = db[key]
	if position then
		target:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
	else
		target:SetPoint(...)
	end
end

-- For small frames: dark, with a border in the bronze of the game's own windows.
function ns.ApplyBackdrop(target)
	if not target.SetBackdrop then return end
	target:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	target:SetBackdropColor(0.06, 0.06, 0.04, 0.96)
	target:SetBackdropBorderColor(0.72, 0.55, 0.32)
end

-- Plays one of the game's interface sounds. A client without that sound stays silent.
function ns.PlayUISound(name)
	local id = SOUNDKIT and SOUNDKIT[name]
	if id then
		PlaySound(id)
	end
end

-- A full window in the game's own style: its border, title bar, round portrait, and
-- close button. If the client doesn't have that template, a plain frame stands in.
function ns.NewWindow(name, title, icon, width, height)
	local ok, frame = pcall(CreateFrame, "Frame", name, UIParent, "PortraitFrameTemplate")
	if ok and frame and frame.SetTitle then
		frame:SetTitle(title)
		if frame.SetPortraitToAsset then frame:SetPortraitToAsset(icon) end
	else
		frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
		ns.ApplyBackdrop(frame)
		local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		text:SetPoint("TOP", 0, -8)
		text:SetText(title)
		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)
	end
	frame:SetSize(width, height)
	return frame
end

-- A recessed panel from the game to hold a list. A plain dark panel stands in without it.
function ns.NewInset(parent)
	local ok, inset = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
	if not ok or not inset then
		inset = CreateFrame("Frame", nil, parent, "BackdropTemplate")
		ns.ApplyBackdrop(inset)
	end
	return inset
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local handlers = {}

function handlers.ADDON_LOADED(name)
	if name ~= ADDON then return end
	TamerDB = TamerDB or {}
	db = TamerDB
	db.chars = db.chars or {}
end

function handlers.PLAYER_LOGIN()
	local name, realm = plain(UnitName("player")), plain(GetRealmName())
	local key = (name or "?") .. "-" .. (realm or "?")
	db.chars[key] = db.chars[key] or {}
	char = db.chars[key]
	char.known = char.known or {}
	char.seenFamilies = char.seenFamilies or {}

	if ns.BuildMinimapButton then ns.BuildMinimapButton() end
	-- Built now, before any fight, because its Teach button can't be made in combat.
	if ns.Dashboard then ns.Dashboard.Build() end
	if ns.Knowledge then ns.Knowledge.Start() end
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

function commands.show()
	ns.Dashboard.Toggle()
end

function commands.minimap()
	ns.ToggleMinimapButton()
	say(db.minimapHidden and "minimap icon hidden. Type /tamer minimap to bring it back." or "minimap icon shown.")
end

function commands.status()
	ns.Knowledge.PrintStatus()
end

function commands.debug()
	ns.Knowledge.PrintDebug()
end

function commands.help()
	say("commands:")
	print("  /tamer: open or close the window")
	print("  /tamer minimap: show or hide the minimap icon")
	print("  /tamer status: print what Tamer can read about you and your pet")
	print("  /tamer debug: print what the game returns, for bug reports")
	print("  /tamer help: list the commands")
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
