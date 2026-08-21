# Contributing to Tavern League TCG

Beta project, contributions very welcome. There is **one edits file and
one command**:

```
node tools/build.js
```

That downloads the item datasets (first run only), regenerates the card
pool, and converts the card art. Needs [Node.js](https://nodejs.org);
art conversion also needs [ffmpeg](https://ffmpeg.org)
(`winget install ffmpeg`) and is skipped gracefully without it.

## Change the cards

Edit **`tools/cards.csv`** - one line per edit, formats documented in the
file: `exclude` a card, force a `tier`, or `add` an item the datasets
lack. Run the build; it prints an **added/removed diff vs the previous
pool** - paste that into your PR description.

The pool is generated from pinned snapshots of the community
[wow-classic-items](https://github.com/nexus-devs/wow-classic-items)
dataset (rarity = item quality; Weapons, Armor and Trade Goods become
cards). Junk-item filters live at the top of `tools/build.js`.
`tools/report_included.csv` / `report_excluded.csv` show every decision
the build made.

## Change the art

Drop a PNG in **`Art/`** with "back" or "front" in the filename and run
the build - the newest match becomes the card back / card front texture.
Keep sources roughly card-shaped (width:height around 0.55-0.65).

If new front art moves the icon window, update **`TT.LAYOUT`** in
`TavernLeagueTCG/Data.lua` - the window position, name band, foil glow
strengths and pack tints are all fractions/numbers in that one commented
table. No UI code changes needed.

## Change the addon

Plain WoW Lua, no libraries, no XML. Shared `TT` namespace across five
files; all saved state goes through `TT.Profile()`; every economy number
is in `TT.ECON` (Data.lua). `CardPool.lua` and `art/` are generated -
never edit them by hand.

To test in-game: copy `deploy.bat.example` to `deploy_tavernleaguetcg.bat`
(gitignored), fix the game paths, run it, `/reload`. `/tltcg dev` lists
the test commands (grant packs/credits, force a god pack, fake a boss
bounty) - dev grants are recorded in the run's event log by design.

## PRs

- One topic per PR. Pool diff output for card changes, a screenshot for
  art/UI changes, and say which client(s) you tested on (Classic Era
  1.15.x / TBC Anniversary 2.5.x).
- License is GPL-3.0 - contributions are accepted under the same.
