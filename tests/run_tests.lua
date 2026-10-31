-- Plain Lua 5.1 tests for the margin engine and data files.
-- Run from the addon folder:  lua tests/run_tests.lua
_G.ShuffleOptimizer = {}
local SO = _G.ShuffleOptimizer
dofile("Data_Disenchant.lua")
dofile("Data_NumMade.lua")
dofile("Recipes.lua")
local Optimizer = dofile("Optimizer.lua")

-- Real LibProfessionDB (a copy of the Era install) under plain Lua, plus a
-- stand-in LibItemDB that, like the real one on an Era realm, has no item above
-- the Season of Discovery range.
LibStub = dofile("libs/LibStub/LibStub.lua") or LibStub
function GetBuildInfo() return "1.15.9", "69722", "", 11509 end
function GetLocale() return "enUS" end
dofile("tests/fixtures/LibProfessionDB-1.0.lua")
for _, f in ipairs({ "Blacksmithing", "Leatherworking", "Mining", "Tailoring", "Engineering", "HiddenRecipes" }) do
    dofile("tests/fixtures/core_" .. f .. ".lua")
end
local PDB = LibStub("LibProfessionDB-1.0")
local eraIDB = { HasItem = function(_, id) return id < 200000 end }
local counts
SO.Recipes, counts = SO.RecipeBuilder.Build(PDB, eraIDB)

local pass, fail = 0, 0
local function ok(cond, name)
    if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b, name) ok(a and b and math.abs(a - b) < 1e-6, name .. " (" .. tostring(a) .. " vs " .. tostring(b) .. ")") end

-- ---------------------------------------------------------------- fixtures
local function env(o)
    local e = {
        recipes = o.recipes or {},
        bands = SO.DisenchantBands,
        essencePairs = SO.EssencePairs,
        itemInfo = function(id) return (o.info or {})[id] end,
        ahPrice = function(id) local p = (o.ah or {})[id]; if p then return p, (o.age or {})[id] or 0 end end,
        vendorBuy = function(id) return (o.vendor or {})[id] end,
        canMake = function(prof) if o.canMake then return o.canMake[prof] end return true end,
        ahCut = 0.05,
    }
    return e
end

local SOUL, GAE, LAE, LGS = 11083, 11082, 10998, 11084
local armor30 = { quality = 2, ilvl = 30, class = "ARMOR" }

-- ---------------------------------------------------------------- disenchant EV
do
    local eng = Optimizer.New(env({ ah = { [SOUL] = 1000, [GAE] = 3000, [LGS] = 2000 } }))
    local ev = eng:DisenchantEV(armor30)
    near(ev, (0.75 * 1.5 * 1000 + 0.20 * 1.5 * 3000 + 0.05 * 2000) * 0.95, "armor ilvl30 EV")
end
do -- greater essence with no listing is valued from 3 x lesser
    local eng = Optimizer.New(env({ ah = { [SOUL] = 1000, [LAE] = 1000, [LGS] = 2000 } }))
    local v = eng:MatValue(GAE)
    near(v, 3000, "greater from 3 lessers")
end
do -- lesser valued as greater/3 when that is better
    local eng = Optimizer.New(env({ ah = { [LAE] = 500, [GAE] = 3000 } }))
    near(eng:MatValue(LAE), 1000, "lesser from greater/3")
    near(eng:MatValue(GAE), 3000, "greater keeps its own price when higher")
end
do -- a material with no price makes EV unknown, not zero
    local eng = Optimizer.New(env({ ah = { [SOUL] = 1000, [GAE] = 3000 } }))
    local ev, _, _, why, missing = eng:DisenchantEV(armor30)
    ok(ev == nil and missing and missing[1] == LGS, "missing shard price -> EV nil")
end
do
    local eng = Optimizer.New(env({}))
    ok(eng:BandFor({ quality = 1, ilvl = 30, class = "ARMOR" }) == nil, "white item not disenchantable")
    ok(eng:BandFor({ quality = 2, ilvl = 30, class = "OTHER" }) == nil, "non armor/weapon not disenchantable")
    ok(eng:BandFor({ quality = 3, ilvl = 18, class = "ARMOR" }) == nil, "rare below 20 not guessed")
    ok(eng:BandFor({ quality = 2, ilvl = 4, class = "WEAPON" }) == nil, "ilvl 4 green not guessed")
    local b = eng:BandFor({ quality = 2, ilvl = 33, class = "WEAPON" })
    ok(b and b[2].item == 11134 and b[2].rate == 0.75, "weapon 31-35 mostly lesser mystic")
end

-- ---------------------------------------------------------------- band table integrity
do
    for _, b in ipairs(SO.DisenchantBands) do
        local s = 0
        for _, m in ipairs(b) do s = s + m.rate; ok(m.min >= 1 and m.max >= m.min, "band counts sane") end
        near(s, 1, string.format("rates sum to 1 (%s q%d %d-%d)", b.class, b.q, b.lo, b.hi))
    end
    for _, class in ipairs({ "ARMOR", "WEAPON" }) do
        for q = 2, 4 do
            local lo = ({ 5, 20, 40 })[q - 1]
            for ilvl = lo, 99 do
                local n = 0
                for _, b in ipairs(SO.DisenchantBands) do
                    if b.class == class and b.q == q and ilvl >= b.lo and ilvl <= b.hi then n = n + 1 end
                end
                ok(n == 1, string.format("exactly one band %s q%d ilvl %d (got %d)", class, q, ilvl, n))
            end
        end
    end
end

-- ---------------------------------------------------------------- buy vs make
local CLOTH, BOLT, THREAD, ROBE = 1, 2, 3, 4
local recipes = {
    [100] = { BOLT, 8, 1, { CLOTH, 4 }, 1 },
    [101] = { ROBE, 8, 1, { BOLT, 3, THREAD, 1 }, 1 },
}
do
    local eng = Optimizer.New(env({ recipes = recipes, ah = { [CLOTH] = 100, [BOLT] = 600 }, vendor = { [THREAD] = 50 } }))
    local c, src = eng:UnitCost(BOLT)
    near(c, 400, "bolt cheaper to make"); ok(src == "craft", "bolt source craft")
    local total = eng:ReagentCost(101)
    near(total, 3 * 400 + 50, "robe reagent cost uses made bolts + vendor thread")
end
do
    local eng = Optimizer.New(env({ recipes = recipes, ah = { [CLOTH] = 100, [BOLT] = 600 },
                                     vendor = { [THREAD] = 50 }, canMake = { [8] = false } }))
    local c, src = eng:UnitCost(BOLT)
    near(c, 600, "cannot make -> buy bolt"); ok(src == "ah", "bolt source ah")
end
do -- vendor beats AH when cheaper
    local eng = Optimizer.New(env({ recipes = {}, ah = { [THREAD] = 80 }, vendor = { [THREAD] = 50 } }))
    local c, src = eng:UnitCost(THREAD)
    near(c, 50, "vendor cheaper"); ok(src == "vendor", "vendor source")
end
do -- cooldown craft is never a make-source
    local MOONCLOTH, FELCLOTH = 14342, 14256
    local r = { [18560] = { MOONCLOTH, 8, 250, { FELCLOTH, 2 }, 1 } }
    local eng = Optimizer.New(env({ recipes = r, ah = { [FELCLOTH] = 10, [MOONCLOTH] = 5000 } }))
    local c, src = eng:UnitCost(MOONCLOTH)
    near(c, 5000, "mooncloth bought, not made"); ok(src == "ah", "mooncloth source ah")
end
do -- cycles terminate
    local A, B = 50, 51
    local r = { [1] = { A, 2, 1, { B, 1 }, 1 }, [2] = { B, 2, 1, { A, 1 }, 1 } }
    local eng = Optimizer.New(env({ recipes = r, ah = {} }))
    local c = eng:UnitCost(A)
    ok(c == nil, "cycle with no prices returns nil without hanging")
end
do -- multi-output recipe: cost per item
    local r = { [200] = { 60, 9, 1, { 61, 1 }, 2 } }
    local eng = Optimizer.New(env({ recipes = r, ah = { [61] = 100 },
                                     info = { [60] = { quality = 1, ilvl = 10, class = "OTHER" } } }))
    local row = eng:Evaluate(200)
    near(row.cost, 50, "two made -> half cost each")
end

-- ---------------------------------------------------------------- full rows
do
    local r = { [101] = { ROBE, 8, 1, { CLOTH, 10 }, 1 } }
    local base = { recipes = r, ah = { [CLOTH] = 100, [SOUL] = 1000, [GAE] = 3000, [LGS] = 2000, [ROBE] = 5000 },
                   info = { [ROBE] = { quality = 2, ilvl = 30, class = "ARMOR", vendorSell = 300 } } }
    local eng = Optimizer.New(env(base))
    local row = eng:Evaluate(101)
    local ev = (0.75 * 1.5 * 1000 + 0.20 * 1.5 * 3000 + 0.05 * 2000) * 0.95
    near(row.cost, 1000, "row cost")
    near(row.de, ev, "row de")
    near(row.profitDE, ev - 1000, "row profitDE")
    near(row.sell, 4750, "row AH sell after cut")
    ok(row.exit == "ah" and math.abs(row.profit - 3750) < 1e-6, "best exit is AH here")
    ok(row.complete, "row complete")

    base.info[ROBE].bop = true
    local row2 = Optimizer.New(env(base)):Evaluate(101)
    ok(row2.sell == nil and row2.exit == "de", "BoP item has no AH exit")
end
do -- missing reagent price -> incomplete, sorted to the bottom
    local r = { [1] = { 70, 8, 1, { 71, 1 }, 1 }, [2] = { 72, 8, 1, { 73, 1 }, 1 } }
    local info = { [70] = armor30, [72] = armor30 }
    local eng = Optimizer.New(env({ recipes = r, info = info,
                                     ah = { [73] = 10, [SOUL] = 1000, [GAE] = 3000, [LGS] = 2000 } }))
    local rows = Optimizer.SortRows((eng:EvaluateAll()), "profitDE")
    ok(rows[1].spell == 2 and rows[2].spell == 1, "unpriced row sorted last")
    ok(rows[2].cost == nil and not rows[2].complete and rows[2].missingReagents[1] == 71, "unpriced row flagged")
end
do -- item not loaded is counted, not silently dropped
    local r = { [1] = { 80, 8, 1, { 81, 1 }, 1 } }
    local rows, pending = Optimizer.New(env({ recipes = r })):EvaluateAll()
    ok(#rows == 0 and pending == 1, "unloaded item counted as pending")
end

do -- ascending sort, missing values stay at the bottom either way
    local rows = { { spell = 1, skill = 300 }, { spell = 2, skill = nil }, { spell = 3, skill = 50 }, { spell = 4, skill = 175 } }
    Optimizer.SortRows(rows, "skill", true)
    ok(rows[1].skill == 50 and rows[3].skill == 300 and rows[4].skill == nil, "skill ascending, unknown last")
    Optimizer.SortRows(rows, "skill", false)
    ok(rows[1].skill == 300 and rows[3].skill == 50 and rows[4].skill == nil, "skill descending, unknown last")
end

-- ---------------------------------------------------------------- recipe data integrity
do
    local n, profs = 0, {}
    for spell, r in pairs(SO.Recipes) do
        n = n + 1
        profs[r[2]] = (profs[r[2]] or 0) + 1
        ok(type(r[1]) == "number" and r[1] > 0 and r[1] < 200000, "created item id " .. spell)
        ok(#r[4] % 2 == 0 and #r[4] >= 2, "reagent pairs " .. spell)
        for i = 2, #r[4], 2 do ok(r[4][i] > 0, "reagent count > 0 " .. spell) end
        ok(spell < 100000, "no Season of Discovery spell " .. spell)
        ok(not PDB:IsHiddenRecipe(spell), "no never-implemented recipe " .. spell)
        ok((r[5] or 1) >= 1, "numMade " .. spell)
    end
    ok(n > 800, "recipe count " .. n)
    for _, p in ipairs({ 164, 165, 186, 197, 202 }) do ok((profs[p] or 0) > 0, "profession present " .. p) end
    ok(counts.hidden > 0 and counts.notOnRealm > 100, string.format("filtered: %d hidden, %d not on this realm",
       counts.hidden, counts.notOnRealm))
    -- the two recipes a web summary got wrong; LibProfessionDB and AtlasLoot agree
    local boots = SO.Recipes[18423]
    local want = { [14048] = 4, [14227] = 2, [8170] = 4, [14341] = 1 }
    local good = boots ~= nil
    for i = 1, #(boots and boots[4] or {}), 2 do if want[boots[4][i]] ~= boots[4][i + 1] then good = false end end
    ok(good and #boots[4] == 8, "Runecloth Boots reagents")
    ok(SO.Recipes[3920] and SO.Recipes[3920][5] == 200, "Crafted Light Shot makes 200 (NumMade)")
    ok(SO.Recipes[3914][3] == 30 or SO.Recipes[3914][3] == nil, "required skill carried through")
    -- known anchors
    local bolt = SO.Recipes[18401]
    ok(bolt and bolt[1] == 14048 and bolt[4][1] == 14047 and bolt[4][2] == 5, "Bolt of Runecloth = 5 Runecloth")
    local linen = SO.Recipes[2963]
    ok(linen and linen[1] == 2996 and linen[4][1] == 2589 and linen[4][2] == 2, "Bolt of Linen Cloth = 2 Linen")
    print(string.format("  (%d recipes from LibProfessionDB: %d hidden, %d not on this realm)",
          counts.kept, counts.hidden, counts.notOnRealm))
end

-- ---------------------------------------------------------------- real data end to end
do -- every real recipe evaluates without error given complete fake data
    local info = setmetatable({}, { __index = function() return { quality = 2, ilvl = 40, class = "ARMOR" } end })
    local ah = setmetatable({}, { __index = function(_, id) return 100 + id % 97 end })
    local eng = Optimizer.New(env({ recipes = SO.Recipes, info = info, ah = ah }))
    local okRun, rows = pcall(function() return eng:EvaluateAll() end)
    ok(okRun and #rows == (function() local c = 0 for _ in pairs(SO.Recipes) do c = c + 1 end return c end)(),
       "every real recipe evaluates")
    if okRun then
        local all = true
        for _, row in ipairs(rows) do if not row.complete then all = false end end
        ok(all, "every real recipe complete when all prices exist")
    end
end

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
