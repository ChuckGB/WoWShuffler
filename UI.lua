--[[ UI.lua --------------------------------------------------------------------
One window: every craftable item ranked by what it nets you to make it and
disenchant it, at today's prices. Hover a row for the full working; nothing is
hidden behind a single number.

Layout rules carried over from RepOptimizer: numbers right-aligned in fixed
columns, blocks anchored to each other rather than to fixed offsets that text
can grow into, and the window reports numbers without editorialising.
--------------------------------------------------------------------------- ]]
local SO = ShuffleOptimizer
local Optimizer = SO.Optimizer

local WIDTH, HEIGHT = 800, 520
local PAD = 14
local ROW_H = 16
local NUM_ROWS = 20

local UI = {}
SO.UI = UI

local QUALITY_COLOR = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
local PROF_SHORT = { [164] = "Blacksmith", [165] = "Leather", [186] = "Mining", [197] = "Tailoring", [202] = "Engineer" }
local PROF_ORDER = SO.PROFESSIONS
local EXIT_LABEL = { de = "DE", ah = "AH", vendor = "Vendor" }

-- --------------------------------------------------------------- frame
local f = CreateFrame("Frame", "ShuffleOptimizerFrame", UIParent, "BasicFrameTemplateWithInset")
f:SetSize(WIDTH, HEIGHT)
f:SetPoint("CENTER")
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetFrameStrata("HIGH")
f:Hide()
tinsert(UISpecialFrames, "ShuffleOptimizerFrame")   -- Escape closes it

f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
f.title:SetPoint("TOP", f.TitleBg, "TOP", 0, -4)
f.title:SetText("Shuffle Optimizer -- craft, disenchant, sell")
SO.Skin.Register("frames", f)
if f.CloseButton then SO.Skin.Register("closes", f.CloseButton) end

local function settings() return ShuffleOptimizerDB end

-- --------------------------------------------------------------- dropdowns
-- Our own small dropdown: a button that opens a list. Blizzard's UIDropDownMenu
-- was dropped after it caused two problems here -- it runs its builder at file
-- load (before saved variables exist), and it did not survive ElvUI skinning.
-- A plain button + a plain list skins cleanly under ElvUI and EllesmereUI.
local menu = CreateFrame("Frame", "ShuffleOptimizerMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
menu:SetFrameStrata("FULLSCREEN_DIALOG")
menu:SetClampedToScreen(true)
menu:EnableMouse(true)
menu:Hide()
if menu.SetBackdrop then
    menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                       edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                       tile = true, tileSize = 16, edgeSize = 14,
                       insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    menu:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
end
tinsert(UISpecialFrames, "ShuffleOptimizerMenu")          -- Escape closes it
SO.Skin.Register("panels", menu)
menu.items = {}

local MENU_ROW = 18
local function menuItem(i)
    local b = menu.items[i]
    if b then return b end
    b = CreateFrame("Button", nil, menu)
    b:SetHeight(MENU_ROW)
    b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * MENU_ROW)
    b:SetPoint("RIGHT", -6, 0)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self)
        menu:Hide()
        if self.onClick then self.onClick() end
    end)
    menu.items[i] = b
    return b
end

-- Close when the mouse has been away from both the menu and its button a moment.
menu:SetScript("OnUpdate", function(self, elapsed)
    if MouseIsOver(self) or (self.owner and MouseIsOver(self.owner)) then
        self.away = 0
    else
        self.away = (self.away or 0) + elapsed
        if self.away > 1.5 then self:Hide() end
    end
end)

--- items: array of { text, selected, onClick }
local function openMenu(owner, items)
    if menu:IsShown() and menu.owner == owner then menu:Hide(); return end
    menu.owner, menu.away = owner, 0
    for i, it in ipairs(items) do
        local b = menuItem(i)
        b.text:SetText(it.selected and ("|cff00ff00" .. it.text .. "|r") or it.text)
        b.onClick = it.onClick
        b:Show()
    end
    for i = #items + 1, #menu.items do menu.items[i]:Hide() end
    menu:SetSize(math.max(owner:GetWidth(), 150), #items * MENU_ROW + 12)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    menu:Show()
end

local function dropdown(name, x, width, buildItems)
    local b = CreateFrame("Button", name, f, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", x, -32)
    local fs = b:GetFontString()
    if fs then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", 8, 0)
        fs:SetPoint("RIGHT", -20, 0)
        fs:SetJustifyH("LEFT")
    end
    b.arrow = b:CreateTexture(nil, "OVERLAY")
    b.arrow:SetSize(14, 14)
    b.arrow:SetPoint("RIGHT", -5, 0)
    b.arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    b:SetScript("OnClick", function(self) openMenu(self, buildItems()) end)
    SO.Skin.Register("buttons", b)
    return b
end

-- Header row: fixed offsets from the window, never chained to each other.
local DD1_X, DD1_W = PAD, 150
local DD2_X, DD2_W = DD1_X + DD1_W + 10, 170
local CHECKS_X = DD2_X + DD2_W + 18

local profDD = dropdown("ShuffleOptimizerProfDD", DD1_X, DD1_W, function()
    local s, items = settings(), {}
    items[1] = { text = "All professions", selected = s.prof == 0,
                 onClick = function() s.prof = 0; UI.Refresh() end }
    for _, p in ipairs(PROF_ORDER) do
        items[#items + 1] = { text = SO.ProfessionName[p], selected = s.prof == p,
                              onClick = function() s.prof = p; UI.Refresh() end }
    end
    return items
end)

-- Which price statistic to use. WHICH sources (Auctionator, TSM, ...) and their
-- order are LibItemDB's settings, shared by every addon that uses it: /itemdb,
-- or right-click the minimap button.
local srcDD = dropdown("ShuffleOptimizerSourceDD", DD2_X, DD2_W, function()
    local s, items = settings(), {}
    for _, st in ipairs(SO.Prices.STATISTICS) do
        items[#items + 1] = { text = st.label, selected = s.statistic == st.key,
                              onClick = function() s.statistic = st.key; UI.Refresh() end }
    end
    return items
end)

f:HookScript("OnHide", function() menu:Hide() end)

local function checkbox(label, anchor, x, tooltip)
    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("LEFT", anchor, "RIGHT", x or 4, 0)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 0, 1)
    cb.label:SetText(label)
    SO.Skin.Register("checks", cb)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return cb
end

local deOnly = checkbox("Disenchantable only", f, 0)
deOnly:ClearAllPoints()
deOnly:SetPoint("TOPLEFT", CHECKS_X, -32)
local knownOnly = checkbox("My recipes only", deOnly.label, 10)
knownOnly:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Only recipes your characters on this realm know.", 1, 1, 1, true)
    GameTooltip:AddLine("Open each crafter's profession window once to record them.", 0.7, 0.7, 0.7, true)
    local known = SO.Known.Summary()
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(known ~= "" and ("Recorded: " .. known) or "Nothing recorded yet.", 0.4, 1, 0.4, true)
    GameTooltip:AddLine(SO.Known.SourceNote(), 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
knownOnly:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- "make intermediates with" row
local makeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
makeLabel:SetPoint("TOPLEFT", PAD, -62)
makeLabel:SetText("Make intermediates yourself:")
local makeBoxes = {}
do
    local prev = makeLabel
    for _, p in ipairs(PROF_ORDER) do
        local cb = checkbox(PROF_SHORT[p], prev, (prev == makeLabel) and 6 or 8,
            "When on, a reagent such as a bolt, bar or part is costed as the cheaper of buying it " ..
            "or crafting it from its own reagents. Turn off professions you cannot use.")
        cb.prof = p
        makeBoxes[p] = cb
        prev = cb.label
    end
end

-- status
-- Max required skill: only recipes you can actually make at your level.
-- Empty means no limit. Recipes LibProfessionDB has no required skill for are
-- kept (they cannot be ruled out) and show "-" in the Profession column.
local skillBox = CreateFrame("EditBox", "ShuffleOptimizerMaxSkill", f, "InputBoxTemplate")
skillBox:SetSize(40, 20)
skillBox:SetPoint("TOPRIGHT", -PAD - 4, -57)
skillBox:SetAutoFocus(false)
skillBox:SetNumeric(true)
skillBox:SetMaxLetters(3)
skillBox:SetJustifyH("CENTER")
SO.Skin.Register("editboxes", skillBox)
local skillLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
skillLabel:SetPoint("RIGHT", skillBox, "LEFT", -8, 0)
skillLabel:SetText("Max skill:")
local function commitSkill(self)
    local n = tonumber(self:GetText() or "")
    settings().maxSkill = (n and n > 0) and n or nil
    self:ClearFocus()
    UI.Refresh()
end
skillBox:SetScript("OnEnterPressed", commitSkill)
skillBox:SetScript("OnEditFocusLost", function(self)
    local n = tonumber(self:GetText() or "")
    if ((n and n > 0) and n or nil) ~= settings().maxSkill then commitSkill(self) end
end)
skillBox:SetScript("OnEscapePressed", function(self)
    self:SetText(settings().maxSkill and tostring(settings().maxSkill) or "")
    self:ClearFocus()
end)
skillBox:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Only show recipes needing this skill or less.", 1, 1, 1, true)
    GameTooltip:AddLine("Leave empty for no limit. Press Enter to apply.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
skillBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

local status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
status:SetPoint("TOPLEFT", makeLabel, "BOTTOMLEFT", 0, -8)
status:SetWidth(WIDTH - PAD * 2)
status:SetJustifyH("LEFT")
status:SetWordWrap(false)          -- one line, always; it must never push into the headers

-- --------------------------------------------------------------- columns
-- { key, header, width, justify, sortKey }
local COLS = {
    { "item",   "Item",          190, "LEFT" },
    { "prof",   "Profession",     88, "LEFT", "skill" },
    { "ilvl",   "ilvl",           30, "RIGHT", "ilvl" },
    { "cost",   "Mat cost",       78, "RIGHT", "cost" },
    { "de",     "DE value",       78, "RIGHT", "de" },
    { "pde",    "DE profit",      84, "RIGHT", "profitDE" },
    { "best",   "Best exit",     104, "RIGHT", "profit" },
    { "age",    "Age",            36, "RIGHT" },
}

local listTop = CreateFrame("Frame", nil, f)
listTop:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -22)
listTop:SetSize(WIDTH - PAD * 2 - 24, ROW_H * NUM_ROWS)

local sortKey, ascending = "profitDE", false
-- First click on a column sorts its natural way (money high-to-low, skill
-- low-to-high); clicking the same column again flips it.
local ASCENDING_FIRST = { skill = true }
local headers = {}
do
    local x = 4
    for _, c in ipairs(COLS) do
        local h = CreateFrame("Button", nil, f)
        h:SetSize(c[3], 16)
        h:SetPoint("BOTTOMLEFT", listTop, "TOPLEFT", x, 2)
        h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h.text:SetAllPoints()
        h.text:SetJustifyH(c[4])
        h.text:SetText(c[2])
        h.sortKey = c[5]
        h.label = c[2]
        if c[5] then
            h:SetScript("OnClick", function()
                if sortKey == c[5] then
                    ascending = not ascending
                else
                    sortKey, ascending = c[5], ASCENDING_FIRST[c[5]] or false
                end
                UI.Refresh()
            end)
            h:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        end
        headers[#headers + 1] = h
        c.x = x
        x = x + c[3] + 6
    end
end

assert(COLS[#COLS].x + COLS[#COLS][3] <= listTop:GetWidth(), "columns wider than the list")

local scroll = CreateFrame("ScrollFrame", "ShuffleOptimizerScroll", f, "FauxScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", listTop, "TOPLEFT", 0, 0)
scroll:SetPoint("BOTTOMRIGHT", listTop, "BOTTOMRIGHT", 0, 0)
SO.Skin.Register("scrollbars", scroll.ScrollBar or _G["ShuffleOptimizerScrollScrollBar"])

local rows = {}
local visible = {}   -- filtered, sorted rows

local function showTooltip(btn)
    local row = btn.row
    if not row then return end
    local Items, Known = SO.Items, SO.Known
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    local q = QUALITY_COLOR[row.quality or 1] or "ffffff"
    GameTooltip:AddLine("|cff" .. q .. Items.Name(row.item) .. "|r")
    GameTooltip:AddLine(string.format("%s %s   ilvl %d%s", SO.ProfessionName[row.prof] or "?",
        row.skill and tostring(row.skill) or "-", row.ilvl or 0,
        row.made > 1 and ("   makes " .. row.made) or ""), 0.7, 0.7, 0.7)
    local who = Known.WhoMakes(row.item)
    local r = SO.Recipes[row.spell]
    if r and r.corrected then
        GameTooltip:AddLine("Reagents as the game lists them (" .. (r.correctedBy or "profession window") ..
                            "); they differ from LibProfessionDB.",
                            1, 0.6, 0.2, true)
    end
    if #who > 0 then
        GameTooltip:AddLine("Known by: " .. table.concat(who, ", "), 0.4, 1, 0.4)
    else
        GameTooltip:AddLine("No character of yours has recorded this recipe.", 0.6, 0.6, 0.6)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(row.made > 1 and "Reagents (one craft):" or "Reagents:", 1, 0.82, 0)
    for _, l in ipairs(row.lines or {}) do
        local right
        if l.unit then
            local src = l.source == "craft" and "made" or l.source == "ah" and "AH" or l.source
            right = SO.Money(l.unit * l.count) .. "  |cff909090" .. src .. "|r"
        else
            right = "|cffff6060no price -- scan it|r"
        end
        GameTooltip:AddDoubleLine(string.format("%d x %s", l.count, Items.Name(l.item)), right, 1, 1, 1, 1, 1, 1)
    end

    if row.deable then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Disenchant, expected per item:", 1, 0.82, 0)
        for _, b in ipairs(row.deBreakdown or {}) do
            local left = string.format("%.0f%%  %d-%d %s", b.rate * 100, b.min, b.max, Items.Name(b.item))
            local right = b.unit and (string.format("%.2f x ", b.expected) .. SO.Money(b.unit))
                or "|cffff6060no price -- scan it|r"
            GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
        end
        GameTooltip:AddLine("Results are random: the expected value only shows up over many disenchants.",
                            0.6, 0.6, 0.6, true)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Mat cost per item", SO.Money(row.cost), 1, 1, 1)
    if row.deable then GameTooltip:AddDoubleLine("Disenchant, after 5% AH cut", SO.Money(row.de), 1, 1, 1) end
    if row.bop then
        GameTooltip:AddDoubleLine("Sell the item on the AH", "|cff909090soulbound|r", 1, 1, 1)
    else
        GameTooltip:AddDoubleLine("Sell the item, after 5% AH cut", SO.Money(row.sell), 1, 1, 1)
        local info = Items.Info(row.item)
        if info and not info.bindKnown then
            GameTooltip:AddLine("(Not yet confirmed tradeable -- the client hasn't loaded this item.)",
                                0.6, 0.6, 0.6, true)
        end
    end
    GameTooltip:AddDoubleLine("Vendor the item", SO.Money(row.vendor), 1, 1, 1)
    GameTooltip:AddLine("Deposits and auctions that expire unsold are not included.", 0.6, 0.6, 0.6, true)
    GameTooltip:AddLine("Shift-click to link.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

for i = 1, NUM_ROWS do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(listTop:GetWidth(), ROW_H)
    b:SetPoint("TOPLEFT", listTop, "TOPLEFT", 0, -(i - 1) * ROW_H)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.cells = {}
    for ci, c in ipairs(COLS) do
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", b, "LEFT", c.x, 0)
        fs:SetWidth(c[3])
        fs:SetJustifyH(c[4])
        fs:SetWordWrap(false)
        b.cells[c[1]] = fs
    end
    b:SetScript("OnEnter", showTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if self.row and IsModifiedClick("CHATLINK") then
            local link = SO.Items.Link(self.row.item)
            if link then ChatEdit_InsertLink(link) end
        end
    end)
    b:Hide()
    rows[i] = b
end

local function ageText(age)
    if not age then return "|cff707070?|r" end
    if age >= 22 then return "|cffff6060old|r" end
    if age == 0 then return "|cff909090today|r" end
    if age > 7 then return "|cffff9933" .. age .. "d|r" end
    return "|cff909090" .. age .. "d|r"
end

local function draw()
    local offset = FauxScrollFrame_GetOffset(scroll)
    for i = 1, NUM_ROWS do
        local b, row = rows[i], visible[i + offset]
        b.row = row
        if row then
            local info = SO.Items.Info(row.item)
            local name = info and info.name or ("item:" .. row.item)
            local q = QUALITY_COLOR[row.quality or 1] or "ffffff"
            b.cells.item:SetText("|cff" .. q .. name .. "|r")
            b.cells.prof:SetText(string.format("%s |cff909090%s|r", PROF_SHORT[row.prof] or "?",
                row.skill and tostring(row.skill) or "-"))
            b.cells.ilvl:SetText(row.ilvl or "")
            b.cells.cost:SetText(SO.Money(row.cost))
            b.cells.de:SetText(row.deable and SO.Money(row.de) or "|cff707070n/a|r")
            b.cells.pde:SetText(row.profitDE and SO.Money(row.profitDE, true) or "|cff707070--|r")
            if row.profit then
                b.cells.best:SetText("|cff909090" .. EXIT_LABEL[row.exit] .. "|r " .. SO.Money(row.profit, true))
            else
                b.cells.best:SetText("|cff707070--|r")
            end
            b.cells.age:SetText(ageText(row.age))
            b:Show()
        else
            b:Hide()
        end
    end
    FauxScrollFrame_Update(scroll, #visible, NUM_ROWS, ROW_H)
end

scroll:SetScript("OnVerticalScroll", function(self, delta)
    FauxScrollFrame_OnVerticalScroll(self, delta, ROW_H, draw)
end)

-- --------------------------------------------------------------- compute
local function buildEnv()
    local s = settings()
    return {
        recipes = SO.Recipes,
        bands = SO.DisenchantBands,
        essencePairs = SO.EssencePairs,
        itemInfo = SO.Items.Info,
        ahPrice = SO.Prices.AH,
        vendorBuy = SO.Prices.Vendor,
        canMake = function(prof) return s.canMake[prof] ~= false end,
        ahCut = 0.05,
    }
end

function UI.Refresh()
    if not f:IsShown() then return end
    local s = settings()
    profDD:SetText(s.prof == 0 and "All professions" or SO.ProfessionName[s.prof])
    srcDD:SetText("Price: " .. SO.Prices.StatisticLabel())
    deOnly:SetChecked(s.deOnly)
    if not skillBox:HasFocus() then skillBox:SetText(s.maxSkill and tostring(s.maxSkill) or "") end
    knownOnly:SetChecked(s.knownOnly)
    for p, cb in pairs(makeBoxes) do cb:SetChecked(s.canMake[p] ~= false) end
    for _, h in ipairs(headers) do
        local active = h.sortKey and h.sortKey == sortKey
        h.text:SetTextColor(1, active and 1 or 0.82, active and 1 or 0)
        h.text:SetText(h.label .. (active and (ascending and " ^" or " v") or ""))
    end

    local offerID, offerName = SO.Prices.OfferableSource()
    if offerID then
        UI.enableBtn:SetText("Use " .. offerName .. " prices")
        UI.enableBtn.sourceID = offerID
        UI.enableBtn:Show()
    else
        UI.enableBtn:Hide()
    end
    if not SO.Prices.HasAnySource() then
        status:SetText(offerID
            and ("|cffff6060LibItemDB has no price source switched on. " ..
                 "Press the button below to use " .. offerName .. ".|r")
            or "|cffff6060No price source: install Auctionator or TSM, or run a LibItemDB scan (/itemdb).|r")
        wipe(visible); draw(); return
    end

    local engine = Optimizer.New(buildEnv())
    local all, pending = engine:EvaluateAll(function(_, r)
        return s.prof == 0 or r[2] == s.prof
    end)
    wipe(visible)
    local unpriced = 0
    for _, row in ipairs(all) do
        local keep = true
        if s.deOnly and not row.deable then keep = false end
        if keep and s.knownOnly and not SO.Known.AnyoneMakes(row.item) then keep = false end
        if keep and s.maxSkill and row.skill and row.skill > s.maxSkill then keep = false end
        if keep then
            visible[#visible + 1] = row
            if not row.complete then unpriced = unpriced + 1 end
        end
    end
    Optimizer.SortRows(visible, sortKey, ascending)

    -- Short and on one line. The longer facts (which characters are recorded)
    -- live in the "My recipes only" tooltip.
    local bits = { string.format("%d recipes", #visible) }
    if unpriced > 0 then bits[#bits + 1] = string.format("%d unpriced (at the bottom)", unpriced) end
    if pending > 0 then bits[#bits + 1] = string.format("%d not in LibItemDB", pending) end
    if (SO.Known.corrected or 0) > 0 then
        bits[#bits + 1] = string.format("|cffff9933%d corrected from your profession window|r", SO.Known.corrected)
    end
    if s.knownOnly and SO.Known.Summary() == "" then
        bits[#bits + 1] = "|cffffd100open a profession window to record your recipes|r"
    end
    bits[#bits + 1] = "prices: " .. SO.Prices.SourceSummary()
    status:SetText(table.concat(bits, "   |cff585858|||r   "))
    draw()
end

-- --------------------------------------------------------------- wiring
deOnly:SetScript("OnClick", function(self) settings().deOnly = self:GetChecked() and true or false; UI.Refresh() end)
knownOnly:SetScript("OnClick", function(self) settings().knownOnly = self:GetChecked() and true or false; UI.Refresh() end)
for p, cb in pairs(makeBoxes) do
    cb:SetScript("OnClick", function(self) settings().canMake[p] = self:GetChecked() and true or false; UI.Refresh() end)
end

local refreshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
refreshBtn:SetSize(110, 22)
refreshBtn:SetPoint("BOTTOMRIGHT", -PAD, 12)
refreshBtn:SetText("Recalculate")
refreshBtn:SetScript("OnClick", function() UI.Refresh() end)
SO.Skin.Register("buttons", refreshBtn)

local sourcesBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
sourcesBtn:SetSize(110, 22)
sourcesBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -6, 0)
sourcesBtn:SetText("Price sources")
sourcesBtn:SetScript("OnClick", function() if SO.IDB.OpenPriceWindow then SO.IDB:OpenPriceWindow() end end)
SO.Skin.Register("buttons", sourcesBtn)

-- Shown only when a price addon is installed but switched off in LibItemDB.
-- Turning it on is the player's click, never something we do quietly.
UI.enableBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
UI.enableBtn:SetSize(170, 22)
UI.enableBtn:SetPoint("RIGHT", sourcesBtn, "LEFT", -6, 0)
UI.enableBtn:Hide()
UI.enableBtn:SetScript("OnClick", function(self)
    if self.sourceID then SO.Prices.EnableSource(self.sourceID) end
    UI.Refresh()
end)
SO.Skin.Register("buttons", UI.enableBtn)

local foot = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
foot:SetPoint("BOTTOMLEFT", PAD, 18)
foot:SetPoint("RIGHT", UI.enableBtn, "LEFT", -10, 0)
foot:SetJustifyH("LEFT")
foot:SetWordWrap(false)
foot:SetText("Prices are only as fresh as your last scan. Hover a row for the working.")

f:SetScript("OnShow", function() SO.Known.Sync(); UI.Refresh() end)

function UI.IsShown() return f:IsShown() end
function UI.Toggle() if f:IsShown() then f:Hide() else f:Show() end end
