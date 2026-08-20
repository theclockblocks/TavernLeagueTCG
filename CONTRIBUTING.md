# Contributing to Tavern League TCG

Beta project, contributions very welcome. The three most useful things you
can do - fixing card data, improving art, and hacking on the addon - each
have a one-command pipeline. No build system, no dependencies beyond
[Node.js](https://nodejs.org) (any recent version) and, for art only,
[ffmpeg](https://ffmpeg.org) (`winget install ffmpeg`).

## Project layout

```
TavernLeagueTCG/       the addon itself (this folder goes in Interface\AddOns)
  Data.lua             config: economy knobs (TT.ECON), card layout (TT.LAYOUT)
  CardPool.lua         GENERATED - never edit by hand, see "Card data" below
  Core.lua             game logic: profiles, credits, packs, ledger, comms
  UI.lua               the window: packs, reveals, binder, locked tab
  Trade.lua            player trading + the solo practice partner
  Enforce.lua          TCG Locked mode enforcement
  art/                 GENERATED textures - see "Art" below
Art/                   art SOURCE images (PNG)
tools/                 the pipelines described below
```

## Card data: add, remove, re-tier cards

`CardPool.lua` is generated from pinned snapshots of the community
[wow-classic-items](https://github.com/nexus-devs/wow-classic-items)
dataset. To change what's in the pool, edit the CSVs and regenerate:

- **Remove a card or change its rarity**: add a line to
  `tools/overrides.csv` (`itemId,exclude` or `itemId,tier,N`).
- **Add a card the datasets lack**: add a line to `tools/custom_cards.csv`
  (`itemId,tier,tbcOnly,name`).

Then rebuild:

```
node tools/fetch_dataset.js     # first time only - downloads the datasets
node tools/build_cardpool.js
```

The build prints a **diff against the previous pool** (added/removed
cards) - include that output in your PR description. It also writes
`tools/report_included.csv` / `report_excluded.csv` for eyeballing what
the junk filter did. Junk patterns live at the top of
`tools/build_cardpool.js` if you spot deprecated/GM items slipping through.

## Art: card backs, fronts, and layout

Source images live in `Art/`. The in-game textures are generated:

```
node tools/build_art.js
```

That converts the **newest** file in `Art/` matching `*back*` to the card
back texture, and `*front*` to the face-up card frame (512x1024 TGA, the
format both game clients load). Keep sources roughly card-shaped
(width:height around 0.55-0.65) - PNG straight out of an image generator
is fine.

**Card layout** (where the item icon and name sit on the front art) is
config, not code: `TT.LAYOUT` in `TavernLeagueTCG/Data.lua`. If your new
front art moves the icon window, measure its edges as fractions of the
image (left/right/top/bottom) and update the `window` table - plus the
foil glow strengths and pack tints, all in the same place, all commented.

## Addon code

Plain WoW Lua, no libraries, no XML - patterns are consistent across the
five files (shared `TT` namespace, one event dispatcher per file, all
saved state through `TT.Profile()`). Economy tuning lives entirely in
`TT.ECON` (Data.lua).

To test in-game: copy `deploy.bat.example` to `deploy_tavernleaguetcg.bat`,
fix the game paths for your machine (it's gitignored), run it, `/reload`.
`/tltcg dev` lists the test commands (grant packs/credits/shards, force a
god pack, fake a boss bounty) - dev grants are recorded in the run's event
log by design.

A quick syntax check without launching the game:

```
npm install luaparse
node -e "require('luaparse').parse(require('fs').readFileSync('TavernLeagueTCG/UI.lua','utf8'),{luaVersion:'5.1'})"
```

## PRs

- One topic per PR; include the pool diff output for card-data changes
  and a screenshot for art/UI changes.
- Both clients matter: Classic Era (1.15.x) and TBC Anniversary (2.5.x).
  Say which one(s) you tested on.
- License is GPL-3.0 - contributions are accepted under the same.
