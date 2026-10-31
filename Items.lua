--[[ Items.lua -----------------------------------------------------------------
Item facts from LibItemDB: name, quality, class, item level and vendor sell price
are shipped data, so the list is complete the moment it opens. No waiting on the
server's item cache.

The one fact LibItemDB does not carry is whether an item is soulbound on pickup
(that only matters for the "sell the crafted item on the AH" exit). That comes
from GetItemInfo when the client has the item cached, and is requested in the
background otherwise. Until it arrives the item is treated as tradeable, and
the tooltip says so.
--------------------------------------------------------------------------- ]]
local SO = ShuffleOptimizer
local Items = {}
SO.Items = Items

local CLASS = { [2] = "WEAPON", [4] = "ARMOR" }
-- Newer clients moved GetItemInfo into C_Item; use whichever exists.
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local cache, bindKnown, requested = {}, {}, {}
local listeners = {}

local function bindFromClient(id, c)
    if bindKnown[id] then return end
    local name, link, _, _, _, _, _, _, _, icon, _, _, _, bindType = GetItemInfo(id)
    if name then
        c.bop, c.link, c.icon = (bindType == 1), link, icon
        c.bindKnown = true
        bindKnown[id] = true
    elseif not requested[id] and C_Item and C_Item.RequestLoadItemDataByID then
        requested[id] = true
        C_Item.RequestLoadItemDataByID(id)
    end
end

--- Info for the optimizer, or nil for an item LibItemDB does not have.
function Items.Info(id)
    local c = cache[id]
    if not c then
        local name, quality, classID, _, _, ilvl = SO.IDB:GetInfo(id)
        if not name then return nil end
        c = {
            name = name, quality = quality or 1, ilvl = ilvl or 0,
            class = CLASS[classID] or "OTHER",
            vendorSell = SO.IDB:GetVendorSellPrice(id),
            bop = false, bindKnown = false,
        }
        cache[id] = c
    end
    if not c.bindKnown then bindFromClient(id, c) end
    return c
end

function Items.Name(id)
    local c = Items.Info(id)
    return c and c.name or ("item:" .. id)
end

--- A chat link if the client has one, else nil (callers fall back to the name).
function Items.Link(id)
    local c = Items.Info(id)
    return c and c.link
end

function Items.OnChange(fn) listeners[#listeners + 1] = fn end

-- Soulbound flags trickle in as the client caches items; redraw in batches.
local pending = false
local ev = CreateFrame("Frame")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:SetScript("OnEvent", function(_, _, id)
    local c = id and cache[id]
    if not c or c.bindKnown then return end
    bindFromClient(id, c)
    if pending then return end
    pending = true
    C_Timer.After(1, function()
        pending = false
        for _, fn in ipairs(listeners) do fn() end
    end)
end)
