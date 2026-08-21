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
- **2,500 Credits buys a pack** of 8 cards - and the pick matters: choose
  an **Equipment** pack (weapons & armor), a **Trade Goods** pack, or a
  **Creatures** pack (quest NPCs, notorious mobs, rare spawns and bosses),
  then rip it open and flip the cards one at a time. The final card is the
  climax slot - guaranteed Uncommon or better, with the best odds of Epics
  and Legendaries. Every card has a 1-in-20 chance to be a **foil**, and
  1 pack in 250 is a **god pack**: all eight cards rolled on climax odds,
  all foil.
- **Creature cards** (~6,100) are curated, not a mob dump: quest givers,
  mobs that quests actually target (yes, Hogger), silver-dragon rares, and
  worldbosses - Ragnaros and the faction leaders are legendary cards.
- **Pity timer**: if 10 packs pass without an Epic+, the next climax card
  is forced Epic.
- **The binder** shows the whole pool (~22,000 cards generated from real
  game data) with paging, rarity/type/ownership filters and search.
- Pack contents are rolled and saved the moment you pay - relogging
  mid-open resumes the exact same pack. No reroll tricks.

## Endgame: bounties, honor, and selling dupes

Leveling dries up at cap, so max-level play has its own faucets:

- **Boss bounties**: killing a dungeon's final boss pays 1,500c; any ??
  raid or world boss you fight pays 2,500c (a full pack). A raid night is
  8-12 packs. The **first bounty boss each day banks a free pack**.
- **Honorable kills** pay 35c each - the game's own honor rules decide
  what counts, so grey-level farming pays nothing.
- **Sell your dupes**: right-click a card in the binder to sell a *spare*
  copy back for credits (15/50/200/800/4,000 by rarity; Ctrl-right-click
  sells a foil for 4x; your last copy can never be sold). Every duplicate
  pull funds the next pack.

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

- `status` - credits, packs, pity, collection counts
- `roster` - per-character contributions for this run
- `simulate N` - roll N packs (no cost) and print the rarity histogram
- `retire <Name> CONFIRM` - revoke a deleted character's pulled cards
- `unlock CONFIRM` / `unhard CONFIRM` - leave Locked mode / Hardmode (logged)
- `minimap` - toggle the minimap button
- `reset` - wipe this profile (confirm dialog)

## Contributing

One edits file (`tools/cards.csv`), one command (`node tools/build.js`) -
that covers card changes and art alike. See
**[CONTRIBUTING.md](CONTRIBUTING.md)**.

## License

GPL-3.0. Card pool data derives from the community wow-classic-items
dataset (MIT). Not affiliated with Blizzard Entertainment.
