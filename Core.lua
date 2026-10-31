--[[ Core.lua -- namespace and small shared helpers. Loaded first. ]]
ShuffleOptimizer = ShuffleOptimizer or {}
local SO = ShuffleOptimizer

SO.ADDON = "ShuffleOptimizer"
SO.TAG = "|cff33ff99Shuffle|r"

--- "12g 34s" -- copper dropped once there is gold, because nobody shuffles for
-- copper and the extra digits make columns harder to scan.
function SO.Money(c, signed)
    if c == nil then return "|cff707070--|r" end
    local neg = c < 0
    c = math.floor(math.abs(c) + 0.5)
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local out
    if g > 0 then
        out = string.format("%d|cffffd700g|r %02d|cffc7c7cfs|r", g, s)
    elseif s > 0 then
        out = string.format("%d|cffc7c7cfs|r %02d|cffeda55fc|r", s, cp)
    else
        out = string.format("%d|cffeda55fc|r", cp)
    end
    if neg then return "|cffff6060-|r" .. out end
    if signed then return "|cff60ff60+|r" .. out end
    return out
end

function SO.Print(msg) print(SO.TAG .. " " .. msg) end
