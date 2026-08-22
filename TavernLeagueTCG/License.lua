-- Tavern League TCG: the license engine - Challenge draws, League draft
-- packs, eligibility and level/retro grants. Deck data comes from
-- LicenseData.lua; per-character state lives behind TT.Run(), and every
-- read goes through the accessors here so a hardmode toggle (which swaps
-- the active run mid-session) can never leave stale license state behind.

local ADDON, TT = ...

---------------------------------------------------------------------------
-- Accessors (the whole addon reads license state through these)
---------------------------------------------------------------------------

function TT.IsDrawn(id)
  return TT.Run().drawn[id] == true
end

function TT.IsUnlocked(key)
  return TT.Run().unlocked[key] == true
end

function TT.LicenseLayerActive()
  return TT.FormatFlag("licenses") == true
end

function TT.ItemLayerActive()
  return TT.FormatFlag("itemEnforce") == true
end

-- Talent points this character has EARNED (box "talent-i" is worth the
-- i-th talent card's points; positional, like DeckLocked).
function TT.LicenseTalentPoints()
  local run = TT.Run()
  local total = 0
  for i, card in ipairs(TT.licenseTalents or {}) do
    if run.unlocked["talent-" .. i] then
      total = total + (card.points or 5)
    end
  end
  return total
end

-- ...and the most this client's deck can ever award (51 Era / 61 TBC)
function TT.LicenseMaxTalentPoints()
  local total = 0
  for _, card in ipairs(TT.licenseTalents or {}) do
    if not TT.IsLicenseGated(card) and card.minLevel <= (TT.MAX_LEVEL or 60) then
      total = total + (card.points or 5)
    end
  end
  return total
end

-- Manual sandbox toggle for the board's boxes, DeckLocked-style: only
-- while the lock is off; with the lock on, unlocks come from Class Packs.
function TT.ToggleLicenseBox(key)
  if TT.Profile().lockedMode then
    TT.Warn("The lock is on - unlocks come from your Class Packs.")
    return
  end
  local run = TT.Run()
  if run.unlocked[key] then
    run.unlocked[key] = nil
  else
    run.unlocked[key] = true
  end
  TT.Refresh()
end

---------------------------------------------------------------------------
-- Eligibility: undrawn, level met, not expansion-gated. Also stamps when
-- each card FIRST became eligible - draft offers favor cards that have
-- been waiting longest, so early essentials keep resurfacing.
---------------------------------------------------------------------------

function TT.EligibleLicenses()
  local run = TT.Run()
  local level = UnitLevel("player") or 1
  local out = {}
  for _, card in ipairs(TT.licenseCards or {}) do
    if not run.drawn[card.id] and card.minLevel <= level
        and not TT.IsLicenseGated(card) then
      if not run.eligibleSince[card.id] then
        run.eligibleSince[card.id] = level
      end
      out[#out + 1] = card
    end
  end
  return out
end

-- Internal: while a character owns none of their class's core abilities
-- (a warrior's stance, a healer's heal - TT.LICENSE.coreAbilities), one
-- offer per draw/draft is steered toward an eligible one. Pure drop
-- steering - the player still chooses - and never surfaced anywhere.
local function CoreForcedLicense(eligible)
  local run = TT.Run()
  local core = TT.LICENSE.coreAbilities[TT.licenseClass]
  if not core then return nil end
  for id in pairs(core) do
    if run.drawn[id] then return nil end
  end
  local cands = {}
  for _, card in ipairs(eligible) do
    if core[card.id] then cands[#cands + 1] = card end
  end
  if #cands > 0 then return cands[math.random(#cands)] end
end

---------------------------------------------------------------------------
-- Taking a license: what each card type unlocks (mirrors DeckLocked)
---------------------------------------------------------------------------

local function ApplyLicense(card)
  local run = TT.Run()
  run.drawn[card.id] = true
  if card.type == "gear" then
    run.unlocked[card.slot] = true
  elseif card.type == "talent" then
    for i = 1, #TT.licenseTalents do
      if not run.unlocked["talent-" .. i] then
        run.unlocked["talent-" .. i] = true
        break
      end
    end
  elseif card.type == "profession" then
    run.unlocked[card.profession] = true
  elseif card.type == "general" then
    run.unlocked[card.general] = true
  end
  -- abilities need no box: enforcement reads drawn state directly
end

local function RevertLicense(card)
  local run = TT.Run()
  run.drawn[card.id] = nil
  if card.type == "gear" then
    run.unlocked[card.slot] = nil
  elseif card.type == "profession" then
    run.unlocked[card.profession] = nil
  elseif card.type == "general" then
    run.unlocked[card.general] = nil
  elseif card.type == "talent" then
    for i = #TT.licenseTalents, 1, -1 do
      if run.unlocked["talent-" .. i] then
        run.unlocked["talent-" .. i] = nil
        break
      end
    end
  end
end

---------------------------------------------------------------------------
-- Challenge: 3-card draws, keep 1. DeckLocked's loop: leveling earns a
-- draw credit, goals earn bonus draws, relogging can't reroll a shown
-- draw, and a single-step undo restores the exact same three cards.
---------------------------------------------------------------------------

function TT.DrawLicenses(isBonus)
  local run = TT.Run()
  if not TT.LicenseLayerActive() then return false end
  if run.pendingDraw then
    TT.Warn("Finish your current draw first - choose a card!")
    return false
  end
  if isBonus then
    if run.bonusDraws < 1 then
      TT.Warn("No bonus Class Packs available!")
      return false
    end
  elseif run.drawCredits < 1 then
    TT.Warn("No Class Packs banked - level up to earn more!")
    return false
  end

  local eligible = TT.EligibleLicenses()
  if #eligible == 0 then
    TT.Msg("Your license deck is complete - nothing left to draw!")
    return false
  end

  local forced = CoreForcedLicense(eligible)
  for i = #eligible, 2, -1 do
    local j = math.random(i)
    eligible[i], eligible[j] = eligible[j], eligible[i]
  end
  local ids = {}
  if forced then ids[1] = forced.id end
  for _, card in ipairs(eligible) do
    if #ids >= TT.LICENSE.drawChoices then break end
    if card ~= forced then ids[#ids + 1] = card.id end
  end

  run.pendingDraw = { ids = ids, bonus = isBonus and true or false }
  run.lastUndo = nil
  TT.PlaySoundKit("IG_QUEST_LOG_OPEN")
  TT.Refresh()
  return true
end

function TT.ChooseLicense(cardId)
  local run = TT.Run()
  local pending = run.pendingDraw
  if not pending then return false end
  local ok = false
  for _, id in ipairs(pending.ids) do
    if id == cardId then ok = true break end
  end
  local card = TT.licenseById[cardId]
  if not ok or not card then return false end

  ApplyLicense(card)
  run.lastUndo = { cardId = cardId, bonus = pending.bonus, ids = pending.ids }
  if pending.bonus then
    run.bonusDraws = math.max(0, run.bonusDraws - 1)
  else
    run.drawCredits = math.max(0, run.drawCredits - 1)
  end
  run.pendingDraw = nil
  TT.PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
  TT.Msg(("License taken: |cffffd100%s|r."):format(card.name))
  TT.Refresh()
  return true
end

-- Single-step undo (DeckLocked semantics). With cards on display and the
-- lock on, the draw must be resolved; with the lock off it may be put
-- back. After a choice: revert the unlock, refund, restore the same
-- three cards.
function TT.UndoLicenseChoice()
  local run = TT.Run()
  if run.pendingDraw then
    if TT.Profile().lockedMode then
      TT.Warn("The lock is on - you must choose one of the drawn cards.")
      return
    end
    run.pendingDraw = nil
    TT.Refresh()
    return
  end
  local undo = run.lastUndo
  if not undo then
    TT.Msg("Nothing to return.")
    return
  end
  local card = TT.licenseById[undo.cardId]
  if card then
    RevertLicense(card)
    if undo.bonus then
      run.bonusDraws = run.bonusDraws + 1
    else
      run.drawCredits = run.drawCredits + 1
    end
    run.pendingDraw = { ids = undo.ids, bonus = undo.bonus }
    TT.Msg(("Returned '%s' - unlock reverted, draw restored."):format(card.name))
  end
  run.lastUndo = nil
  TT.Refresh()
end

---------------------------------------------------------------------------
-- League: draft packs. Five cards - license offers plus level-appropriate
-- gear - and the player keeps EXACTLY ONE. Licenses only ever come from
-- these picks; spending and rolling both persist, so relogs resume.
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

-- A level-appropriate equipment card: requiredLevel met, itemLevel close
-- to current, and an actual wearable (no shirts/tabards). Tier falls back
-- down then up when a bracket is thin at this level.
local function DraftItemOk(row, level)
  if (row.kind or "item") ~= "item" then return false end
  if (row.rl or 0) > level then return false end
  if (row.il or 0) < level - TT.LICENSE.draftIlvlWindow then return false end
  local _, _, _, loc = GetItemInfoInstant(row.i)
  if loc == "INVTYPE_BODY" or loc == "INVTYPE_TABARD" or loc == "" then
    return false
  end
  return true
end

local function PickDraftItem(tier, level)
  local byTier = TT.poolByType and TT.poolByType.equipment
  if not byTier then return nil end
  local order = {}
  for t = tier, 1, -1 do order[#order + 1] = t end
  for t = tier + 1, TT.MAX_RARITY do order[#order + 1] = t end
  for _, t in ipairs(order) do
    local bucket = byTier[t]
    if bucket and #bucket > 0 then
      for _ = 1, 40 do
        local row = bucket[math.random(#bucket)]
        if DraftItemOk(row, level) then return row end
      end
      local cands = {}
      for _, row in ipairs(bucket) do
        if DraftItemOk(row, level) then cands[#cands + 1] = row end
      end
      if #cands > 0 then return cands[math.random(#cands)] end
    end
  end
  return nil
end

function TT.BuildDraftPack()
  local run = TT.Run()
  if not TT.FormatFlag("drafts") then return false end
  if run.pendingDraft then return true end   -- resume the live one
  if run.draftPacks < 1 then
    TT.Warn("No draft packs banked - level up to earn more!")
    return false
  end

  local level = UnitLevel("player") or 1
  local L = TT.LICENSE
  local eligible = TT.EligibleLicenses()
  local slots = {}

  -- license offers: the core steer first, then weighted by how long each
  -- card has been waiting since it became eligible
  local picks = {}
  local forced = CoreForcedLicense(eligible)
  if forced then picks[#picks + 1] = forced end
  local cands = {}
  for _, card in ipairs(eligible) do
    if card ~= forced then cands[#cands + 1] = card end
  end
  while #picks < L.draftLicenseSlots and #cands > 0 do
    local total = 0
    for _, card in ipairs(cands) do
      total = total + (level - (run.eligibleSince[card.id] or level) + 1)
    end
    local r = math.random() * total
    local acc = 0
    for i, card in ipairs(cands) do
      acc = acc + (level - (run.eligibleSince[card.id] or level) + 1)
      if r <= acc then
        picks[#picks + 1] = card
        table.remove(cands, i)
        break
      end
    end
  end
  for _, card in ipairs(picks) do
    slots[#slots + 1] = { kind = "license", id = card.id }
  end

  -- item slots fill the rest (all of it, late-game, once the deck runs dry)
  local nItems = L.draftSize - #slots
  for i = 1, nItems do
    local odds = (i == nItems) and L.draftClimaxOdds or L.draftSlotOdds
    local row = PickDraftItem(rollTier(odds), level)
    if row then
      slots[#slots + 1] = { kind = "item", k = TT.CardKey(row),
        f = (math.random(L.draftFoilChance) == 1) or nil }
    end
  end
  if #slots == 0 then
    TT.Warn("Nothing left to draft!")
    return false
  end

  run.draftPacks = run.draftPacks - 1
  run.pendingDraft = { slots = slots, revealed = 0 }
  TT.Refresh()
  return true
end

function TT.DraftKeep(index)
  local run = TT.Run()
  local pending = run.pendingDraft
  if not pending then return false end
  local slot = pending.slots[index]
  if not slot then return false end

  if slot.kind == "license" then
    local card = TT.licenseById[slot.id]
    if not card then return false end
    ApplyLicense(card)
    TT.Msg(("Draft pick: license |cffffd100%s|r."):format(card.name))
  else
    TT.FoldCardIntoCollection(slot.k, slot.f and true or false, UnitName("player"))
    local row = TT.cardIndex[slot.k]
    TT.Msg(("Draft pick: |cffffd100%s|r%s added to the binder."):format(
      row and row.n or slot.k, slot.f and " (foil!)" or ""))
  end
  local p = TT.Profile()
  p.stats.drafts = (p.stats.drafts or 0) + 1
  run.lastUndo = nil          -- draft picks are not undoable
  run.pendingDraft = nil
  TT.PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
  TT.Refresh()
  return true
end

---------------------------------------------------------------------------
-- Grants: level-ups (called from Core's OnLevelUp) and the one-time
-- catch-up when a character adopts a license format mid-career.
---------------------------------------------------------------------------

function TT.OnLevelUpLicenses(newLevel)
  if not TT.LicenseLayerActive() then return end
  local run = TT.Run()
  if TT.FormatFlag("drafts") then
    run.draftPacks = run.draftPacks + 1
    TT.Msg(("Ding! Level %s - |cffffd100a draft pack awaits!|r (%d banked)"):format(
      tostring(newLevel or "?"), run.draftPacks))
  else
    run.drawCredits = run.drawCredits + 1
    TT.Msg(("Ding! Level %s - |cffffd100a Class Pack has been issued!|r (%d banked)"):format(
      tostring(newLevel or "?"), run.drawCredits))
  end
  -- new level = newly eligible cards; stamp them now
  TT.EligibleLicenses()
end

---------------------------------------------------------------------------
-- DeckLocked import: card ids were preserved, so a DeckLocked character
-- can carry their whole permission run into Challenge or League. Copies
-- only - DeckLockedCharDB is NEVER written.
---------------------------------------------------------------------------

-- DeckLocked's short dungeon keys -> this addon's display names
local DL_DUNGEONS = {
  ["RFC"] = "Ragefire Chasm", ["WC"] = "Wailing Caverns",
  ["DM"] = "The Deadmines", ["SFK"] = "Shadowfang Keep",
  ["BFD"] = "Blackfathom Deeps", ["Stocks"] = "The Stockade",
  ["Gnomer"] = "Gnomeregan", ["RFK"] = "Razorfen Kraul",
  ["SM GY"] = "SM Graveyard", ["SM Lib"] = "SM Library",
  ["SM Arms"] = "SM Armory", ["SM Cath"] = "SM Cathedral",
  ["SM Bonus"] = "SM Bonus", ["RFD"] = "Razorfen Downs",
  ["Ulda"] = "Uldaman", ["ZF"] = "Zul'Farrak", ["Mara"] = "Maraudon",
  ["ST"] = "Sunken Temple", ["BRD"] = "Blackrock Depths",
  ["LBRS"] = "Lower Blackrock Spire", ["UBRS"] = "Upper Blackrock Spire",
  ["DME"] = "Dire Maul East", ["DMW"] = "Dire Maul West",
  ["DMN"] = "Dire Maul North", ["Strat"] = "Stratholme",
  ["Scholo"] = "Scholomance", ["Classic Bonus"] = "Classic Bonus",
  ["Ramps"] = "Hellfire Ramparts", ["BF"] = "The Blood Furnace",
  ["SP"] = "The Slave Pens", ["UB"] = "The Underbog",
  ["MT"] = "Mana-Tombs", ["AC"] = "Auchenai Crypts",
  ["Old Hillsbrad"] = "Old Hillsbrad", ["Sethekk Halls"] = "Sethekk Halls",
  ["SV"] = "The Steamvault", ["Shadow Lab"] = "Shadow Labyrinth",
  ["SHalls"] = "The Shattered Halls", ["BM"] = "The Black Morass",
  ["Bot"] = "The Botanica", ["Mech"] = "The Mechanar",
  ["Arca"] = "The Arcatraz", ["TBC Bonus"] = "TBC Bonus",
}

function TT.ImportDeckLocked()
  local dl = DeckLockedCharDB
  if not dl then return end
  local run = TT.Run()
  local level = UnitLevel("player") or 1
  local imported = 0

  for id in pairs(dl.drawn or {}) do
    if TT.licenseById[id] and not run.drawn[id] then
      run.drawn[id] = true
      imported = imported + 1
    end
  end
  -- DeckLocked kept goal boxes and unlock boxes in one table; split them
  for key in pairs(dl.unlocked or {}) do
    if TT.goalBoxIndex and TT.goalBoxIndex[key] then
      run.goals[key] = true
    else
      run.unlocked[key] = true
    end
  end
  for short in pairs(dl.dungeons or {}) do
    local name = DL_DUNGEONS[short]
    if name then run.dungeons[name] = true end
  end
  for short in pairs(dl.heroics or {}) do
    local name = DL_DUNGEONS[short]
    if name then run.dungeonsHeroic[name] = true end
  end

  local drawnCount = 0
  for _ in pairs(run.drawn) do drawnCount = drawnCount + 1 end
  if TT.FormatFlag("drafts") then
    -- League never existed in DeckLocked: each level owed one pick, and
    -- the imported keeps count as picks already taken
    run.draftPacks = math.max(0, (level - 1) - drawnCount)
  else
    -- Challenge trusts DeckLocked's own draw accounting
    run.drawCredits = dl.drawCredits or 0
    run.bonusDraws = dl.bonusDraws or 0
  end
  run.importedFrom = "decklocked"
  TT.cdb.retroLicense[TT.Profile().format] = true   -- import replaces the catch-up

  TT.LogEvent("event", ("%s imported their DeckLocked run: %d licenses."):format(
    UnitName("player") or "?", imported))
  TT.Msg(("DeckLocked run imported: |cffffd100%d licenses|r, goals and dungeons carried over."):format(
    imported))
  TT.Refresh()
end

-- Offer the import once per character, when a license-format run is
-- fresh and DeckLocked progress exists on this character.
function TT.MaybeOfferDeckLockedImport()
  if TT.cdb.dlImportOffered then return end
  if not TT.LicenseLayerActive() then return end
  local dl = DeckLockedCharDB
  if not dl or not dl.drawn or not next(dl.drawn) then return end
  if next(TT.Run().drawn) then return end   -- this run already has picks
  TT.cdb.dlImportOffered = true
  StaticPopup_Show("TAVERNLEAGUETCG_DLIMPORT")
end

StaticPopupDialogs.TAVERNLEAGUETCG_DLIMPORT = {
  text = "DeckLocked progress found for this character.\n\nImport it into this run? "
    .. "Licenses, talent boxes, goals and dungeon clears carry over 1:1 "
    .. "(DeckLocked itself is not modified). This replaces the level catch-up grant.",
  button1 = "Import",
  button2 = "Start fresh",
  OnAccept = function() TT.ImportDeckLocked() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

function TT.GrantRetroLicenses()
  if not TT.LicenseLayerActive() then return end
  local p = TT.Profile()
  if not p.format then return end
  if TT.cdb.retroLicense[p.format] then return end
  TT.cdb.retroLicense[p.format] = true
  local run = TT.Run()
  local level = UnitLevel("player") or 1
  if TT.FormatFlag("drafts") then
    local grant = math.max(0, level - 1)
    if grant > 0 then
      run.draftPacks = run.draftPacks + grant
      TT.LogEvent("event", ("%s joined League at level %d: +%d retroactive draft packs."):format(
        UnitName("player") or "?", level, grant))
      TT.Msg(("Level %d catch-up: |cffffd100+%d draft packs banked!|r"):format(level, grant))
    end
  else
    run.drawCredits = run.drawCredits + level
    TT.LogEvent("event", ("%s joined Challenge at level %d: +%d retroactive Class Packs."):format(
      UnitName("player") or "?", level, level))
    TT.Msg(("Level %d catch-up: |cffffd100+%d Class Packs banked!|r"):format(level, level))
  end
  TT.Refresh()
end
