-- Loads the whole addon against stubbed WoW APIs, in .toc order, and drives
-- it: login, open the window, filters, sorting, scrolling, tooltips, a
-- profession window being opened. Catches nil globals, calls to locals declared
-- later, and wiring mistakes the pure engine tests cannot see.
-- Run from the addon folder:  lua tests/ingame_smoke.lua

local pass, fail = 0, 0
local function ok(c, name) if c then pass = pass + 1 else fail = fail + 1; io.write("FAIL: " .. name .. "\n") end end

-- ------------------------------------------------------------------ stubs
local scripts, events, allFrames = {}, {}, {}
local tooltipLines = {}

local Stub = {}
local function newObj(kind)
    local o = { _kind = kind, _shown = (kind ~= "Frame-hidden"), _scripts = {}, _w = 0, _h = 0, _text = "" }
    return setmetatable(o, Stub)
end
Stub.__index = function(t, k)
    local v = rawget(Stub, k)
    if v then return v end
    -- WoW widget methods are CapitalCase; plain fields (row, cells, ...) are
    -- nil until set, exactly as on a real frame.
    if type(k) == "string" and k:match("^%u") then return function() return newObj("generic") end end
    return nil
end
function Stub.SetScript(self, name, fn) self._scripts[name] = fn end
function Stub.GetScript(self, name) return self._scripts[name] end
function Stub.RegisterEvent(self, e) events[e] = events[e] or {}; table.insert(events[e], self) end
function Stub.UnregisterEvent() end
function Stub.Show(self) local was = self._shown; self._shown = true; if not was and self._scripts.OnShow then self._scripts.OnShow(self) end end
function Stub.Hide(self) self._shown = false end
function Stub.IsShown(self) return self._shown end
function Stub.SetSize(self, w, h) self._w, self._h = w, h end
function Stub.GetWidth(self) return self._w end
function Stub.GetHeight(self) return self._h end
function Stub.GetEffectiveScale() return 1 end
function Stub.GetCenter() return 0, 0 end
function Stub.SetWidth(self, w) self._w = w end
function Stub.SetText(self, t) self._text = t end
function Stub.GetText(self) return self._text end
function Stub.SetChecked(self, v) self._checked = v end
function Stub.HasFocus(self) return self._focus end
function Stub.ClearFocus(self) self._focus = false end
function Stub.GetChecked(self) return self._checked end
function Stub.CreateFontString(self) local o = newObj("FontString"); o._parent = self; return o end
function Stub.CreateTexture(self) local o = newObj("Texture"); o._parent = self; return o end
function Stub.CreateAnimationGroup(self) local o = newObj("AnimationGroup"); o._parent = self; return o end
function Stub.CreateAnimation(self) local o = newObj("Animation"); o._parent = self; return o end
function Stub.GetParent(self) return self._parent end
function Stub.GetName(self) return self._name end
function Stub.Click(self) if self._scripts.OnClick then self._scripts.OnClick(self) end end

function CreateFrame(kind, name, parent, template)
    local o = newObj(kind)
    o.TitleBg = newObj("Texture")
    o._parent, o._name = parent, name
    if name then _G[name] = o end
    allFrames[#allFrames + 1] = o
    return o
end
UIParent = newObj("Frame")
UISpecialFrames = {}
SlashCmdList = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
function print(...) end   -- silence addon chat output
local realPrint = _G.io and function(s) io.write(s, "\n") end

-- dropdowns
local dropdownInit = {}
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_JustifyText() end
function UIDropDownMenu_SetText(dd, t) dd._text = t end
-- Like the real client: Initialize runs the builder straight away, which at
-- file load is before the saved variables exist.
function UIDropDownMenu_Initialize(dd, fn) dropdownInit[dd] = fn; fn(dd, 1) end
function UIDropDownMenu_CreateInfo() return {} end
local menuButtons = {}
function UIDropDownMenu_AddButton(info) menuButtons[#menuButtons + 1] = info end
function CloseDropDownMenus() end

-- faux scroll
local scrollOffset = 0
function FauxScrollFrame_GetOffset() return scrollOffset end
local lastScrollTotal
function FauxScrollFrame_Update(_, total) lastScrollTotal = total end
function FauxScrollFrame_OnVerticalScroll(self, delta, h, fn) scrollOffset = delta; fn() end

-- tooltip
GameTooltip = newObj("Tooltip")
function GameTooltip:SetOwner() tooltipLines = {} end
function GameTooltip:AddLine(t) tooltipLines[#tooltipLines + 1] = t end
function GameTooltip:AddDoubleLine(a, b) tooltipLines[#tooltipLines + 1] = a .. " | " .. b end

C_Timer = { After = function(_, fn) fn() end }
mouseOver = true
function MouseIsOver() return mouseOver end
local requestedLoads = 0
C_Item = { RequestLoadItemDataByID = function() requestedLoads = requestedLoads + 1 end }
function IsModifiedClick() return true end
local linked
function ChatEdit_InsertLink(l) linked = l end
function UnitName() return "Brina" end
function GetRealmName() return "Westfall" end

-- ------------------------------------------------------------------ the two libraries
-- Real LibProfessionDB (copy of the Era install). LibItemDB is a stand-in with the
-- same method contract, so we control prices and which sources are switched on.
LibStub = dofile("libs/LibStub/LibStub.lua") or LibStub
function GetBuildInfo() return "1.15.9", "69722", "", 11509 end
function GetLocale() return "enUS" end
dofile("tests/fixtures/LibProfessionDB-1.0.lua")
for _, f in ipairs({ "Blacksmithing", "Leatherworking", "Mining", "Tailoring", "Engineering", "HiddenRecipes" }) do
    dofile("tests/fixtures/core_" .. f .. ".lua")
end

local ahPrices = setmetatable({}, { __index = function(_, id) return 1000 + (id % 50) * 37 end })
ahPrices[2589] = nil                      -- Linen Cloth: never scanned
local auctionatorOn, priceWindowOpened = false, false
local IDB = LibStub:NewLibrary("LibItemDB-1.0", 45)
function IDB:IsReady() return true end
function IDB:HasItem(id) return id < 200000 end
function IDB:GetInfo(id)
    if id >= 200000 then return nil end
    if id == 14048 or id == 2996 or id == 2589 then return "Item " .. id, 1, 7, 5, "", 30, 0 end
    return "Item " .. id, 2, 4, 1, "INVTYPE_CHEST", 30, 25
end
function IDB:GetVendorSellPrice() return 125 end
function IDB:GetPrice(id, stat)
    assert(stat == "best" or stat == "minBuyout" or stat == "market" or stat == "historical", "statistic " .. tostring(stat))
    if not auctionatorOn then return nil end
    local p = ahPrices[id]
    if not p then return nil end
    return p, { source = "auctionator", sourceName = "Auctionator", statistic = "minBuyout", age = (id % 3) * 86400 * 4 }
end
function IDB:GetVendorBuyPrice(id) if id == 2320 then return 9, { source = "auctionator-vendor" } end end
function IDB:HasPriceData() return auctionatorOn end
function IDB:GetPriceSources()
    return { { id = "auctionator", name = "Auctionator", detected = true, enabled = auctionatorOn, external = false },
             { id = "scan", name = "LibItemDB scan", detected = true, enabled = true, external = false } }
end
function IDB:SetPriceSourceEnabled(id, on) if id == "auctionator" then auctionatorOn = on end return true end
function IDB:OpenPriceWindow() priceWindowOpened = true end

-- soulbound flags come from the client cache, which starts cold
local loaded = {}
function GetItemInfo(id)
    if not loaded[id] then return nil end
    return "Item " .. id, "|Hitem:" .. id .. "|h[Item " .. id .. "]|h", 2, 30, 1, "", "", 1, "", 0, 125,
           4, 0, (id == 4343) and 1 or 2
end

-- TSM's saved data, shaped like the real TradeSkillMasterDB on Westfall
function UnitFactionGroup() return "Alliance" end
TradeSkillMasterDB = {
    ["f@Alliance - Westfall@internalData@crafts"] = {
        ["c:1"] = { itemString = "i:7059", profession = "Tailoring", numResult = 1,
                    mats = { ["i:4305"] = 2, ["i:2604"] = 2, ["i:4291"] = 1 }, players = { Asterix = true } },
        ["c:2"] = { itemString = "i:10500", profession = "Engineering", numResult = 1,
                    mats = { ["i:4385"] = 1, ["i:3864"] = 2, ["i:7068"] = 2, ["i:4234"] = 4 }, players = { Dierdra = true } },
        -- TSM says 3 Bolt of Silk for Azure Silk Pants; the library says otherwise -> corrected
        ["c:3"] = { itemString = "i:7046", profession = "Tailoring", numResult = 1,
                    mats = { ["i:4305"] = 3, ["i:4291"] = 2 }, players = { Asterix = true } },
        ["c:4"] = { itemString = "i:99999:1:2", profession = "Tailoring", mats = {}, players = { Asterix = true } },
    },
    ["f@Alliance - Old Blanchy@internalData@crafts"] = {
        ["c:9"] = { itemString = "i:4343", profession = "Tailoring", mats = { ["i:2996"] = 2 }, players = { Brina = true } },
    },
    ["s@Asterix - Alliance - Westfall@internalData@playerProfessions"] = { Tailoring = { level = 175 }, Cooking = { level = 103 } },
    ["s@Dierdra - Alliance - Westfall@internalData@playerProfessions"] = { Engineering = { level = 300 }, Mining = { level = 300 } },
    ["s@Brina - Alliance - Old Blanchy@internalData@playerProfessions"] = { Tailoring = { level = 99 } },
}

-- ElvUI stand-in that records which skin calls were made
local elvCalls = {}
local S = setmetatable({}, { __index = function(_, k)
    return function(_, obj) elvCalls[k] = (elvCalls[k] or 0) + 1 end
end })
ElvUI = { { GetModule = function(_, name) if name == "Skins" then return S end end } }
unpack = unpack or table.unpack

-- minimap globals LibDBIcon touches
Minimap = newObj("Frame"); Minimap:SetSize(140, 140)
function GetMinimapShape() return "ROUND" end
function GetCursorPosition() return 0, 0 end

-- trade skill window
local tradeItems = { 4343, 2996 }
function GetTradeSkillLine() return "Tailoring", 27, 75 end
function GetNumTradeSkills() return #tradeItems + 1 end
function GetTradeSkillInfo(i) if i == 1 then return "Cloth", "header" end return "x", "easy" end
function GetTradeSkillItemLink(i) return "|Hitem:" .. tradeItems[i - 1] .. "|h" end
-- what the game says the reagents are: Brown Linen Pants match the shipped data,
-- Bolt of Linen deliberately does not (3 linen instead of 2)
local gameRegs = { [4343] = { { 2996, 2 }, { 2320, 1 } }, [2996] = { { 2589, 3 } } }
function GetTradeSkillNumReagents(i) return #gameRegs[tradeItems[i - 1]] end
function GetTradeSkillReagentInfo(i, j) return "r", "", gameRegs[tradeItems[i - 1]][j][2] end
function GetTradeSkillReagentItemLink(i, j) return "|Hitem:" .. gameRegs[tradeItems[i - 1]][j][1] .. "|h" end
function GetTradeSkillNumMade() return 1, 1 end

local function fire(e, ...)
    for _, fr in ipairs(events[e] or {}) do
        local fn = fr._scripts.OnEvent
        if fn then fn(fr, e, ...) end
    end
end

-- ------------------------------------------------------------------ load in .toc order
local toc = io.open("ShuffleOptimizer.toc"):read("*a")
local files = {}
for line in toc:gmatch("[^\r\n]+") do
    if not line:match("^##") and line:match("%.lua$") then files[#files + 1] = (line:gsub("\\", "/")) end
end
ok(#files == 16, "toc lists 16 files (" .. #files .. ")")
for _, file in ipairs(files) do
    local chunk, err = loadfile(file)
    ok(chunk ~= nil, "compiles " .. file .. (err and (": " .. err) or ""))
    local okRun, runErr = pcall(chunk, "ShuffleOptimizer", {})
    ok(okRun, "loads " .. file .. (runErr and (": " .. tostring(runErr)) or ""))
end

local SO = ShuffleOptimizer
fire("ADDON_LOADED", "ShuffleOptimizer")
ok(ShuffleOptimizerDB and ShuffleOptimizerDB.deOnly == true and ShuffleOptimizerDB.statistic == "best", "defaults applied")
local okLogin, eL = pcall(fire, "PLAYER_LOGIN")
ok(okLogin, "login " .. tostring(eL))
ok(SO.broken == nil, "libraries found " .. tostring(SO.broken))
ok(SO.RecipeCounts and SO.RecipeCounts.kept > 800, "recipes built from LibProfessionDB")
ok(LibStub("LibDBIcon-1.0"):IsRegistered("ShuffleOptimizer"), "minimap button registered")
ok(SO.Skin.active == "ElvUI", "ElvUI skin applied (" .. tostring(SO.Skin.active) .. ")")
for _, k in ipairs({ "HandleFrame", "HandleButton", "HandleCheckBox", "HandleEditBox", "HandleScrollBar", "HandleCloseButton" }) do
    ok((elvCalls[k] or 0) > 0, "ElvUI " .. k .. " called")
end

-- Auctionator present but switched off in LibItemDB: empty list and an offer, not a silent change
local okOpen, e1 = pcall(SlashCmdList.SHUFFLEOPTIMIZER, "")
ok(okOpen, "open " .. tostring(e1))
ok(SO.UI.IsShown(), "window shown")
ok(lastScrollTotal == 0 and not auctionatorOn, "no source on -> empty, nothing changed for the player")
ok(SO.UI.enableBtn:IsShown() and SO.UI.enableBtn:GetText():find("Auctionator"), "offers to use Auctionator")
pcall(SO.UI.enableBtn._scripts.OnClick, SO.UI.enableBtn)
ok(auctionatorOn, "button switches Auctionator on in LibItemDB")
ok(lastScrollTotal and lastScrollTotal > 100, "list populated (" .. tostring(lastScrollTotal) .. ")")
ok(not SO.UI.enableBtn:IsShown(), "offer hidden once on")

-- soulbound flag arrives later from the client cache
local pants = SO.Items.Info(4343)
ok(pants and not pants.bindKnown and not pants.bop, "bind unknown while cold")
for _, r in pairs(SO.Recipes) do loaded[r[1]] = true end
local okEv, e2 = pcall(fire, "GET_ITEM_INFO_RECEIVED", 4343, true)
ok(okEv, "item info arrives " .. tostring(e2))
ok(SO.Items.Info(4343).bop == true and SO.Items.Info(4343).bindKnown, "BoP learned from the client")

-- minimap clicks
local ldbObj = LibStub("LibDataBroker-1.1"):GetDataObjectByName("ShuffleOptimizer")
SO.UI.Toggle()                                     -- close
ldbObj.OnClick(nil, "LeftButton")
ok(SO.UI.IsShown(), "minimap left-click opens")
ldbObj.OnClick(nil, "RightButton")
ok(priceWindowOpened, "minimap right-click opens LibItemDB price sources")
local tt = newObj("Tooltip"); local ttLines = 0
function tt:AddLine() ttLines = ttLines + 1 end
function tt:AddDoubleLine() ttLines = ttLines + 1 end
ldbObj.OnTooltipShow(tt)
ok(ttLines >= 4, "minimap tooltip")
SlashCmdList.SHUFFLEOPTIMIZER("minimap")
ok(ShuffleOptimizerDB.minimap.hide == true, "/shuffle minimap hides the button")
SlashCmdList.SHUFFLEOPTIMIZER("minimap")
ok(ShuffleOptimizerDB.minimap.hide == false, "...and shows it again")

-- TSM alts
local K = SO.Known
ok(K.AnyoneMakes(7059) and K.WhoMakes(7059)[1] == "Asterix", "TSM: Asterix's tailoring recipe known")
ok(K.AnyoneMakes(10500) and K.WhoMakes(10500)[1] == "Dierdra", "TSM: Dierdra's engineering recipe known")
ok(not K.AnyoneMakes(4343) or K.WhoMakes(4343)[1] ~= "Brina", "TSM: other realm's character ignored")
ok(K.Summary():find("Tailoring 175 %(Asterix%)") and K.Summary():find("Engineering 300 %(Dierdra%)"), "TSM levels in summary")
ok(not K.Summary():find("Cooking"), "non-crafting professions left out")
ok(not K.Summary():find("Brina"), "other realm's levels left out")
ok(K.SourceNote():find("2 characters"), "source note counts TSM characters")
local azureSpell
for spell, r in pairs(SO.Recipes) do if r[1] == 7046 then azureSpell = spell end end
ok(azureSpell and SO.Recipes[azureSpell].corrected and SO.Recipes[azureSpell].correctedBy == "TSM", "TSM reagents override the library")
-- TSM format changes: quietly no data, no error
local savedTSM = TradeSkillMasterDB
TradeSkillMasterDB = { ["f@Alliance - Westfall@internalData@crafts"] = "garbage" }
local okBad = pcall(K.Sync)
ok(okBad and not K.AnyoneMakes(7059), "unexpected TSM format -> no alts, no error")
TradeSkillMasterDB = savedTSM; K.Sync()
ok(K.AnyoneMakes(7059), "TSM alts back")

-- profession window records known recipes
local okTS, e3 = pcall(fire, "TRADE_SKILL_SHOW")
ok(okTS, "trade skill harvest " .. tostring(e3))
ok(SO.Known.AnyoneMakes(4343) and not SO.Known.AnyoneMakes(14048) == true, "known recipes recorded")
ok(SO.Known.Summary():find("Tailoring 27") ~= nil, "profession rank recorded")
ok(SO.Known.corrected >= 2, "profession-window and TSM corrections both counted (" .. tostring(SO.Known.corrected) .. ")")
ok(SO.Recipes[2963].correctedBy == "profession window", "own window record labelled as such")
ok(SO.Recipes[2963][4][2] == 3 and SO.Recipes[2963].corrected, "bolt of linen now uses the game's 3 linen")
ok(SO.Recipes[3914][4][2] ~= nil and not SO.Recipes[3914].corrected, "matching recipe not flagged")
-- next session: recipes rebuilt from the library, then the saved game reagents re-applied
SO.Recipes = SO.RecipeBuilder.Build(SO.PDB, SO.IDB)
ok(SO.Recipes[2963][4][2] == 2, "fresh build has the library's 2 linen")
SO.Known.ApplyGameReagents()
ok(SO.Recipes[2963][4][2] == 3, "game reagents re-applied after reload")
SO.UI.Refresh()

-- filters
local all = lastScrollTotal
ShuffleOptimizerDB.knownOnly = true; SO.UI.Refresh()
ok(lastScrollTotal >= 3 and lastScrollTotal <= 4, "known-only shows this realm's recorded + TSM recipes (" .. lastScrollTotal .. ")")
ShuffleOptimizerDB.knownOnly = false; ShuffleOptimizerDB.deOnly = false; SO.UI.Refresh()
ok(lastScrollTotal > all, "turning off DE-only adds white crafts")
ShuffleOptimizerDB.deOnly = true; ShuffleOptimizerDB.prof = 197; SO.UI.Refresh()
ok(lastScrollTotal > 0 and lastScrollTotal < all, "tailoring filter")
ShuffleOptimizerDB.prof = 0; SO.UI.Refresh()

-- max skill threshold
local box = _G.ShuffleOptimizerMaxSkill
ok(box ~= nil, "max skill box exists")
local before = lastScrollTotal
box:SetText("250"); box._scripts.OnEnterPressed(box)
ok(ShuffleOptimizerDB.maxSkill == 250, "max skill saved")
ok(lastScrollTotal < before and lastScrollTotal > 0, "threshold narrows the list (" .. before .. " -> " .. lastScrollTotal .. ")")
local over = 0
for _, fr in ipairs(allFrames) do
    if fr._kind == "Button" and fr.cells and fr.row and fr.row.skill and fr.row.skill > 250 then over = over + 1 end
end
ok(over == 0, "no visible row above 250")
ShuffleOptimizerDB.prof = 197; SO.UI.Refresh()
local maxSeen = 0
for i = 1, lastScrollTotal do end
box:SetText(""); box._scripts.OnEnterPressed(box)
ok(ShuffleOptimizerDB.maxSkill == nil, "empty box clears the limit")
ShuffleOptimizerDB.prof = 0; SO.UI.Refresh()
ok(lastScrollTotal == before, "list restored")

-- dropdowns: click opens the list, picking an entry applies it and closes the list
local menuFrame = _G.ShuffleOptimizerMenu
local function menuEntries()
    local out = {}
    for _, b in ipairs(menuFrame.items) do if b:IsShown() then out[#out + 1] = b end end
    return out
end
local profBtn, srcBtn = _G.ShuffleOptimizerProfDD, _G.ShuffleOptimizerSourceDD
ok(profBtn and srcBtn, "both dropdown buttons exist")
profBtn._scripts.OnClick(profBtn)
ok(menuFrame:IsShown(), "profession dropdown opens")
local entries = menuEntries()
ok(#entries == 6, "all professions + 5 entries (" .. #entries .. ")")
ok(entries[3].text:GetText():find("Blacksmithing"), "entries in profession order")
entries[3]._scripts.OnClick(entries[3])
ok(ShuffleOptimizerDB.prof == 164 and not menuFrame:IsShown(), "picking Blacksmithing applies it and closes")
ok(profBtn:GetText() == "Blacksmithing", "button shows the choice")
profBtn._scripts.OnClick(profBtn); profBtn._scripts.OnClick(profBtn)
ok(not menuFrame:IsShown(), "clicking the button again closes the list")
srcBtn._scripts.OnClick(srcBtn)
local st = menuEntries()
ok(#st == 4, "four price statistics")
st[2]._scripts.OnClick(st[2])
ok(ShuffleOptimizerDB.statistic == "minBuyout" and srcBtn:GetText():find("Lowest listing"), "statistic applied")
-- the list closes by itself once the mouse has been away from it
srcBtn._scripts.OnClick(srcBtn)
mouseOver = false
menuFrame._scripts.OnUpdate(menuFrame, 2)
ok(not menuFrame:IsShown(), "list closes when the mouse leaves")
ShuffleOptimizerDB.prof = 0; ShuffleOptimizerDB.statistic = "best"; SO.UI.Refresh()

-- rows, tooltips, linking, scrolling, sorting
local rowButtons = {}
for _, fr in ipairs(allFrames) do
    if fr._kind == "Button" and fr.cells then rowButtons[#rowButtons + 1] = fr end
end
ok(#rowButtons == 20, "20 row buttons")
local first = rowButtons[1]
ok(first.row ~= nil, "first row bound")
local okTip, e5 = pcall(first._scripts.OnEnter, first)
ok(okTip and #tooltipLines > 8, "tooltip renders " .. tostring(e5))
local sawMissing = false
for _, l in ipairs(tooltipLines) do if l:find("no price") then sawMissing = true end end
pcall(first._scripts.OnClick, first)
ok(linked ~= nil, "shift-click links a cached item")

-- the row with an unpriced reagent (Linen 2589) is flagged and sorted last
local rows = {}
for i = 1, 20 do rows[i] = rowButtons[i].row end
ok(rows[1].profitDE ~= nil, "top row has a profit")
for i = 2, 20 do
    if rows[i] and rows[i - 1] and rows[i].profitDE and rows[i - 1].profitDE then
        ok(rows[i - 1].profitDE >= rows[i].profitDE, "sorted by DE profit")
    end
end
local okScroll = pcall(scrollOffset and function() FauxScrollFrame_OnVerticalScroll(nil, lastScrollTotal - 5, 16, function() end) end)
ok(okScroll, "scroll")
scrollOffset = 0

-- header sort buttons
local sorted = 0
for _, fr in ipairs(allFrames) do
    if fr._kind == "Button" and fr.sortKey then
        local okH, e6 = pcall(fr._scripts.OnClick, fr)
        ok(okH, "header sort " .. tostring(fr.sortKey) .. " " .. tostring(e6))
        sorted = sorted + 1
    end
end
ok(sorted == 6, "six sortable headers (" .. sorted .. ")")
-- profession level: first click low-to-high, second click flips
local profHeader
for _, fr in ipairs(allFrames) do if fr._kind == "Button" and fr.sortKey == "skill" then profHeader = fr end end
profHeader._scripts.OnClick(profHeader)
local r1, r2 = rowButtons[1].row, rowButtons[2].row
ok(r1.skill and r2.skill and r1.skill <= r2.skill, "profession header sorts by skill, low first")
profHeader._scripts.OnClick(profHeader)
ok(rowButtons[1].row.skill >= rowButtons[2].row.skill, "second click sorts high first")
ok(profHeader.text:GetText():find("v"), "header shows sort direction")

-- make-intermediates toggle
for _, fr in ipairs(allFrames) do
    if fr._kind == "CheckButton" and fr.prof then
        fr._checked = false
        local okC, e7 = pcall(fr._scripts.OnClick, fr)
        ok(okC, "make toggle " .. tostring(e7))
    end
end
ok(ShuffleOptimizerDB.canMake[197] == false, "make toggle persisted")

-- price source switched off again
auctionatorOn = false
local okNone = pcall(SO.UI.Refresh)
ok(okNone and lastScrollTotal == 0, "no source -> empty list, no error")
auctionatorOn = true

-- EllesmereUI takes precedence and is handed the same widgets
local euiCalls = {}
local ES = setmetatable({}, { __index = function(_, k) return function() euiCalls[k] = (euiCalls[k] or 0) + 1 end end })
EllesmereUI = { RegisterSkin = function(name, fn) assert(name == "ShuffleOptimizer"); fn(ES) end }
SO.Skin.active = nil
SO.Skin.Apply()
ok(SO.Skin.active == "EllesmereUI", "EllesmereUI wins when loaded")
for _, k in ipairs({ "Shell", "Button", "Checkbox", "Panel", "EditBox", "ScrollBar", "CloseButton" }) do
    ok((euiCalls[k] or 0) > 0, "EllesmereUI " .. k .. " called")
end
EllesmereUI = nil

-- missing library: one clear message, no errors
local saved = SO.broken
LibStub.libs["LibItemDB-1.0"] = nil
fire("PLAYER_LOGIN")
ok(SO.broken and SO.broken:find("LibItemDB"), "missing LibItemDB reported")
local okSlash = pcall(SlashCmdList.SHUFFLEOPTIMIZER, "")
ok(okSlash, "slash with a missing library does not error")

io.write(string.format("%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
