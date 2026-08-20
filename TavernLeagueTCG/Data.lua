-- Tavern League TCG: client detection, economy config, rarity tables and
-- the card-category registry. Pure data + tiny helpers; no state lives here.

local ADDON, TT = ...

---------------------------------------------------------------------------
-- Client detection (Classic Era vs TBC Anniversary)
---------------------------------------------------------------------------

TT.IS_TBC = (WOW_PROJECT_ID ~= nil and WOW_PROJECT_BURNING_CRUSADE_CLASSIC ~= nil
  and WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC)
if not TT.IS_TBC then
  local major = tonumber((strsplit(".", (GetBuildInfo()))))
  TT.IS_TBC = (major ~= nil and major >= 2)
end

TT.EXPANSION = TT.IS_TBC and 1 or 0   -- 0 = Classic Era, 1 = TBC
TT.MAX_LEVEL = TT.IS_TBC and 70 or 60

-- true if this pool row should be excluded on the current client
function TT.IsGated(row)
  return (row.x or 0) > TT.EXPANSION
end

---------------------------------------------------------------------------
-- Economy: every tunable knob in one place
---------------------------------------------------------------------------

TT.ECON = {
  packPrice        = 2500,
  cardsPerPack     = 8,       -- last slot is the climax card

  -- credit sources
  creditsPerXP     = 0.15,    -- per XP point earned
  levelUpBonus     = 25,      -- * newLevel on ding
  killBase         = 2,       -- * mobLevel per killing blow
  killUnknownLevel = 1,       -- * playerLevel when the mob's level is unknown
  questBase        = 100,     -- flat per quest turn-in
  questPerLevel    = 10,      -- * playerLevel per quest turn-in
  skillPerPoint    = 0.5,     -- * the rank reached, per skill point gained
                              -- (weapon skills, defense, professions,
                              --  cooking/fishing/first aid - not reputation)

  -- endgame faucets
  dungeonBossBounty = 1500,   -- final boss of a dungeon (id table below)
  raidBossBounty    = 2500,   -- any ?? world/raid boss you fight
  honorKill         = 35,     -- per honorable kill (the game's own honor rules gate this)

  -- dusting & crafting (shards): dust a SPARE copy, craft a missing card
  dustValue    = { 5, 20, 100, 400, 1600 },   -- shards per dusted spare, by tier
  craftCost    = { 20, 80, 400, 1600, 8000 }, -- shards to craft a card, by tier
  foilDustMult = 4,                            -- foil spares dust for 4x

  -- pack odds: per-slot rarity weights out of 1000
  slotOdds  = { 650, 250, 80, 20, 0 },     -- slots 1-7 (common..legendary)
  bonusOdds = { 0, 600, 300, 90, 10 },     -- slot 8: guaranteed uncommon+
  foilChance = 20,            -- 1 in N per card
  godChance  = 250,           -- 1 in N packs: every slot on bonusOdds, all foil
  pityEpic   = 10,            -- slot 8 forced epic+ if none in the last N packs
}

---------------------------------------------------------------------------
-- Dungeon final bosses (npcId -> dungeon). Killing one pays the dungeon
-- bounty; the first bounty boss each day also banks a free pack. Raid and
-- world bosses need no table - any ?? "worldboss" unit you fight pays the
-- raid bounty. IDs verified in DeckLocked.
---------------------------------------------------------------------------

TT.FINAL_BOSSES = {
  -- Classic Era
  [11518] = "Ragefire Chasm", [11519] = "Ragefire Chasm", [11520] = "Ragefire Chasm",
  [3654]  = "Wailing Caverns",
  [639]   = "The Deadmines",
  [4275]  = "Shadowfang Keep",
  [4829]  = "Blackfathom Deeps",
  [1716]  = "The Stockade",
  [7800]  = "Gnomeregan",
  [4421]  = "Razorfen Kraul",
  [4543]  = "SM Graveyard",
  [6487]  = "SM Library",
  [3975]  = "SM Armory",
  [3977]  = "SM Cathedral", [3976] = "SM Cathedral",
  [7358]  = "Razorfen Downs",
  [2748]  = "Uldaman",
  [7267]  = "Zul'Farrak",
  [12201] = "Maraudon",
  [5709]  = "Sunken Temple",
  [9019]  = "Blackrock Depths",
  [9568]  = "Lower Blackrock Spire",
  [10363] = "Upper Blackrock Spire",
  [11492] = "Dire Maul East",
  [11486] = "Dire Maul West",
  [11501] = "Dire Maul North",
  [10440] = "Stratholme", [10813] = "Stratholme",
  [1853]  = "Scholomance",
  -- TBC (inert on Classic Era clients)
  [17536] = "Hellfire Ramparts", [17537] = "Hellfire Ramparts",
  [17377] = "The Blood Furnace",
  [17942] = "The Slave Pens",
  [17882] = "The Underbog",
  [18344] = "Mana-Tombs",
  [18373] = "Auchenai Crypts",
  [18096] = "Old Hillsbrad",
  [18473] = "Sethekk Halls",
  [17798] = "The Steamvault",
  [18708] = "Shadow Labyrinth",
  [16808] = "The Shattered Halls",
  [17881] = "The Black Morass",
  [17977] = "The Botanica",
  [19220] = "The Mechanar",
  [20912] = "The Arcatraz",
}

---------------------------------------------------------------------------
-- Rarity tiers
---------------------------------------------------------------------------

TT.RARITY = {
  [1] = { key = "common",    label = "Common",    color = { 0.92, 0.92, 0.92 } },
  [2] = { key = "uncommon",  label = "Uncommon",  color = { 0.12, 1.00, 0.00 } },
  [3] = { key = "rare",      label = "Rare",      color = { 0.00, 0.44, 0.87 } },
  [4] = { key = "epic",      label = "Epic",      color = { 0.64, 0.21, 0.93 } },
  [5] = { key = "legendary", label = "Legendary", color = { 1.00, 0.50, 0.00 } },
}
TT.MAX_RARITY = 5

function TT.RarityColor(tier)
  local r = TT.RARITY[tier] or TT.RARITY[1]
  return r.color[1], r.color[2], r.color[3]
end

function TT.RarityLabel(tier)
  local r = TT.RARITY[tier]
  return r and r.label or "?"
end

---------------------------------------------------------------------------
-- Card categories: v1 ships "item"; creatures/bosses/NPCs/professions plug
-- in here later without touching the pack, binder or ledger code.
---------------------------------------------------------------------------

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

TT.categories = {}

function TT.RegisterCategory(kind, def)
  TT.categories[kind] = def
end

TT.RegisterCategory("item", {
  label = "Items & Gear",
  -- cache-independent: icon + class/slot always resolve instantly
  GetIconNow = function(row)
    local _, _, _, _, icon = GetItemInfoInstant(row.i)
    return icon
  end,
  -- names ship inside CardPool.lua; the item cache is only a fallback
  GetNameNow = function(row)
    return row.n or (GetItemInfoCompat(row.i))
  end,
  LockCheck = "equip",
})

-- Namespaced card keys so future kinds never collide: "item:16846"
function TT.CardKey(row)
  return (row.kind or "item") .. ":" .. row.i
end

function TT.ParseKey(key)
  local kind, id = key:match("^(%a+):(%d+)$")
  return kind, tonumber(id)
end

-- Slot bucket for the binder filter, derived at runtime (nothing stored in
-- the pool). itemClassID: 2 = Weapon, 4 = Armor, 7 = Trade Goods.
function TT.SlotBucket(row)
  local _, _, _, _, _, classID = GetItemInfoInstant(row.i)
  if classID == 2 then return "weapon"
  elseif classID == 4 then return "armor"
  elseif classID == 7 then return "trade"
  end
  return "other"
end

TT.SLOT_BUCKETS = {
  { key = "all",    label = "All Types" },
  { key = "weapon", label = "Weapons" },
  { key = "armor",  label = "Armor" },
  { key = "trade",  label = "Trade Goods" },
}

---------------------------------------------------------------------------
-- Misc constants
---------------------------------------------------------------------------

TT.QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
TT.CARD_BACK_ICON = "Interface\\Icons\\INV_Misc_Ticket_Tarot_Stack_01"  -- minimap/tab icon
TT.CARD_BACK_TEX = "Interface\\AddOns\\TavernLeagueTCG\\art\\cardback"  -- the card back art
