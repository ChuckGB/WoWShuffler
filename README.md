# Shuffle Optimizer (Classic Era first) — v0.2

Ranks every Blacksmithing, Leatherworking, Tailoring and Engineering recipe by
what it nets you to buy the mats, craft the item, disenchant it and sell the
dust, essences and shards. Mining's smelting recipes are included as
intermediates (bars).

**Open it:** the minimap button (left-click), `/shuffle` or `/so`.
Right-click the minimap button for LibItemDB's price-source settings.
`/shuffle minimap` hides or shows the button.

## Requires
- **LibProfessionDB** (folder `ProfessionDB`): recipes and reagents.
- **LibItemDB** (folder `ItemDB`): item level, quality and class, vendor prices,
  and AH prices.
- Both need Ace3 and VersionCheck-1.0.
- A price source:
  - Auctionator, TSM or Auctioneer, or a LibItemDB scan.
  - LibItemDB ships with third-party sources switched **off**. If one is installed
    but off, the window shows a "Use Auctionator prices" button. Clicking it is
    the only way this addon changes a LibItemDB setting.

## Looks
- EllesmereUI on Forever / Retail: uses its skinning API.
- Otherwise ElvUI: uses its Skins module, on any game version.
- Otherwise the Blizzard look.

## Columns
| Column | Meaning |
|---|---|
| Mat cost | The cheapest way to get the reagents, per item made. Each reagent is priced as the cheapest of the vendor, the AH, or crafting it yourself (bolts, bars, cured leather, parts). |
| DE value | Expected AH proceeds from disenchanting one, after the 5% AH cut. |
| DE profit | DE value minus mat cost. The shuffle number. |
| Best exit | The best of disenchanting, selling the item on the AH, or vendoring it, minus mat cost. |
| Age | Days since the oldest price in the row was seen. `?` means the source doesn't say (TSM, Auctioneer). |

Hover a row for the full working. Click a header to sort. Shift-click a row to
link the item.

## Data notes
- **Disenchanting:** Classic Era has no enchanting-skill requirement, so the addon
  doesn't check skill.
- **Recipes:** recipes LibProfessionDB marks as never implemented are hidden.
  - Recipes whose items LibItemDB doesn't have on this realm are hidden too.
    On an Era realm that removes every Season of Discovery recipe.
- **Number made per cast** isn't in LibProfessionDB. It comes from
  `Data_NumMade.lua`, generated from AtlasLootClassic.
- **Profession window is the authority:** opening one records the game's own
  reagents and count, and they override the library for those recipes. A
  difference is flagged in the tooltip.
- **Essences** are valued at the better of their lesser and greater forms (3:1).
- **Cooldown crafts** (Mooncloth) are never assumed makeable on demand.

## Known limits
- One price per item. It doesn't use auction depth or sell-through yet; that's
  Phase 2.
- Deposits and auctions that expire unsold aren't counted.
- Disenchant results are random, so the expected value is an average over many
  disenchants.

## Tests (Lua 5.1, from this folder)
```
lua tests/run_tests.lua      # engine, DE table, recipes built from the real LibProfessionDB data
lua tests/ingame_smoke.lua   # whole addon against stubbed WoW APIs, ElvUI and EllesmereUI
```


## Install

Copy this folder into `World of Warcraft/_classic_era_/Interface/AddOns/` and name it `ShuffleOptimizer`.

## License

MIT. See [LICENSE](LICENSE).

Test fixtures in `tests/fixtures/` are from [ProfessionDB](https://www.curseforge.com/wow/addons/professiondb) by Pimptasty, MIT-licensed; see `tests/fixtures/LICENSE-ProfessionDB`.
