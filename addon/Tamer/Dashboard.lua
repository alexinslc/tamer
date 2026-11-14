-- The one window: the summoned pet, what it knows, what it can train now, what comes
-- next, and what to go learn. It only draws what Advisor.Build returns.
local _, ns = ...

local Dashboard = {}
ns.Dashboard = Dashboard

local WIDTH, HEIGHT = 360, 480
local PAD = 10
local INDENT = 14

local frame, header, scroll, content
local rows, used = {}, 0
local expanded = {} -- "Ability#rank" -> true while its beasts are shown.

local COLORS = {
	heading = { 1, 0.82, 0 },
	item = { 1, 1, 1 },
	note = { 0.75, 0.75, 0.75 },
	alert = { 1, 0.82, 0 },
	beast = { 0.9, 0.9, 0.9 },
	far = { 0.6, 0.6, 0.6 },
	right = { 0.67, 0.83, 0.45 },
}

local function rankName(entry)
	return ("%s (Rank %d)"):format(entry.ability, entry.rank)
end

local function plural(n, one, many)
	return n == 1 and one or many
end

-------------------------------------------------------------------------------
-- Rows
-------------------------------------------------------------------------------

local function newRow()
	local row = CreateFrame("Button", nil, content)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.text:SetJustifyH("LEFT")
	if row.text.SetWordWrap then row.text:SetWordWrap(true) end
	row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.right:SetJustifyH("RIGHT")
	row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
	row:SetScript("OnClick", function(self)
		if self.onClick then self.onClick() end
	end)
	row:SetScript("OnEnter", function(self)
		if self.onClick then self.text:SetTextColor(1, 1, 0.6) end
	end)
	row:SetScript("OnLeave", function(self)
		if self.onClick then self.text:SetTextColor(unpack(self.color)) end
	end)
	return row
end

local y -- How far down the content the next row goes.

-- Adds one line of text. kind picks its font and color; right is a short value on the
-- right; onClick makes it clickable.
local function add(kind, text, right, onClick)
	used = used + 1
	local row = rows[used] or newRow()
	rows[used] = row

	local indent = kind == "beast" and INDENT or 0
	local width = content:GetWidth()
	if kind == "heading" and used > 1 then y = y + 8 end

	row.text:SetFontObject(kind == "heading" and "GameFontNormal"
		or (kind == "item" and "GameFontHighlight" or "GameFontHighlightSmall"))
	row.color = COLORS[kind] or COLORS.item
	row.text:SetTextColor(unpack(row.color))
	row.text:ClearAllPoints()
	row.text:SetPoint("TOPLEFT", row, "TOPLEFT", indent, 0)
	row.text:SetWidth(width - indent - (right and 90 or 0))
	row.text:SetText(text)
	row.right:SetText(right or "")
	row.right:SetTextColor(unpack(COLORS.right))
	row.onClick = onClick
	row:EnableMouse(onClick ~= nil)

	local height = math.max(row.text:GetStringHeight() or 12, 12)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
	row:SetSize(width, height)
	row:Show()
	y = y + height + 3
	return row
end

local function clear()
	for i = 1, used do rows[i]:Hide() end
	used, y = 0, 0
end

-------------------------------------------------------------------------------
-- Sections
-------------------------------------------------------------------------------

local function addKnown(advice)
	local pet = advice.pet
	add("heading", ("What %s knows"):format(pet.name))
	if #advice.known == 0 then
		add("note", "Nothing yet.")
		return
	end
	local parts = {}
	for i, entry in ipairs(advice.known) do
		parts[i] = ("%s %d"):format(entry.ability, entry.rank)
	end
	add("note", table.concat(parts, ", "))
end

local function addReady(advice)
	local pet = advice.pet
	add("heading", "Ready to train")
	if #advice.ready == 0 then
		add("note", "Nothing to train right now.")
	else
		for _, entry in ipairs(advice.ready) do
			add("item", rankName(entry), entry.cost and ("%d %s"):format(entry.cost, plural(entry.cost, "point", "points")) or nil)
		end
		add("note", ("You know %s and %s is ready for %s. Cast Beast Training to teach %s."):format(
			plural(#advice.ready, "this", "these"), pet.name, plural(#advice.ready, "it", "them"),
			plural(#advice.ready, "it", "them")))
	end

	if #advice.needsPoints > 0 then
		add("heading", "Needs training points")
		for _, entry in ipairs(advice.needsPoints) do
			add("item", rankName(entry), entry.cost and ("needs %d"):format(entry.cost) or nil)
		end
		add("note", ("%s has %d training %s left. More come as %s levels up and grows more loyal."):format(
			pet.name, pet.points or 0, plural(pet.points or 0, "point", "points"), pet.name))
	end
end

local function addNextUp(advice)
	local pet = advice.pet
	add("heading", "Next upgrade")
	if #advice.nextUp == 0 then
		add("note", "Nothing else you know is waiting on a level.")
		return
	end
	for _, entry in ipairs(advice.nextUp) do
		add("item", rankName(entry), ("at level %d"):format(entry.level))
	end
	local first = advice.nextUp[1]
	local levels = first.level - pet.level
	add("note", ("You already know %s. %s needs %d more %s for the first one."):format(
		plural(#advice.nextUp, "it", "these"), pet.name, levels, plural(levels, "level", "levels")))
end

local function addTeachers(entry)
	if entry.source == "trainer" then
		add("beast", "Learn it from a Pet Trainer in a capital city.")
		return
	end
	if #entry.beasts == 0 then
		add("beast", "No beast for this rank in Tamer's list yet.")
		return
	end
	for _, beast in ipairs(entry.beasts) do
		local levels = beast.low == beast.high and tostring(beast.low) or ("%d-%d"):format(beast.low, beast.high)
		local text = ("%s, level %s, %s"):format(beast.name, levels, beast.zone)
		if beast.tooHigh then
			add("far", text .. " (too high for you to tame yet)")
		else
			add("beast", text)
		end
	end
	add("beast", "Tame one and fight with it until you learn the rank.")
end

local function addGoLearn(advice)
	add("heading", "Go learn it")
	if #advice.goLearn == 0 then
		add("note", "You know every rank Tamer has for this family.")
		return
	end
	add("note", "You don't know these yet. Click one to see where to learn it.")
	for _, entry in ipairs(advice.goLearn) do
		local key = entry.ability .. "#" .. entry.rank
		local open = expanded[key]
		add("item", (open and "- " or "+ ") .. rankName(entry), entry.level and ("pet level %d"):format(entry.level) or nil, function()
			expanded[key] = not expanded[key] or nil
			Dashboard.Refresh()
		end)
		if open then addTeachers(entry) end
	end
end

-------------------------------------------------------------------------------
-- Header
-------------------------------------------------------------------------------

local function drawHeader(pet)
	if not pet then
		header.name:SetText("No pet")
		header.info:SetText("")
		header.points:SetText("")
		header.xp:Hide()
		return
	end
	header.name:SetText(pet.name)
	header.info:SetText(("%s, level %d"):format(pet.family or "Unknown family", pet.level))
	header.points:SetText(pet.points and ("%d training %s"):format(pet.points, plural(pet.points, "point", "points")) or "")
	if pet.xp and pet.xpMax and pet.xpMax > 0 then
		header.xp:SetMinMaxValues(0, pet.xpMax)
		header.xp:SetValue(pet.xp)
		header.xp.text:SetText(("%d / %d"):format(pet.xp, pet.xpMax))
		header.xp:Show()
	else
		header.xp:Hide()
	end
end

-------------------------------------------------------------------------------
-- Building and drawing
-------------------------------------------------------------------------------

function Dashboard.Refresh()
	if not frame or not frame:IsShown() then return end
	clear()
	if not ns.IsHunter() then
		drawHeader(nil)
		add("note", "Tamer is for Hunters. Log in on one to see what their pet can learn.")
	else
		local advice = ns.Knowledge.Advice()
		drawHeader(advice.pet)
		if advice.noPet then
			add("note", "Call your pet to see what it can learn.")
		elseif advice.noData then
			add("note", ("Tamer doesn't have any abilities for %s's family (%s) yet."):format(
				advice.pet.name, advice.pet.family or "unknown"))
		else
			if advice.needsBeastTraining then
				add("alert", ("Cast Beast Training once with %s out, so Tamer can see which ranks you know."):format(advice.pet.name))
			end
			addKnown(advice)
			if not advice.needsBeastTraining then
				addReady(advice)
				addNextUp(advice)
				addGoLearn(advice)
			end
		end
	end
	content:SetHeight(math.max(y, 1))
end

local function build()
	frame = ns.NewWindow("TamerDashboard", "Tamer", ns.Icon, WIDTH, HEIGHT)
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	ns.PlaceFrame(frame, "dashboardPosition", "CENTER", UIParent, "CENTER", 0, 0)
	ns.MakeDraggable(frame, "dashboardPosition")
	frame:Hide()
	tinsert(UISpecialFrames, "TamerDashboard") -- Escape closes it.

	header = {}
	header.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	header.name:SetPoint("TOPLEFT", frame, "TOPLEFT", 66, -30)
	header.info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	header.info:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -2)
	header.points = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	header.points:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 4, -48)
	header.points:SetTextColor(unpack(COLORS.right))

	header.xp = CreateFrame("StatusBar", nil, frame)
	header.xp:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	header.xp:SetStatusBarColor(0.58, 0.0, 0.55)
	header.xp:SetPoint("TOPLEFT", frame, "TOPLEFT", 66, -66)
	header.xp:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 4, -66)
	header.xp:SetHeight(12)
	local xpBack = header.xp:CreateTexture(nil, "BACKGROUND")
	xpBack:SetAllPoints()
	xpBack:SetColorTexture(0, 0, 0, 0.5)
	header.xp.text = header.xp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	header.xp.text:SetPoint("CENTER")

	local inset = ns.NewInset(frame)
	inset:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -88)
	inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)

	local ok, made = pcall(CreateFrame, "ScrollFrame", "TamerDashboardScroll", inset, "UIPanelScrollFrameTemplate")
	scroll = ok and made or CreateFrame("ScrollFrame", nil, inset)
	scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -28, 8)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange() or 0
		local value = math.min(math.max((self:GetVerticalScroll() or 0) - delta * 30, 0), range)
		self:SetVerticalScroll(value)
	end)

	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - 2 * PAD - 36, 1)
	scroll:SetScrollChild(content)

	frame:SetScript("OnShow", function()
		ns.PlayUISound("IG_CHARACTER_INFO_OPEN")
		Dashboard.Refresh()
	end)
	frame:SetScript("OnHide", function()
		ns.PlayUISound("IG_CHARACTER_INFO_CLOSE")
	end)
end

function Dashboard.Toggle()
	if not frame then build() end
	frame:SetShown(not frame:IsShown())
end

function Dashboard.IsShown()
	return frame ~= nil and frame:IsShown()
end
