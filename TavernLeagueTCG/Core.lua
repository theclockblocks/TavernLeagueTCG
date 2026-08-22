-- Tavern League TCG core: saved variables, the profile resolver, the
-- credits engine, the pack engine, the contribution ledger and comms.
-- UI.lua and Enforce.lua read state through TT and call these functions.

local ADDON, TT = ...

---------------------------------------------------------------------------
-- Saved state: two files.
--   TavernLeagueTCGDB       (account-wide) - realm + hardmode profiles
--   TavernLeagueTCGCharDB   (per character) - toon-local bookkeeping
---------------------------------------------------------------------------

-- Adding a profile key? TT.DisableHardmode merges hardmode profiles into
-- the realm run field by field - new keys need an explicit merge line
-- there or they silently vanish when a toon leaves Hardmode.
local profileDefaults = {
  credits = 0,
  freePacks = 0,        -- banked packs from level-ups; consumed before credits
  stats = { xp = 0, kills = 0, quests = 0, levels = 0, packs = 0, gods = 0,
    bosses = 0, honor = 0, sold = 0, trades = 0, drafts = 0 },
  collection = {},      -- [cardKey] = { n = count, f = foilCount }
  firstSeen = {},       -- [cardKey] = time() of first pull
  fresh = {},           -- [cardKey] = true until viewed in the binder (NEW badge)
  pendingPack = nil,    -- set by RollPack, cleared by FinishPack
  pity = 0,             -- packs since the last epic+ pull
  lockedMode = false,
  lockedModeAt = nil,
  violations = {},      -- newest-first, capped: violations + mode/roster events
  roster = {},          -- [charName] = { guid, lastSeen, level, creditsEarned, packsOpened, retired }
  contributions = {},   -- [charName] = { [cardKey] = { n, f } }
}

local charDefaults = {
  hardmode = false,
  hardmodeAt = nil,
  grandfathered = {},   -- [itemId] = true, equipped when this toon first saw the lock
  lockSeen = false,     -- grandfather snapshot taken
  lastXP = nil,
  lastXPMax = nil,
  skillRanks = {},      -- [skillName] = last seen rank (diff base for skill credits)
  retroPacks = false,   -- one-time level-catchup pack grant done
  runs = {},            -- [runKey] = this character's license-layer state (TT.Run)
  retroLicense = {},    -- [format] = true, one-time draw/draft catch-up done
  minimapAngle = 200,
  minimapHide = false,
  binder = { own = "all", rarity = 0, bucket = "all", search = "", page = 1 },
}

local function applyDefaults(tbl, defaults)
  for k, v in pairs(defaults) do
    if tbl[k] == nil then
      if type(v) == "table" then
        tbl[k] = {}
        applyDefaults(tbl[k], v)
      else
        tbl[k] = v
      end
    elseif type(v) == "table" and type(tbl[k]) == "table" then
      applyDefaults(tbl[k], v)
    end
  end
end

function TT.InitDB()
  TavernLeagueTCGDB = TavernLeagueTCGDB or {}
  local db = TavernLeagueTCGDB
  db.schema = db.schema or 1
  db.realms = db.realms or {}
  db.hardmode = db.hardmode or {}
  TT.db = db

  TavernLeagueTCGCharDB = TavernLeagueTCGCharDB or {}
  applyDefaults(TavernLeagueTCGCharDB, charDefaults)
  TavernLeagueTCGCharDB.schema = TavernLeagueTCGCharDB.schema or 1
  TT.cdb = TavernLeagueTCGCharDB

  TT.MigrateDB()
end

-- Schema migrations: additive only, idempotent, and no v1 key is ever
-- renamed or deleted - a downgraded client must still find its data.
function TT.MigrateDB()
  local db, cdb = TT.db, TT.cdb
  if db.schema < 2 then
    -- formats arrived in 0.5.0; every pre-existing run IS the old game
    for _, bucket in pairs({ db.realms, db.hardmode }) do
      for _, p in pairs(bucket) do
        p.format = p.format or "collection"
      end
    end
    db.schema = 2
  end
  if cdb.schema < 2 then
    cdb.runs = cdb.runs or {}
    -- 0.5.0 turns warn-only item locks into hard enforcement; the amnesty
    -- (consumed in SetupForPlayer) re-grandfathers what this character is
    -- wearing so the upgrade never strips anyone on login
    cdb.amnestyPending = true
    cdb.schema = 2
  end
end

local function ensureProfile(bucket, key)
  bucket[key] = bucket[key] or {}
  applyDefaults(bucket[key], profileDefaults)
  bucket[key].project = TT.EXPANSION
  return bucket[key]
end

-- Every game system reads/writes TT.Profile() only; whether that is the
-- shared realm run or this toon's isolated Hardmode run is invisible to it.
function TT.Profile()
  if TT.cdb and TT.cdb.hardmode then
    return ensureProfile(TT.db.hardmode, TT.RealmKey() .. "-" .. UnitName("player"))
  end
  return ensureProfile(TT.db.realms, TT.RealmKey())
end

function TT.RealmKey()
  return GetRealmName() or "Unknown Realm"
end

function TT.ProfileLabel()
  if TT.cdb and TT.cdb.hardmode then
    return "Hardmode: " .. TT.RealmKey() .. "-" .. (UnitName("player") or "?")
  end
  return "Realm: " .. TT.RealmKey()
end

---------------------------------------------------------------------------
-- Per-character run state (the license layer). The binder is shared per
-- realm, but permissions are earned per character: TT.Run() is this
-- character's license progress for the ACTIVE run. Never cache the result -
-- hardmode toggles change which run is active mid-session.
---------------------------------------------------------------------------

local runDefaults = {
  drawn = {},            -- [licenseCardId] = true, every license taken
  unlocked = {},         -- [boxKey] = true ("head", "bag-2", "talent-4", "cooking", ...)
  drawCredits = 0,       -- Challenge: banked 3-card draws
  bonusDraws = 0,        -- Challenge: goal payouts
  draftPacks = 0,        -- League: banked draft packs
  eligibleSince = {},    -- [licenseCardId] = level it first became eligible
  packsSinceUsable = 0,  -- internal pack-roll bookkeeping
  goals = {},            -- [goalId] = true
  dungeons = {},         -- [dungeonName] = true
  dungeonsHeroic = {},   -- [dungeonName] = true (TBC heroic clears)
  -- pendingDraw / pendingDraft persist an in-progress draw or draft pack
  -- across relogs (no defaults: absent until one is live)
}

function TT.RunKey()
  if TT.cdb and TT.cdb.hardmode then
    return "hard:" .. TT.RealmKey() .. "-" .. (UnitName("player") or "?")
  end
  return "realm:" .. TT.RealmKey()
end

local seededRuns = {}   -- session cache: default-fill each run once

function TT.Run()
  local runs = TT.cdb.runs
  local key = TT.RunKey()
  runs[key] = runs[key] or {}
  if not seededRuns[key] then
    applyDefaults(runs[key], runDefaults)
    seededRuns[key] = true
  end
  return runs[key]
end

-- The format is picked once, when a run begins, and is immutable: a
-- different format means a new Hardmode run or a retired profile.
function TT.SetFormat(fmt)
  local p = TT.Profile()
  if p.format ~= nil or not TT.FORMATS[fmt] then return false end
  p.format = fmt
  TT.LogEvent("event", ("%s chose the %s format for %s."):format(
    UnitName("player") or "?", TT.FORMATS[fmt].label, TT.ProfileLabel()))
  TT.Msg(("Format locked in: |cffffd100%s|r."):format(TT.FORMATS[fmt].label))
  -- the catch-up grants and goal scans waited for the format decision
  TT.GrantRetroPacks()
  if TT.GrantRetroLicenses then TT.GrantRetroLicenses() end
  if TT.RunGoalScans and C_Timer and C_Timer.After then
    C_Timer.After(0.2, function() TT.RunGoalScans(true) end)
  end
  TT.Refresh()
  return true
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

function TT.Msg(text)
  print("|cffffd100TavernLeague:|r " .. text)
end

function TT.Warn(text)
  if UIErrorsFrame then
    UIErrorsFrame:AddMessage(text, 1, 0.3, 0.3)
  end
  TT.Msg(text)
end

-- kit: a SOUNDKIT constant name, or a raw soundkit id for sounds that
-- have no constant (see TT.SOUND_* in Data.lua)
local function playSound(kit)
  if not PlaySound then return end
  if type(kit) == "number" then
    PlaySound(kit)
  elseif SOUNDKIT and SOUNDKIT[kit] then
    PlaySound(SOUNDKIT[kit])
  end
end
TT.PlaySoundKit = playSound

function TT.FormatNumber(n)
  n = math.floor(n or 0)
  local s = tostring(n)
  local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (formatted:gsub("^,", ""))
end

-- Log an event or violation into the profile's newest-first ring buffer.
function TT.LogEvent(kind, text, extra)
  local p = TT.Profile()
  local entry = { t = time(), char = UnitName("player"), kind = kind, text = text }
  if extra then
    for k, v in pairs(extra) do entry[k] = v end
  end
  table.insert(p.violations, 1, entry)
  for i = #p.violations, 101, -1 do
    table.remove(p.violations, i)
  end
end

---------------------------------------------------------------------------
-- Pool indexes (skip rows gated to a later expansion than this client)
---------------------------------------------------------------------------

function TT.BuildPoolIndex()
  TT.cardIndex = {}     -- [cardKey] = row
  TT.poolByType = {}    -- [packType][tier] = { row, ... }
  TT.poolCount = 0
  for _, ptype in ipairs(TT.PACK_TYPES) do
    TT.poolByType[ptype.key] = {}
    for tier = 1, TT.MAX_RARITY do TT.poolByType[ptype.key][tier] = {} end
  end
  for _, row in ipairs(TT.pool or {}) do
    if not TT.IsGated(row) then
      TT.cardIndex[TT.CardKey(row)] = row
      local byTier = TT.poolByType[TT.PackTypeOf(row)]
      local bucket = byTier[row.r] or byTier[1]
      bucket[#bucket + 1] = row
      -- wild packs draw from the entire pool
      local wild = TT.poolByType.wild[row.r] or TT.poolByType.wild[1]
      wild[#wild + 1] = row
      TT.poolCount = TT.poolCount + 1
    end
  end
end

function TT.OwnedCounts()
  local p = TT.Profile()
  local owned, foils = 0, 0
  for key, c in pairs(p.collection) do
    if TT.cardIndex[key] and (c.n or 0) + (c.f or 0) > 0 then
      owned = owned + 1
      if (c.f or 0) > 0 then foils = foils + 1 end
    end
  end
  return owned, foils
end

function TT.IsCardOwned(key)
  local c = TT.Profile().collection[key]
  return c ~= nil and ((c.n or 0) + (c.f or 0)) > 0
end

---------------------------------------------------------------------------
-- Item name cache: icons are instant, names may need a server round-trip.
---------------------------------------------------------------------------

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local RequestLoadItem = C_Item and C_Item.RequestLoadItemDataByID
local pendingNames = {}   -- [itemId] = true, waiting on GET_ITEM_INFO_RECEIVED
local pendingCount = 0
local MAX_INFLIGHT = 50

-- Returns the item name if cached; otherwise queues a load and returns nil.
function TT.ItemName(itemId)
  local name = GetItemInfoCompat(itemId)
  if name then return name end
  if not pendingNames[itemId] and pendingCount < MAX_INFLIGHT then
    pendingNames[itemId] = true
    pendingCount = pendingCount + 1
    if RequestLoadItem then
      RequestLoadItem(itemId)
    else
      -- ancient-client fallback: poke the tooltip cache
      if not TT.probeTip then
        TT.probeTip = CreateFrame("GameTooltip", "TavernLeagueTCGProbeTip", nil, "GameTooltipTemplate")
        TT.probeTip:SetOwner(UIParent, "ANCHOR_NONE")
      end
      pcall(TT.probeTip.SetItemByID, TT.probeTip, itemId)
    end
    -- dropped responses must not clog the queue forever: free the slot
    -- after a beat so a later call retries
    if C_Timer and C_Timer.After then
      C_Timer.After(2, function()
        if pendingNames[itemId] then
          pendingNames[itemId] = nil
          pendingCount = math.max(0, pendingCount - 1)
        end
      end)
    end
  end
  return nil
end

-- Warm the item cache for a list of pool rows (binder pages call this so
-- tooltips are ready before the player hovers).
function TT.PrefetchItems(rows)
  for _, row in ipairs(rows) do
    if row.i then TT.ItemName(row.i) end
  end
end

function TT.OnItemInfoReceived(itemId, success)
  if itemId and pendingNames[itemId] then
    pendingNames[itemId] = nil
    pendingCount = math.max(0, pendingCount - 1)
    if TT.UI_OnItemCached then TT.UI_OnItemCached(itemId) end
  end
end

---------------------------------------------------------------------------
-- Roster + contribution ledger (delete-reroll protection)
---------------------------------------------------------------------------

function TT.RegisterRoster()
  local p = TT.Profile()
  local name = UnitName("player")
  local guid = UnitGUID("player")
  local entry = p.roster[name]

  if entry and entry.guid and guid and entry.guid ~= guid and not entry.retired then
    -- Same name, different character: the old toon was provably deleted.
    TT.Msg("|cffff4444Roster:|r a previous '" .. name .. "' was deleted. Revoking their pulled cards.")
    TT.RevokeContributions(name, "deleted (name re-used)")
    entry = nil
  end

  if not entry then
    entry = { guid = guid, creditsEarned = 0, packsOpened = 0 }
    p.roster[name] = entry
  end
  entry.guid = guid
  entry.lastSeen = time()
  entry.level = UnitLevel("player")
  entry.retired = nil
end

function TT.AddContribution(charName, key, foil)
  local p = TT.Profile()
  p.contributions[charName] = p.contributions[charName] or {}
  local c = p.contributions[charName][key] or { n = 0, f = 0 }
  if foil then c.f = c.f + 1 else c.n = c.n + 1 end
  p.contributions[charName][key] = c
end

-- Attribution follows physical cards: when copies leave the collection
-- (trade, sell), reduce the acting character's ledger first, then anyone's.
function TT.LedgerRemove(p, charName, key, foil, amount)
  local field = foil and "f" or "n"
  local function take(led, n)
    local c = led and led[key]
    if not c then return n end
    local used = math.min(c[field] or 0, n)
    c[field] = (c[field] or 0) - used
    if (c.n or 0) <= 0 and (c.f or 0) <= 0 then led[key] = nil end
    return n - used
  end
  local left = take(p.contributions[charName], amount)
  if left > 0 then
    for other, led in pairs(p.contributions) do
      if other ~= charName and left > 0 then
        left = take(led, left)
      end
    end
  end
end

-- Remove exactly the cards a toon pulled from the shared collection.
function TT.RevokeContributions(charName, why)
  local p = TT.Profile()
  local led = p.contributions[charName]
  local removed = 0
  if led then
    for key, c in pairs(led) do
      local col = p.collection[key]
      if col then
        col.n = math.max(0, (col.n or 0) - (c.n or 0))
        col.f = math.max(0, (col.f or 0) - (c.f or 0))
        removed = removed + (c.n or 0) + (c.f or 0)
        if col.n == 0 and col.f == 0 then
          p.collection[key] = nil
          p.firstSeen[key] = nil
          p.fresh[key] = nil
        end
      end
    end
    p.contributions[charName] = nil
  end
  if p.roster[charName] then
    p.roster[charName].retired = true
  end
  TT.LogEvent("event", charName .. " removed from the run (" .. (why or "retired") ..
    "): " .. removed .. " card(s) revoked.")
  TT.Msg("Revoked " .. removed .. " card(s) pulled by " .. charName .. ".")
  TT.Refresh()
end

function TT.PrintRoster()
  local p = TT.Profile()
  TT.Msg("Roster for " .. TT.ProfileLabel() .. ":")
  local any = false
  for name, e in pairs(p.roster) do
    any = true
    local pulls = 0
    for _, c in pairs(p.contributions[name] or {}) do
      pulls = pulls + (c.n or 0) + (c.f or 0)
    end
    TT.Msg(("  %s%s - lvl %s, %s credits earned, %s packs, %s cards pulled"):format(
      name, e.retired and " |cffff4444(retired)|r" or "",
      e.level or "?", TT.FormatNumber(e.creditsEarned or 0), e.packsOpened or 0, pulls))
  end
  if not any then TT.Msg("  (empty)") end
end

---------------------------------------------------------------------------
-- Credits engine
---------------------------------------------------------------------------

local creditBlip = 0  -- prints a chat line for every ~500 earned

function TT.AddCredits(amount, source)
  if not TT.FormatFlag("credits") then return end   -- Challenge has no economy
  amount = math.floor(amount)
  if amount <= 0 then return end
  local p = TT.Profile()
  p.credits = p.credits + amount
  p.stats[source] = (p.stats[source] or 0) + amount

  local name = UnitName("player")
  if p.roster[name] then
    p.roster[name].creditsEarned = (p.roster[name].creditsEarned or 0) + amount
  end

  creditBlip = creditBlip + amount
  if creditBlip >= 500 then
    creditBlip = 0
    TT.Msg("Credits: |cffffd100" .. TT.FormatNumber(p.credits) .. "|r (+" ..
      TT.FormatNumber(amount) .. " from " .. source .. ")")
  end
  TT.Refresh()
end

function TT.OnXPUpdate()
  local cdb = TT.cdb
  local newXP = UnitXP("player")
  local newMax = UnitXPMax("player")
  if cdb.lastXP == nil then
    cdb.lastXP, cdb.lastXPMax = newXP, newMax
    return
  end
  local delta
  if newXP >= cdb.lastXP then
    delta = newXP - cdb.lastXP
  else
    -- leveled: remainder of the old bar plus progress into the new one
    delta = (cdb.lastXPMax - cdb.lastXP) + newXP
  end
  cdb.lastXP, cdb.lastXPMax = newXP, newMax
  if delta > 0 and delta < 1000000 then
    TT.AddCredits(delta * TT.ECON.creditsPerXP, "xp")
  end
end

function TT.OnLevelUp(newLevel)
  TT.AddCredits(TT.ECON.levelUpBonus * (newLevel or UnitLevel("player") or 1), "levels")
  local p = TT.Profile()
  local name = UnitName("player")
  if p.roster[name] then p.roster[name].level = newLevel end
  if TT.FormatFlag("packs") then
    -- every character level grants a full pack (60-70 packs per toon leveled;
    -- the contribution ledger keeps delete-reroll farming revocable)
    p.freePacks = (p.freePacks or 0) + 1
    TT.Msg(("Ding! Level %s - |cffffd100you earned a card pack!|r (%d banked)"):format(
      tostring(newLevel or "?"), p.freePacks))
  end
  -- license formats: a draw (Challenge) or a draft pack (League) per ding
  if TT.OnLevelUpLicenses then TT.OnLevelUpLicenses(newLevel) end
  TT.Refresh()
end

function TT.OnQuestTurnedIn()
  TT.AddCredits(TT.ECON.questBase + TT.ECON.questPerLevel * (UnitLevel("player") or 1), "quests")
end

-- Skill credits: weapon skills, defense, and primary/secondary professions
-- all live in the skill-lines API (reputation is a separate system and is
-- deliberately not tracked). We diff ranks against a per-character snapshot
-- and pay per point, scaled by the rank reached - the higher the skill,
-- the more each point is worth.
function TT.OnSkillsChanged()
  if not GetNumSkillLines or not GetSkillLineInfo then return end
  local ranks = TT.cdb.skillRanks
  local seeding = (next(ranks) == nil)
  local total = 0
  local lastSkill, lastRank

  for i = 1, GetNumSkillLines() do
    local name, isHeader, _, rank = GetSkillLineInfo(i)
    if name and not isHeader and type(rank) == "number" and rank > 0 then
      local old = ranks[name]
      -- newly learned skills are recorded silently (no credits for training
      -- something at the trainer); only genuine rank-ups pay out
      if not seeding and old and rank > old then
        for pt = old + 1, rank do
          total = total + TT.ECON.skillPerPoint * pt
        end
        lastSkill, lastRank = name, rank
      end
      ranks[name] = rank
    end
  end

  if total >= 1 then
    TT.AddCredits(total, "skills")
    if lastSkill then
      TT.Msg(("Skill up! %s %d (+%s credits)"):format(
        lastSkill, lastRank, TT.FormatNumber(total)))
    end
  end
end

-- Mob levels are not in the combat log: harvest them from unit tokens.
-- ?? "worldboss" units are flagged for the raid bounty at the same time.
local guidLevels = {}
local bossGuids = {}
local paidBosses = {}

function TT.HarvestUnitLevel(unit)
  if not unit or not UnitExists(unit) or UnitIsPlayer(unit) then return end
  local guid = UnitGUID(unit)
  if not guid or not guid:match("^Creature") then return end
  local level = UnitLevel(unit)
  if level and level > 0 then
    guidLevels[guid] = level
  elseif level == -1 then
    -- boss/skull mob: worth more than anything we can see
    guidLevels[guid] = (UnitLevel("player") or 1) + 5
    if UnitClassification(unit) == "worldboss" then
      bossGuids[guid] = true
    end
  end
end

function TT.WipeUnitLevels()
  wipe(guidLevels)
  wipe(bossGuids)
  wipe(paidBosses)
end

-- A qualifying boss died: pay the bounty, and the first one each day also
-- banks a free pack.
local function BossBounty(amount, label)
  if not TT.FormatFlag("packs") then return end   -- a pack-economy faucet
  TT.AddCredits(amount, "bosses")
  local p = TT.Profile()
  local today = date("%Y-%m-%d")
  local daily = ""
  if p.lastDailyPack ~= today then
    p.lastDailyPack = today
    p.freePacks = (p.freePacks or 0) + 1
    daily = "  |cffffd100First boss of the day: +1 card pack!|r"
  end
  TT.Msg(("Boss bounty: +%s credits%s%s"):format(TT.FormatNumber(amount),
    label and (" - " .. label) or "", daily))
  TT.Refresh()
end
TT.BossBounty = BossBounty  -- local Dev.lua uses this for test bounties

function TT.OnCombatLogEvent()
  local _, subevent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
  if not destGUID or not destGUID:match("^Creature") then return end

  if subevent == "PARTY_KILL" then
    local npcId = tonumber((select(6, strsplit("-", destGUID))))
    -- bosses are paid via UNIT_DIED; no kill credit on top
    if npcId and TT.FINAL_BOSSES[npcId] then return end
    if bossGuids[destGUID] then return end
    local level = guidLevels[destGUID]
    local credits
    if level then
      credits = TT.ECON.killBase * level
    else
      credits = TT.ECON.killUnknownLevel * (UnitLevel("player") or 1)
    end
    guidLevels[destGUID] = nil
    TT.AddCredits(credits, "kills")

  elseif subevent == "UNIT_DIED" then
    local npcId = tonumber((select(6, strsplit("-", destGUID))))
    -- goal/dungeon detection is idempotent and must see every death -
    -- including repeat kills of a boss the bounty already paid (a normal
    -- clear followed by a heroic clear, say)
    if npcId and TT.Goals_OnKill then TT.Goals_OnKill(npcId) end
    if paidBosses[destGUID] then return end
    local dungeon = npcId and TT.FINAL_BOSSES[npcId]
    if dungeon then
      paidBosses[destGUID] = true
      BossBounty(TT.ECON.dungeonBossBounty, dungeon)
    elseif bossGuids[destGUID] and UnitAffectingCombat("player") then
      -- ?? boss we harvested, and we're actually fighting - not spectating
      paidBosses[destGUID] = true
      BossBounty(TT.ECON.raidBossBounty, "boss kill")
    end
  end
end

-- Honorable kills: diff the game's own session HK counter, so the game's
-- honor rules (level ranges, no grey farming) decide what counts.
local sessionHK = nil

function TT.SeedHonorKills()
  if GetPVPSessionStats then
    sessionHK = GetPVPSessionStats()
  end
end

function TT.OnPvpKillsChanged()
  if not GetPVPSessionStats then return end
  local hk = GetPVPSessionStats()
  if sessionHK ~= nil and hk and hk > sessionHK then
    TT.AddCredits((hk - sessionHK) * TT.ECON.honorKill, "honor")
  end
  sessionHK = hk
end

---------------------------------------------------------------------------
-- Selling duplicates: a spare copy sells back for credits, so every
-- duplicate pull still funds the next pack. The last copy is protected.
---------------------------------------------------------------------------

function TT.SellCard(key, foil)
  local p = TT.Profile()
  local row = TT.cardIndex[key]
  local col = p.collection[key]
  if not row or not col then return end
  local field = foil and "f" or "n"
  if (col[field] or 0) < 1 then
    TT.Msg(foil and "No foil copy of that card to sell." or "No normal copy of that card to sell.")
    return
  end
  if ((col.n or 0) + (col.f or 0)) <= 1 then
    TT.Msg("That's your last copy - selling always keeps at least one.")
    return
  end
  col[field] = col[field] - 1
  TT.LedgerRemove(p, UnitName("player"), key, foil, 1)
  local credits = TT.ECON.sellValue[row.r] * (foil and TT.ECON.foilSellMult or 1)
  p.credits = p.credits + credits
  p.stats.sold = (p.stats.sold or 0) + 1
  TT.PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
  TT.Msg(("Sold %s%s: +%s credits (%s total)."):format(
    foil and "foil " or "", row.n or key, TT.FormatNumber(credits),
    TT.FormatNumber(p.credits)))
  TT.Refresh()
end

---------------------------------------------------------------------------
-- Pack engine. Buying pays and persists an UNOPENED pack; the player then
-- picks a pack TYPE (Equipment / Trade Goods / Creatures) and the contents
-- roll from that type's pool, persisting immediately - so the pick is a
-- real choice, nothing is rolled before it, and relogging at any stage
-- resumes exactly where you were with nothing to reroll.
---------------------------------------------------------------------------

local function rollTier(odds)
  local roll = math.random(1000)
  local acc = 0
  for tier = 1, TT.MAX_RARITY do
    acc = acc + (odds[tier] or 0)
    if roll <= acc then return tier end
  end
  return 1
end

---------------------------------------------------------------------------
-- Which gear-slot license permits an item, by inventory type. Slots the
-- license deck doesn't gate (shirts, tabards) map to nothing. Shared with
-- the enforcement layer for the League equip rule.
---------------------------------------------------------------------------

TT.INVTYPE_LICENSES = {
  INVTYPE_HEAD = { "head" }, INVTYPE_NECK = { "neck" },
  INVTYPE_SHOULDER = { "shoulders" }, INVTYPE_CLOAK = { "back" },
  INVTYPE_CHEST = { "chest" }, INVTYPE_ROBE = { "chest" },
  INVTYPE_WRIST = { "wrists" }, INVTYPE_HAND = { "hands" },
  INVTYPE_WAIST = { "waist" }, INVTYPE_LEGS = { "legs" },
  INVTYPE_FEET = { "feet" },
  INVTYPE_FINGER = { "ring1", "ring2" },
  INVTYPE_TRINKET = { "trinket1", "trinket2" },
  INVTYPE_WEAPON = { "mainhand" }, INVTYPE_WEAPONMAINHAND = { "mainhand" },
  INVTYPE_2HWEAPON = { "mainhand" },
  INVTYPE_WEAPONOFFHAND = { "offhand" }, INVTYPE_SHIELD = { "offhand" },
  INVTYPE_HOLDABLE = { "offhand" },
  INVTYPE_RANGED = { "relic" }, INVTYPE_RANGEDRIGHT = { "relic" },
  INVTYPE_THROWN = { "relic" }, INVTYPE_RELIC = { "relic" },
}

-- "Usable" = an equipment card this character could wear right now:
-- level requirement met and, when the license layer is on, a license for
-- its slot owned (twin slots count either license). Drives the quiet
-- climax-slot steering below.
function TT.IsUsableEquipCard(row)
  if (row.kind or "item") ~= "item" then return false end
  if (row.rl or 0) > (UnitLevel("player") or 1) then return false end
  local _, _, _, loc, _, classID = GetItemInfoInstant(row.i)
  if classID ~= 2 and classID ~= 4 then return false end
  local lics = TT.INVTYPE_LICENSES[loc]
  if not lics then return false end
  if not TT.LicenseLayerActive() then return true end
  for _, slot in ipairs(lics) do
    if TT.IsUnlocked(slot) then return true end
  end
  return false
end

-- A usable card near the rolled tier (fall back down, then up); nil when
-- nothing usable exists in this pool at all.
local function pickUsable(byTier, tier)
  local order = {}
  for t = tier, 1, -1 do order[#order + 1] = t end
  for t = tier + 1, TT.MAX_RARITY do order[#order + 1] = t end
  for _, t in ipairs(order) do
    local bucket = byTier[t]
    if bucket and #bucket > 0 then
      for _ = 1, 40 do
        local row = bucket[math.random(#bucket)]
        if TT.IsUsableEquipCard(row) then return row, t end
      end
      local cands = {}
      for _, row in ipairs(bucket) do
        if TT.IsUsableEquipCard(row) then cands[#cands + 1] = row end
      end
      if #cands > 0 then return cands[math.random(#cands)], t end
    end
  end
  return nil
end

-- Some tiers can be thin in a given type's pool (e.g. few creature epics):
-- fall back to the nearest lower populated tier, then upward.
local function pickCard(byTier, tier)
  for t = tier, 1, -1 do
    local bucket = byTier[t]
    if bucket and #bucket > 0 then
      return bucket[math.random(#bucket)], t
    end
  end
  for t = tier + 1, TT.MAX_RARITY do
    local bucket = byTier[t]
    if bucket and #bucket > 0 then
      return bucket[math.random(#bucket)], t
    end
  end
  return nil
end

function TT.RollPack(packType)
  local E = TT.ECON
  local byTier = TT.poolByType[packType]
  if not byTier then return nil end
  local god = (math.random(E.godChance) == 1)
  if TT.forceGodPack then
    god = true
    TT.forceGodPack = nil
  end
  local cards = {}
  local sawEpic = false
  local eqPack = (packType == "equipment" or packType == "wild")

  for slot = 1, E.cardsPerPack do
    local odds = (god or slot == E.cardsPerPack) and E.bonusOdds or E.slotOdds
    local tier = rollTier(odds)
    -- pity: if this is the climax slot, no epic+ yet this pack, and the
    -- drought counter has hit the cap, force an epic
    if slot == E.cardsPerPack and not god and not sawEpic
        and TT.Profile().pity >= E.pityEpic and tier < 4 then
      tier = 4
    end
    local row, actual
    -- climax-slot steering (equipment/wild): keep the last flip relevant
    -- to what this character can actually wear (see TT.IsUsableEquipCard)
    if slot == E.cardsPerPack and eqPack and TT.Run then
      local since = TT.Run().packsSinceUsable or 0
      if since >= TT.LICENSE.pityWindow - 1
          or math.random() < TT.LICENSE.pityBias then
        row, actual = pickUsable(byTier, tier)
      end
    end
    if not row then
      row, actual = pickCard(byTier, tier)
    end
    if not row then return nil end
    if actual >= 4 then sawEpic = true end
    local foil = god or (math.random(E.foilChance) == 1)
    cards[slot] = { k = TT.CardKey(row), f = foil }
  end

  return { cards = cards, revealed = 0, ptype = packType, god = god }
end

-- Pays for a pack; contents don't exist until the type is picked.
function TT.BuyPack()
  if not TT.FormatFlag("packs") then
    TT.Msg("This run's format has no card packs.")
    return false
  end
  local p = TT.Profile()
  if p.pendingPack then
    TT.Warn("Finish opening your current pack first!")
    return false
  end
  local useFree = (p.freePacks or 0) > 0
  if not useFree and p.credits < TT.ECON.packPrice then
    TT.Warn("Not enough credits (" .. TT.FormatNumber(TT.ECON.packPrice) .. " needed).")
    return false
  end
  if useFree then
    p.freePacks = p.freePacks - 1
  else
    p.credits = p.credits - TT.ECON.packPrice
  end
  p.pendingPack = { unopened = true }
  TT.Refresh()
  return true
end

-- The player committed to a pack type: roll + persist before any reveal.
function TT.PickPackType(packType)
  local p = TT.Profile()
  local pending = p.pendingPack
  if not pending or pending.cards then return false end
  local pack = TT.RollPack(packType)
  if not pack then
    TT.Warn("That card pool is empty on this client!")
    return false
  end
  p.pendingPack = pack
  if pack.god then
    p.pity = 0
  else
    local hasEpic = false
    for _, c in ipairs(pack.cards) do
      local row = TT.cardIndex[c.k]
      if row and row.r >= 4 then hasEpic = true end
    end
    p.pity = hasEpic and 0 or (p.pity + 1)
  end
  -- usable-drop bookkeeping (equipment/wild packs only; goods and
  -- creature packs neither advance nor reset it)
  if (packType == "equipment" or packType == "wild") and TT.Run then
    local run = TT.Run()
    local usable = false
    for _, c in ipairs(pack.cards) do
      local row = TT.cardIndex[c.k]
      if row and TT.IsUsableEquipCard(row) then usable = true break end
    end
    run.packsSinceUsable = usable and 0 or ((run.packsSinceUsable or 0) + 1)
  end
  return true
end

function TT.RevealNext()
  local p = TT.Profile()
  local pack = p.pendingPack
  if not pack or not pack.cards then return nil end
  if pack.revealed >= #pack.cards then return nil end
  pack.revealed = pack.revealed + 1
  return pack.revealed, pack.cards[pack.revealed]
end

-- One card enters the shared collection: counts, NEW tracking and the
-- contribution ledger. Packs and League draft picks both land here.
function TT.FoldCardIntoCollection(key, foil, charName)
  local p = TT.Profile()
  local col = p.collection[key] or { n = 0, f = 0 }
  local isNew = (col.n + col.f) == 0
  if isNew then
    p.firstSeen[key] = time()
    p.fresh[key] = true
  end
  if foil then col.f = col.f + 1 else col.n = col.n + 1 end
  p.collection[key] = col
  TT.AddContribution(charName, key, foil)
  return isNew
end

function TT.FinishPack()
  local p = TT.Profile()
  local pack = p.pendingPack
  if not pack or not pack.cards then return end
  local name = UnitName("player")
  local newCount = 0

  for _, c in ipairs(pack.cards) do
    if TT.FoldCardIntoCollection(c.k, c.f, name) then
      newCount = newCount + 1
    end
  end

  p.stats.packs = (p.stats.packs or 0) + 1
  if pack.god then p.stats.gods = (p.stats.gods or 0) + 1 end
  if p.roster[name] then
    p.roster[name].packsOpened = (p.roster[name].packsOpened or 0) + 1
  end
  p.pendingPack = nil
  TT.Refresh()
  return newCount
end

-- Dev helper: roll N packs without paying and print a rarity histogram.
function TT.SimulatePacks(args)
  local count, ptype = tostring(args or ""):match("^(%d*)%s*(%a*)$")
  count = math.min(tonumber(count) or 100, 100000)
  ptype = (ptype ~= "" and ptype) or "equipment"
  if not TT.poolByType[ptype] then
    TT.Msg("Usage: simulate N [equipment|goods|creatures|wild]")
    return
  end
  local hist, foils, gods = {}, 0, 0
  local savedPity = TT.Profile().pity
  for _ = 1, count do
    local pack = TT.RollPack(ptype)
    if not pack then TT.Msg("Pool empty."); return end
    if pack.god then gods = gods + 1 end
    for _, c in ipairs(pack.cards) do
      local row = TT.cardIndex[c.k]
      hist[row.r] = (hist[row.r] or 0) + 1
      if c.f then foils = foils + 1 end
    end
  end
  TT.Profile().pity = savedPity
  TT.Msg(("Simulated %d packs (%d cards):"):format(count, count * TT.ECON.cardsPerPack))
  for tier = 1, TT.MAX_RARITY do
    TT.Msg(("  %s: %d"):format(TT.RarityLabel(tier), hist[tier] or 0))
  end
  TT.Msg(("  foils: %d, god packs: %d"):format(foils, gods))
end

---------------------------------------------------------------------------
-- Locked mode + Hardmode
---------------------------------------------------------------------------

function TT.EnableLockedMode()
  local p = TT.Profile()
  if p.lockedMode then return end
  p.lockedMode = true
  p.lockedModeAt = time()
  TT.LogEvent("event", "TCG Locked mode ENABLED for " .. TT.ProfileLabel() .. ".")
  TT.Msg("|cffff4444TCG Locked mode is ON.|r Equipping gear now requires owning its card.")
  if TT.Enforce_OnLockEnabled then TT.Enforce_OnLockEnabled() end
  TT.Refresh()
end

function TT.DisableLockedMode()
  local p = TT.Profile()
  if not p.lockedMode then
    TT.Msg("Locked mode is not on.")
    return
  end
  p.lockedMode = false
  TT.LogEvent("event", "TCG Locked mode DISABLED by " .. UnitName("player") ..
    " (permanently on record).")
  TT.Msg("Locked mode disabled. This is recorded in the run's event log.")
  TT.Refresh()
end

function TT.EnableHardmode()
  if TT.cdb.hardmode then return end
  -- log the departure on the realm profile before switching
  TT.LogEvent("event", UnitName("player") .. " left the realm run for HARDMODE.")
  TT.cdb.hardmode = true
  TT.cdb.hardmodeAt = time()
  TT.cdb.lockSeen = false
  TT.RegisterRoster()
  TT.LogEvent("event", UnitName("player") .. " began a HARDMODE run.")
  TT.Msg("|cffff4444Hardmode.|r This character now has its own isolated collection and credits.")
  TT.Refresh()
end

-- Leaving Hardmode merges the toon's cards + credits into the realm pool.
function TT.DisableHardmode()
  if not TT.cdb.hardmode then
    TT.Msg("This character is not in Hardmode.")
    return
  end
  local hp = TT.Profile()             -- hardmode profile (flag still set)
  TT.cdb.hardmode = false
  local rp = TT.Profile()             -- realm profile
  local name = UnitName("player")

  rp.credits = rp.credits + hp.credits
  rp.freePacks = (rp.freePacks or 0) + (hp.freePacks or 0)
  for key, c in pairs(hp.collection) do
    local col = rp.collection[key] or { n = 0, f = 0 }
    if (col.n + col.f) == 0 then
      rp.firstSeen[key] = hp.firstSeen[key] or time()
      rp.fresh[key] = true
    end
    col.n = col.n + (c.n or 0)
    col.f = col.f + (c.f or 0)
    rp.collection[key] = col
  end
  for char, led in pairs(hp.contributions) do
    rp.contributions[char] = rp.contributions[char] or {}
    for key, c in pairs(led) do
      local m = rp.contributions[char][key] or { n = 0, f = 0 }
      m.n = m.n + (c.n or 0)
      m.f = m.f + (c.f or 0)
      rp.contributions[char][key] = m
    end
  end
  for stat, v in pairs(hp.stats) do
    rp.stats[stat] = (rp.stats[stat] or 0) + v
  end
  -- drought protection carries over conservatively; the daily-pack stamp
  -- keeps whichever run claimed a boss most recently (ISO dates compare)
  rp.pity = math.max(rp.pity or 0, hp.pity or 0)
  if (hp.lastDailyPack or "") > (rp.lastDailyPack or "") then
    rp.lastDailyPack = hp.lastDailyPack
  end
  -- license-layer state does NOT merge: cdb.runs["hard:..."] simply goes
  -- dormant - the realm run has its own per-character entry, and the two
  -- runs may not even share a format

  TT.db.hardmode[TT.RealmKey() .. "-" .. name] = nil
  TT.cdb.lockSeen = false
  TT.RegisterRoster()
  TT.LogEvent("event", name .. " LEFT Hardmode; their collection merged into the realm run " ..
    "(permanently on record).")
  TT.Msg("Hardmode ended. Collection and credits merged into the realm run.")
  TT.Refresh()
end

---------------------------------------------------------------------------
-- Comms: HELLO ping now; the trade protocol is frozen for v2 and politely
-- declined in v1. Wire format: "1:VERB:payload" (protocol version first).
---------------------------------------------------------------------------

TT.MSG_PREFIX = "TavernLeagueTCG"
TT.PROTOCOL = 1

local function send(verb, payload, channel, target)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
  local msg = TT.PROTOCOL .. ":" .. verb .. ":" .. (payload or "")
  if channel == "WHISPER" then
    C_ChatInfo.SendAddonMessage(TT.MSG_PREFIX, msg, "WHISPER", target)
  else
    C_ChatInfo.SendAddonMessage(TT.MSG_PREFIX, msg, channel)
  end
end
TT.CommSend = send  -- Trade.lua sends through this

function TT.SendHello()
  local channel
  if IsInRaid() then channel = "RAID"
  elseif IsInGroup() then channel = "PARTY" end
  if channel then
    send("HELLO", GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version") or "0", channel)
  end
end

local TRADE_VERBS = { T_REQ = true, T_OFFER = true, T_ACCEPT = true,
  T_LOCK = true, T_COMMIT = true, T_ABORT = true }
local GROUP_VERBS = { KILL = true, KILLH = true }

function TT.OnAddonMessage(prefix, msg, channel, sender)
  if prefix ~= TT.MSG_PREFIX then return end
  local shortSender = Ambiguate and Ambiguate(sender, "short") or sender
  if shortSender == UnitName("player") then return end

  local version, verb, payload = msg:match("^(%d+):([%u_]+):(.*)$")
  if not verb then return end

  if verb == "HELLO" then
    if channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT" then
      -- capability ping; nothing to do in v1
    end
  elseif TRADE_VERBS[verb] then
    if channel ~= "WHISPER" then return end
    if not TT.FormatFlag("trade") then return end   -- format has no trading
    if TT.Trade_OnMessage then
      TT.Trade_OnMessage(verb, payload, sender, shortSender, version)
    end
  elseif GROUP_VERBS[verb] then
    -- boss-kill sync: group channels only; deliberately lenient on the
    -- protocol version (a stale peer's boss kill is still true)
    if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" then
      return
    end
    if TT.Goals_OnGroupKill then
      TT.Goals_OnGroupKill(verb == "KILLH", tonumber(payload), shortSender)
    end
  end
end

---------------------------------------------------------------------------
-- Refresh dispatch (UI.lua / Enforce.lua fill these in)
---------------------------------------------------------------------------

function TT.Refresh()
  if TT.UI_Refresh then TT.UI_Refresh() end
  if TT.Enforce_Update then TT.Enforce_Update() end
  if TT.LicenseEnforce_Update then TT.LicenseEnforce_Update() end
end

---------------------------------------------------------------------------
-- Login setup
---------------------------------------------------------------------------

function TT.SetupForPlayer()
  TT.BuildPoolIndex()
  local _, classToken = UnitClass("player")
  if TT.BuildLicenseDeck then TT.BuildLicenseDeck(classToken) end
  TT.RegisterRoster()
  -- one-time 0.5.0 amnesty: hard enforcement replaces warn-only, so this
  -- character re-grandfathers what they're wearing before the rules bite
  if TT.cdb.amnestyPending then
    TT.cdb.amnestyPending = nil
    if TT.Profile().lockedMode then
      TT.cdb.lockSeen = false   -- Enforce re-snapshots on entering world
      TT.LogEvent("event", (UnitName("player") or "?") ..
        " re-grandfathered equipped items (v0.5.0 enforcement upgrade).")
    end
  end
  -- seed XP bookkeeping so the first PLAYER_XP_UPDATE doesn't mis-delta
  if TT.cdb.lastXP == nil then
    TT.cdb.lastXP = UnitXP("player")
    TT.cdb.lastXPMax = UnitXPMax("player")
  end
  -- seed (or diff) the skill snapshot
  TT.OnSkillsChanged()
  TT.SeedHonorKills()
  TT.GrantRetroPacks()
  if TT.GrantRetroLicenses then TT.GrantRetroLicenses() end
end

-- One-time catch-up so the addon is worth installing on an existing
-- character: bank a free pack for every level already earned (a max-level
-- toon joins the run with 59/69 packs). Once per character ever - normal
-- dings pay from here on, rerolled toons restart at level 1 for ~nothing,
-- and the grant is logged for the run's audit trail.
function TT.GrantRetroPacks()
  if TT.cdb.retroPacks then return end
  -- only consume the once-ever flag once a format WITH packs is locked
  -- in: a character whose first run is Challenge (or who hasn't picked
  -- yet) still gets this grant on a pack format later
  local p = TT.Profile()
  if not p.format or not TT.FORMATS[p.format].packs then return end
  TT.cdb.retroPacks = true
  local level = UnitLevel("player") or 1
  local grant = math.max(0, level - 1)
  if grant > 0 then
    local p = TT.Profile()
    p.freePacks = (p.freePacks or 0) + grant
    TT.LogEvent("event", ("%s joined the run at level %d: +%d retroactive packs."):format(
      UnitName("player"), level, grant))
    TT.Msg(("Level %d catch-up: |cffffd100+%d card packs banked!|r"):format(level, grant))
    TT.Refresh()
  end
end

function TT.ResetProfile()
  local p = TT.Profile()
  if TT.cdb.hardmode then
    TT.db.hardmode[TT.RealmKey() .. "-" .. UnitName("player")] = nil
  else
    TT.db.realms[TT.RealmKey()] = nil
  end
  TT.cdb.lockSeen = false
  TT.cdb.grandfathered = {}
  TT.SetupForPlayer()
  TT.Refresh()
  TT.Msg("Profile reset (" .. TT.ProfileLabel() .. ").")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_XP_UPDATE")
loader:RegisterEvent("PLAYER_LEVEL_UP")
loader:RegisterEvent("QUEST_TURNED_IN")
loader:RegisterEvent("SKILL_LINES_CHANGED")
loader:RegisterEvent("PLAYER_PVP_KILLS_CHANGED")
loader:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
loader:RegisterEvent("CHAT_MSG_ADDON")
loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
loader:RegisterEvent("PLAYER_TARGET_CHANGED")
loader:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
loader:RegisterEvent("NAME_PLATE_UNIT_ADDED")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(loader.RegisterEvent, loader, "GROUP_JOINED")

loader:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then
      TT.InitDB()
      self:UnregisterEvent("ADDON_LOADED")
    end
    return
  end
  if event == "PLAYER_LOGIN" then
    if not TT.db then TT.InitDB() end
    TT.SetupForPlayer()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
      C_ChatInfo.RegisterAddonMessagePrefix(TT.MSG_PREFIX)
    end
    if TT.UI_Init then TT.UI_Init() end
    return
  end
  if not TT.db then return end

  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    TT.OnCombatLogEvent()
  elseif event == "PLAYER_XP_UPDATE" then
    if arg1 == "player" then TT.OnXPUpdate() end
  elseif event == "PLAYER_LEVEL_UP" then
    TT.OnLevelUp(arg1)
  elseif event == "QUEST_TURNED_IN" then
    TT.OnQuestTurnedIn()
  elseif event == "SKILL_LINES_CHANGED" then
    TT.OnSkillsChanged()
  elseif event == "PLAYER_PVP_KILLS_CHANGED" then
    TT.OnPvpKillsChanged()
  elseif event == "CHAT_MSG_ADDON" then
    TT.OnAddonMessage(arg1, arg2, arg3, arg4)
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    TT.OnItemInfoReceived(arg1, arg2)
  elseif event == "PLAYER_TARGET_CHANGED" then
    TT.HarvestUnitLevel("target")
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    TT.HarvestUnitLevel("mouseover")
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    TT.HarvestUnitLevel(arg1)
  elseif event == "PLAYER_ENTERING_WORLD" then
    TT.WipeUnitLevels()
  elseif event == "GROUP_JOINED" then
    TT.SendHello()
  end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_TAVERNLEAGUETCG1 = "/tavernleague"
SLASH_TAVERNLEAGUETCG2 = "/tltcg"
SLASH_TAVERNLEAGUETCG3 = "/tcg"
SlashCmdList.TAVERNLEAGUETCG = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S*)%s*(.*)$")
  cmd = cmd:lower()

  if cmd == "" then
    TT.ToggleFrame()
  elseif cmd == "status" then
    local p = TT.Profile()
    local owned, foils = TT.OwnedCounts()
    local fmt = p.format and TT.FORMATS[p.format]
    TT.Msg(TT.ProfileLabel() .. (fmt and ("  [" .. fmt.label .. "]") or "")
      .. (p.lockedMode and "  |cffff4444[LOCKED]|r" or ""))
    TT.Msg(("Credits: %s  |  Free packs: %d  |  Packs opened: %d (god: %d)  |  Trades: %d  |  Pity: %d/%d"):format(
      TT.FormatNumber(p.credits), p.freePacks or 0, p.stats.packs or 0, p.stats.gods or 0,
      p.stats.trades or 0, p.pity, TT.ECON.pityEpic))
    TT.Msg(("Collection: %d/%d cards (%d foil)  |  Dupes sold: %d"):format(
      owned, TT.poolCount or 0, foils, p.stats.sold or 0))
    TT.Msg(("Earned - xp: %s, kills: %s, quests: %s, levels: %s, skills: %s, bosses: %s, honor: %s"):format(
      TT.FormatNumber(p.stats.xp or 0), TT.FormatNumber(p.stats.kills or 0),
      TT.FormatNumber(p.stats.quests or 0), TT.FormatNumber(p.stats.levels or 0),
      TT.FormatNumber(p.stats.skills or 0), TT.FormatNumber(p.stats.bosses or 0),
      TT.FormatNumber(p.stats.honor or 0)))
  elseif cmd == "roster" then
    TT.PrintRoster()
  elseif cmd == "open" then
    if TT.BuyPack() and TT.UI_ShowPackOverlay then TT.UI_ShowPackOverlay() end
  elseif cmd == "simulate" then
    TT.SimulatePacks(rest)
  elseif cmd == "retire" then
    local name, confirm = rest:match("^(%S+)%s+(%S+)$")
    if name and confirm == "CONFIRM" then
      if TT.Profile().roster[name] then
        TT.RevokeContributions(name, "retired by " .. UnitName("player"))
      else
        TT.Msg("'" .. name .. "' is not on this run's roster.")
      end
    else
      TT.Msg("Usage: /tltcg retire <ToonName> CONFIRM  (revokes their pulled cards)")
    end
  elseif cmd == "unlock" then
    if rest == "CONFIRM" then
      TT.DisableLockedMode()
    else
      TT.Msg("Locked mode is permanent. To disable anyway (permanently recorded): /tltcg unlock CONFIRM")
    end
  elseif cmd == "unhard" then
    if rest == "CONFIRM" then
      TT.DisableHardmode()
    else
      TT.Msg("Hardmode is permanent. To leave and merge into the realm run: /tltcg unhard CONFIRM")
    end
  elseif cmd == "minimap" then
    TT.cdb.minimapHide = not TT.cdb.minimapHide
    if TT.UpdateMinimapButton then TT.UpdateMinimapButton() end
    TT.Msg("Minimap button " .. (TT.cdb.minimapHide and "hidden" or "shown") .. ".")
  elseif cmd == "reset" then
    StaticPopup_Show("TAVERNLEAGUETCG_RESET")
  else
    -- local test builds may carry a gitignored Dev.lua with extra commands
    if TT.DevCommand and TT.DevCommand(cmd, rest) then return end
    TT.Msg("Commands: status, roster, open, simulate N, retire <name> CONFIRM, unlock CONFIRM, unhard CONFIRM, minimap, reset")
  end
end

StaticPopupDialogs.TAVERNLEAGUETCG_RESET = {
  text = "Reset ALL Tavern League TCG progress for this profile?\n\nThis wipes the shared collection, credits, roster and logs.",
  button1 = YES,
  button2 = NO,
  OnAccept = function() TT.ResetProfile() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

StaticPopupDialogs.TAVERNLEAGUETCG_LOCKMODE = {
  text = "Enable TCG LOCKED MODE?\n\nThis marks the WHOLE RUN (%s) as locked: every character sharing this collection may only equip gear whose card the run owns.\n\nCurrently equipped gear is grandfathered per character. This choice is permanent and any later unlock is recorded forever.",
  button1 = "Lock it in",
  button2 = CANCEL,
  OnAccept = function() TT.EnableLockedMode() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

-- Sell confirmation: UI stores the pending card, popup text is fully
-- formatted by the caller and passed as the single %s.
StaticPopupDialogs.TAVERNLEAGUETCG_SELL = {
  text = "%s",
  button1 = "Sell it",
  button2 = CANCEL,
  OnAccept = function()
    if TT._sellKey then TT.SellCard(TT._sellKey, TT._sellFoil) end
    TT._sellKey = nil
  end,
  OnCancel = function() TT._sellKey = nil end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

StaticPopupDialogs.TAVERNLEAGUETCG_HARDMODE = {
  text = "Go HARDMODE?\n\n%s abandons the shared realm collection and starts an ISOLATED collection and credit balance. The extreme challenge.\n\nLeaving Hardmode later merges your cards back and is recorded forever.",
  button1 = "Hardmode",
  button2 = CANCEL,
  OnAccept = function() TT.EnableHardmode() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}
