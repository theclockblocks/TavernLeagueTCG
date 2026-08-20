# Tavern League TCG

> **BETA** - actively developed and looking for testers! Everything works,
> but expect balance changes and the occasional rough edge. Feedback and
> bug reports very welcome in the issues.

A trading card game inside WoW Classic, inspired by the OSRS TCG RuneLite
plugin. Play the game, earn Credits, rip open card packs, fill your binder,
trade with friends - and optionally run **TCG Locked mode**, where gear may
only be equipped if your run owns its card.

Works on **Classic Era** (1.15.x) and **TBC Anniversary** (2.5.x) from one
addon folder. TBC-only cards are hidden on Era clients.

## Installation

1. Download the latest release zip (or clone this repo).
2. Copy the `TavernLeagueTCG` folder into your AddOns directory:
   - Classic Era: `World of Warcraft\_classic_era_\Interface\AddOns\`
   - TBC Anniversary: `World of Warcraft\_anniversary_\Interface\AddOns\`
3. `/reload` or restart the game. Type `/tcg` to open.

## How it plays

- **Earn Credits** from experience gained, level-ups, killing blows
  (scaled by mob level), quest turn-ins and **skill points** - weapon
  skills, Defense, primary professions and Cooking/Fishing/First Aid all
  pay out per point, scaled by the rank reached (point 300 is worth 150x
  point 2), so leveling anything gets more and more rewarding. Reputation
  is deliberately not tracked.
- **Every character level grants a free pack** - that's 60 (Era) or 70
  (TBC) packs from a full leveling journey, on top of everything below.
  Free packs are banked on the run and consumed before credits.
- **Starting on an existing character?** A one-time catch-up banks a pack
  for every level already earned, so a fresh max-level toon joins the run
  with a fat stack to rip. Logged in the event log; once per character.
- **2,500 Credits buys a pack** of 8 cards: pick one of three sealed packs,
  rip it open, and flip the cards one at a time. The final card is the
  climax slot - guaranteed Uncommon or better, with the best odds of Epics
  and Legendaries. Every card has a 1-in-20 chance to be a **foil**, and
  1 pack in 250 is a **god pack**: all eight cards rolled on climax odds,
  all foil.
- **Pity timer**: if 10 packs pass without an Epic+, the next climax card
  is forced Epic.
- **The binder** shows the whole pool (~15,800 cards generated from real
  item data) with paging, rarity/type/ownership filters and search.
- Pack contents are rolled and saved the moment you pay - relogging
  mid-open resumes the exact same pack. No reroll tricks.

## Endgame: bounties, honor, dusting & crafting

Leveling dries up at cap, so max-level play has its own faucets:

- **Boss bounties**: killing a dungeon's final boss pays 1,500c; any ??
  raid or world boss you fight pays 2,500c (a full pack). A raid night is
  8-12 packs. The **first bounty boss each day banks a free pack**.
- **Honorable kills** pay 35c each - the game's own honor rules decide
  what counts, so grey-level farming pays nothing.
- **Dusting & crafting**: right-click a card in the binder to dust a
  *spare* copy into shards (5/20/100/400/1,600 by rarity; Ctrl-right-click
  dusts a foil for 4x; your last copy can never be dusted). Right-click a
  missing card to craft it for shards (20/80/400/1,600/8,000). Every
  duplicate pull still moves the collection forward - that's the
  completion engine.

## Trading

The **Trade** tab trades cards with another Tavern League player - same
realm and faction, both running the addon. Propose by name (or "Use My
Target"), the partner gets an accept popup, then both sides build offers
by clicking cards in their **Binder** (Ctrl-click offers a foil copy; up
to 8 cards per side). When both press Accept, a two-phase commit runs over
addon whispers and the cards swap.

- Offers changing resets both Accepts (like the real trade window).
- Hardmode characters cannot trade - that's the point of Hardmode.
- **Practice Trade** runs the entire flow solo against the "Tavern
  Keeper", a simulated partner - great for a first look; no cards move.

## Runs, realms and Hardmode

Progress is **shared per realm**: every character you play on a realm feeds
one credit balance and one collection. Roll on a new realm for a fresh run.

- Each card pull is attributed to the character that opened the pack
  (`/tltcg roster` shows the audit trail). If a character is deleted and its
  name re-used, its pulled cards are automatically revoked; if you delete a
  toon outright, `/tltcg retire <Name> CONFIRM` removes its cards honestly.
- **Hardmode** (per character, opt-in): that toon leaves the realm pool and
  plays with an isolated collection and credits. Leaving Hardmode merges
  everything back and is permanently logged.

## TCG Locked mode

Enable it from the **Locked** tab (permanent, confirm dialog). From then on,
equipping an item whose card the run does not own triggers a raid-style
warning and a permanent log entry, plus red lock overlays on the character
sheet and bag items you can't legally wear. Items with no card in the pool
are always free. Gear already equipped when the lock first sees a character
is grandfathered.

It is the honor system with receipts: the addon cannot hard-block equipping,
but every violation - and any use of the `/tltcg unlock CONFIRM` escape
hatch - is recorded in the run's event log.

## Commands

`/tcg`, `/tltcg`, `/tavernleague` - open the window

- `status` - credits, packs, shards, pity, collection counts
- `roster` - per-character contributions for this run
- `simulate N` - roll N packs (no cost) and print the rarity histogram
- `retire <Name> CONFIRM` - revoke a deleted character's pulled cards
- `unlock CONFIRM` / `unhard CONFIRM` - leave Locked mode / Hardmode (logged)
- `minimap` - toggle the minimap button
- `reset` - wipe this profile (confirm dialog)

## Rebuilding the card pool (developers)

The pool (`TavernLeagueTCG/CardPool.lua`) is generated from the community
[wow-classic-items](https://github.com/nexus-devs/wow-classic-items)
dataset - pinned npm versions 0.8.2 (Classic era build) and 1.0.0 (TBC
Classic build), so Era/TBC tagging and item quality are expansion-accurate:

```
node tools/fetch_dataset.js
node tools/build_cardpool.js
```

Weapons, Armor and Trade Goods become cards; rarity = item quality.
Hand-tune with `tools/overrides.csv` (exclude/re-tier specific items) and
eyeball `tools/report_included.csv` / `report_excluded.csv`.

## License

GPL-3.0. Card pool data derives from the community wow-classic-items
dataset (MIT). Not affiliated with Blizzard Entertainment.
