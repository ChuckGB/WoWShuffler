--[[ Optimizer.lua -------------------------------------------------------------
The margin engine. Touches no WoW API: every game fact arrives through `env`,
so this file runs under plain Lua 5.1 in tests.

env = {
  recipes      = SO.Recipes            [spell] = { item, prof, skill, {id,n,...}, made }
  bands        = SO.DisenchantBands
  essencePairs = SO.EssencePairs       [lesser] = greater
  itemInfo(id)  -> { quality=, ilvl=, class="ARMOR"|"WEAPON"|"OTHER", bop=, vendorSell= }
                   or nil while the client has not loaded the item yet
  ahPrice(id)   -> copper, ageDays     (nil if never seen)
  vendorBuy(id) -> copper              (nil if no vendor sells it)
  canMake(prof) -> bool                (may we craft intermediates of this profession?)
  ahCut         = 0.05
}

All money is copper. Every price is PER ITEM.
--------------------------------------------------------------------------- ]]

local Optimizer = {}
local SO = _G.ShuffleOptimizer
if SO then SO.Optimizer = Optimizer end

-- Crafts on a cooldown cannot be repeated on demand, so they are never used as
-- a "make it yourself" source for an intermediate.
Optimizer.COOLDOWN_SPELLS = {
    [18560] = true,   -- Mooncloth
}

local MAX_DEPTH = 3   -- ore -> bar -> part -> item is as deep as Classic goes

local Engine = {}
Engine.__index = Engine

function Optimizer.New(env)
    local self = setmetatable({ env = env, cut = env.ahCut or 0.05 }, Engine)
    -- index: which spells produce a given item, for buy-vs-make on reagents
    self.producers = {}
    for spell, r in pairs(env.recipes) do
        local list = self.producers[r[1]]
        if not list then list = {}; self.producers[r[1]] = list end
        list[#list + 1] = spell
    end
    self:Reset()
    return self
end

--- Forget memoised costs. Call whenever prices change.
function Engine:Reset()
    self.costMemo = {}
end

-- ---------------------------------------------------------------------------
-- Selling side: what one unit of an enchanting material is worth to us.
-- ---------------------------------------------------------------------------

local greaterOf, lesserOf = {}, {}

local function buildPairs(pairsTbl)
    for l, g in pairs(pairsTbl or {}) do greaterOf[l] = g; lesserOf[g] = l end
end

--- Sale value of one unit of a material, before the AH cut. Lesser and greater
-- essences convert 3:1 either way, so take whichever form sells better.
-- Returns value, ageDays (nil value if neither form has a price).
function Engine:MatValue(id)
    if not self.pairsBuilt then buildPairs(self.env.essencePairs); self.pairsBuilt = true end
    local p, age = self.env.ahPrice(id)
    local best, bestAge = p, age
    local g, l = greaterOf[id], lesserOf[id]
    if g then
        local pg, ag = self.env.ahPrice(g)
        if pg and (not best or pg / 3 > best) then best, bestAge = pg / 3, ag end
    elseif l then
        local pl, al = self.env.ahPrice(l)
        if pl and (not best or pl * 3 > best) then best, bestAge = pl * 3, al end
    end
    return best, bestAge
end

--- The band an item disenchants under, or nil if it does not disenchant.
function Engine:BandFor(info)
    if not info or (info.class ~= "ARMOR" and info.class ~= "WEAPON") then return nil end
    if not info.quality or info.quality < 2 or info.quality > 4 then return nil end
    for _, b in ipairs(self.env.bands) do
        if b.class == info.class and b.q == info.quality and info.ilvl >= b.lo and info.ilvl <= b.hi then
            return b
        end
    end
    return nil
end

--- Expected AH proceeds from disenchanting one item, after the AH cut.
-- Returns ev (nil if any possible material has no price), breakdown, ageDays.
function Engine:DisenchantEV(info)
    local band = self:BandFor(info)
    if not band then return nil, nil, nil, "not disenchantable" end
    local ev, worstAge, breakdown, missing = 0, 0, {}, nil
    for _, mat in ipairs(band) do
        local expected = mat.rate * (mat.min + mat.max) / 2
        local unit, age = self:MatValue(mat.item)
        breakdown[#breakdown + 1] = { item = mat.item, expected = expected, unit = unit, rate = mat.rate,
                                      min = mat.min, max = mat.max }
        if unit then
            ev = ev + expected * unit * (1 - self.cut)
            if age and age > worstAge then worstAge = age end
        else
            missing = missing or {}
            missing[#missing + 1] = mat.item
        end
    end
    if missing then return nil, breakdown, worstAge, "no price for a disenchant material", missing end
    return ev, breakdown, worstAge
end

-- ---------------------------------------------------------------------------
-- Buying side: cheapest way to obtain one unit of a reagent.
-- ---------------------------------------------------------------------------

--- Cheapest per-unit cost of an item: vendor, auction house, or crafting it
-- from its own reagents (recursively, for professions we may craft).
-- Returns cost, source ("vendor"|"ah"|"craft"), ageDays, detail.
-- cost is nil when no source has a price.
function Engine:UnitCost(id, depth, visiting)
    depth = depth or 0
    local memo = self.costMemo[id]
    if memo and depth == 0 then return memo.cost, memo.source, memo.age, memo.detail end

    local best, source, age, detail = nil, nil, nil, nil
    local v = self.env.vendorBuy(id)
    if v then best, source, age = v, "vendor", 0 end
    local p, pa = self.env.ahPrice(id)
    if p and (not best or p < best) then best, source, age = p, "ah", pa end

    if depth < MAX_DEPTH and self.producers[id] then
        visiting = visiting or {}
        if not visiting[id] then
            visiting[id] = true
            for _, spell in ipairs(self.producers[id]) do
                local r = self.env.recipes[spell]
                if not Optimizer.COOLDOWN_SPELLS[spell] and self.env.canMake(r[2]) then
                    local total, lines, worst = self:ReagentCost(spell, depth + 1, visiting)
                    if total then
                        local per = total / (r[5] or 1)
                        if not best or per < best then
                            best, source, age, detail = per, "craft", worst, { spell = spell, lines = lines }
                        end
                    end
                end
            end
            visiting[id] = nil
        end
    end

    if depth == 0 then
        self.costMemo[id] = { cost = best, source = source, age = age, detail = detail }
    end
    return best, source, age, detail
end

--- Total reagent cost of casting a recipe once (which may make several items).
-- Returns total, lines, worstAge, missing (list of reagent ids with no price).
function Engine:ReagentCost(spell, depth, visiting)
    local r = self.env.recipes[spell]
    local regs = r[4]
    local total, worst, lines, missing = 0, 0, {}, nil
    for i = 1, #regs, 2 do
        local id, n = regs[i], regs[i + 1]
        local unit, src, age = self:UnitCost(id, depth or 0, visiting)
        lines[#lines + 1] = { item = id, count = n, unit = unit, source = src }
        if unit then
            total = total + unit * n
            if age and age > worst then worst = age end
        else
            missing = missing or {}
            missing[#missing + 1] = id
        end
    end
    if missing then return nil, lines, worst, missing end
    return total, lines, worst
end

-- ---------------------------------------------------------------------------
-- One recipe, all exits.
-- ---------------------------------------------------------------------------

--- Evaluate one recipe. Everything per ITEM made (a recipe making 2 halves
-- the cost per item). Returns a row table, or nil + reason if item info is
-- not loaded yet.
function Engine:Evaluate(spell)
    local r = self.env.recipes[spell]
    if not r then return nil, "unknown recipe" end
    local itemID, made = r[1], r[5] or 1
    local info = self.env.itemInfo(itemID)
    if not info then return nil, "item not loaded" end

    local row = {
        spell = spell, item = itemID, prof = r[2], skill = r[3], made = made,
        quality = info.quality, ilvl = info.ilvl, class = info.class, bop = info.bop,
    }

    local total, lines, costAge, missing = self:ReagentCost(spell, 0)
    row.lines, row.missingReagents = lines, missing
    row.cost = total and (total / made) or nil

    local ev, breakdown, deAge, why, missingMats = self:DisenchantEV(info)
    row.deable = self:BandFor(info) ~= nil
    row.de, row.deBreakdown, row.missingMats = ev, breakdown, missingMats

    if not info.bop then
        local p, pa = self.env.ahPrice(itemID)
        if p then row.sell = p * (1 - self.cut); row.sellAge = pa end
    end
    row.vendor = (info.vendorSell and info.vendorSell > 0) and info.vendorSell or nil

    -- the best way out, and which one it is
    local exits = { { "de", row.de }, { "ah", row.sell }, { "vendor", row.vendor } }
    for _, e in ipairs(exits) do
        if e[2] and (not row.best or e[2] > row.best) then row.best, row.exit = e[2], e[1] end
    end

    if row.cost then
        if row.de then row.profitDE = row.de - row.cost end
        if row.best then row.profit = row.best - row.cost end
    end
    row.age = math.max(costAge or 0, deAge or 0)
    row.complete = row.cost ~= nil and (not row.deable or row.de ~= nil)
    return row
end

--- Evaluate every recipe passing `filter(spell, recipe)`. Returns rows and the
-- number of recipes skipped because their item is not loaded yet.
function Engine:EvaluateAll(filter)
    self:Reset()
    local rows, pending = {}, 0
    for spell, r in pairs(self.env.recipes) do
        if not filter or filter(spell, r) then
            local row, why = self:Evaluate(spell)
            if row then rows[#rows + 1] = row
            elseif why == "item not loaded" then pending = pending + 1 end
        end
    end
    return rows, pending
end

--- Sort rows: complete rows by the chosen profit, best first; rows we cannot
-- price at all go to the bottom rather than masquerading as zero.
function Optimizer.SortRows(rows, key, ascending)
    key = key or "profitDE"
    table.sort(rows, function(a, b)
        local va, vb = a[key], b[key]
        if va and vb then
            if va ~= vb then
                if ascending then return va < vb end
                return va > vb
            end
            return a.spell < b.spell
        end
        -- rows with no value (no price, no known skill) always sit at the
        -- bottom, whichever way the column is sorted
        if va then return true end
        if vb then return false end
        return a.spell < b.spell
    end)
    return rows
end

return Optimizer
