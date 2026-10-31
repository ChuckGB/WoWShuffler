--[[ Known.lua -----------------------------------------------------------------
Which recipes your characters know, and at what skill, on THIS realm and faction.

Two sources, merged:

  1. Our own record. Whenever one of your characters opens a profession window,
     its recipes, its skill and the game's own reagent lists are saved.
  2. TradeSkillMaster, if installed. TSM keeps the same facts for every alt it
     has seen open a profession window, so the tailor's recipes show up while
     you are logged in on the enchanter, without visiting each alt.
     TSM has no public API for this, so we READ its saved data
     (TradeSkillMasterDB, "f@<faction> - <realm>@internalData@crafts" and each
     character's "playerProfessions"). Read only, never written, and every read
     is pcall-wrapped: if a TSM update changes the format, this source simply
     goes quiet and the rest of the addon is unaffected.

Reagent lists from either source come from the game itself, so they override
LibProfessionDB for those recipes (ApplyGameReagents). Our own record wins over
TSM's when both have the same item, being the more recent look.

Keyed by created item ID: the Classic trade skill API hands out item links, not
spell IDs.
--------------------------------------------------------------------------- ]]
local SO = ShuffleOptimizer
local Known = {}
SO.Known = Known

-- the merged picture, rebuilt by Known.Sync()
local view = { items = {}, profs = {}, regs = {}, tsmChars = 0, tsmCrafts = 0 }
Known.view = view

local function realm() return GetRealmName() or "?" end
local function charKey() return (UnitName("player") or "?") .. "-" .. realm() end

local function db()
    ShuffleOptimizerDB.known = ShuffleOptimizerDB.known or {}
    return ShuffleOptimizerDB.known
end

-- ------------------------------------------------------------------ TSM read
local function readTSM()
    local T = _G.TradeSkillMasterDB
    if type(T) ~= "table" then return nil end
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Alliance"
    local scope = faction .. " - " .. realm()
    local out = { items = {}, profs = {}, regs = {}, chars = 0, crafts = 0 }

    local crafts = T["f@" .. scope .. "@internalData@crafts"]
    if type(crafts) == "table" then
        for _, c in pairs(crafts) do
            local id = type(c) == "table" and type(c.itemString) == "string"
                and tonumber(c.itemString:match("^i:(%d+)$"))
            if id then
                out.crafts = out.crafts + 1
                for name in pairs(c.players or {}) do
                    out.items[id] = out.items[id] or {}
                    out.items[id][name] = true
                end
                local regs, complete = {}, type(c.mats) == "table"
                for key, n in pairs(c.mats or {}) do
                    local rid = type(key) == "string" and tonumber(key:match("^i:(%d+)$"))
                    if rid and type(n) == "number" then
                        regs[#regs + 1] = rid; regs[#regs + 1] = n
                    else
                        complete = false     -- an optional/other reagent form we don't model
                    end
                end
                if complete and #regs > 0 then
                    out.regs[id] = { regs = regs, made = tonumber(c.numResult) or 1, source = "TSM" }
                end
            end
        end
    end

    local suffix = " - " .. scope .. "@internalData@playerProfessions"
    for key, profs in pairs(T) do
        if type(key) == "string" and type(profs) == "table" and key:sub(-#suffix) == suffix then
            local name = key:match("^s@(.-) %- ")
            if name then
                out.chars = out.chars + 1
                for prof, t in pairs(profs) do
                    if type(t) == "table" and type(t.level) == "number" then
                        out.profs[name] = out.profs[name] or {}
                        out.profs[name][prof] = t.level
                    end
                end
            end
        end
    end
    return out
end

--- Rebuild the merged view from our record and TSM. Cheap; called at login,
-- when a profession window is read, and whenever the window opens.
function Known.Sync()
    wipe(view.items); wipe(view.profs); wipe(view.regs)
    view.tsmChars, view.tsmCrafts = 0, 0

    local okT, tsm = pcall(readTSM)
    if okT and tsm then
        view.tsmChars, view.tsmCrafts = tsm.chars, tsm.crafts
        for id, names in pairs(tsm.items) do
            view.items[id] = view.items[id] or {}
            for n in pairs(names) do view.items[id][n] = true end
        end
        for name, p in pairs(tsm.profs) do
            view.profs[name] = view.profs[name] or {}
            for prof, lvl in pairs(p) do view.profs[name][prof] = lvl end
        end
        for id, g in pairs(tsm.regs) do view.regs[id] = g end
    end
    Known.tsmError = (not okT) and tostring(tsm) or nil

    -- our own record, this realm only, overrides TSM where both know an item
    local suffix = "-" .. realm()
    for key, c in pairs(db()) do
        if key:sub(-#suffix) == suffix then
            local name = key:sub(1, #key - #suffix)
            for id in pairs(c.items or {}) do
                view.items[id] = view.items[id] or {}
                view.items[id][name] = true
            end
            view.profs[name] = view.profs[name] or {}
            for prof, lvl in pairs(c.profs or {}) do view.profs[name][prof] = lvl end
        end
    end
    for id, g in pairs(ShuffleOptimizerDB.gameReagents or {}) do
        view.regs[id] = { regs = g.regs, made = g.made, source = "profession window" }
    end

    Known.ApplyGameReagents()
end

-- ------------------------------------------------------------------ our own record
local function harvest()
    if not GetNumTradeSkills or not SO.Recipes then return end
    local profName, rank = GetTradeSkillLine()
    if not profName or profName == "UNKNOWN" then return end
    local n = GetNumTradeSkills()
    if not n or n == 0 then return end

    local me = db()[charKey()] or { profs = {}, items = {} }
    db()[charKey()] = me
    me.profs[profName] = rank
    local game = ShuffleOptimizerDB.gameReagents
    for i = 1, n do
        local _, kind = GetTradeSkillInfo(i)
        if kind and kind ~= "header" then
            local link = GetTradeSkillItemLink(i)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then
                me.items[id] = profName
                local regs, complete = {}, true
                for j = 1, (GetTradeSkillNumReagents(i) or 0) do
                    local _, _, count = GetTradeSkillReagentInfo(i, j)
                    local rlink = GetTradeSkillReagentItemLink(i, j)
                    local rid = rlink and tonumber(rlink:match("item:(%d+)"))
                    if rid and count then
                        regs[#regs + 1] = rid; regs[#regs + 1] = count
                    else
                        complete = false     -- reagent not cached yet; try next time
                    end
                end
                -- Some crafts (explosives) make a random count; cost per item
                -- uses the average of the range the game reports.
                local lo, hi = 1, 1
                if GetTradeSkillNumMade then lo, hi = GetTradeSkillNumMade(i) end
                lo = lo or 1; hi = hi or lo
                if complete and #regs > 0 then game[id] = { regs = regs, made = (lo + hi) / 2 } end
            end
        end
    end
    -- A filtered window (search box, "have materials") shows a subset; only
    -- add, never prune, so a filter cannot make recipes disappear.
    Known.Sync()
    if SO.UI and SO.UI.IsShown() then SO.UI.Refresh() end
end

-- ------------------------------------------------------------------ apply
local function sameReagents(a, b)
    if #a ~= #b then return false end
    local ma = {}
    for i = 1, #a, 2 do ma[a[i]] = a[i + 1] end
    for i = 1, #b, 2 do if ma[b[i]] ~= b[i + 1] then return false end end
    return true
end

--- Overwrite LibProfessionDB's reagents with what the game showed (via our own
-- record or TSM), and count the ones that disagreed.
function Known.ApplyGameReagents()
    if not SO.Recipes then return 0 end
    local byItem = {}
    for spell, r in pairs(SO.Recipes) do byItem[r[1]] = byItem[r[1]] or spell end
    local corrected = 0
    for itemID, g in pairs(view.regs) do
        local spell = byItem[itemID]
        local r = spell and SO.Recipes[spell]
        if r then
            r.shipped = r.shipped or { regs = r[4], made = r[5] }
            r.corrected = not sameReagents(r.shipped.regs, g.regs) or (r.shipped.made or 1) ~= (g.made or 1)
            if r.corrected then corrected = corrected + 1 end
            r.correctedBy = r.corrected and g.source or nil
            r[4], r[5] = g.regs, g.made or 1
        end
    end
    Known.corrected = corrected
    return corrected
end

-- ------------------------------------------------------------------ queries
--- Characters on this realm who know how to make this item.
function Known.WhoMakes(itemID)
    local out = {}
    for name in pairs(view.items[itemID] or {}) do out[#out + 1] = name end
    table.sort(out)
    return out
end

function Known.AnyoneMakes(itemID)
    return next(view.items[itemID] or {}) ~= nil
end

local CRAFTING = { Tailoring = true, Blacksmithing = true, Leatherworking = true,
                   Engineering = true, Mining = true, Enchanting = true }

--- "Engineering 300 (Dierdra), Tailoring 175 (Asterix)" -- crafting professions only.
function Known.Summary()
    local bits = {}
    for name, p in pairs(view.profs) do
        for prof, lvl in pairs(p) do
            if CRAFTING[prof] then bits[#bits + 1] = string.format("%s %d (%s)", prof, lvl or 0, name) end
        end
    end
    table.sort(bits)
    return table.concat(bits, ", ")
end

--- Where the alt data came from, for the tooltip.
function Known.SourceNote()
    if view.tsmChars > 0 then
        return string.format("Includes %d characters from TradeSkillMaster.", view.tsmChars)
    end
    if _G.TradeSkillMasterDB then return "TradeSkillMaster found, but it has no recipes for this realm yet." end
    return "Install TradeSkillMaster to include alts you haven't opened a profession window on here."
end

local f = CreateFrame("Frame")
f:RegisterEvent("TRADE_SKILL_SHOW")
f:RegisterEvent("TRADE_SKILL_UPDATE")
f:SetScript("OnEvent", function()
    if ShuffleOptimizerDB then harvest() end
end)
