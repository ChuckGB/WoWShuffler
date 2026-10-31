--[[ Recipes.lua ---------------------------------------------------------------
Builds SO.Recipes from LibProfessionDB at login.

  [spellID] = { createdItemID, professionID, requiredSkill|nil, { reagentID, count, ... }, numMade }

professionID is the client's skill line: 164 Blacksmithing, 165 Leatherworking,
186 Mining, 197 Tailoring, 202 Engineering.

What gets left out, and why:
  * recipes LibProfessionDB marks as never implemented;
  * recipes whose item or any reagent LibItemDB does not have for this realm.
    LibItemDB only loads the seasonal items (Season of Discovery, Anniversary)
    on realms that have them, so on an Era realm this drops those recipes
    without a hardcoded ID cutoff.

Number made per cast is not in LibProfessionDB; Data_NumMade.lua supplies it,
and the profession window replaces it with the game's own figure (Known.lua).
--------------------------------------------------------------------------- ]]
local SO = ShuffleOptimizer
local Recipes = {}
SO.RecipeBuilder = Recipes

SO.PROFESSIONS = { 197, 164, 165, 202, 186 }   -- display order
SO.ProfessionName = {
    [164] = "Blacksmithing", [165] = "Leatherworking", [186] = "Mining",
    [197] = "Tailoring", [202] = "Engineering",
}

--- @param PDB LibProfessionDB-1.0
--- @param IDB LibItemDB-1.0
--- @return table recipes, table counts { kept, hidden, notOnRealm }
function Recipes.Build(PDB, IDB)
    local out, kept, hidden, absent = {}, 0, 0, 0
    for _, prof in ipairs(SO.PROFESSIONS) do
        local list = PDB:GetRecipes(prof) or {}
        for spell, e in pairs(list) do
            local item = e.craftedItemId
            if item then
                if PDB.IsHiddenRecipe and PDB:IsHiddenRecipe(spell) then
                    hidden = hidden + 1
                else
                    local regs, ok = {}, IDB:HasItem(item)
                    for rid, n in pairs(e.reagents or {}) do
                        if not IDB:HasItem(rid) then ok = false end
                        regs[#regs + 1] = rid; regs[#regs + 1] = n
                    end
                    if ok and #regs > 0 then
                        out[spell] = { item, prof, e.requiredSkill, regs, SO.NumMade[spell] or 1 }
                        kept = kept + 1
                    else
                        absent = absent + 1
                    end
                end
            end
        end
    end
    return out, { kept = kept, hidden = hidden, notOnRealm = absent }
end
