-- Works out what the pet knows, what it can train now, what comes next, and what the
-- Hunter should go learn. Plain tables in, plain tables out, with no game calls, so
-- the test harness can check every case.
local _, ns = ...

local Advisor = {}
ns.Advisor = Advisor

local MAX_BEASTS = 3

local function familyCanLearn(info, family)
	if info.families == "all" then return true end
	for _, name in ipairs(info.families) do
		if name == family then return true end
	end
	return false
end

local function isFamily(data, family)
	for _, name in ipairs(data.Families or {}) do
		if name == family then return true end
	end
	return false
end

-- The abilities this family can learn, in alphabetical order. A family Tamer doesn't
-- know gets none, rather than only the ones every family shares.
function Advisor.FamilyAbilities(data, family)
	local names = {}
	family = data.FamilyAliases and data.FamilyAliases[family] or family
	if not family or not isFamily(data, family) then return names end
	for name, info in pairs(data.Abilities) do
		if familyCanLearn(info, family) then names[#names + 1] = name end
	end
	table.sort(names)
	return names
end

-- A rank's level and full training point cost. What the Hunter's Beast Training window
-- showed comes first, then Tamer's data.
local function rankInfo(data, hunterRanks, ability, rank)
	local seen = hunterRanks and hunterRanks[ability] and hunterRanks[ability][rank]
	local entry = data.Abilities[ability].ranks[rank]
	local level = (entry and entry.level) or (seen and seen.level)
	local cost = (entry and entry.cost) or (seen and seen.cost)
	return level, cost
end

-- Training a higher rank refunds the points spent on the rank the pet has, so it costs
-- the difference.
local function netCost(data, hunterRanks, ability, rank, petRank)
	local _, cost = rankInfo(data, hunterRanks, ability, rank)
	if not cost then return nil end
	if petRank > 0 then
		local _, current = rankInfo(data, hunterRanks, ability, petRank)
		cost = cost - (current or 0)
	end
	return math.max(cost, 0)
end

-- Up to three beasts that teach this rank. Beasts you can tame at your level come first,
-- nearest your level first, then the ones you're still too low for.
function Advisor.Teachers(data, ability, rank, playerLevel)
	local found = {}
	for _, beast in ipairs(data.Beasts or {}) do
		for _, taught in ipairs(beast.teaches) do
			if taught[1] == ability and taught[2] == rank then
				local low, high = beast.level[1], beast.level[2] or beast.level[1]
				local tooHigh = low > playerLevel
				local distance = tooHigh and (low - playerLevel) or math.max(0, playerLevel - high)
				found[#found + 1] = {
					name = beast.name, family = beast.family, zone = beast.zone,
					low = low, high = high, tooHigh = tooHigh, distance = distance,
				}
				break
			end
		end
	end
	table.sort(found, function(a, b)
		if a.tooHigh ~= b.tooHigh then return not a.tooHigh end
		if a.distance ~= b.distance then return a.distance < b.distance end
		return a.name < b.name
	end)
	for i = #found, MAX_BEASTS + 1, -1 do found[i] = nil end
	return found
end

local function sortedRanks(byRank)
	local list = {}
	for rank in pairs(byRank or {}) do list[#list + 1] = rank end
	table.sort(list)
	return list
end

--[[
input = {
	pet = { name, family, level, points } or nil,
	petRanks = { [ability] = highest rank the pet knows },
	hunterRanks = { [ability] = { [rank] = { level, cost } } }, or nil if Beast Training
		hasn't been seen with this family yet,
	playerLevel = number,
	data = ns.Data,
}
]]
function Advisor.Build(input)
	local data, pet = input.data, input.pet
	local advice = { pet = pet, known = {}, ready = {}, needsPoints = {}, nextUp = {}, goLearn = {} }
	if not pet then
		advice.noPet = true
		return advice
	end
	local abilities = Advisor.FamilyAbilities(data, pet.family)
	if #abilities == 0 then
		advice.noData = true
		return advice
	end
	local hunterRanks = input.hunterRanks
	advice.needsBeastTraining = hunterRanks == nil
	local petRanks = input.petRanks or {}
	local points = pet.points or 0

	for _, ability in ipairs(abilities) do
		local petRank = petRanks[ability] or 0
		if petRank > 0 then
			advice.known[#advice.known + 1] = { ability = ability, rank = petRank }
		end

		if hunterRanks then
			local known = sortedRanks(hunterRanks[ability])
			local best, bestAllowed, upcoming
			for _, rank in ipairs(known) do
				if rank > petRank then
					local level = rankInfo(data, hunterRanks, ability, rank)
					if level and level <= pet.level then
						bestAllowed = rank
						local cost = netCost(data, hunterRanks, ability, rank, petRank)
						if cost and cost <= points then best = rank end
					elseif level and not upcoming then
						upcoming = rank
					end
				end
			end

			if best then
				advice.ready[#advice.ready + 1] = {
					ability = ability, rank = best, cost = netCost(data, hunterRanks, ability, best, petRank),
				}
			end
			if bestAllowed and bestAllowed ~= best then
				advice.needsPoints[#advice.needsPoints + 1] = {
					ability = ability, rank = bestAllowed,
					cost = netCost(data, hunterRanks, ability, bestAllowed, petRank), points = points,
				}
			end
			if upcoming then
				local level = rankInfo(data, hunterRanks, ability, upcoming)
				advice.nextUp[#advice.nextUp + 1] = { ability = ability, rank = upcoming, level = level }
			end

			-- The next rank the Hunter doesn't know yet.
			local highest = math.max(known[#known] or 0, petRank)
			local nextRank = highest + 1
			if data.Abilities[ability].ranks[nextRank] and not (hunterRanks[ability] or {})[nextRank] then
				local level = rankInfo(data, hunterRanks, ability, nextRank)
				local source = data.Abilities[ability].source
				advice.goLearn[#advice.goLearn + 1] = {
					ability = ability, rank = nextRank, level = level, source = source,
					beasts = source == "beast" and Advisor.Teachers(data, ability, nextRank, input.playerLevel or 1) or {},
				}
			end
		end
	end

	table.sort(advice.nextUp, function(a, b)
		if a.level ~= b.level then return a.level < b.level end
		return a.ability < b.ability
	end)
	table.sort(advice.goLearn, function(a, b)
		if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
		return a.ability < b.ability
	end)
	return advice
end
