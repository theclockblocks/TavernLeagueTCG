# Tavern League TCG

Two games in one addon: a trading card game inside WoW Classic, and a
permission challenge where your character may only use what the cards have
granted. Pick a format when a run begins - play the collection, play the
challenge, or fuse both - and the format never changes.

Works on **Classic Era** (1.15.x) and **TBC Anniversary** (2.5.x) from one
addon folder. TBC-only cards are hidden on Era clients.

## Pick a format

A run chooses one format at the start and keeps it for life. Choosing a
different one means a new Hardmode run or a fresh profile.

| Format | What you play |
| --- | --- |
| **Collection** | The trading card game: credits, packs, binder, trading. |
| **Challenge** | The permission game: gear slots, abilities, talents, bags and professions are locked until a card grants them. No credits, packs or trading. |
| **League** | Both, fused. The full economy runs alongside a draft pack every level. |

## Collection: the card game

- **Earn Credits** from experience gained, level-ups, killing blows
  (scaled by mob level), quest turn-ins and **skill points** - weapon
  skills, Defense, primary professions and Cooking/Fishing/First Aid all
  pay out per point, scaled by the rank reached (point 300 is worth 150x
  point 2), so leveling anything gets more and more rewarding. Reputation
  is deliberately not tracked.
- **Every character level grants a free pack** - that's 60 (Era) or 70
  (TBC) packs from a full leveling journey. Free packs are banked and
  consumed before credits.
- **Starting on an existing character?** A one-time catch-up banks a pack
  for every level already earned, so a fresh max-level toon joins with a
  fat stack to rip. Logged in the event log; once per character.
- **2,500 Credits buys a sealed pack.** You then choose what it is -
  Equipment, Trade Goods, Creatures or Wild - and the eight cards roll at
  that moment. The last card is the climax slot: guaranteed Uncommon or
  better, with the best odds of Epics and Legendaries. Every card has a
  1-in-20 chance to be **foil**, and 1 pack in 250 is a **god pack**: all
  eight cards on climax odds, all foil.
- **Pity timer**: if 10 packs pass without an Epic+, the next climax card
  is forced Epic.
- **The binder** shows the whole pool - about 13,600 cards on Era and
  21,900 on TBC, generated from real item and creature data - with paging,
  rarity/type/ownership filters and search.
- **Creature cards render the real NPC in 3D**, and you can drag to spin
  them.
- Pack contents are rolled and saved the moment you pay - relogging
  mid-open resumes the exact same pack. No reroll tricks.

### Endgame faucets

Leveling dries up at cap, so max-level play has its own sources:

- **Boss bounties**: a dungeon's final boss pays 1,500c; any ?? raid or
  world boss you fight pays 2,500c. A raid night is 8-12 packs. The
  **first bounty boss each day banks a free pack**.
- **Honorable kills** pay 35c each - the game's own honor rules decide
  what counts, so grey-level farming pays nothing.
- **Selling spares**: right-click a duplicate in the binder to sell it back
  (15/50/200/800/4,000 by rarity; foils are 4x). Your last copy of a card
  can never be sold, so every duplicate still moves the collection forward.

## Challenge: the permission game

Your character starts with nothing unlocked. Cards grant it back.

- **A Class Pack every level.** Ripping one deals three cards face-down;
  they flip in turn and you learn exactly one. The other two are gone.
- Cards cover **gear slots, abilities, talent tiers, bags and professions**.
  An ability card you have not drawn is one you may not use - not one that
  arrives at some level.
- **Goals and dungeon clears** pay bonus packs.
- The **Tavern** tab is the board: gear slots down the left, your class's
  ability pools in the middle showing only what you have drawn, and
  talents, professions and general unlocks on the right. Red until earned.

### What "locked" actually means

The format *is* the lock - there is no toggle and nothing is grandfathered.

- **Gear**: locked slots are emptied automatically and wear a lock on the
  character sheet.
- **Bags**: locked bag slots are called out and overlaid.
- **Talents**: the talent frame is capped at the points you have earned.
- **Professions**: a locked trade's window will not open, trainers refuse
  to teach or advance it, and its icons wear a lock on your bars and in
  the spellbook.
- **Abilities and gathering** are protected actions that no addon can
  block, so casting a locked spell or working a locked trade raises a
  **LICENSE VIOLATION** - a raid warning, and a permanent entry in the log.

Bar locks work on Blizzard's bars and on anything built with
**LibActionButton-1.0** - Bartender4, Dominos, ElvUI, ConsolePort - with
round buttons detected and drawn to match.

## League: both at once

Every level deals a **draft pack of five licenses** and you keep exactly
one. Licenses come only from those picks, so what your character can do is
shaped entirely by drafting - while the full credit economy, packs, binder
and trading run alongside for gear cards.

League can also run **TCG Locked mode** on top.

## TCG Locked mode

An opt-in extra for Collection and League, enabled from the **Locked** tab
(permanent, confirm dialog). From then on, equipping an item whose card the
run does not own triggers a raid-style warning and a permanent log entry,
plus red lock overlays on the character sheet and on bag items you cannot
legally wear. Items with no card in the pool are always free, and gear
already equipped when the lock first sees a character is grandfathered.

It is the honor system with receipts: every violation - and any use of the
`/tltcg unlock CONFIRM` escape hatch - is recorded in the run's event log.

## Runs, realms and Hardmode

Your **collection is shared per realm**: every character on a realm feeds
one credit balance and one binder. **Licenses are per character** - they
are that character's own progress.

- Each card pull is attributed to the character that opened the pack
  (`/tltcg roster` shows the audit trail). If a character is deleted and its
  name re-used, its pulled cards are automatically revoked; if you delete a
  toon outright, `/tltcg retire <Name> CONFIRM` removes its cards honestly.
- **Hardmode** (per character, opt-in): that toon leaves the realm pool and
  plays with an isolated collection and credits. Leaving Hardmode merges
  everything back and is permanently logged.

## Trading

The **Trade** tab trades cards with another Tavern League player - same
realm and faction, both running the addon. Propose by name (or "Use My
Target"), the partner gets an accept popup, then both sides build offers
by clicking cards in their **Binder** (Ctrl-click offers a foil copy; up
to 8 cards per side). When both press Accept, a two-phase commit runs over
addon whispers and the cards swap - attribution in the contribution ledger
follows the physical cards, so revocation stays honest after trades.

- Offers changing resets both Accepts (like the real trade window).
- Hardmode characters cannot trade - that's the point of Hardmode.
- **Practice Trade** runs the entire flow solo against the "Tavern
  Keeper", a simulated partner - great for testing; no cards move.

## Commands

`/tcg`, `/tltcg`, `/tavernleague` - open the window

- `status` - credits, packs, pity, collection counts
- `roster` - per-character contributions for this run
- `simulate N` - roll N packs (no cost) and print the rarity histogram
- `retire <Name> CONFIRM` - revoke a deleted character's pulled cards
- `unlock CONFIRM` / `unhard CONFIRM` - leave Locked mode / Hardmode (logged)
- `minimap` - toggle the minimap button
- `reset` - wipe this profile (confirm dialog)

## Rebuilding the card pool (developers)

`CardPool.lua` is generated from two community datasets: item cards from
[wow-classic-items](https://github.com/nexus-devs/wow-classic-items)
(pinned npm 0.8.2 for Era and 1.0.0 for TBC, so expansion tagging and item
quality stay accurate), and creature cards from the
[Questie](https://github.com/Questie/Questie) database at a pinned commit.

```
node tools/build.js
```

Rarity comes from item quality and creature rank. Hand-tune with
`tools/cards.csv`, and eyeball `tools/report_included.csv` /
`report_excluded.csv`.
