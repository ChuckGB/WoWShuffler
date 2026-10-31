--[[ Data_Disenchant.lua -------------------------------------------------------
Classic Era (1.12) disenchanting results.

Classic Era has NO enchanting-skill requirement to disenchant -- any enchanter
can disenchant any item. (The skill-by-item-level gate arrived with TBC.) So
nothing here, or anywhere in the addon, checks enchanting skill.

Each band: item class, quality, item-level range, and the possible results.
  rate          chance that this material is the one you get
  min, max      how many of it, uniform between them
Expected count of a material per disenchant = rate * (min + max) / 2.

Rates and counts cross-checked against TSM's vanilla destroy table and the
material bands on public disenchanting guides. One correction: TSM lists
uncommon armor 46-50 Greater Nether Essence at 25%, which makes that band sum
to 105%; every other armor band uses 20% essence, so this does too.

Only quality 2 (uncommon), 3 (rare) and 4 (epic) armor and weapons disenchant.
Items outside every band (e.g. rare below ilvl 20) are treated as not
disenchantable rather than guessed at.
--------------------------------------------------------------------------- ]]
local SO = _G.ShuffleOptimizer

-- material item IDs
local STRANGE, SOUL, VISION, DREAM, ILLUSION = 10940, 11083, 11137, 11176, 16204
local LME, GME, LAE, GAE = 10938, 10939, 10998, 11082
local LMYE, GMYE, LNE, GNE, LEE, GEE = 11134, 11135, 11174, 11175, 16202, 16203
local SGS, LGS, SGWS, LGWS = 10978, 11084, 11138, 11139
local SRS, LRS, SBS, LBS, NEXUS = 11177, 11178, 14343, 14344, 20725

SO.EnchantingMats = {
    STRANGE, SOUL, VISION, DREAM, ILLUSION,
    LME, GME, LAE, GAE, LMYE, GMYE, LNE, GNE, LEE, GEE,
    SGS, LGS, SGWS, LGWS, SRS, LRS, SBS, LBS, NEXUS,
}

-- Lesser <-> greater essences convert 3:1 and back by right-clicking, so an
-- essence is worth whichever form sells better. [lesser] = greater.
SO.EssencePairs = {
    [LME] = GME, [LAE] = GAE, [LMYE] = GMYE, [LNE] = GNE, [LEE] = GEE,
}

local function m(item, rate, min, max) return { item = item, rate = rate, min = min, max = max } end

-- class: "ARMOR" or "WEAPON"; q: quality
SO.DisenchantBands = {
    -- uncommon armor: mostly dust
    { class = "ARMOR", q = 2, lo = 5,  hi = 15, m(STRANGE, 0.80, 1, 2), m(LME, 0.20, 1, 2) },
    { class = "ARMOR", q = 2, lo = 16, hi = 20, m(STRANGE, 0.75, 2, 3), m(GME, 0.20, 1, 2), m(SGS, 0.05, 1, 1) },
    { class = "ARMOR", q = 2, lo = 21, hi = 25, m(STRANGE, 0.75, 4, 6), m(LAE, 0.15, 1, 2), m(SGS, 0.10, 1, 1) },
    { class = "ARMOR", q = 2, lo = 26, hi = 30, m(SOUL, 0.75, 1, 2), m(GAE, 0.20, 1, 2), m(LGS, 0.05, 1, 1) },
    { class = "ARMOR", q = 2, lo = 31, hi = 35, m(SOUL, 0.75, 2, 5), m(LMYE, 0.20, 1, 2), m(SGWS, 0.05, 1, 1) },
    { class = "ARMOR", q = 2, lo = 36, hi = 40, m(VISION, 0.75, 1, 2), m(GMYE, 0.20, 1, 2), m(LGWS, 0.05, 1, 1) },
    { class = "ARMOR", q = 2, lo = 41, hi = 45, m(VISION, 0.75, 2, 5), m(LNE, 0.20, 1, 2), m(SRS, 0.05, 1, 1) },
    { class = "ARMOR", q = 2, lo = 46, hi = 50, m(DREAM, 0.75, 1, 2), m(GNE, 0.20, 1, 2), m(LRS, 0.05, 1, 1) },
    { class = "ARMOR", q = 2, lo = 51, hi = 55, m(DREAM, 0.75, 2, 5), m(LEE, 0.20, 1, 2), m(SBS, 0.05, 1, 1) },
    { class = "ARMOR", q = 2, lo = 56, hi = 60, m(ILLUSION, 0.75, 1, 2), m(GEE, 0.20, 1, 2), m(LBS, 0.05, 1, 1) },
    { class = "ARMOR", q = 2, lo = 61, hi = 99, m(ILLUSION, 0.75, 2, 5), m(GEE, 0.20, 2, 3), m(LBS, 0.05, 1, 1) },

    -- uncommon weapons: mostly essence
    { class = "WEAPON", q = 2, lo = 5,  hi = 15, m(STRANGE, 0.20, 1, 2), m(LME, 0.80, 1, 2) },
    { class = "WEAPON", q = 2, lo = 16, hi = 20, m(STRANGE, 0.20, 2, 3), m(GME, 0.75, 1, 2), m(SGS, 0.05, 1, 1) },
    { class = "WEAPON", q = 2, lo = 21, hi = 25, m(STRANGE, 0.15, 4, 6), m(LAE, 0.75, 1, 2), m(SGS, 0.10, 1, 1) },
    { class = "WEAPON", q = 2, lo = 26, hi = 30, m(SOUL, 0.20, 1, 2), m(GAE, 0.75, 1, 2), m(LGS, 0.05, 1, 1) },
    { class = "WEAPON", q = 2, lo = 31, hi = 35, m(SOUL, 0.20, 2, 5), m(LMYE, 0.75, 1, 2), m(SGWS, 0.05, 1, 1) },
    { class = "WEAPON", q = 2, lo = 36, hi = 40, m(VISION, 0.20, 1, 2), m(GMYE, 0.75, 1, 2), m(LGWS, 0.05, 1, 1) },
    { class = "WEAPON", q = 2, lo = 41, hi = 45, m(VISION, 0.20, 2, 5), m(LNE, 0.75, 1, 2), m(SRS, 0.05, 1, 1) },
    { class = "WEAPON", q = 2, lo = 46, hi = 50, m(DREAM, 0.20, 1, 2), m(GNE, 0.75, 1, 2), m(LRS, 0.05, 1, 1) },
    { class = "WEAPON", q = 2, lo = 51, hi = 55, m(DREAM, 0.20, 2, 5), m(LEE, 0.75, 1, 2), m(SBS, 0.05, 1, 1) },
    { class = "WEAPON", q = 2, lo = 56, hi = 60, m(ILLUSION, 0.20, 1, 2), m(GEE, 0.75, 1, 2), m(LBS, 0.05, 1, 1) },
    { class = "WEAPON", q = 2, lo = 61, hi = 99, m(ILLUSION, 0.20, 2, 5), m(GEE, 0.75, 2, 3), m(LBS, 0.05, 1, 1) },
}

-- rare and epic: identical for armor and weapons
local function both(t)
    local a, w = {}, {}
    for k, v in pairs(t) do a[k] = v; w[k] = v end
    a.class, w.class = "ARMOR", "WEAPON"
    table.insert(SO.DisenchantBands, a)
    table.insert(SO.DisenchantBands, w)
end
both({ q = 3, lo = 20, hi = 25, m(SGS, 1, 1, 1) })
both({ q = 3, lo = 26, hi = 30, m(LGS, 1, 1, 1) })
both({ q = 3, lo = 31, hi = 35, m(SGWS, 1, 1, 1) })
both({ q = 3, lo = 36, hi = 40, m(LGWS, 1, 1, 1) })
both({ q = 3, lo = 41, hi = 45, m(SRS, 1, 1, 1) })
both({ q = 3, lo = 46, hi = 50, m(LRS, 1, 1, 1) })
both({ q = 3, lo = 51, hi = 55, m(SBS, 1, 1, 1) })
both({ q = 3, lo = 56, hi = 60, m(LBS, 0.995, 1, 1), m(NEXUS, 0.005, 1, 1) })
both({ q = 3, lo = 61, hi = 99, m(LBS, 0.99, 1, 1), m(NEXUS, 0.01, 1, 1) })
both({ q = 4, lo = 40, hi = 45, m(SRS, 1, 2, 4) })
both({ q = 4, lo = 46, hi = 50, m(LRS, 1, 2, 4) })
both({ q = 4, lo = 51, hi = 55, m(SBS, 1, 2, 4) })
both({ q = 4, lo = 56, hi = 60, m(NEXUS, 1, 1, 1) })
both({ q = 4, lo = 61, hi = 99, m(NEXUS, 1, 1, 2) })
