--[[ Prices.lua ----------------------------------------------------------------
Every price comes from LibItemDB. It looks up Auctionator, Auctioneer, TSM or its
own AH scan in the order you set in /itemdb, and says where each answer came
from and how old it is.

Classic Era has no web auction API, so all of these are data your own client
already holds. Prices are only as fresh as your last scan.

LibItemDB ships with every third-party source switched OFF. If Auctionator is
installed but not switched on there, the window offers a one-click "use
Auctionator" button rather than changing your LibItemDB settings behind your
back.
--------------------------------------------------------------------------- ]]
local SO = ShuffleOptimizer
local Prices = {}
SO.Prices = Prices

local DAY = 86400
Prices.STATISTICS = {
    { key = "best",       label = "Best available" },
    { key = "minBuyout",  label = "Lowest listing" },
    { key = "market",     label = "Market value" },
    { key = "historical", label = "Historical" },
}

local function idb() return SO.IDB end
local function statistic() return ShuffleOptimizerDB and ShuffleOptimizerDB.statistic or "best" end

--- AH price per item in copper, age in whole days (nil = source does not say),
-- and the source's display name. nil when no enabled source has the item.
function Prices.AH(id)
    local p, why = idb():GetPrice(id, statistic())
    if not p then return nil end
    local age = why and why.age and math.floor(why.age / DAY) or nil
    return p, age, why and why.sourceName
end

--- What a vendor charges you, or nil. Prefers Auctionator's record of what you
-- actually paid (your rep discount), then a price LibItemDB saw at a merchant,
-- then the shipped Neutral list price.
function Prices.Vendor(id)
    return (idb():GetVendorBuyPrice(id))
end

--- Whether any price source can answer at all on this machine.
function Prices.HasAnySource()
    return idb():HasPriceData()
end

--- A detected-but-disabled source we can offer to switch on, e.g. "auctionator".
function Prices.OfferableSource()
    for _, s in ipairs(idb():GetPriceSources() or {}) do
        if s.detected and not s.enabled and not s.external
           and (s.id == "auctionator" or s.id == "tsm" or s.id == "auctioneer") then
            return s.id, s.name
        end
    end
end

function Prices.EnableSource(id)
    return idb():SetPriceSourceEnabled(id, true)
end

--- "Auctionator, TSM" -- the enabled sources in precedence order, for the status line.
function Prices.SourceSummary()
    local names = {}
    for _, s in ipairs(idb():GetPriceSources() or {}) do
        if s.detected and s.enabled then names[#names + 1] = s.name end
    end
    return #names > 0 and table.concat(names, ", ") or "none"
end

function Prices.StatisticLabel()
    local k = statistic()
    for _, s in ipairs(Prices.STATISTICS) do if s.key == k then return s.label end end
    return k
end
