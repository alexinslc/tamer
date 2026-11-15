-- The one window. A header with the pet and its training points, then up to three cards:
-- green for what to teach now, gold for what's coming soon, blue for what to go find.
-- A Teach button at the bottom casts Beast Training. Details live in tooltips, so the
-- window itself stays short. It only draws what Advisor.Build returns.
local _, ns = ...

local Dashboard = {}
ns.Dashboard = Dashboard

local WIDTH = 340
local MIN_HEIGHT, MAX_HEIGHT = 240, 600
local TOP, BOTTOM = 88, 52 -- The header above the cards, and the Teach button below them.
local BAR = 24 -- Room for the scrollbar when the cards don't fit.
local PAD = 10
local CARD_PAD = 10
local TILE_ICON = 40
local ROW_ICON = 28
local ROW_HEIGHT = 34
local FIND_SHOWN = 3
local BEAST_TRAINING = 5149
local CALL_PET_ICON = "Interface\\Icons\\Ability_Hunter_BeastCall"

local frame, header, scroll, content, teach
local showAllFinds = false
local teachWanted -- Whether the Teach button should be shown once combat ends.

local CARDS = {
	ready = { bg = { 0.07, 0.16, 0.05 }, border = { 0.45, 0.78, 0.28 }, title = { 0.72, 0.96, 0.55 },
		icon = "Interface\\RaidFrame\\ReadyCheck-Ready" },
	soon = { bg = { 0.18, 0.14, 0.04 }, border = { 0.78, 0.62, 0.20 }, title = { 1, 0.82, 0.20 },
		icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
	find = { bg = { 0.06, 0.10, 0.18 }, border = { 0.36, 0.56, 0.82 }, title = { 0.62, 0.80, 1 },
		icon = "Interface\\Icons\\INV_Misc_Map_01" },
	note = { bg = { 0.08, 0.07, 0.05 }, border = { 0.62, 0.50, 0.30 }, title = { 1, 0.82, 0 },
		icon = "Interface\\Icons\\Ability_Hunter_BeastTraining" },
}

local GREY = { 0.72, 0.72, 0.72 }
local GREEN = { 0.55, 0.90, 0.40 }

local function plural(n, one, many)
	return n == 1 and one or many
end

local function points(n)
	return ("%d %s"):format(n, plural(n, "point", "points"))
end

local function rankName(entry)
	return ("%s (Rank %d)"):format(entry.ability, entry.rank)
end

local function beastTrainingName()
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(BEAST_TRAINING)
	if not name and GetSpellInfo then name = GetSpellInfo(BEAST_TRAINING) end
	return ns.Plain(name) or "Beast Training"
end

-------------------------------------------------------------------------------
-- Tooltips
-------------------------------------------------------------------------------

-- lines[1] is the title. Each later line is a string, or { text, color }.
local function showTooltip(owner, lines)
	if not lines then return end
	-- Beside the window, level with what you're hovering, so it never covers the window.
	if frame and owner ~= teach then
		GameTooltip:SetOwner(owner, "ANCHOR_NONE")
		GameTooltip:ClearAllPoints()
		GameTooltip:SetPoint("TOP", owner, "TOP", 0, 0)
		local right, screen = frame:GetRight(), UIParent:GetRight()
		if right and screen and right + 280 > screen then
			GameTooltip:SetPoint("RIGHT", frame, "LEFT", -4, 0)
		else
			GameTooltip:SetPoint("LEFT", frame, "RIGHT", 4, 0)
		end
	else
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	end
	GameTooltip:SetText(lines[1], 1, 0.82, 0)
	for i = 2, #lines do
		local line = lines[i]
		local text, color = line, { 1, 1, 1 }
		if type(line) == "table" then text, color = line[1], line[2] end
		GameTooltip:AddLine(text, color[1], color[2], color[3], true)
	end
	GameTooltip:Show()
end

local function hookTooltip(target)
	target:SetScript("OnEnter", function(self) showTooltip(self, self.tooltip) end)
	target:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-------------------------------------------------------------------------------
-- Pools: every refresh hides everything and takes what it needs again.
-------------------------------------------------------------------------------

local pools = {}

local function take(kind, make)
	local pool = pools[kind]
	if not pool then
		pool = { n = 0 }
		pools[kind] = pool
	end
	pool.n = pool.n + 1
	local item = pool[pool.n]
	if not item then
		item = make()
		pool[pool.n] = item
	end
	item:ClearAllPoints()
	item:Show()
	return item
end

local function releaseAll()
	for _, pool in pairs(pools) do
		for i = 1, #pool do pool[i]:Hide() end
		pool.n = 0
	end
end

local function newCard()
	local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
	if card.SetBackdrop then
		card:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
	end
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(20, 20)
	card.icon:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD)
	card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	card.title:SetPoint("LEFT", card.icon, "RIGHT", 6, 0)
	card.title:SetJustifyH("LEFT")
	return card
end

local function newTile()
	local tile = CreateFrame("Button", nil, content)
	tile.icon = tile:CreateTexture(nil, "ARTWORK")
	tile.icon:SetSize(TILE_ICON, TILE_ICON)
	tile.icon:SetPoint("TOP", 0, 0)
	tile.rank = tile:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	tile.rank:SetPoint("BOTTOMRIGHT", tile.icon, "BOTTOMRIGHT", -2, 2)
	tile.name = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tile.name:SetPoint("TOP", tile.icon, "BOTTOM", 0, -4)
	tile.cost = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tile.cost:SetPoint("TOP", tile.name, "BOTTOM", 0, -1)
	tile.cost:SetTextColor(unpack(GREEN))
	hookTooltip(tile)
	return tile
end

local function newRow()
	local row = CreateFrame("Button", nil, content)
	row:SetHeight(ROW_HEIGHT)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW_ICON, ROW_ICON)
	row.icon:SetPoint("LEFT", 0, 0)
	row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
	row.title:SetJustifyH("LEFT")
	row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
	row.sub:SetJustifyH("LEFT")
	row.sub:SetTextColor(unpack(GREY))
	row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.right:SetPoint("RIGHT", 0, 0)
	row.right:SetJustifyH("RIGHT")
	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints()
	row.highlight:SetColorTexture(1, 1, 1, 0.06)
	hookTooltip(row)
	row:SetScript("OnClick", function(self)
		if self.onClick then self.onClick() end
	end)
	return row
end

local function newText()
	local holder = CreateFrame("Frame", nil, content)
	holder.text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	holder.text:SetPoint("TOPLEFT")
	holder.text:SetJustifyH("LEFT")
	if holder.text.SetWordWrap then holder.text:SetWordWrap(true) end
	return holder
end

-------------------------------------------------------------------------------
-- Cards
-------------------------------------------------------------------------------

local y -- How far down the content the next card goes.

-- Starts a card and returns it with a cursor for its insides. finishCard sets its height.
local function startCard(kind, title)
	local style = CARDS[kind]
	local card = take("card", newCard)
	card:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
	card:SetWidth(content:GetWidth())
	if card.SetBackdropColor then
		card:SetBackdropColor(style.bg[1], style.bg[2], style.bg[3], 0.95)
		card:SetBackdropBorderColor(unpack(style.border))
	end
	card.icon:SetTexture(style.icon)
	card.title:SetText(title)
	card.title:SetTextColor(unpack(style.title))
	card.title:SetWidth(content:GetWidth() - 2 * CARD_PAD - 26)
	card.inner = CARD_PAD + 28
	return card
end

local function finishCard(card)
	local height = card.inner + CARD_PAD - 4
	card:SetHeight(height)
	y = y + height + 8
end

local function addText(card, text, color)
	local holder = take("text", newText)
	local width = content:GetWidth() - 2 * CARD_PAD
	holder:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -card.inner)
	holder.text:SetWidth(width)
	holder.text:SetText(text)
	holder.text:SetTextColor(unpack(color or { 1, 1, 1 }))
	local height = math.max(holder.text:GetStringHeight() or 14, 14)
	holder:SetSize(width, height)
	card.inner = card.inner + height + 6
end

local function addRow(card, info)
	local row = take("row", newRow)
	row:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -card.inner)
	row:SetWidth(content:GetWidth() - 2 * CARD_PAD)
	row.icon:SetTexture(info.icon)
	row.title:SetText(info.title)
	row.sub:SetText(info.sub or "")
	row.right:SetText(info.right or "")
	row.right:SetTextColor(unpack(info.rightColor or GREY))
	row.title:SetWidth(row:GetWidth() - ROW_ICON - 8 - 60)
	row.sub:SetWidth(row:GetWidth() - ROW_ICON - 8 - 60)
	row.tooltip = info.tooltip
	row.onClick = info.onClick
	card.inner = card.inner + ROW_HEIGHT + 4
	return row
end

-- The icons in a row of up to three, with the rank on the icon and the cost below.
local function addTiles(card, entries, pet)
	local width = (content:GetWidth() - 2 * CARD_PAD) / 3
	for i, entry in ipairs(entries) do
		local column = (i - 1) % 3
		local line = math.floor((i - 1) / 3)
		local tile = take("tile", newTile)
		tile:SetSize(width, TILE_ICON + 32)
		tile:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD + column * width, -(card.inner + line * (TILE_ICON + 38)))
		tile.icon:SetTexture(ns.Knowledge.Icon(entry.ability))
		tile.rank:SetText(entry.rank)
		tile.name:SetText(entry.ability)
		tile.name:SetWidth(width - 4)
		tile.cost:SetText(entry.cost and points(entry.cost) or "")
		tile.tooltip = { rankName(entry) }
		if entry.cost then
			tile.tooltip[2] = ("Costs %s. %s has %s."):format(points(entry.cost), pet.name, points(pet.points or 0))
		end
		tile.tooltip[#tile.tooltip + 1] = "Press Teach to open Beast Training, then pick it."
	end
	local lines = math.ceil(#entries / 3)
	card.inner = card.inner + lines * (TILE_ICON + 38)
end

local function addReady(advice)
	local pet, count = advice.pet, #advice.ready
	local card = startCard("ready", ("%s can learn %d %s now"):format(pet.name, count, plural(count, "thing", "things")))
	addTiles(card, advice.ready, pet)
	finishCard(card)
end

local function addSoon(advice)
	local pet = advice.pet
	if #advice.needsPoints == 0 and #advice.nextUp == 0 then return end
	local card = startCard("soon", "Coming soon")
	for _, entry in ipairs(advice.needsPoints) do
		local short = (entry.cost or 0) - (pet.points or 0)
		addRow(card, {
			icon = ns.Knowledge.Icon(entry.ability),
			title = rankName(entry),
			sub = ("Needs %s more"):format(points(math.max(short, 1))),
			right = points(entry.cost or 0),
			tooltip = {
				rankName(entry),
				("Costs %s and %s has %s."):format(points(entry.cost or 0), pet.name, points(pet.points or 0)),
				("%s gets more points as it levels up and grows more loyal."):format(pet.name),
			},
		})
	end
	for _, entry in ipairs(advice.nextUp) do
		local levels = entry.level - pet.level
		addRow(card, {
			icon = ns.Knowledge.Icon(entry.ability),
			title = rankName(entry),
			sub = ("%d more %s"):format(levels, plural(levels, "level", "levels")),
			right = ("Level %d"):format(entry.level),
			tooltip = {
				rankName(entry),
				("You know it already. %s can learn it at level %d."):format(pet.name, entry.level),
			},
		})
	end
	finishCard(card)
end

local function findTooltip(entry, pet)
	local lines = { rankName(entry) }
	if entry.level then
		lines[#lines + 1] = ("%s can use it from level %d."):format(pet.name, entry.level)
	end
	if entry.source == "trainer" then
		lines[#lines + 1] = "Buy it from a Pet Trainer in a capital city."
	elseif #entry.beasts == 0 then
		lines[#lines + 1] = { "Tamer doesn't know a beast that teaches this rank yet.", GREY }
	else
		lines[#lines + 1] = "Tame one of these and fight with it until you learn it:"
		for _, beast in ipairs(entry.beasts) do
			local levels = beast.low == beast.high and tostring(beast.low) or ("%d-%d"):format(beast.low, beast.high)
			local text = ("%s, level %s, %s"):format(beast.name, levels, beast.zone)
			if beast.tooHigh then
				lines[#lines + 1] = { text .. " (too high for you)", GREY }
			else
				lines[#lines + 1] = { text, GREEN }
			end
		end
	end
	return lines
end

local function findSub(entry)
	if entry.source == "trainer" then return "Pet Trainer in a city" end
	local beast = entry.beasts[1]
	if not beast then return "No beast in Tamer's list yet" end
	return ("%s, %s"):format(beast.name, beast.zone)
end

local function addFind(advice)
	local pet = advice.pet
	local card = startCard("find", "Go find these")
	if #advice.goLearn == 0 then
		addText(card, "You know every rank Tamer has for this family.", GREY)
		finishCard(card)
		return
	end
	local shown = showAllFinds and #advice.goLearn or math.min(#advice.goLearn, FIND_SHOWN)
	for i = 1, shown do
		local entry = advice.goLearn[i]
		addRow(card, {
			icon = ns.Knowledge.Icon(entry.ability),
			title = rankName(entry),
			sub = findSub(entry),
			right = entry.level and ("Level %d"):format(entry.level) or nil,
			tooltip = findTooltip(entry, pet),
		})
	end
	local hidden = #advice.goLearn - FIND_SHOWN
	if hidden > 0 then
		addRow(card, {
			icon = showAllFinds and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up",
			title = showAllFinds and "Show less" or ("Show %d more"):format(hidden),
			onClick = function()
				showAllFinds = not showAllFinds
				scroll:SetVerticalScroll(0)
				Dashboard.Refresh()
			end,
		})
	end
	finishCard(card)
end

local function addNote(title, text)
	local card = startCard("note", title)
	if text then addText(card, text, GREY) end
	finishCard(card)
end

-------------------------------------------------------------------------------
-- Header
-------------------------------------------------------------------------------

local function setPortrait(pet)
	local texture = frame.GetPortrait and frame:GetPortrait()
	if type(texture) ~= "table" then texture = frame.portrait end
	if type(texture) ~= "table" and type(frame.PortraitContainer) == "table" then
		texture = frame.PortraitContainer.portrait
	end
	if type(texture) ~= "table" then texture = nil end
	if pet and texture and SetPortraitTexture then
		SetPortraitTexture(texture, "pet")
	elseif frame.SetPortraitToAsset then
		-- With no pet, the Call Pet icon. It fills the circle, where Tamer's own icon has a
		-- see-through background.
		frame:SetPortraitToAsset(CALL_PET_ICON)
	end
end

local function drawHeader(pet)
	setPortrait(pet)
	if not pet then
		header.name:SetText("No pet")
		header.info:SetText("")
		header.badge:Hide()
		header.xp:Hide()
		return
	end
	header.name:SetText(pet.name)
	header.info:SetText(("Level %d %s"):format(pet.level, pet.family or ""))
	if pet.points then
		header.badge:Show()
		header.badge.number:SetText(pet.points)
		header.badge.label:SetText(plural(pet.points, "point", "points"))
		header.badge.tooltip = {
			"Training points",
			("%s spends these to learn abilities. It gets more as it levels up and grows more loyal."):format(pet.name),
		}
	else
		header.badge:Hide()
	end
	if pet.xp and pet.xpMax and pet.xpMax > 0 then
		header.xp:SetMinMaxValues(0, pet.xpMax)
		header.xp:SetValue(pet.xp)
		header.xp.tooltip = { "Experience", ("%d / %d to level %d"):format(pet.xp, pet.xpMax, pet.level + 1) }
		header.xp:Show()
	else
		header.xp:Hide()
	end
end

-------------------------------------------------------------------------------
-- The Teach button
-------------------------------------------------------------------------------

-- It casts Beast Training, so it's a protected button. The game won't let addons show,
-- hide or move one during combat, so it's made at login, parented to UIParent so the
-- window itself stays unprotected, and only shown or hidden outside combat.
local function syncTeach()
	if not teach then return end
	local want = frame and frame:IsShown() or false
	if InCombatLockdown and InCombatLockdown() then
		teachWanted = want
		teach:SetAlpha(want and 1 or 0)
		return
	end
	teachWanted = nil
	teach:SetAlpha(1)
	teach:SetShown(want)
end

local function setTeachText(advice)
	if not teach then return end
	local pet = advice and advice.pet
	if pet and advice.ready and #advice.ready > 0 then
		teach:SetText(("Teach %s"):format(pet.name))
	else
		teach:SetText("Open Beast Training")
	end
end

local function buildTeach()
	local ok, made = pcall(CreateFrame, "Button", "TamerTeachButton", UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
	teach = ok and made or CreateFrame("Button", "TamerTeachButton", UIParent, "UIPanelButtonTemplate")
	teach:SetSize(WIDTH - 2 * PAD - 40, 30)
	teach:SetFrameStrata("HIGH")
	teach:SetPoint("BOTTOM", frame, "BOTTOM", 0, PAD + 2)
	teach:SetAttribute("type", "spell")
	teach:SetAttribute("spell", beastTrainingName())
	-- Newer clients act on the press or the release depending on a setting, and need both.
	teach:RegisterForClicks("AnyUp", "AnyDown")
	teach:SetText("Open Beast Training")
	teach:SetScript("OnEnter", function(self)
		showTooltip(self, { "Beast Training", "Opens the window where you teach your pet. Not in combat." })
	end)
	teach:SetScript("OnLeave", function() GameTooltip:Hide() end)
	teach:Hide()

	local watcher = CreateFrame("Frame")
	pcall(watcher.RegisterEvent, watcher, "PLAYER_REGEN_ENABLED")
	watcher:SetScript("OnEvent", function()
		if teachWanted ~= nil then syncTeach() end
	end)
end

-------------------------------------------------------------------------------
-- Building and drawing
-------------------------------------------------------------------------------

-- Anchors the window by its top-left corner, so it grows and shrinks downward and the
-- header stays where you put it. The saved spot is kept the same way.
local function pinTop()
	local left, top = frame:GetLeft(), frame:GetTop()
	if not left or not top then return end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	ns.GetDB().dashboardPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = left, y = top }
end

local function scrollBar()
	local bar = scroll.ScrollBar or _G[(scroll:GetName() or "") .. "ScrollBar"]
	return type(bar) == "table" and bar or nil
end

local function draw()
	releaseAll()
	y = 0
	local advice
	if not ns.IsHunter() then
		drawHeader(nil)
		addNote("Tamer is for Hunters", "Log in on a Hunter to see what their pet can learn.")
	else
		advice = ns.Knowledge.Advice()
		drawHeader(advice.pet)
		if advice.noPet then
			addNote("Call your pet", "Tamer shows what your pet can learn while it's out.")
		elseif advice.noData then
			addNote(("Tamer doesn't know %s yet"):format(advice.pet.family or "this family"),
				("There's no ability list for %s's family."):format(advice.pet.name))
		elseif advice.needsBeastTraining then
			addNote("Open Beast Training once",
				("Press the button below with %s out. Tamer reads it to learn what you can teach."):format(advice.pet.name))
		else
			if #advice.ready > 0 then addReady(advice) end
			addSoon(advice)
			addFind(advice)
		end
	end
	setTeachText(advice)
	content:SetHeight(math.max(y, 1))
end

-- Draws the cards, then sizes the window to fit them. Only when they don't fit under the
-- tallest window does the scrollbar show, and the cards get narrower to make room for it.
function Dashboard.Refresh()
	if not frame or not frame:IsShown() then return end
	local room = (frame:GetTop() or MAX_HEIGHT + 120) - 120
	local view = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, room)) - TOP - BOTTOM
	content:SetWidth(WIDTH - 2 * PAD - 4)
	draw()
	local fits = y <= view
	if not fits then
		content:SetWidth(WIDTH - 2 * PAD - 4 - BAR)
		draw()
	end
	local bar = scrollBar()
	if bar then bar:SetShown(not fits) end
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", fits and -PAD - 2 or -PAD - BAR, BOTTOM)
	-- Never taller than the room below the window's top, keeping clear of the action bars.
	local tallest = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, room))
	frame:SetHeight(math.max(MIN_HEIGHT, math.min(tallest, TOP + y + BOTTOM)))
	if fits then scroll:SetVerticalScroll(0) end
end

function Dashboard.Build()
	if frame then return end
	frame = ns.NewWindow("TamerDashboard", "Tamer", ns.Icon, WIDTH, MIN_HEIGHT)
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	ns.PlaceFrame(frame, "dashboardPosition", "CENTER", UIParent, "CENTER", 0, 0)
	ns.MakeDraggable(frame, "dashboardPosition")
	frame:Hide()
	tinsert(UISpecialFrames, "TamerDashboard") -- Escape closes it.

	header = {}
	header.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	header.name:SetPoint("TOPLEFT", frame, "TOPLEFT", 66, -28)
	header.info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	header.info:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -2)

	header.badge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	header.badge:SetSize(64, 40)
	header.badge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 2, -28)
	ns.ApplyBackdrop(header.badge)
	header.badge.number = header.badge:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	header.badge.number:SetPoint("TOP", 0, -6)
	header.badge.label = header.badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	header.badge.label:SetPoint("TOP", header.badge.number, "BOTTOM", 0, -1)
	header.badge:EnableMouse(true)
	hookTooltip(header.badge)

	header.xp = CreateFrame("StatusBar", nil, frame)
	header.xp:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	header.xp:SetStatusBarColor(0.58, 0.0, 0.55)
	header.xp:SetPoint("TOPLEFT", frame, "TOPLEFT", 66, -74)
	header.xp:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 2, -74)
	header.xp:SetHeight(6)
	local xpBack = header.xp:CreateTexture(nil, "BACKGROUND")
	xpBack:SetAllPoints()
	xpBack:SetColorTexture(0, 0, 0, 0.6)
	header.xp:EnableMouse(true)
	hookTooltip(header.xp)

	local ok, made = pcall(CreateFrame, "ScrollFrame", "TamerDashboardScroll", frame, "UIPanelScrollFrameTemplate")
	scroll = ok and made or CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 2, -TOP)
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - BAR, BOTTOM)
	scroll:EnableMouseWheel(true)
	-- One wheel tick moves about one row. The scrollbar, when there is one, is moved
	-- instead of the frame, so the two stay in step.
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange() or 0
		local value = math.min(math.max((self:GetVerticalScroll() or 0) - delta * ROW_HEIGHT * 2, 0), range)
		local bar = scrollBar()
		if bar and bar.SetValue and bar:IsShown() then
			bar:SetValue(value)
		else
			self:SetVerticalScroll(value)
		end
	end)

	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - 2 * PAD - 4, 1)
	scroll:SetScrollChild(content)

	frame:HookScript("OnDragStop", pinTop)
	frame:SetScript("OnShow", function()
		ns.PlayUISound("IG_CHARACTER_INFO_OPEN")
		pinTop()
		syncTeach()
		Dashboard.Refresh()
	end)
	frame:SetScript("OnHide", function()
		ns.PlayUISound("IG_CHARACTER_INFO_CLOSE")
		GameTooltip:Hide()
		syncTeach()
	end)

	buildTeach()
end

function Dashboard.Toggle()
	if not frame then Dashboard.Build() end
	frame:SetShown(not frame:IsShown())
end

function Dashboard.IsShown()
	return frame ~= nil and frame:IsShown()
end
