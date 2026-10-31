--[[ Init.lua -- saved variables, library hookup, slash command. Loaded last. ]]
local SO = ShuffleOptimizer

local DEFAULTS = {
    prof = 0,                  -- 0 = all, else a profession skill line id
    statistic = "best",        -- LibItemDB statistic: best / minBuyout / market / historical
    deOnly = true,
    knownOnly = false,
    canMake = {},              -- [profession id] = false to buy that profession's intermediates
    gameReagents = {},         -- [createdItemID] = { regs = {id,n,...}, made = } as the game showed them
    minimap = {},              -- LibDBIcon position / hidden flag
}

local function libraries()
    local PDB = LibStub and LibStub("LibProfessionDB-1.0", true)
    local IDB = LibStub and LibStub("LibItemDB-1.0", true)
    local missing = {}
    if not (PDB and PDB:IsReady()) then missing[#missing + 1] = "LibProfessionDB" end
    if not (IDB and IDB:IsReady()) then missing[#missing + 1] = "LibItemDB" end
    return PDB, IDB, missing
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == SO.ADDON then
        ShuffleOptimizerDB = ShuffleOptimizerDB or {}
        for k, v in pairs(DEFAULTS) do
            if ShuffleOptimizerDB[k] == nil then
                ShuffleOptimizerDB[k] = type(v) == "table" and {} or v
            end
        end
        ShuffleOptimizerDB.priceSource = nil   -- v0.1 setting; LibItemDB owns sources now
    elseif event == "PLAYER_LOGIN" then
        local PDB, IDB, missing = libraries()
        if #missing > 0 then
            SO.broken = "Needs " .. table.concat(missing, " and ") .. " (installed and enabled)."
            SO.Print("|cffff6060" .. SO.broken .. "|r")
            return
        end
        SO.PDB, SO.IDB = PDB, IDB
        SO.Recipes, SO.RecipeCounts = SO.RecipeBuilder.Build(PDB, IDB)
        SO.Known.Sync()            -- our record + TSM alts, then game reagents over the library
        SO.Items.OnChange(function() if SO.UI.IsShown() then SO.UI.Refresh() end end)
        SO.Minimap.Init()
        SO.Skin.Apply()
        SO.Print(string.format("%d recipes loaded. |cffffffff/shuffle|r or the minimap button.",
                               SO.RecipeCounts.kept))
    end
end)

SLASH_SHUFFLEOPTIMIZER1 = "/shuffle"
SLASH_SHUFFLEOPTIMIZER2 = "/so"
SlashCmdList["SHUFFLEOPTIMIZER"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if SO.broken then SO.Print("|cffff6060" .. SO.broken .. "|r"); return end
    if msg == "minimap" then
        local shown = SO.Minimap.Toggle()
        SO.Print("minimap button " .. (shown and "shown" or "hidden") .. ".")
    else
        SO.UI.Toggle()
    end
end
