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
	-- Forever keeps this in C_PetInfo. Classic has it as a global.
	local trainingPoints = (C_PetInfo and C_PetInfo.GetPetTrainingPoints) or GetPetTrainingPoints
	if trainingPoints then
		local total, spent = trainingPoints()
		total, spent = plain(total), plain(spent)
		if type(total) == "number" then pet.points = total - (type(spent) == "number" and spent or 0) end
	end
	return pet
end

local BOOK = BOOKTYPE_PET or "pet"
local MAX_SLOTS = 200

-- A spell's rank text, such as "Rank 3", from its spell ID.
local function spellSubtext(id)
	if not id then return nil end
	local text
	if C_Spell and C_Spell.GetSpellSubtext then
		text = C_Spell.GetSpellSubtext(id)
	elseif GetSpellSubtext then
		text = GetSpellSubtext(id)
	end
	text = plain(text)
	if text and text ~= "" then return text end
	return nil
end

-- Splits "Bite (Rank 3)" into "Bite" and "Rank 3". Other names come back as they are.
local function splitName(name)
	local base, rankText = name:match("^(.-) %((.-)%)$")
	if base and rankText:find("%d") then return base, rankText end
	return name
end

-- The name, rank text and spell ID of one slot in the pet's spellbook. Forever runs on a
-- newer engine than Classic, so the newer spellbook API comes first.
local function petSpellAt(index)
	local name, sub, id
	if C_SpellBook and C_SpellBook.GetSpellBookItemName and Enum and Enum.SpellBookSpellBank then
		name, sub, id = C_SpellBook.GetSpellBookItemName(index, Enum.SpellBookSpellBank.Pet)
	elseif GetSpellBookItemName then
		name, sub, id = GetSpellBookItemName(index, BOOK)
	elseif GetSpellName then
		name, sub = GetSpellName(index, BOOK)
	end
	name, sub = plain(name), plain(sub)
	if (not id) and C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank then
		local info = C_SpellBook.GetSpellBookItemInfo(index, Enum.SpellBookSpellBank.Pet)
		id = type(info) == "table" and (info.spellID or info.actionID) or nil
	end
	return name, sub, id
end

-- How many slots to look at. When the game won't say, look until the book runs out.
local function petSlotCount()
	local count = HasPetSpells and plain(HasPetSpells()) or nil
	if type(count) == "number" and count > 0 then return count, true end
	return MAX_SLOTS, false
end

-- One pet ability: its name and rank, or nil when it isn't a pet ability Tamer knows.
local function readAbility(name, sub, id)
	if not name then return nil end
	local base, rankText = splitName(name)
	if not ns.Data.Abilities[base] then return nil end
	if not sub or sub == "" then sub = rankText or spellSubtext(id) end
	return base, K.RankNumber(sub)
end

-- The highest rank of each ability the pet knows, e.g. { Claw = 3, Growl = 2 }.
function K.PetRanks()
	local ranks = {}
	if not UnitExists("pet") then return ranks end
	local count, exact = petSlotCount()
	for i = 1, count do
		local name, sub, id = petSpellAt(i)
		if not name and not exact then break end
		local ability, rank = readAbility(name, sub, id)
		if ability and rank > (ranks[ability] or 0) then ranks[ability] = rank end
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

-- Classic's Beast Training window, which uses the craft API.
local function readCrafts()
	if not GetNumCrafts or not GetCraftInfo then return 0 end
	local found = 0
	for i = 1, GetNumCrafts() or 0 do
		local name, sub, kind, _, _, cost, level = GetCraftInfo(i)
		name = plain(name)
		if name and kind ~= "header" then
			local ability, rankText = splitName(name)
			if ns.Data.Abilities[ability] then
				remember(ability, K.RankNumber(rankText or plain(sub)), plain(level), plain(cost))
				found = found + 1
			end
		end
	end
	return found
end

-- The recipes in the open trade skill window, as { id, name, rankText } for pet abilities.
local function tradeSkillAbilities()
	local list = {}
	local ui = C_TradeSkillUI
	if not ui or not ui.GetAllRecipeIDs or not ui.GetRecipeInfo then return list end
	for _, id in ipairs(ui.GetAllRecipeIDs() or {}) do
		local info = ui.GetRecipeInfo(id)
		if type(info) == "table" and info.learned ~= false then
			local name = plain(info.name)
			if name then
				local ability, rankText = splitName(name)
				if ns.Data.Abilities[ability] then
					rankText = rankText or plain(info.subText) or spellSubtext(id)
					if rankText == "" then rankText = nil end
					list[#list + 1] = { id = id, ability = ability, rankText = rankText }
				end
			end
		end
	end
	return list
end

-- Forever's Beast Training window, which is a trade skill window. When a rank has no rank
-- text, the ranks of an ability are numbered in spell ID order, since higher ranks have
-- higher IDs.
local function readTradeSkill()
	local list = tradeSkillAbilities()
	local unranked = {}
	for _, entry in ipairs(list) do
		if entry.rankText then
			remember(entry.ability, K.RankNumber(entry.rankText))
		else
			unranked[entry.ability] = unranked[entry.ability] or {}
			table.insert(unranked[entry.ability], entry.id)
		end
	end
	for ability, ids in pairs(unranked) do
		table.sort(ids)
		for rank = 1, #ids do remember(ability, rank) end
	end
	return #list
end

-- Forever's Beast Training window, if it's a trainer window. A Pet Trainer NPC uses the same
-- window to sell ranks you don't know yet, so a window with an NPC behind it is skipped.
local CATEGORIES = { available = true, unavailable = true, used = true, header = true }

local function readTrainer()
	if not GetNumTrainerServices or not GetTrainerServiceInfo then return 0 end
	if UnitExists("npc") then return 0 end
	local found = 0
	for i = 1, GetNumTrainerServices() or 0 do
		-- Classic returns name, rank, category. Forever returns name, category, icon, level,
		-- rank. So the rank and category are found by what they look like.
		local values = { GetTrainerServiceInfo(i) }
		local name = plain(values[1])
		local category, sub
		for j = 2, #values do
			local value = plain(values[j])
			if type(value) == "string" then
				if CATEGORIES[value] and not category then
					category = value
				elseif value:find("%d") and not sub then
					sub = value
				end
			end
		end
		if name and category ~= "header" then
			local ability, rankText = splitName(name)
			if ns.Data.Abilities[ability] then
				local level = GetTrainerServiceLevelReq and plain(GetTrainerServiceLevelReq(i)) or nil
				if type(level) ~= "number" or level < 1 then level = nil end
				remember(ability, K.RankNumber(rankText or sub), level)
				found = found + 1
			end
		end
	end
	return found
end

-- Reads the open Beast Training window. It lists the ranks the Hunter knows for the
-- current pet's family, so seeing it once per family is enough.
function K.ReadBeastTraining()
	local found = readCrafts() + readTradeSkill() + readTrainer()
	local pet = K.Pet()
	if found > 0 and pet and pet.family then
		ns.CharData().seenFamilies[pet.family] = true
	end
	return found
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
-- Forever opens Beast Training as a trade skill window.
handlers.TRADE_SKILL_SHOW = handlers.CRAFT_SHOW
handlers.TRADE_SKILL_LIST_UPDATE = handlers.CRAFT_SHOW
handlers.TRADE_SKILL_DATA_SOURCE_CHANGED = handlers.CRAFT_SHOW
handlers.TRAINER_SHOW = handlers.CRAFT_SHOW
handlers.TRAINER_UPDATE = handlers.CRAFT_SHOW

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
-- /tamer debug
-------------------------------------------------------------------------------

local function show(...)
	local parts = {}
	for i = 1, select("#", ...) do local value = plain((select(i, ...))); parts[i] = tostring(value) end
	return table.concat(parts, " | ")
end

local function fields(info)
	if type(info) ~= "table" then return tostring(info) end
	local parts = {}
	for key, value in pairs(info) do
		local kind = type(value)
		if kind == "string" or kind == "number" or kind == "boolean" then
			parts[#parts + 1] = key .. "=" .. tostring(value)
		end
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

-- Prints what the game returns for the pet's spellbook and the open trade skill or craft
-- window, so a bug report shows exactly what Tamer had to work with.
function K.PrintDebug()
	ns.Say("debug. Run it with Beast Training open to include the window.")
	print("  GetPetTrainingPoints: " .. (GetPetTrainingPoints and show(GetPetTrainingPoints()) or "missing")
		.. ", C_PetInfo: " .. (C_PetInfo and C_PetInfo.GetPetTrainingPoints and show(C_PetInfo.GetPetTrainingPoints()) or "missing"))
	print("  npc: " .. show(UnitExists("npc"), UnitName("npc")))
	print("  APIs: C_SpellBook=" .. tostring(C_SpellBook ~= nil) .. " GetSpellBookItemName=" .. tostring(GetSpellBookItemName ~= nil)
		.. " C_TradeSkillUI=" .. tostring(C_TradeSkillUI ~= nil) .. " GetCraftInfo=" .. tostring(GetCraftInfo ~= nil))
	print("  HasPetSpells: " .. (HasPetSpells and show(HasPetSpells()) or "missing"))
	local count, exact = petSlotCount()
	for i = 1, math.min(count, 20) do
		local name, sub, id = petSpellAt(i)
		if not name and not exact then break end
		print(("  pet %d: %s | sub=%s | id=%s | subtext=%s"):format(i, tostring(name), tostring(sub), tostring(id), tostring((spellSubtext(id)))))
	end
	local ui = C_TradeSkillUI
	if ui and ui.GetAllRecipeIDs then
		local base = ui.GetBaseProfessionInfo and ui.GetBaseProfessionInfo()
		print("  Trade skill: " .. fields(base))
		local ids = ui.GetAllRecipeIDs() or {}
		print("  Recipes: " .. #ids)
		for i = 1, math.min(#ids, 12) do
			print(("  recipe %d: %s | subtext=%s"):format(ids[i], fields(ui.GetRecipeInfo and ui.GetRecipeInfo(ids[i])), tostring((spellSubtext(ids[i])))))
		end
	end
	if GetNumTrainerServices then
		local count = GetNumTrainerServices() or 0
		print("  Trainer services: " .. tostring(count) .. ", type " .. (C_Trainer and C_Trainer.GetTrainerType and show(C_Trainer.GetTrainerType()) or "?"))
		for i = 1, math.min(count, 12) do
			print(("  service %d: %s | level %s | cost %s"):format(i, show(GetTrainerServiceInfo(i)),
				GetTrainerServiceLevelReq and show(GetTrainerServiceLevelReq(i)) or "?",
				GetTrainerServiceCost and show(GetTrainerServiceCost(i)) or "?"))
		end
	end
	if GetNumCrafts then
		print("  Crafts: " .. tostring(GetNumCrafts()))
		for i = 1, math.min(GetNumCrafts() or 0, 12) do
			print("  craft " .. i .. ": " .. show(GetCraftInfo(i)))
		end
	end
	print("  Tamer read: " .. tostring(K.ReadBeastTraining()) .. " Beast Training ranks, pet ranks " .. (function()
		local parts = {}
		for ability, rank in pairs(K.PetRanks()) do parts[#parts + 1] = ability .. " " .. rank end
		table.sort(parts)
		return #parts > 0 and table.concat(parts, ", ") or "none"
	end)())
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
