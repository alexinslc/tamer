-- Reads the game: the pet, its spellbook, its training points, and the Beast Training
-- window. Saves which ranks the Hunter knows, since the game only shows them while
-- Beast Training is open.
local _, ns = ...

local K = {}
ns.Knowledge = K

local plain = function(value) return ns.Plain(value) end

-- Goes up whenever the Hunter learns a rank, so the level-up line can tell a rank that
-- became ready from leveling apart from one that's ready because you just learned it.
K.version = 0

-- "Rank 3" -> 3. An ability with no rank text is rank 1.
function K.RankNumber(text)
	text = plain(text)
	if not text or text == "" then return 1 end
	return tonumber(text:match("(%d+)")) or 1
end

local function rankCost(ability, rank)
	local info = ns.Data.Abilities[ability]
	local entry = info and info.ranks[rank]
	return entry and entry.cost or nil, entry and entry.level or nil
end

-------------------------------------------------------------------------------
-- Reading
-------------------------------------------------------------------------------

-- The summoned pet, or nil. Only a Hunter's pet counts.
function K.Pet()
	if not ns.IsHunter() or not UnitExists("pet") then return nil end
	local pet = {
		name = plain(UnitName("pet")) or "Your pet",
		level = plain(UnitLevel("pet")) or 0,
		family = plain(UnitCreatureFamily("pet")),
	}
	if GetPetExperience then
		pet.xp, pet.xpMax = GetPetExperience()
	end
	if GetPetTrainingPoints then
		local total, spent = GetPetTrainingPoints()
		if total then pet.points = total - (spent or 0) end
	end
	return pet
end

local BOOK = BOOKTYPE_PET or "pet"

local function petSpellName(index)
	if GetSpellBookItemName then
		return GetSpellBookItemName(index, BOOK)
	elseif GetSpellName then
		return GetSpellName(index, BOOK)
	end
end

-- The highest rank of each ability the pet knows, e.g. { Claw = 3, Growl = 2 }.
function K.PetRanks()
	local ranks = {}
	local count = HasPetSpells and HasPetSpells() or 0
	for i = 1, count or 0 do
		local name, sub = petSpellName(i)
		name = plain(name)
		if name and ns.Data.Abilities[name] then
			local rank = K.RankNumber(sub)
			if rank > (ranks[name] or 0) then ranks[name] = rank end
		end
	end
	return ranks
end

-- Records one rank the Hunter knows. Tamer only ever adds ranks, since a Hunter
-- never forgets one.
local function remember(ability, rank, level, cost)
	local char = ns.CharData()
	if not char or not ns.Data.Abilities[ability] then return false end
	char.known[ability] = char.known[ability] or {}
	local isNew = char.known[ability][rank] == nil
	if isNew then K.version = K.version + 1 end
	local dataCost, dataLevel = rankCost(ability, rank)
	char.known[ability][rank] = { level = level or dataLevel, cost = cost or dataCost }
	return isNew
end

-- Reads the open Beast Training window. It lists the ranks the Hunter knows for the
-- current pet's family, so seeing it once per family is enough.
function K.ReadBeastTraining()
	if not GetNumCrafts or not GetCraftInfo then return end
	local found = 0
	for i = 1, GetNumCrafts() or 0 do
		local name, sub, kind, _, _, cost, level = GetCraftInfo(i)
		name = plain(name)
		if name and kind ~= "header" and ns.Data.Abilities[name] then
			remember(name, K.RankNumber(sub), plain(level), plain(cost))
			found = found + 1
		end
	end
	local pet = K.Pet()
	if found > 0 and pet and pet.family then
		ns.CharData().seenFamilies[pet.family] = true
	end
end

-- Turns a game string such as "You have learned a new spell: %s." into a pattern.
local function toPattern(format)
	if type(format) ~= "string" then return nil end
	local escaped = format:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	return "^" .. escaped:gsub("%%%%s", "(.+)") .. "$"
end

local learnPatterns = {}
for _, key in ipairs({ "ERR_LEARN_SPELL_S", "ERR_LEARN_ABILITY_S" }) do
	learnPatterns[#learnPatterns + 1] = toPattern(_G[key])
end

-- "You have learned a new spell: Claw (Rank 3)." adds Claw 3 to what the Hunter knows.
function K.ReadLearnMessage(message)
	message = plain(message)
	if not message then return false end
	for _, pattern in ipairs(learnPatterns) do
		local what = message:match(pattern)
		if what then
			local ability, rankText = what:match("^(.-) %((.-)%)$")
			ability = ability or what
			if ns.Data.Abilities[ability] then
				return remember(ability, K.RankNumber(rankText))
			end
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- What the advisor needs
-------------------------------------------------------------------------------

-- Everything Advisor.Build takes, read fresh from the game.
function K.Snapshot()
	local pet = K.Pet()
	local char = ns.CharData()
	local seen = pet and pet.family and char and char.seenFamilies[pet.family]
	return {
		pet = pet,
		petRanks = pet and K.PetRanks() or {},
		hunterRanks = seen and char.known or nil,
		playerLevel = plain(UnitLevel("player")) or 1,
		data = ns.Data,
	}
end

function K.Advice()
	return ns.Advisor.Build(K.Snapshot())
end

-------------------------------------------------------------------------------
-- The level-up line
-------------------------------------------------------------------------------

local last -- The pet and its ready ranks the last time Tamer looked.

local function readyKeys(advice)
	local keys = {}
	for _, entry in ipairs(advice.ready or {}) do
		keys[entry.ability .. "#" .. entry.rank] = entry
	end
	return keys
end

local function listNames(entries)
	local names = {}
	for i, entry in ipairs(entries) do
		names[i] = ("%s (Rank %d)"):format(entry.ability, entry.rank)
	end
	if #names <= 1 then return names[1] or "" end
	return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- Prints one line when the pet levels into a rank it can be taught. Not at login,
-- not when the pet changes, and not when you learn a rank some other way. The game
-- can raise the pet's training points a moment after its level, so more points on
-- the same pet counts too.
local function checkLevelUp()
	local advice = K.Advice()
	local pet = advice.pet
	local now = {
		name = pet and pet.name, family = pet and pet.family, level = pet and pet.level,
		points = pet and pet.points or 0, version = K.version, ready = readyKeys(advice),
	}
	local grew = last and pet and (now.level > (last.level or now.level) or now.points > (last.points or now.points))
	if grew and last.name == now.name and last.family == now.family and last.version == now.version then
		local fresh = {}
		for key, entry in pairs(now.ready) do
			if not last.ready[key] then fresh[#fresh + 1] = entry end
		end
		table.sort(fresh, function(a, b) return a.ability < b.ability end)
		if #fresh > 0 then
			ns.Say(("%s can now learn %s. Cast Beast Training to teach %s."):format(
				pet.name, listNames(fresh), #fresh == 1 and "it" or "them"))
		end
	end
	last = now
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local function changed()
	checkLevelUp()
	if ns.Dashboard then ns.Dashboard.Refresh() end
end

local handlers = {}

function handlers.UNIT_PET(unit)
	if unit == "player" then changed() end
end

function handlers.UNIT_LEVEL(unit)
	if unit == "pet" or unit == "player" then changed() end
end

function handlers.UNIT_PET_EXPERIENCE(unit)
	if not unit or unit == "pet" then
		if ns.Dashboard then ns.Dashboard.Refresh() end
	end
end

function handlers.UNIT_PET_TRAINING_POINTS(unit)
	if not unit or unit == "player" or unit == "pet" then changed() end
end

handlers.PET_BAR_UPDATE = changed
handlers.SPELLS_CHANGED = changed
handlers.PLAYER_ENTERING_WORLD = changed

function handlers.CRAFT_SHOW()
	K.ReadBeastTraining()
	changed()
end
handlers.CRAFT_UPDATE = handlers.CRAFT_SHOW

function handlers.CHAT_MSG_SYSTEM(message)
	if K.ReadLearnMessage(message) then changed() end
end

local frame
function K.Start()
	if frame then return end
	frame = CreateFrame("Frame")
	-- A client without one of these events errors on registering it, so each is tried alone.
	for event in pairs(handlers) do
		pcall(frame.RegisterEvent, frame, event)
	end
	frame:SetScript("OnEvent", function(_, event, ...)
		handlers[event](...)
	end)
	checkLevelUp()
end

-------------------------------------------------------------------------------
-- /tamer status
-------------------------------------------------------------------------------

local function rankList(ranks)
	local parts = {}
	for ability, rank in pairs(ranks) do
		parts[#parts + 1] = ("%s %d"):format(ability, rank)
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, ", ") or "none"
end

function K.PrintStatus()
	if not ns.IsHunter() then
		ns.Say("you're not a Hunter, so there's no pet to read.")
		return
	end
	local pet = K.Pet()
	if not pet then
		ns.Say("no pet out. Call your pet and try again.")
	else
		ns.Say(("%s, level %d %s."):format(pet.name, pet.level, pet.family or "unknown family"))
		print(("  Experience: %s / %s"):format(tostring(pet.xp), tostring(pet.xpMax)))
		print(("  Training points left: %s"):format(tostring(pet.points)))
		print("  Pet knows: " .. rankList(K.PetRanks()))
	end
	local char = ns.CharData()
	local best = {}
	for ability, ranks in pairs(char.known) do
		for rank in pairs(ranks) do
			if rank > (best[ability] or 0) then best[ability] = rank end
		end
	end
	print("  You know (highest ranks): " .. rankList(best))
	local families = {}
	for family in pairs(char.seenFamilies) do families[#families + 1] = family end
	table.sort(families)
	print("  Beast Training seen with: " .. (#families > 0 and table.concat(families, ", ") or "no pets yet"))
end
