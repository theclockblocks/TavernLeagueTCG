-- Tavern League TCG: the license deck (permission cards) and tavern-goal
-- definitions, ported from DeckLocked (the author's own GPL addon) with
-- CARD IDS INTACT so DeckLocked characters can import their progress.
-- Pure data + tiny helpers; per-character state lives in TT.Run().
--
-- Icon conventions (resolved by TT.GetLicenseIcon):
--   icon = "Interface\\Icons\\..." -> texture path
--   item = <itemID>                 -> GetItemIcon at runtime
--   invSlot = "HeadSlot" etc        -> empty paperdoll slot art
--   spell = <spellID>               -> spell texture (rank 1)

local ADDON, TT = ...

local ICON = "Interface\\Icons\\"

---------------------------------------------------------------------------
-- License-layer tunables. Every number here was validated by the 0.5.0
-- economy simulation before shipping; retuning is a data edit.
---------------------------------------------------------------------------

TT.LICENSE = {
  drawChoices       = 3,     -- Challenge: licenses shown per draw, keep 1
  draftSize         = 5,     -- League: cards per draft pack, keep 1
  draftLicenseSlots = 2,     -- of draftSize; the rest are item cards
  draftSlotOdds     = { 600, 280, 95, 25, 0 },   -- item slots (per mille)
  draftClimaxOdds   = { 0, 600, 300, 90, 10 },   -- last item slot
  draftFoilChance   = 20,    -- 1 in N per draft card
  draftIlvlWindow   = 15,    -- item slots: itemLevel >= playerLevel - N
  pityWindow        = 5,     -- internal pack-roll bookkeeping (see Core)
  pityBias          = 0.30,
  goalRewards       = { challenge = "bonusDraw", collection = "freePack",
                        league = "draftPack" },
  -- the shared deck's Ranged/Relic license unlocks at 50 for most classes;
  -- classes whose ranged slot is core get it much earlier
  relicMinLevel     = { HUNTER = 1, MAGE = 20, WARLOCK = 20, PRIEST = 20 },
}

---------------------------------------------------------------------------
-- Shared cards: gear, talents, professions, general (same for every class)
---------------------------------------------------------------------------

TT.licenseShared = {
  -- Gear slots -----------------------------------------------------------
  { id = "head1",      name = "Helm Slot",       type = "gear", slot = "head",      invSlot = "HeadSlot",          minLevel = 20 },
  { id = "neck1",      name = "Neck Slot",       type = "gear", slot = "neck",      invSlot = "NeckSlot",          minLevel = 20 },
  { id = "shoulders1", name = "Shoulder Slot",   type = "gear", slot = "shoulders", invSlot = "ShoulderSlot",      minLevel = 15 },
  { id = "back1",      name = "Back Slot",       type = "gear", slot = "back",      invSlot = "BackSlot",          minLevel = 1 },
  { id = "chest1",     name = "Chest Slot",      type = "gear", slot = "chest",     invSlot = "ChestSlot",         minLevel = 1 },
  { id = "wrists1",    name = "Wrist Slot",      type = "gear", slot = "wrists",    invSlot = "WristSlot",         minLevel = 1 },
  { id = "hands1",     name = "Glove Slot",      type = "gear", slot = "hands",     invSlot = "HandsSlot",         minLevel = 1 },
  { id = "waist1",     name = "Waist Slot",      type = "gear", slot = "waist",     invSlot = "WaistSlot",         minLevel = 1 },
  { id = "legs1",      name = "Leg Slot",        type = "gear", slot = "legs",      invSlot = "LegsSlot",          minLevel = 1 },
  { id = "feet1",      name = "Feet Slot",       type = "gear", slot = "feet",      invSlot = "FeetSlot",          minLevel = 1 },
  { id = "ring1",      name = "Ring Slot 1",     type = "gear", slot = "ring1",     invSlot = "Finger0Slot",       minLevel = 15 },
  { id = "ring2",      name = "Ring Slot 2",     type = "gear", slot = "ring2",     invSlot = "Finger1Slot",       minLevel = 15 },
  { id = "trinket1",   name = "Trinket Slot 1",  type = "gear", slot = "trinket1",  invSlot = "Trinket0Slot",      minLevel = 40 },
  { id = "trinket2",   name = "Trinket Slot 2",  type = "gear", slot = "trinket2",  invSlot = "Trinket1Slot",      minLevel = 40 },
  { id = "mainhand1",  name = "Main Hand",       type = "gear", slot = "mainhand",  invSlot = "MainHandSlot",      minLevel = 1 },
  { id = "offhand1",   name = "Offhand",         type = "gear", slot = "offhand",   invSlot = "SecondaryHandSlot", minLevel = 1 },
  { id = "relic1",     name = "Ranged/Relic Slot", type = "gear", slot = "relic",   invSlot = "RangedSlot",        minLevel = 50 },

  -- Talents ----------------------------------------------------------------
  -- Ten +5 cards up to the Era cap plus a +1 capstone at 60 (the game grants
  -- 51 points at level 60), then two more +5 cards for TBC levels (61 total
  -- at level 70). Order matters: box "talent-i" maps to the i-th card here.
  { id = "talent1",   name = "Talent +5", type = "talent", points = 5, icon = ICON .. "INV_Misc_Book_09", minLevel = 15 },
  { id = "talent2",   name = "Talent +5", type = "talent", points = 5, icon = ICON .. "INV_Misc_Book_09", minLevel = 20 },
  { id = "talent3",   name = "Talent +5", type = "talent", points = 5, icon = ICON .. "INV_Misc_Book_09", minLevel = 25 },
  { id = "talent4",   name = "Talent +5", type = "talent", points = 5, icon = ICON .. "INV_Misc_Book_09", minLevel = 30 },
  { id = "talent5",   name = "Talent +5", type = "talent", points = 5, icon = ICON .. "INV_Misc_Book_09", minLevel = 35 },
  { id = "talent6",   name = "Talent +5", type = "talent", points = 5, icon = ICON .. "INV_Misc_Book_09", minLevel = 40 },
  { id = "talent7",   name = "Talent +5", type = "talent", points = 5, icon = ICON .. "INV_Misc_Book_09", minLevel = 45 },
  { id = "talent8",   name = "Talent +5", type = "talent", points = 5, icon = ICON .. "INV_Misc_Book_09", minLevel = 50 },
  { id = "talent9",   name = "Talent +5", type = "talent", points = 5, icon = ICON .. "INV_Misc_Book_09", minLevel = 55 },
  { id = "talent10",  name = "Talent +5", type = "talent", points = 5, icon = ICON .. "INV_Misc_Book_09", minLevel = 60 },
  { id = "talentcap", name = "Talent +1", type = "talent", points = 1, icon = ICON .. "INV_Misc_Book_09", minLevel = 60 },
  { id = "talent11",  name = "Talent +5", type = "talent", points = 5, icon = ICON .. "INV_Misc_Book_09", minLevel = 65 },
  { id = "talent12",  name = "Talent +5", type = "talent", points = 5, icon = ICON .. "INV_Misc_Book_09", minLevel = 70 },

  -- Professions ----------------------------------------------------------
  { id = "prof1_card",    name = "Unlock Profession",   type = "profession", profession = "prof-1",   icon = ICON .. "Trade_BlackSmithing",        minLevel = 5 },
  { id = "prof2_card",    name = "Unlock Profession 2", type = "profession", profession = "prof-2",   icon = ICON .. "Trade_Engineering",          minLevel = 5 },
  { id = "cooking_card",  name = "Unlock Cooking",      type = "profession", profession = "cooking",  icon = ICON .. "INV_Misc_Food_15",           minLevel = 5 },
  { id = "fishing_card",  name = "Learn Fishing",       type = "profession", profession = "fishing",  icon = ICON .. "Trade_Fishing",              minLevel = 5 },
  { id = "firstaid_card", name = "Learn First Aid",     type = "profession", profession = "firstaid", icon = ICON .. "Spell_Holy_SealOfSacrifice", minLevel = 5 },

  -- General --------------------------------------------------------------
  { id = "bag1_card",       name = "Unlock Bag Slot 1",        type = "general", general = "bag-1",             icon = ICON .. "INV_Misc_Bag_08",             minLevel = 1 },
  { id = "bag2_card",       name = "Unlock Bag Slot 2",        type = "general", general = "bag-2",             icon = ICON .. "INV_Misc_Bag_10",             minLevel = 5 },
  { id = "bag3_card",       name = "Unlock Bag Slot 3",        type = "general", general = "bag-3",             icon = ICON .. "INV_Misc_Bag_11",             minLevel = 10 },
  { id = "bag4_card",       name = "Unlock Bag Slot 4",        type = "general", general = "bag-4",             icon = ICON .. "INV_Misc_Bag_12",             minLevel = 15 },
  { id = "mount_card",      name = "Unlock Mount",             type = "general", general = "mount",             icon = ICON .. "Ability_Mount_RidingHorse",   minLevel = 30 },
  { id = "epicmount_card",  name = "Unlock Epic Mount",        type = "general", general = "epic-mount",        icon = ICON .. "Ability_Mount_Charger",       minLevel = 60 },
  { id = "flying_card",     name = "Unlock Flying Mount",      type = "general", general = "flying-mount",      icon = ICON .. "Ability_Mount_Gryphon_01",    minLevel = 70 },
  -- NB: Ability_Mount_GoldenGryphon is a Wrath-era file (TBC gryphons all
  -- use Gryphon_01), so the epic flyer uses the Swift Nether Drake icon.
  { id = "epicflying_card", name = "Unlock Epic Flying Mount", type = "general", general = "epic-flying-mount", icon = ICON .. "Ability_Mount_NetherdrakeElite", minLevel = 70 },
}

-- Ordered talent card list: Core and UI iterate this instead of hardcoding
-- a count, and box "talent-i" is worth TT.licenseTalents[i].points.
TT.licenseTalents = {}
for _, card in ipairs(TT.licenseShared) do
  if card.type == "talent" then
    TT.licenseTalents[#TT.licenseTalents + 1] = card
  end
end

---------------------------------------------------------------------------
-- Class spec sections (UI headers) and ability decks.
-- Ability entries: { id, name, subspec, icon, minLevel }.
-- minLevel = the level the first rank is trainable; entries above the
-- client's level cap simply never become eligible.
---------------------------------------------------------------------------

TT.licenseSpecs = {
  WARRIOR = { { key = "arms", label = "Arms" }, { key = "fury", label = "Fury" }, { key = "protection", label = "Protection" } },
  PALADIN = { { key = "holy", label = "Holy" }, { key = "protection", label = "Protection" }, { key = "retribution", label = "Retribution" } },
  HUNTER  = { { key = "beastmastery", label = "Beast Mastery" }, { key = "marksmanship", label = "Marksmanship" }, { key = "survival", label = "Survival" } },
  ROGUE   = { { key = "assassination", label = "Assassination" }, { key = "combat", label = "Combat" }, { key = "subtlety", label = "Subtlety" } },
  PRIEST  = { { key = "discipline", label = "Discipline" }, { key = "holy", label = "Holy" }, { key = "shadow", label = "Shadow" } },
  SHAMAN  = { { key = "elemental", label = "Elemental" }, { key = "enhance", label = "Enhancement" }, { key = "restoration", label = "Restoration" } },
  MAGE    = { { key = "arcane", label = "Arcane" }, { key = "fire", label = "Fire" }, { key = "frost", label = "Frost" } },
  WARLOCK = { { key = "affliction", label = "Affliction" }, { key = "demonology", label = "Demonology" }, { key = "destruction", label = "Destruction" } },
  DRUID   = { { key = "balance", label = "Balance" }, { key = "feral", label = "Feral" }, { key = "restoration", label = "Restoration" } },
}

TT.licenseAbilityDecks = {}

-- SHAMAN -----------------------------------------------------------------
-- Complete Classic trainer/quest ability list, verified against Wowhead
-- Classic (spell = rank-1 spell ID; icons resolve from it automatically).
-- Card ids preserved from v1 so existing progress carries over.
-- expansion = 1 cards are hidden on the Classic Era client.
TT.licenseAbilityDecks.SHAMAN = {
  { id = "lightning",         name = "Lightning Bolt",          subspec = "elemental",   spell = 403,   minLevel = 1 },
  { id = "rockbiter",         name = "Rockbiter Weapon",        subspec = "enhance",     spell = 8017,  minLevel = 1 },
  { id = "healingwave",       name = "Healing Wave",            subspec = "restoration", spell = 331,   minLevel = 1 },
  { id = "earthshock",        name = "Earth Shock",             subspec = "elemental",   spell = 8042,  minLevel = 4 },
  { id = "stoneskin",         name = "Stoneskin Totem",         subspec = "enhance",     spell = 8071,  minLevel = 4 },
  { id = "earthbind",         name = "Earthbind Totem",         subspec = "elemental",   spell = 2484,  minLevel = 6 },
  { id = "lightningshield",   name = "Lightning Shield",        subspec = "enhance",     spell = 324,   minLevel = 8 },
  { id = "stoneclaw",         name = "Stoneclaw Totem",         subspec = "elemental",   spell = 5730,  minLevel = 8 },
  { id = "flameshock",        name = "Flame Shock",             subspec = "elemental",   spell = 8050,  minLevel = 10 },
  { id = "flametonguewep",    name = "Flametongue Weapon",      subspec = "enhance",     spell = 8024,  minLevel = 10 },
  { id = "searingtotem",      name = "Searing Totem",           subspec = "elemental",   spell = 3599,  minLevel = 10 },
  { id = "strengthofearth",   name = "Strength of Earth Totem", subspec = "enhance",     spell = 8075,  minLevel = 10 },
  { id = "ancestralspirit",   name = "Ancestral Spirit",        subspec = "restoration", spell = 2008,  minLevel = 12 },
  { id = "firenova",          name = "Fire Nova Totem",         subspec = "elemental",   spell = 1535,  minLevel = 12 },
  { id = "purge",             name = "Purge",                   subspec = "elemental",   spell = 370,   minLevel = 12 },
  { id = "curepoison",        name = "Cure Poison",             subspec = "restoration", spell = 526,   minLevel = 16 },
  { id = "tremor",            name = "Tremor Totem",            subspec = "restoration", spell = 8143,  minLevel = 18 },
  { id = "frostshock",        name = "Frost Shock",             subspec = "elemental",   spell = 8056,  minLevel = 20 },
  { id = "frostbrandwep",     name = "Frostbrand Weapon",       subspec = "enhance",     spell = 8033,  minLevel = 20 },
  { id = "ghostwolf",         name = "Ghost Wolf",              subspec = "enhance",     spell = 2645,  minLevel = 20 },
  { id = "healingstream",     name = "Healing Stream Totem",    subspec = "restoration", spell = 5394,  minLevel = 20 },
  { id = "lesserhealingwave", name = "Lesser Healing Wave",     subspec = "restoration", spell = 8004,  minLevel = 20 },
  { id = "curedisease",       name = "Cure Disease",            subspec = "restoration", spell = 2870,  minLevel = 22 },
  { id = "poisoncleansetotem",name = "Poison Cleansing Totem",  subspec = "restoration", spell = 8166,  minLevel = 22 },
  { id = "waterbreathing",    name = "Water Breathing",         subspec = "enhance",     spell = 131,   minLevel = 22 },
  { id = "frosttotem",        name = "Frost Resistance Totem",  subspec = "enhance",     spell = 8181,  minLevel = 24 },
  { id = "farsight",          name = "Far Sight",               subspec = "enhance",     spell = 6196,  minLevel = 26 },
  { id = "magmatotem",        name = "Magma Totem",             subspec = "elemental",   spell = 8190,  minLevel = 26 },
  { id = "manaspring",        name = "Mana Spring Totem",       subspec = "restoration", spell = 5675,  minLevel = 26 },
  { id = "firetotem",         name = "Fire Resistance Totem",   subspec = "enhance",     spell = 8184,  minLevel = 28 },
  { id = "flametonguetotem",  name = "Flametongue Totem",       subspec = "enhance",     spell = 8227,  minLevel = 28 },
  { id = "waterwalking",      name = "Water Walking",           subspec = "enhance",     spell = 546,   minLevel = 28 },
  { id = "astralrecall",      name = "Astral Recall",           subspec = "enhance",     spell = 556,   minLevel = 30 },
  { id = "grounding",         name = "Grounding Totem",         subspec = "enhance",     spell = 8177,  minLevel = 30 },
  { id = "naturetotem",       name = "Nature Resistance Totem", subspec = "enhance",     spell = 10595, minLevel = 30 },
  { id = "reincarnation",     name = "Reincarnation",           subspec = "restoration", spell = 20608, minLevel = 30 },
  { id = "windfurywep",       name = "Windfury Weapon",         subspec = "enhance",     spell = 8232,  minLevel = 30 },
  { id = "chainlightning",    name = "Chain Lightning",         subspec = "elemental",   spell = 421,   minLevel = 32 },
  { id = "windfurytotem",     name = "Windfury Totem",          subspec = "enhance",     spell = 8512,  minLevel = 32 },
  { id = "sentry",            name = "Sentry Totem",            subspec = "enhance",     spell = 6495,  minLevel = 34 },
  { id = "windwall",          name = "Windwall Totem",          subspec = "enhance",     spell = 15107, minLevel = 36 },
  { id = "diseasetotem",      name = "Disease Cleansing Totem", subspec = "restoration", spell = 8170,  minLevel = 38 },
  { id = "chainheal",         name = "Chain Heal",              subspec = "restoration", spell = 1064,  minLevel = 40 },
  { id = "graceofair",        name = "Grace of Air Totem",      subspec = "enhance",     spell = 8835,  minLevel = 42 },
  { id = "tranquiltotem",     name = "Tranquil Air Totem",      subspec = "restoration", spell = 25908, minLevel = 50 },
  -- TBC (complete new-spell trainer list, verified against Wowhead TBC;
  -- gated on Classic Era). spell2 = the other faction's twin spell.
  { id = "totemiccall",       name = "Totemic Call",            subspec = "restoration", spell = 36936, icon = ICON .. "Spell_Shaman_TotemRecall",          minLevel = 30, expansion = 1 },
  { id = "watershield",       name = "Water Shield",            subspec = "restoration", spell = 24398, icon = ICON .. "Ability_Shaman_WaterShield",        minLevel = 62, expansion = 1 },
  { id = "wrathtotem",        name = "Wrath of Air Totem",      subspec = "enhance",     spell = 3738,  icon = ICON .. "Spell_Nature_SlowingTotem",         minLevel = 64, expansion = 1 },
  { id = "earthele",          name = "Earth Elemental Totem",   subspec = "enhance",     spell = 2062,  icon = ICON .. "Spell_Nature_EarthElemental_Totem", minLevel = 66, expansion = 1 },
  { id = "fireele",           name = "Fire Elemental Totem",    subspec = "elemental",   spell = 2894,  icon = ICON .. "Spell_Fire_Elemental_Totem",        minLevel = 68, expansion = 1 },
  { id = "bloodlust",         name = "Bloodlust/Heroism",       subspec = "enhance",     spell = 2825,  spell2 = 32182, icon = ICON .. "Spell_Nature_BloodLust", minLevel = 70, expansion = 1 },
}

-- WARRIOR ----------------------------------------------------------------
-- Verified against Wowhead Classic (spell = rank-1 ID, icons auto-resolve)
TT.licenseAbilityDecks.WARRIOR = {
  { id = "heroicstrike",     name = "Heroic Strike",       subspec = "arms",       spell = 78,    minLevel = 1 },
  { id = "battlestance",     name = "Battle Stance",       subspec = "arms",       spell = 2457,  minLevel = 1 },
  { id = "battleshout",      name = "Battle Shout",        subspec = "fury",       spell = 6673,  minLevel = 1 },
  { id = "charge",           name = "Charge",              subspec = "arms",       spell = 100,   minLevel = 4 },
  { id = "rend",             name = "Rend",                subspec = "arms",       spell = 772,   minLevel = 4 },
  { id = "thunderclap",      name = "Thunder Clap",        subspec = "arms",       spell = 6343,  minLevel = 6 },
  { id = "hamstring",        name = "Hamstring",           subspec = "arms",       spell = 1715,  minLevel = 8 },
  { id = "bloodrage",        name = "Bloodrage",           subspec = "fury",       spell = 2687,  minLevel = 10 },
  { id = "defensivestance",  name = "Defensive Stance",    subspec = "protection", spell = 71,    minLevel = 10 },
  { id = "sunderarmor",      name = "Sunder Armor",        subspec = "protection", spell = 7386,  minLevel = 10 },
  { id = "taunt",            name = "Taunt",               subspec = "protection", spell = 355,   minLevel = 10 },
  { id = "overpower",        name = "Overpower",           subspec = "arms",       spell = 7384,  minLevel = 12 },
  { id = "shieldbash",       name = "Shield Bash",         subspec = "protection", spell = 72,    minLevel = 12 },
  { id = "demoshout",        name = "Demoralizing Shout",  subspec = "fury",       spell = 1160,  minLevel = 14 },
  { id = "revenge",          name = "Revenge",             subspec = "protection", spell = 6572,  minLevel = 14 },
  { id = "mockingblow",      name = "Mocking Blow",        subspec = "arms",       spell = 694,   minLevel = 16 },
  { id = "shieldblock",      name = "Shield Block",        subspec = "protection", spell = 2565,  minLevel = 16 },
  { id = "disarm",           name = "Disarm",              subspec = "protection", spell = 676,   minLevel = 18 },
  { id = "cleave",           name = "Cleave",              subspec = "fury",       spell = 845,   minLevel = 20 },
  { id = "retaliation",      name = "Retaliation",         subspec = "arms",       spell = 20230, minLevel = 20 },
  { id = "intimidatingshout",name = "Intimidating Shout",  subspec = "fury",       spell = 5246,  minLevel = 22 },
  { id = "execute",          name = "Execute",             subspec = "fury",       spell = 5308,  minLevel = 24 },
  { id = "challengingshout", name = "Challenging Shout",   subspec = "protection", spell = 1161,  minLevel = 26 },
  { id = "shieldwall",       name = "Shield Wall",         subspec = "protection", spell = 871,   minLevel = 28 },
  { id = "berserkerstance",  name = "Berserker Stance",    subspec = "fury",       spell = 2458,  minLevel = 30 },
  { id = "intercept",        name = "Intercept",           subspec = "fury",       spell = 20252, minLevel = 30 },
  { id = "slam",             name = "Slam",                subspec = "arms",       spell = 1464,  minLevel = 30 },
  { id = "berserkerrage",    name = "Berserker Rage",      subspec = "fury",       spell = 18499, minLevel = 32 },
  { id = "whirlwind",        name = "Whirlwind",           subspec = "fury",       spell = 1680,  minLevel = 36 },
  { id = "pummel",           name = "Pummel",              subspec = "fury",       spell = 6552,  minLevel = 38 },
  { id = "recklessness",     name = "Recklessness",        subspec = "fury",       spell = 1719,  minLevel = 50 },
  -- TBC (complete new-spell trainer list, verified against Wowhead TBC)
  { id = "victoryrush",      name = "Victory Rush",        subspec = "fury",       spell = 34428, icon = ICON .. "Ability_Warrior_Devastate",        minLevel = 62, expansion = 1 },
  { id = "spellreflection",  name = "Spell Reflection",    subspec = "protection", spell = 23920, icon = ICON .. "Ability_Warrior_ShieldReflection", minLevel = 64, expansion = 1 },
  { id = "commandingshout",  name = "Commanding Shout",    subspec = "fury",       spell = 469,   icon = ICON .. "Ability_Warrior_RallyingCry",      minLevel = 68, expansion = 1 },
  { id = "intervene",        name = "Intervene",           subspec = "protection", spell = 3411,  icon = ICON .. "Ability_Warrior_VictoryRush",      minLevel = 70, expansion = 1 },
}

-- PALADIN ----------------------------------------------------------------
-- Verified against Wowhead Classic (spell = rank-1 ID, icons auto-resolve)
TT.licenseAbilityDecks.PALADIN = {
  { id = "holylight",        name = "Holy Light",             subspec = "holy",        spell = 635,   minLevel = 1 },
  { id = "devotionaura",     name = "Devotion Aura",          subspec = "protection",  spell = 465,   minLevel = 1 },
  { id = "sealofright",      name = "Seal of Righteousness",  subspec = "retribution", spell = 20154, minLevel = 1 },
  { id = "judgement",        name = "Judgement",              subspec = "retribution", spell = 20271, minLevel = 4 },
  { id = "blessingofmight",  name = "Blessing of Might",      subspec = "retribution", spell = 19740, minLevel = 4 },
  { id = "sealofcrusader",   name = "Seal of the Crusader",   subspec = "retribution", spell = 21082, minLevel = 6 },
  { id = "divineprotection", name = "Divine Protection",      subspec = "protection",  spell = 498,   minLevel = 6 },
  { id = "purify",           name = "Purify",                 subspec = "holy",        spell = 1152,  minLevel = 8 },
  { id = "hammerofjustice",  name = "Hammer of Justice",      subspec = "protection",  spell = 853,   minLevel = 8 },
  { id = "layonhands",       name = "Lay on Hands",           subspec = "holy",        spell = 633,   minLevel = 10 },
  { id = "blessingofprot",   name = "Blessing of Protection", subspec = "protection",  spell = 1022,  minLevel = 10 },
  { id = "redemption",       name = "Redemption",             subspec = "holy",        spell = 7328,  minLevel = 12 },
  { id = "blessingofwisdom", name = "Blessing of Wisdom",     subspec = "holy",        spell = 19742, minLevel = 14 },
  { id = "righteousfury",    name = "Righteous Fury",         subspec = "protection",  spell = 25780, minLevel = 16 },
  { id = "retributionaura",  name = "Retribution Aura",       subspec = "retribution", spell = 7294,  minLevel = 16 },
  { id = "blessingoffreedom",name = "Blessing of Freedom",    subspec = "protection",  spell = 1044,  minLevel = 18 },
  { id = "flashoflight",     name = "Flash of Light",         subspec = "holy",        spell = 19750, minLevel = 20 },
  { id = "exorcism",         name = "Exorcism",               subspec = "retribution", spell = 879,   minLevel = 20 },
  { id = "senseundead",      name = "Sense Undead",           subspec = "protection",  spell = 5502,  minLevel = 20 },
  { id = "sealofjustice",    name = "Seal of Justice",        subspec = "retribution", spell = 20164, minLevel = 22 },
  { id = "concentrationaura",name = "Concentration Aura",     subspec = "holy",        spell = 19746, minLevel = 22 },
  { id = "turnundead",       name = "Turn Undead",            subspec = "holy",        spell = 2878,  minLevel = 24 },
  { id = "blessingofsalv",   name = "Blessing of Salvation",  subspec = "protection",  spell = 1038,  minLevel = 26 },
  { id = "shadowresaura",    name = "Shadow Resistance Aura", subspec = "protection",  spell = 19876, minLevel = 28 },
  { id = "divineinterv",     name = "Divine Intervention",    subspec = "holy",        spell = 19752, minLevel = 30 },
  { id = "sealoflight",      name = "Seal of Light",          subspec = "holy",        spell = 20165, minLevel = 30 },
  { id = "frostresaura",     name = "Frost Resistance Aura",  subspec = "protection",  spell = 19888, minLevel = 32 },
  { id = "divineshield",     name = "Divine Shield",          subspec = "holy",        spell = 642,   minLevel = 34 },
  { id = "fireresaura",      name = "Fire Resistance Aura",   subspec = "protection",  spell = 19891, minLevel = 36 },
  { id = "sealofwisdom",     name = "Seal of Wisdom",         subspec = "holy",        spell = 20166, minLevel = 38 },
  { id = "blessingoflight",  name = "Blessing of Light",      subspec = "holy",        spell = 19977, minLevel = 40 },
  { id = "summonwarhorse",   name = "Summon Warhorse",        subspec = "retribution", spell = 13819, minLevel = 40 },
  { id = "cleanse",          name = "Cleanse",                subspec = "holy",        spell = 4987,  minLevel = 42 },
  { id = "hammerofwrath",    name = "Hammer of Wrath",        subspec = "retribution", spell = 24275, minLevel = 44 },
  { id = "blessingofsac",    name = "Blessing of Sacrifice",  subspec = "protection",  spell = 6940,  minLevel = 46 },
  { id = "holywrath",        name = "Holy Wrath",             subspec = "holy",        spell = 2812,  minLevel = 50 },
  { id = "gblessingmight",   name = "Greater Blessing of Might",   subspec = "retribution", spell = 25782, minLevel = 52 },
  { id = "gblessingwisdom",  name = "Greater Blessing of Wisdom",  subspec = "holy",        spell = 25894, minLevel = 54 },
  { id = "gblessingkings",   name = "Greater Blessing of Kings",   subspec = "protection",  spell = 25898, minLevel = 60 },
  { id = "gblessinglight",   name = "Greater Blessing of Light",   subspec = "holy",        spell = 25890, minLevel = 60 },
  { id = "gblessingsalv",    name = "Greater Blessing of Salvation", subspec = "protection", spell = 25895, minLevel = 60 },
  { id = "gblessingsanc",    name = "Greater Blessing of Sanctuary", subspec = "protection", spell = 25899, minLevel = 60 },
  { id = "summoncharger",    name = "Summon Charger",         subspec = "retribution", spell = 23214, minLevel = 60 },
  -- TBC (complete new-spell trainer list, verified against Wowhead TBC;
  -- Righteous Defense and Spiritual Attunement are low-level TBC additions)
  { id = "righteousdefense", name = "Righteous Defense",      subspec = "protection",  spell = 31789, icon = ICON .. "INV_Shoulder_37",            minLevel = 14, expansion = 1 },
  { id = "spiritualattune",  name = "Spiritual Attunement",   subspec = "holy",        spell = 31785, icon = ICON .. "Spell_Holy_ReviveChampion",  minLevel = 18, expansion = 1 },
  { id = "crusaderaura",     name = "Crusader Aura",          subspec = "retribution", spell = 32223, icon = ICON .. "Spell_Holy_CrusaderAura",  minLevel = 62, expansion = 1 },
  { id = "sealofblood",      name = "Seal of Blood/Vengeance",subspec = "retribution", spell = 31892, spell2 = 31801, icon = ICON .. "Spell_Holy_SealOfBlood", minLevel = 64, expansion = 1 },
  { id = "avengingwrath",    name = "Avenging Wrath",         subspec = "retribution", spell = 31884, icon = ICON .. "Spell_Holy_AvengineWrath", minLevel = 70, expansion = 1 },
}

-- HUNTER -----------------------------------------------------------------
-- Verified against Wowhead Classic (spell = rank-1 ID, icons auto-resolve)
-- Pet-training spells (Growl, Great Stamina, resistances) are excluded:
-- those are taught to the pet, not the hunter.
TT.licenseAbilityDecks.HUNTER = {
  { id = "raptorstrike",    name = "Raptor Strike",         subspec = "survival",     spell = 2973,  minLevel = 1 },
  { id = "trackbeasts",     name = "Track Beasts",          subspec = "survival",     spell = 1494,  minLevel = 1 },
  { id = "aspectmonkey",    name = "Aspect of the Monkey",  subspec = "survival",     spell = 13163, minLevel = 4 },
  { id = "serpentsting",    name = "Serpent Sting",         subspec = "marksmanship", spell = 1978,  minLevel = 4 },
  { id = "arcaneshot",      name = "Arcane Shot",           subspec = "marksmanship", spell = 3044,  minLevel = 6 },
  { id = "huntersmark",     name = "Hunter's Mark",         subspec = "marksmanship", spell = 1130,  minLevel = 6 },
  { id = "concussiveshot",  name = "Concussive Shot",       subspec = "marksmanship", spell = 5116,  minLevel = 8 },
  { id = "tamebeast",       name = "Tame Beast",            subspec = "beastmastery", spell = 1515,  minLevel = 10 },
  { id = "callpet",         name = "Call Pet",              subspec = "beastmastery", spell = 883,   minLevel = 10 },
  { id = "dismisspet",      name = "Dismiss Pet",           subspec = "beastmastery", spell = 2641,  minLevel = 10 },
  { id = "feedpet",         name = "Feed Pet",              subspec = "beastmastery", spell = 6991,  minLevel = 10 },
  { id = "revivepet",       name = "Revive Pet",            subspec = "beastmastery", spell = 982,   minLevel = 10 },
  { id = "aspecthawk",      name = "Aspect of the Hawk",    subspec = "marksmanship", spell = 13165, minLevel = 10 },
  { id = "trackhumanoids",  name = "Track Humanoids",       subspec = "survival",     spell = 19883, minLevel = 10 },
  { id = "distractingshot", name = "Distracting Shot",      subspec = "marksmanship", spell = 20736, minLevel = 12 },
  { id = "mendpet",         name = "Mend Pet",              subspec = "beastmastery", spell = 136,   minLevel = 12 },
  { id = "wingclip",        name = "Wing Clip",             subspec = "survival",     spell = 2974,  minLevel = 12 },
  { id = "eagleeye",        name = "Eagle Eye",             subspec = "marksmanship", spell = 6197,  minLevel = 14 },
  { id = "eyesofbeast",     name = "Eyes of the Beast",     subspec = "beastmastery", spell = 1002,  minLevel = 14 },
  { id = "scarebeast",      name = "Scare Beast",           subspec = "beastmastery", spell = 1513,  minLevel = 14 },
  { id = "immolationtrap",  name = "Immolation Trap",       subspec = "survival",     spell = 13795, minLevel = 16 },
  { id = "mongoosebite",    name = "Mongoose Bite",         subspec = "survival",     spell = 1495,  minLevel = 16 },
  { id = "multishot",       name = "Multi-Shot",            subspec = "marksmanship", spell = 2643,  minLevel = 18 },
  { id = "trackundead",     name = "Track Undead",          subspec = "survival",     spell = 19884, minLevel = 18 },
  { id = "aspectcheetah",   name = "Aspect of the Cheetah", subspec = "survival",     spell = 5118,  minLevel = 20 },
  { id = "disengage",       name = "Disengage",             subspec = "survival",     spell = 781,   minLevel = 20 },
  { id = "freezingtrap",    name = "Freezing Trap",         subspec = "survival",     spell = 1499,  minLevel = 20 },
  { id = "scorpidsting",    name = "Scorpid Sting",         subspec = "marksmanship", spell = 3043,  minLevel = 22 },
  { id = "beastlore",       name = "Beast Lore",            subspec = "beastmastery", spell = 1462,  minLevel = 24 },
  { id = "trackhidden",     name = "Track Hidden",          subspec = "survival",     spell = 19885, minLevel = 24 },
  { id = "rapidfire",       name = "Rapid Fire",            subspec = "marksmanship", spell = 3045,  minLevel = 26 },
  { id = "trackelementals", name = "Track Elementals",      subspec = "survival",     spell = 19880, minLevel = 26 },
  { id = "frosttrap",       name = "Frost Trap",            subspec = "survival",     spell = 13809, minLevel = 28 },
  { id = "aspectbeast",     name = "Aspect of the Beast",   subspec = "beastmastery", spell = 13161, minLevel = 30 },
  { id = "feigndeath",      name = "Feign Death",           subspec = "survival",     spell = 5384,  minLevel = 30 },
  { id = "flare",           name = "Flare",                 subspec = "survival",     spell = 1543,  minLevel = 32 },
  { id = "trackdemons",     name = "Track Demons",          subspec = "survival",     spell = 19878, minLevel = 32 },
  { id = "explosivetrap",   name = "Explosive Trap",        subspec = "survival",     spell = 13813, minLevel = 34 },
  { id = "vipersting",      name = "Viper Sting",           subspec = "marksmanship", spell = 3034,  minLevel = 36 },
  { id = "aspectpack",      name = "Aspect of the Pack",    subspec = "beastmastery", spell = 13159, minLevel = 40 },
  { id = "trackgiants",     name = "Track Giants",          subspec = "survival",     spell = 19882, minLevel = 40 },
  { id = "volley",          name = "Volley",                subspec = "marksmanship", spell = 1510,  minLevel = 40 },
  { id = "aspectwild",      name = "Aspect of the Wild",    subspec = "beastmastery", spell = 20043, minLevel = 46 },
  { id = "trackdragonkin",  name = "Track Dragonkin",       subspec = "survival",     spell = 19879, minLevel = 50 },
  { id = "tranqshot",       name = "Tranquilizing Shot",    subspec = "marksmanship", spell = 19801, minLevel = 60 },
  -- TBC (complete new-spell trainer list, verified against Wowhead TBC)
  { id = "steadyshot",      name = "Steady Shot",           subspec = "marksmanship", spell = 34120, icon = ICON .. "Ability_Hunter_SteadyShot",        minLevel = 62, expansion = 1 },
  { id = "aspectviper",     name = "Aspect of the Viper",   subspec = "beastmastery", spell = 34074, icon = ICON .. "Ability_Hunter_AspectOfTheViper",  minLevel = 64, expansion = 1 },
  { id = "killcommand",     name = "Kill Command",          subspec = "beastmastery", spell = 34026, icon = ICON .. "Ability_Hunter_KillCommand",       minLevel = 66, expansion = 1 },
  { id = "snaketrap",       name = "Snake Trap",            subspec = "survival",     spell = 34600, icon = ICON .. "Ability_Hunter_SnakeTrap",         minLevel = 68, expansion = 1 },
  { id = "misdirection",    name = "Misdirection",          subspec = "marksmanship", spell = 34477, icon = ICON .. "Ability_Hunter_Misdirection",      minLevel = 70, expansion = 1 },
}

-- ROGUE ------------------------------------------------------------------
-- Verified against Wowhead Classic (spell = rank-1 ID, icons auto-resolve)
-- Poison ranks (Instant Poison II etc.) collapse into one card per poison.
TT.licenseAbilityDecks.ROGUE = {
  { id = "sinisterstrike", name = "Sinister Strike",    subspec = "combat",        spell = 1752,  minLevel = 1 },
  { id = "eviscerate",     name = "Eviscerate",         subspec = "assassination", spell = 2098,  minLevel = 1 },
  { id = "stealth",        name = "Stealth",            subspec = "subtlety",      spell = 1784,  minLevel = 1 },
  { id = "backstab",       name = "Backstab",           subspec = "assassination", spell = 53,    minLevel = 4 },
  { id = "pickpocket",     name = "Pick Pocket",        subspec = "subtlety",      spell = 921,   minLevel = 4 },
  { id = "gouge",          name = "Gouge",              subspec = "combat",        spell = 1776,  minLevel = 6 },
  { id = "evasion",        name = "Evasion",            subspec = "combat",        spell = 5277,  minLevel = 8 },
  { id = "sap",            name = "Sap",                subspec = "subtlety",      spell = 6770,  minLevel = 10 },
  { id = "sprint",         name = "Sprint",             subspec = "combat",        spell = 2983,  minLevel = 10 },
  { id = "sliceanddice",   name = "Slice and Dice",     subspec = "assassination", spell = 5171,  minLevel = 10 },
  { id = "kick",           name = "Kick",               subspec = "combat",        spell = 1766,  minLevel = 12 },
  { id = "garrote",        name = "Garrote",            subspec = "assassination", spell = 703,   minLevel = 14 },
  { id = "exposearmor",    name = "Expose Armor",       subspec = "assassination", spell = 8647,  minLevel = 14 },
  { id = "feint",          name = "Feint",              subspec = "subtlety",      spell = 1966,  minLevel = 16 },
  -- Pick Lock's spell data says level 1, but trainers gate it at 16
  { id = "picklock",       name = "Pick Lock",          subspec = "subtlety",      spell = 1804,  minLevel = 16 },
  { id = "ambush",         name = "Ambush",             subspec = "subtlety",      spell = 8676,  minLevel = 18 },
  { id = "poisons",        name = "Poisons",            subspec = "assassination", spell = 2842,  minLevel = 20 },
  { id = "cripplingpoison",name = "Crippling Poison",   subspec = "assassination", spell = 3420,  minLevel = 20 },
  { id = "instantpoison",  name = "Instant Poison",     subspec = "assassination", spell = 8681,  minLevel = 20 },
  { id = "rupture",        name = "Rupture",            subspec = "assassination", spell = 1943,  minLevel = 20 },
  { id = "distract",       name = "Distract",           subspec = "subtlety",      spell = 1725,  minLevel = 22 },
  { id = "vanish",         name = "Vanish",             subspec = "subtlety",      spell = 1856,  minLevel = 22 },
  { id = "detecttraps",    name = "Detect Traps",       subspec = "subtlety",      spell = 2836,  minLevel = 24 },
  { id = "mindnumbing",    name = "Mind-numbing Poison",subspec = "assassination", spell = 5763,  minLevel = 24 },
  { id = "cheapshot",      name = "Cheap Shot",         subspec = "subtlety",      spell = 1833,  minLevel = 26 },
  { id = "deadlypoison",   name = "Deadly Poison",      subspec = "assassination", spell = 2835,  minLevel = 30 },
  { id = "disarmtrap",     name = "Disarm Trap",        subspec = "subtlety",      spell = 1842,  minLevel = 30 },
  { id = "kidneyshot",     name = "Kidney Shot",        subspec = "assassination", spell = 408,   minLevel = 30 },
  { id = "woundpoison",    name = "Wound Poison",       subspec = "assassination", spell = 13220, minLevel = 32 },
  { id = "blind",          name = "Blind",              subspec = "subtlety",      spell = 2094,  minLevel = 34 },
  { id = "safefall",       name = "Safe Fall",          subspec = "subtlety",      spell = 1860,  minLevel = 40 },
  -- TBC (complete new-spell trainer list, verified against Wowhead TBC)
  { id = "envenom",        name = "Envenom",            subspec = "assassination", spell = 32645, icon = ICON .. "Ability_Rogue_Disembowel",  minLevel = 62, expansion = 1 },
  { id = "deadlythrow",    name = "Deadly Throw",       subspec = "combat",        spell = 26679, icon = ICON .. "INV_ThrowingKnife_06",      minLevel = 64, expansion = 1 },
  { id = "cloakofshadows", name = "Cloak of Shadows",   subspec = "subtlety",      spell = 31224, icon = ICON .. "Spell_Shadow_NetherCloak",  minLevel = 66, expansion = 1 },
  { id = "anestheticpoison", name = "Anesthetic Poison", subspec = "assassination", spell = 26785, icon = ICON .. "Spell_Nature_SlowPoison",  minLevel = 68, expansion = 1 },
  { id = "shiv",           name = "Shiv",               subspec = "combat",        spell = 5938,  icon = ICON .. "INV_ThrowingKnife_04",      minLevel = 70, expansion = 1 },
}

-- PRIEST -----------------------------------------------------------------
-- Verified against Wowhead Classic (spell = rank-1 ID, icons auto-resolve)
-- Race-specific priest spells (Fear Ward, Starshards, etc.) are excluded.
TT.licenseAbilityDecks.PRIEST = {
  { id = "smite",           name = "Smite",                subspec = "holy",       spell = 585,   minLevel = 1 },
  { id = "lesserheal",      name = "Lesser Heal",          subspec = "holy",       spell = 2050,  minLevel = 1 },
  { id = "pwfortitude",     name = "Power Word: Fortitude",        subspec = "discipline", spell = 1243,  minLevel = 1 },
  { id = "swpain",          name = "Shadow Word: Pain",             subspec = "shadow",     spell = 589,   minLevel = 4 },
  { id = "pwshield",        name = "Power Word: Shield",           subspec = "discipline", spell = 17,    minLevel = 6 },
  { id = "renew",           name = "Renew",                subspec = "holy",       spell = 139,   minLevel = 8 },
  { id = "fade",            name = "Fade",                 subspec = "shadow",     spell = 586,   minLevel = 8 },
  { id = "mindblast",       name = "Mind Blast",           subspec = "shadow",     spell = 8092,  minLevel = 10 },
  { id = "resurrection",    name = "Resurrection",         subspec = "holy",       spell = 2006,  minLevel = 10 },
  { id = "innerfire",       name = "Inner Fire",           subspec = "discipline", spell = 588,   minLevel = 12 },
  { id = "psychicscream",   name = "Psychic Scream",       subspec = "shadow",     spell = 8122,  minLevel = 14 },
  { id = "curedisease",     name = "Cure Disease",         subspec = "holy",       spell = 528,   minLevel = 14 },
  { id = "heal",            name = "Heal",                 subspec = "holy",       spell = 2054,  minLevel = 16 },
  { id = "dispelmagic",     name = "Dispel Magic",         subspec = "discipline", spell = 527,   minLevel = 18 },
  { id = "flashheal",       name = "Flash Heal",           subspec = "holy",       spell = 2061,  minLevel = 20 },
  { id = "holyfire",        name = "Holy Fire",            subspec = "holy",       spell = 14914, minLevel = 20 },
  { id = "mindsoothe",      name = "Mind Soothe",          subspec = "shadow",     spell = 453,   minLevel = 20 },
  { id = "shackleundead",   name = "Shackle Undead",       subspec = "discipline", spell = 9484,  minLevel = 20 },
  { id = "mindvision",      name = "Mind Vision",          subspec = "shadow",     spell = 2096,  minLevel = 22 },
  { id = "manaburn",        name = "Mana Burn",            subspec = "discipline", spell = 8129,  minLevel = 24 },
  { id = "prayerofhealing", name = "Prayer of Healing",    subspec = "holy",       spell = 596,   minLevel = 30 },
  { id = "mindcontrol",     name = "Mind Control",         subspec = "shadow",     spell = 605,   minLevel = 30 },
  { id = "shadowprotection",name = "Shadow Protection",    subspec = "discipline", spell = 976,   minLevel = 30 },
  { id = "abolishdisease",  name = "Abolish Disease",      subspec = "holy",       spell = 552,   minLevel = 32 },
  { id = "levitate",        name = "Levitate",             subspec = "discipline", spell = 1706,  minLevel = 34 },
  { id = "greaterheal",     name = "Greater Heal",         subspec = "holy",       spell = 2060,  minLevel = 40 },
  { id = "prayerfortitude", name = "Prayer of Fortitude",  subspec = "discipline", spell = 21562, minLevel = 48 },
  { id = "prayershadowprot",name = "Prayer of Shadow Protection",subspec = "discipline", spell = 27683, minLevel = 56 },
  { id = "prayerspirit",    name = "Prayer of Spirit",     subspec = "discipline", spell = 27681, minLevel = 60 },
  -- TBC (complete new-spell trainer list, verified against Wowhead TBC)
  { id = "swdeath",         name = "Shadow Word: Death",   subspec = "shadow",     spell = 32379, icon = ICON .. "Spell_Shadow_DemonicFortitude", minLevel = 62, expansion = 1 },
  { id = "bindingheal",     name = "Binding Heal",         subspec = "holy",       spell = 32546, icon = ICON .. "Spell_Holy_BlindingHeal",       minLevel = 64, expansion = 1 },
  { id = "shadowfiend",     name = "Shadowfiend",          subspec = "shadow",     spell = 34433, icon = ICON .. "Spell_Shadow_Shadowfiend",      minLevel = 66, expansion = 1 },
  { id = "prayerofmending", name = "Prayer of Mending",    subspec = "holy",       spell = 33076, icon = ICON .. "Spell_Holy_PrayerOfMendingtga", minLevel = 68, expansion = 1 },
  { id = "massdispel",      name = "Mass Dispel",          subspec = "discipline", spell = 32375, icon = ICON .. "Spell_Arcane_MassDispel",       minLevel = 70, expansion = 1 },
}

-- MAGE -------------------------------------------------------------------
-- Verified against Wowhead Classic (spell = rank-1 ID, icons auto-resolve)
-- Teleports and portals stay collapsed into one generic card each.
TT.licenseAbilityDecks.MAGE = {
  { id = "fireball",        name = "Fireball",             subspec = "fire",   spell = 133,   minLevel = 1 },
  { id = "arcaneintellect", name = "Arcane Intellect",     subspec = "arcane", spell = 1459,  minLevel = 1 },
  { id = "frostarmor",      name = "Frost Armor",          subspec = "frost",  spell = 168,   minLevel = 1 },
  { id = "frostbolt",       name = "Frostbolt",            subspec = "frost",  spell = 116,   minLevel = 4 },
  { id = "conjurewater",    name = "Conjure Water",        subspec = "arcane", spell = 5504,  minLevel = 4 },
  { id = "fireblast",       name = "Fire Blast",           subspec = "fire",   spell = 2136,  minLevel = 6 },
  { id = "conjurefood",     name = "Conjure Food",         subspec = "arcane", spell = 587,   minLevel = 6 },
  { id = "arcanemissiles",  name = "Arcane Missiles",      subspec = "arcane", spell = 5143,  minLevel = 8 },
  { id = "polymorph",       name = "Polymorph",            subspec = "arcane", spell = 118,   minLevel = 8 },
  { id = "frostnova",       name = "Frost Nova",           subspec = "frost",  spell = 122,   minLevel = 10 },
  { id = "dampenmagic",     name = "Dampen Magic",         subspec = "arcane", spell = 604,   minLevel = 12 },
  { id = "slowfall",        name = "Slow Fall",            subspec = "arcane", spell = 130,   minLevel = 12 },
  { id = "arcaneexplosion", name = "Arcane Explosion",     subspec = "arcane", spell = 1449,  minLevel = 14 },
  { id = "detectmagic",     name = "Detect Magic",         subspec = "arcane", spell = 2855,  minLevel = 16 },
  { id = "flamestrike",     name = "Flamestrike",          subspec = "fire",   spell = 2120,  minLevel = 16 },
  { id = "amplifymagic",    name = "Amplify Magic",        subspec = "arcane", spell = 1008,  minLevel = 18 },
  { id = "removecurse",     name = "Remove Lesser Curse",  subspec = "arcane", spell = 475,   minLevel = 18 },
  { id = "blink",           name = "Blink",                subspec = "arcane", spell = 1953,  minLevel = 20 },
  { id = "blizzard",        name = "Blizzard",             subspec = "frost",  spell = 10,    minLevel = 20 },
  { id = "manashield",      name = "Mana Shield",          subspec = "arcane", spell = 1463,  minLevel = 20 },
  { id = "teleport",        name = "Teleport",             subspec = "arcane", spell = 3561,  minLevel = 20 },
  { id = "evocation",       name = "Evocation",            subspec = "arcane", spell = 12051, minLevel = 20 },
  { id = "fireward",        name = "Fire Ward",            subspec = "fire",   spell = 543,   minLevel = 20 },
  { id = "scorch",          name = "Scorch",               subspec = "fire",   spell = 2948,  minLevel = 22 },
  { id = "frostward",       name = "Frost Ward",           subspec = "frost",  spell = 6143,  minLevel = 22 },
  { id = "counterspell",    name = "Counterspell",         subspec = "arcane", spell = 2139,  minLevel = 24 },
  { id = "coneofcold",      name = "Cone of Cold",         subspec = "frost",  spell = 120,   minLevel = 26 },
  { id = "conjuremanaagate",name = "Conjure Mana Agate",   subspec = "arcane", spell = 759,   minLevel = 28 },
  { id = "icearmor",        name = "Ice Armor",            subspec = "frost",  spell = 7302,  minLevel = 30 },
  { id = "magearmor",       name = "Mage Armor",           subspec = "arcane", spell = 6117,  minLevel = 34 },
  { id = "conjuremanajade", name = "Conjure Mana Jade",    subspec = "arcane", spell = 3552,  minLevel = 38 },
  { id = "portal",          name = "Portal",               subspec = "arcane", spell = 10059, minLevel = 40 },
  { id = "conjuremanacitrine", name = "Conjure Mana Citrine", subspec = "arcane", spell = 10053, minLevel = 48 },
  { id = "arcanebrilliance",name = "Arcane Brilliance",    subspec = "arcane", spell = 23028, minLevel = 56 },
  { id = "conjuremanaruby", name = "Conjure Mana Ruby",    subspec = "arcane", spell = 10054, minLevel = 58 },
  { id = "polycow",         name = "Polymorph: Cow",       subspec = "arcane", spell = 28270, minLevel = 60 },
  -- TBC (complete new-spell trainer list, verified against Wowhead TBC)
  { id = "moltenarmor",     name = "Molten Armor",         subspec = "fire",   spell = 30482, icon = ICON .. "Ability_Mage_MoltenArmor",  minLevel = 62, expansion = 1 },
  { id = "arcaneblast",     name = "Arcane Blast",         subspec = "arcane", spell = 30451, icon = ICON .. "Spell_Arcane_Blast",        minLevel = 64, expansion = 1 },
  { id = "icelance",        name = "Ice Lance",            subspec = "frost",  spell = 30455, icon = ICON .. "Spell_Frost_FrostBlast",    minLevel = 66, expansion = 1 },
  { id = "invisibility",    name = "Invisibility",         subspec = "arcane", spell = 66,    icon = ICON .. "Ability_Mage_Invisibility", minLevel = 68, expansion = 1 },
  { id = "conjuremanaemerald", name = "Conjure Mana Emerald", subspec = "arcane", spell = 27101, icon = ICON .. "INV_Misc_Gem_Stone_01",  minLevel = 68, expansion = 1 },
  { id = "spellsteal",      name = "Spellsteal",           subspec = "arcane", spell = 30449, icon = ICON .. "Spell_Arcane_Arcane02",     minLevel = 70, expansion = 1 },
  { id = "ritualofrefreshment", name = "Ritual of Refreshment", subspec = "arcane", spell = 43987, icon = ICON .. "Spell_Arcane_MassDispel", minLevel = 70, expansion = 1 },
}

-- WARLOCK ----------------------------------------------------------------
-- Verified against Wowhead Classic (spell = rank-1 ID, icons auto-resolve)
-- Stone-creation tiers (Minor/Lesser/etc.) collapse into one card each;
-- Detect Invisibility tiers collapse into one card at 26.
TT.licenseAbilityDecks.WARLOCK = {
  { id = "demonskin",       name = "Demon Skin",           subspec = "demonology",  spell = 687,   minLevel = 1 },
  { id = "shadowbolt",      name = "Shadow Bolt",          subspec = "destruction", spell = 686,   minLevel = 1 },
  { id = "summonimp",       name = "Summon Imp",           subspec = "demonology",  spell = 688,   minLevel = 1 },
  { id = "immolate",        name = "Immolate",             subspec = "destruction", spell = 348,   minLevel = 1 },
  { id = "corruption",      name = "Corruption",           subspec = "affliction",  spell = 172,   minLevel = 4 },
  { id = "curseofweakness", name = "Curse of Weakness",    subspec = "affliction",  spell = 702,   minLevel = 4 },
  { id = "lifetap",         name = "Life Tap",             subspec = "affliction",  spell = 1454,  minLevel = 6 },
  { id = "curseofagony",    name = "Curse of Agony",       subspec = "affliction",  spell = 980,   minLevel = 8 },
  { id = "fear",            name = "Fear",                 subspec = "affliction",  spell = 5782,  minLevel = 8 },
  { id = "createhealthstone",name = "Create Healthstone",  subspec = "demonology",  spell = 6201,  minLevel = 10 },
  { id = "drainsoul",       name = "Drain Soul",           subspec = "affliction",  spell = 1120,  minLevel = 10 },
  { id = "summonvoidwalker",name = "Summon Voidwalker",    subspec = "demonology",  spell = 697,   minLevel = 10 },
  { id = "healthfunnel",    name = "Health Funnel",        subspec = "demonology",  spell = 755,   minLevel = 12 },
  { id = "curseofreck",     name = "Curse of Recklessness",subspec = "affliction",  spell = 704,   minLevel = 14 },
  { id = "drainlife",       name = "Drain Life",           subspec = "affliction",  spell = 689,   minLevel = 14 },
  { id = "unendingbreath",  name = "Unending Breath",      subspec = "demonology",  spell = 5697,  minLevel = 16 },
  { id = "createsoulstone", name = "Create Soulstone",     subspec = "demonology",  spell = 693,   minLevel = 18 },
  { id = "searingpain",     name = "Searing Pain",         subspec = "destruction", spell = 5676,  minLevel = 18 },
  { id = "demonarmor",      name = "Demon Armor",          subspec = "demonology",  spell = 706,   minLevel = 20 },
  { id = "rainoffire",      name = "Rain of Fire",         subspec = "destruction", spell = 5740,  minLevel = 20 },
  { id = "ritualofsummon",  name = "Ritual of Summoning",  subspec = "demonology",  spell = 698,   minLevel = 20 },
  { id = "summonsuccubus",  name = "Summon Succubus",      subspec = "demonology",  spell = 712,   minLevel = 20 },
  { id = "eyeofkilrogg",    name = "Eye of Kilrogg",       subspec = "demonology",  spell = 126,   minLevel = 22 },
  { id = "drainmana",       name = "Drain Mana",           subspec = "affliction",  spell = 5138,  minLevel = 24 },
  { id = "sensedemons",     name = "Sense Demons",         subspec = "demonology",  spell = 5500,  minLevel = 24 },
  { id = "curseoftongues",  name = "Curse of Tongues",     subspec = "affliction",  spell = 1714,  minLevel = 26 },
  { id = "detectinvis",     name = "Detect Invisibility",  subspec = "demonology",  spell = 132,   minLevel = 26 },
  { id = "banish",          name = "Banish",               subspec = "demonology",  spell = 710,   minLevel = 28 },
  { id = "createfirestone", name = "Create Firestone",     subspec = "demonology",  spell = 6366,  minLevel = 28 },
  { id = "hellfire",        name = "Hellfire",             subspec = "destruction", spell = 1949,  minLevel = 30 },
  { id = "subjugatedemon",  name = "Subjugate Demon",      subspec = "demonology",  spell = 1098,  minLevel = 30 },
  { id = "summonfelhunter", name = "Summon Felhunter",     subspec = "demonology",  spell = 691,   minLevel = 30 },
  { id = "curseofelements", name = "Curse of the Elements",subspec = "affliction",  spell = 1490,  minLevel = 32 },
  { id = "shadowward",      name = "Shadow Ward",          subspec = "destruction", spell = 6229,  minLevel = 32 },
  { id = "createspellstone",name = "Create Spellstone",    subspec = "demonology",  spell = 2362,  minLevel = 36 },
  { id = "howlofterror",    name = "Howl of Terror",       subspec = "affliction",  spell = 5484,  minLevel = 40 },
  { id = "summonfelsteed",  name = "Summon Felsteed",      subspec = "demonology",  spell = 5784,  minLevel = 40 },
  { id = "deathcoil",       name = "Death Coil",           subspec = "affliction",  spell = 6789,  minLevel = 42 },
  { id = "curseofshadow",   name = "Curse of Shadow",      subspec = "affliction",  spell = 17862, minLevel = 44 },
  { id = "soulfire",        name = "Soul Fire",            subspec = "destruction", spell = 6353,  minLevel = 48 },
  { id = "inferno",         name = "Inferno",              subspec = "destruction", spell = 1122,  minLevel = 50 },
  { id = "curseofdoom",     name = "Curse of Doom",        subspec = "affliction",  spell = 603,   minLevel = 60 },
  { id = "ritualofdoom",    name = "Ritual of Doom",       subspec = "demonology",  spell = 18540, minLevel = 60 },
  { id = "summondreadsteed",name = "Summon Dreadsteed",    subspec = "demonology",  spell = 23161, minLevel = 60 },
  -- TBC (complete new-spell trainer list, verified against Wowhead TBC)
  { id = "felarmor",        name = "Fel Armor",            subspec = "demonology",  spell = 28176, icon = ICON .. "Spell_Shadow_FelArmour",         minLevel = 62, expansion = 1 },
  { id = "incinerate",      name = "Incinerate",           subspec = "destruction", spell = 29722, icon = ICON .. "Spell_Fire_Burnout",             minLevel = 64, expansion = 1 },
  { id = "soulshatter",     name = "Soulshatter",          subspec = "demonology",  spell = 29858, icon = ICON .. "Spell_Arcane_Arcane01",          minLevel = 66, expansion = 1 },
  { id = "ritualofsouls",   name = "Ritual of Souls",      subspec = "demonology",  spell = 29893, icon = ICON .. "Spell_Shadow_ShadesOfDarkness",  minLevel = 68, expansion = 1 },
  { id = "seedofcorruption",name = "Seed of Corruption",   subspec = "affliction",  spell = 27243, icon = ICON .. "Spell_Shadow_SeedOfDestruction", minLevel = 70, expansion = 1 },
}

-- DRUID ------------------------------------------------------------------
-- Verified against Wowhead Classic (spell = rank-1 ID, icons auto-resolve)
TT.licenseAbilityDecks.DRUID = {
  { id = "wrath",           name = "Wrath",               subspec = "balance",     spell = 5176,  minLevel = 1 },
  { id = "healingtouch",    name = "Healing Touch",       subspec = "restoration", spell = 5185,  minLevel = 1 },
  { id = "markofthewild",   name = "Mark of the Wild",    subspec = "restoration", spell = 1126,  minLevel = 1 },
  { id = "moonfire",        name = "Moonfire",            subspec = "balance",     spell = 8921,  minLevel = 4 },
  { id = "rejuvenation",    name = "Rejuvenation",        subspec = "restoration", spell = 774,   minLevel = 4 },
  { id = "thorns",          name = "Thorns",              subspec = "balance",     spell = 467,   minLevel = 6 },
  { id = "entanglingroots", name = "Entangling Roots",    subspec = "balance",     spell = 339,   minLevel = 8 },
  { id = "bearform",        name = "Bear Form",           subspec = "feral",       spell = 5487,  minLevel = 10 },
  { id = "maul",            name = "Maul",                subspec = "feral",       spell = 6807,  minLevel = 10 },
  { id = "demoroar",        name = "Demoralizing Roar",   subspec = "feral",       spell = 99,    minLevel = 10 },
  { id = "growl",           name = "Growl",               subspec = "feral",       spell = 6795,  minLevel = 10 },
  { id = "teleportmoonglade",name = "Teleport: Moonglade",subspec = "balance",     spell = 18960, minLevel = 10 },
  { id = "enrage",          name = "Enrage",              subspec = "feral",       spell = 5229,  minLevel = 12 },
  { id = "regrowth",        name = "Regrowth",            subspec = "restoration", spell = 8936,  minLevel = 12 },
  { id = "bash",            name = "Bash",                subspec = "feral",       spell = 5211,  minLevel = 14 },
  { id = "curepoison",      name = "Cure Poison",         subspec = "restoration", spell = 8946,  minLevel = 14 },
  { id = "aquaticform",     name = "Aquatic Form",        subspec = "feral",       spell = 1066,  minLevel = 16 },
  { id = "swipe",           name = "Swipe",               subspec = "feral",       spell = 779,   minLevel = 16 },
  { id = "faeriefire",      name = "Faerie Fire",         subspec = "balance",     spell = 770,   minLevel = 18 },
  { id = "hibernate",       name = "Hibernate",           subspec = "balance",     spell = 2637,  minLevel = 18 },
  { id = "catform",         name = "Cat Form",            subspec = "feral",       spell = 768,   minLevel = 20 },
  { id = "claw",            name = "Claw",                subspec = "feral",       spell = 1082,  minLevel = 20 },
  { id = "prowl",           name = "Prowl",               subspec = "feral",       spell = 5215,  minLevel = 20 },
  { id = "rip",             name = "Rip",                 subspec = "feral",       spell = 1079,  minLevel = 20 },
  { id = "rebirth",         name = "Rebirth",             subspec = "restoration", spell = 20484, minLevel = 20 },
  { id = "starfire",        name = "Starfire",            subspec = "balance",     spell = 2912,  minLevel = 20 },
  { id = "shred",           name = "Shred",               subspec = "feral",       spell = 5221,  minLevel = 22 },
  { id = "sootheanimal",    name = "Soothe Animal",       subspec = "balance",     spell = 2908,  minLevel = 22 },
  { id = "rake",            name = "Rake",                subspec = "feral",       spell = 1822,  minLevel = 24 },
  { id = "removecurse",     name = "Remove Curse",        subspec = "restoration", spell = 2782,  minLevel = 24 },
  { id = "tigersfury",      name = "Tiger's Fury",        subspec = "feral",       spell = 5217,  minLevel = 24 },
  { id = "abolishpoison",   name = "Abolish Poison",      subspec = "restoration", spell = 2893,  minLevel = 26 },
  { id = "dash",            name = "Dash",                subspec = "feral",       spell = 1850,  minLevel = 26 },
  { id = "challengingroar", name = "Challenging Roar",    subspec = "feral",       spell = 5209,  minLevel = 28 },
  { id = "cower",           name = "Cower",               subspec = "feral",       spell = 8998,  minLevel = 28 },
  { id = "tranquility",     name = "Tranquility",         subspec = "restoration", spell = 740,   minLevel = 30 },
  { id = "travelform",      name = "Travel Form",         subspec = "feral",       spell = 783,   minLevel = 30 },
  { id = "ferociousbite",   name = "Ferocious Bite",      subspec = "feral",       spell = 22568, minLevel = 32 },
  { id = "ravage",          name = "Ravage",              subspec = "feral",       spell = 6785,  minLevel = 32 },
  { id = "trackhumanoids",  name = "Track Humanoids",     subspec = "feral",       spell = 5225,  minLevel = 32 },
  { id = "frenziedregen",   name = "Frenzied Regeneration", subspec = "feral",     spell = 22842, minLevel = 36 },
  { id = "pounce",          name = "Pounce",              subspec = "feral",       spell = 9005,  minLevel = 36 },
  { id = "direbearform",    name = "Dire Bear Form",      subspec = "feral",       spell = 9634,  minLevel = 40 },
  { id = "felinegrace",     name = "Feline Grace",        subspec = "feral",       spell = 20719, minLevel = 40 },
  { id = "hurricane",       name = "Hurricane",           subspec = "balance",     spell = 16914, minLevel = 40 },
  { id = "innervate",       name = "Innervate",           subspec = "restoration", spell = 29166, minLevel = 40 },
  { id = "barkskin",        name = "Barkskin",            subspec = "balance",     spell = 22812, minLevel = 44 },
  { id = "giftofthewild",   name = "Gift of the Wild",    subspec = "restoration", spell = 21849, minLevel = 50 },
  -- TBC (complete new-spell trainer list, verified against Wowhead TBC;
  -- Swift Flight Form comes from the level-70 Anzu quest chain)
  { id = "maim",            name = "Maim",                subspec = "feral",       spell = 22570, icon = ICON .. "Ability_Druid_Mangle2",    minLevel = 62, expansion = 1 },
  { id = "lifebloom",       name = "Lifebloom",           subspec = "restoration", spell = 33763, icon = ICON .. "INV_Misc_Herb_Felblossom", minLevel = 64, expansion = 1 },
  { id = "lacerate",        name = "Lacerate",            subspec = "feral",       spell = 33745, icon = ICON .. "Ability_Druid_Lacerate",   minLevel = 66, expansion = 1 },
  { id = "flightform",      name = "Flight Form",         subspec = "feral",       spell = 33943, icon = ICON .. "Ability_Druid_FlightForm", minLevel = 68, expansion = 1 },
  { id = "cyclone",         name = "Cyclone",             subspec = "balance",     spell = 33786, icon = ICON .. "Spell_Nature_EarthBind",   minLevel = 70, expansion = 1 },
  { id = "swiftflightform", name = "Swift Flight Form",   subspec = "feral",       spell = 40120, icon = ICON .. "Ability_Druid_FlightForm", minLevel = 70, expansion = 1 },
}

---------------------------------------------------------------------------
-- Bonus-draw checkboxes (profession levels + misc goals)
---------------------------------------------------------------------------

-- Each checked box banks 1 bonus draw. Boxes with a `skill` or `auto`
-- field are auto-detected by Core and can't be hand-toggled while
-- enforcement is on; boxes with `honor = true` stay self-reported
-- (no reliable API exists for them on these clients).

TT.goalEnchantBoxes = {
  { id = "enchant-75",  label = "75",  name = "Enchanting 75",  skill = "enchanting", threshold = 75 },
  { id = "enchant-150", label = "150", name = "Enchanting 150", skill = "enchanting", threshold = 150 },
  { id = "enchant-225", label = "225", name = "Enchanting 225", skill = "enchanting", threshold = 225 },
  { id = "enchant-300", label = "300", name = "Enchanting 300", skill = "enchanting", threshold = 300 },
  { id = "enchant-375", label = "375", name = "Enchanting 375", skill = "enchanting", threshold = 375 },
}

TT.goalJcBoxes = {
  { id = "jc-75",  label = "75",  name = "Jewelcrafting 75",  skill = "jewelcrafting", threshold = 75 },
  { id = "jc-150", label = "150", name = "Jewelcrafting 150", skill = "jewelcrafting", threshold = 150 },
  { id = "jc-225", label = "225", name = "Jewelcrafting 225", skill = "jewelcrafting", threshold = 225 },
  { id = "jc-300", label = "300", name = "Jewelcrafting 300", skill = "jewelcrafting", threshold = 300 },
  { id = "jc-375", label = "375", name = "Jewelcrafting 375", skill = "jewelcrafting", threshold = 375 },
}

-- Some ids don't match their labels (misc-dire-mauls etc): the ids are
-- saved-variable keys from v1 and must stay stable; labels are current.
-- NPC ids verified against Wowhead (classic + TBC databases).
TT.goalMiscBoxes = {
  { id = "misc-exalted-rep",   label = "Exalted Rep",      name = "Exalted Rep",
    desc = "Reach Exalted with any faction.",                        auto = "rep" },
  { id = "misc-1k-hk",         label = "1k HK",            name = "1k Honorable Kills",
    desc = "Earn 1,000 lifetime honorable kills.",                   auto = "hk" },
  { id = "misc-mongoose",      label = "Big Game Hunter",  name = "Big Game Hunter",
    desc = "Kill King Bangalash in Stranglethorn Vale.",             auto = "kill", npcs = { 731 } },
  { id = "misc-dire-mauls",    label = "Kill Illidan",     name = "Kill Illidan",
    desc = "Kill Illidan Stormrage in the Black Temple.",            auto = "kill", npcs = { 22917 } },
  { id = "misc-classic-dungs", label = "Epic Weapons",     name = "Epic Weapons",
    desc = "Have an epic-quality weapon equipped.",                  auto = "equip" },
  { id = "misc-tbc-dungs",     label = "Explore Outlands", name = "Explore Outlands",
    desc = "Fully explore every Outland zone.",                      honor = true },
  { id = "misc-kara",          label = "Kara",             name = "Karazhan",
    desc = "Kill Prince Malchezaar in Karazhan.",                    auto = "kill", npcs = { 15690 } },
  { id = "misc-pet",           label = "Pet",              name = "Vanity Pet",
    desc = "Own a vanity pet.",                                      honor = true },
  { id = "misc-epic-flier",    label = "Epic Flier",       name = "Epic Flier",
    desc = "Reach Riding skill 300 (epic flying).",                  auto = "skill" },
  { id = "misc-world-boss",    label = "World Boss",       name = "World Boss",
    desc = "Kill any world boss (Azuregos, Kazzak, an emerald dragon, Doom Lord Kazzak or Doomwalker).",
    auto = "kill", npcs = { 6109, 12397, 14887, 14888, 14889, 14890, 18728, 17711 } },
  { id = "misc-tbc-heroics",   label = "TBC Heroics",      name = "TBC Heroics",
    desc = "Clear every TBC dungeon on Heroic difficulty.",          auto = "heroics" },
}

-- id -> box across all three groups (labels for messages, enforcement
-- checks for manual toggles)
TT.goalBoxIndex = {}
for _, group in ipairs({ TT.goalEnchantBoxes, TT.goalJcBoxes, TT.goalMiscBoxes }) do
  for _, box in ipairs(group) do
    TT.goalBoxIndex[box.id] = box
  end
end

-- npcId -> misc goal id, for combat-log goal detection
TT.goalKills = {}
for _, box in ipairs(TT.goalMiscBoxes) do
  if box.npcs then
    for _, id in ipairs(box.npcs) do
      TT.goalKills[id] = box.id
    end
  end
end

---------------------------------------------------------------------------
-- Deck assembly: shared cards + the player's class abilities. Mirrors
-- DeckLocked's BuildDeck, with the per-class Ranged/Relic retune.
---------------------------------------------------------------------------

local GENERIC_SPECS = {
  { key = "spec1", label = "Abilities" },
  { key = "spec2", label = "" },
  { key = "spec3", label = "" },
}

TT.licenseById = {}

function TT.BuildLicenseDeck(classToken)
  TT.licenseClass = classToken
  TT.licenseSpecList = TT.licenseSpecs[classToken] or GENERIC_SPECS

  TT.licenseCards = {}
  for _, card in ipairs(TT.licenseShared) do
    if card.slot == "relic" then
      card.minLevel = TT.LICENSE.relicMinLevel[classToken] or 50
    end
    TT.licenseCards[#TT.licenseCards + 1] = card
  end

  local abilities = TT.licenseAbilityDecks[classToken]
  if abilities then
    for _, card in ipairs(abilities) do
      card.type = "ability"
      TT.licenseCards[#TT.licenseCards + 1] = card
    end
  end

  TT.licenseById = {}
  for _, card in ipairs(TT.licenseCards) do
    TT.licenseById[card.id] = card
  end
end

-- Expansion gating: cards carry expansion = 0 (Classic, the default) or 1
-- (TBC); anything above this client's expansion never appears.
function TT.IsLicenseGated(card)
  return (card.expansion or 0) > TT.EXPANSION
end

---------------------------------------------------------------------------
-- Icon resolution + category registration
---------------------------------------------------------------------------

local GetItemIconCompat = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local GetSpellTextureCompat = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture

function TT.GetLicenseIcon(card)
  if card.spell then
    local tex = GetSpellTextureCompat and GetSpellTextureCompat(card.spell)
    if tex then return tex end
  end
  if card.item then
    local tex = GetItemIconCompat and GetItemIconCompat(card.item)
    if tex then return tex end
  end
  if card.invSlot then
    local _, tex = GetInventorySlotInfo(card.invSlot)
    if tex then return tex end
  end
  return card.icon or TT.QUESTION_MARK
end

-- License cards render through the same card-face pipeline as pool cards,
-- but they are NOT pool rows: they never enter TT.pool, packs, the binder
-- or trading. This category entry exists for UI dispatch only.
TT.RegisterCategory("license", {
  label = "Licenses",
  GetIconNow = function(card) return TT.GetLicenseIcon(card) end,
  GetNameNow = function(card) return card.name end,
  LockCheck = nil,
})

---------------------------------------------------------------------------
-- Dungeon tracker (Challenge/League). Names match TT.FINAL_BOSSES values,
-- so kill detection is just a TT.FINAL_BOSSES lookup; the Bonus rows are
-- derived from full groups and have no bosses of their own.
---------------------------------------------------------------------------

TT.DUNGEONS_ERA = {
  "Ragefire Chasm", "Wailing Caverns", "The Deadmines", "Shadowfang Keep",
  "Blackfathom Deeps", "The Stockade", "Gnomeregan", "Razorfen Kraul",
  "SM Graveyard", "SM Library", "SM Armory", "SM Cathedral", "SM Bonus",
  "Razorfen Downs", "Uldaman", "Zul'Farrak", "Maraudon", "Sunken Temple",
  "Blackrock Depths", "Lower Blackrock Spire", "Upper Blackrock Spire",
  "Dire Maul East", "Dire Maul West", "Dire Maul North", "Stratholme",
  "Scholomance", "Classic Bonus",
}

TT.DUNGEONS_TBC = {
  "Hellfire Ramparts", "The Blood Furnace", "The Slave Pens", "The Underbog",
  "Mana-Tombs", "Auchenai Crypts", "Old Hillsbrad", "Sethekk Halls",
  "The Steamvault", "Shadow Labyrinth", "The Shattered Halls",
  "The Black Morass", "The Botanica", "The Mechanar", "The Arcatraz",
  "TBC Bonus",
}

-- derived rows: completing every member completes the bonus row
TT.DUNGEON_BONUS = {
  ["SM Bonus"] = { "SM Graveyard", "SM Library", "SM Armory", "SM Cathedral" },
  -- filled below: every non-bonus era / tbc dungeon
  ["Classic Bonus"] = {},
  ["TBC Bonus"] = {},
}
for _, name in ipairs(TT.DUNGEONS_ERA) do
  if not TT.DUNGEON_BONUS[name] then
    local t = TT.DUNGEON_BONUS["Classic Bonus"]
    t[#t + 1] = name
  end
end
for _, name in ipairs(TT.DUNGEONS_TBC) do
  if not TT.DUNGEON_BONUS[name] then
    local t = TT.DUNGEON_BONUS["TBC Bonus"]
    t[#t + 1] = name
  end
end

-- the real (non-derived) TBC dungeons, for the heroics goal
TT.HEROIC_DUNGEONS = {}
for _, name in ipairs(TT.DUNGEONS_TBC) do
  if name ~= "TBC Bonus" then
    TT.HEROIC_DUNGEONS[#TT.HEROIC_DUNGEONS + 1] = name
  end
end
