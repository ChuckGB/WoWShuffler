--[[ Minimap.lua -- the minimap button (LibDataBroker + LibDBIcon, embedded).
Left-click: open/close the window. Right-click: LibItemDB's price-source window.
Being a LibDataBroker launcher, it also shows in ElvUI's datatexts, Titan Panel
and any other broker display. ]]
local SO = ShuffleOptimizer
local Minimap = {}
SO.Minimap = Minimap

local ICON = "Interface\\Icons\\INV_Enchant_DustIllusion"

function Minimap.Init()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local DBI = LibStub("LibDBIcon-1.0", true)
    if not LDB or not DBI then return end
    local obj = LDB:NewDataObject(SO.ADDON, {
        type = "launcher",
        text = "Shuffle",
        icon = ICON,
        OnClick = function(_, button)
            if button == "RightButton" then
                if SO.IDB and SO.IDB.OpenPriceWindow then SO.IDB:OpenPriceWindow() end
            else
                SO.UI.Toggle()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("Shuffle Optimizer")
            tt:AddLine("Craft, disenchant, sell the mats.", 0.7, 0.7, 0.7)
            tt:AddLine(" ")
            tt:AddDoubleLine("Left-click", "open / close", 1, 1, 1, 0.7, 0.7, 0.7)
            tt:AddDoubleLine("Right-click", "price sources (LibItemDB)", 1, 1, 1, 0.7, 0.7, 0.7)
            tt:AddDoubleLine("Drag", "move this button", 1, 1, 1, 0.7, 0.7, 0.7)
        end,
    })
    ShuffleOptimizerDB.minimap = ShuffleOptimizerDB.minimap or {}
    DBI:Register(SO.ADDON, obj, ShuffleOptimizerDB.minimap)
end

function Minimap.Toggle()
    local DBI = LibStub("LibDBIcon-1.0", true)
    if not DBI then return end
    local db = ShuffleOptimizerDB.minimap
    db.hide = not db.hide
    if db.hide then DBI:Hide(SO.ADDON) else DBI:Show(SO.ADDON) end
    return not db.hide
end
