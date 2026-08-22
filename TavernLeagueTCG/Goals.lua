-- Tavern League TCG: tavern goals + the dungeon tracker, ported from
-- DeckLocked's auto-detection engine. Skills, reputation, honorable
-- kills, equipped gear and boss kills all flow into TT.AutoCompleteGoal;
-- detection only ever checks a box - unlearning a profession or
-- unequipping a weapon never claws a reward back. Goal ids are the
-- DeckLocked saved-variable keys, unchanged, for the import path.
--
-- Rewards dispatch per format: a bonus draw (Challenge), a free pack
-- (Collection) or a draft pack (League).

local ADDON, TT = ...

---------------------------------------------------------------------------
-- Rewards
---------------------------------------------------------------------------

function TT.PayGoalReward()
  local p = TT.Profile()
  local kind = TT.LICENSE.goalRewards[p.format or "collection"] or "freePack"
  if kind == "bonusDraw" then
    local run = TT.Run()
    run.bonusDraws = run.bonusDraws + 1
    return ("+1 bonus draw (%d banked)"):format(run.bonusDraws)
  elseif kind == "draftPack" then
    local run = TT.Run()
    run.draftPacks = run.draftPacks + 1
    return ("+1 draft pack (%d banked)"):format(run.draftPacks)
  end
  p.freePacks = (p.freePacks or 0) + 1
  return ("+1 card pack (%d banked)"):format(p.freePacks)
end

-- The auto path bypasses the lock: the game state itself is the proof.
-- Idempotent - a goal pays exactly once per run.
function TT.AutoCompleteGoal(id)
  if not TT.Profile().format then return end   -- rewards wait for the pick
  local run = TT.Run()
  if run.goals[id] then return end
  run.goals[id] = true
  local box = TT.goalBoxIndex and TT.goalBoxIndex[id]
  local reward = TT.PayGoalReward()
  TT.Msg((box and (box.name or box.label) or id) .. " complete! " .. reward .. ".")
  TT.PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
  TT.Refresh()
end

-- Manual toggles exist only for honor-system goals (no reliable API);
-- auto-detected goals check themselves, and nothing un-checks.
function TT.ToggleGoal(id)
  local box = TT.goalBoxIndex and TT.goalBoxIndex[id]
  if not box then return end
  local run = TT.Run()
  if run.goals[id] then
    TT.Msg("Goals pay out once - completed goals stay complete.")
    return
  end
  if not box.honor then
    TT.Warn("That goal completes automatically when the game says so.")
    return
  end
  TT.AutoCompleteGoal(id)
end

---------------------------------------------------------------------------
-- Dungeon tracker (Challenge/League). Names match TT.FINAL_BOSSES, so
-- kill detection is a straight lookup; the Bonus rows derive from full
-- groups (TT.DUNGEON_BONUS) and can't be earned directly.
---------------------------------------------------------------------------

function TT.CheckBonusDungeons()
  local run = TT.Run()
  for bonus, members in pairs(TT.DUNGEON_BONUS) do
    if not run.dungeons[bonus] then
      local all = true
      for _, name in ipairs(members) do
        if not run.dungeons[name] then all = false break end
      end
      if all and #members > 0 then
        TT.CompleteDungeon(bonus, true)
      end
    end
  end
end

-- auto = a detected boss kill (or a derived bonus row) - the only path
-- allowed while the lock is on
function TT.CompleteDungeon(name, auto)
  if TT.Profile().lockedMode and not auto then
    TT.Warn("The lock is on - dungeons complete when the final boss dies.")
    return
  end
  local run = TT.Run()
  if run.dungeons[name] then return end
  run.dungeons[name] = true
  TT.PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
  TT.Msg(name .. " complete!")
  TT.CheckBonusDungeons()
  TT.Refresh()
end

-- Shift-click un-complete (manual-mode QoL only)
function TT.UncompleteDungeon(name)
  if TT.Profile().lockedMode then
    TT.Warn("The lock is on - dungeon completion can't be undone.")
    return
  end
  local run = TT.Run()
  if run.dungeons[name] then
    run.dungeons[name] = nil
    TT.Refresh()
  end
end

function TT.HeroicsCleared()
  local run = TT.Run()
  local count = 0
  for _, name in ipairs(TT.HEROIC_DUNGEONS) do
    if run.dungeonsHeroic[name] then count = count + 1 end
  end
  return count, #TT.HEROIC_DUNGEONS
end

local function CheckHeroicsGoal()
  local cleared, total = TT.HeroicsCleared()
  if total > 0 and cleared >= total then
    TT.AutoCompleteGoal("misc-tbc-heroics")
  end
end

---------------------------------------------------------------------------
-- Skill / reputation / stat scans (ported detection, states in TT.Run)
---------------------------------------------------------------------------

-- Profession + riding skill ranks. Names are matched via the profession
-- spells (localization-proof); Riding has no spell of its own, so it
-- falls back to the English skill-line name plus IsSpellKnown.
local ARTISAN_RIDING = 34091

local function skillTargets()
  return {
    [(GetSpellInfo and GetSpellInfo(7411)) or "Enchanting"] = "enchanting",
    [(GetSpellInfo and GetSpellInfo(25229)) or "Jewelcrafting"] = "jewelcrafting",
    ["Riding"] = "riding",
  }
end

-- fullScan expands collapsed skill headers (done once, at login, on a
-- delay). The frequent event path reads visible rows only: expanding or
-- collapsing fires SKILL_LINES_CHANGED itself, which would loop.
function TT.Goals_ScanSkills(fullScan)
  if not (GetNumSkillLines and GetSkillLineInfo) then return end
  local targets = skillTargets()

  local collapsed = {}
  if fullScan then
    for i = 1, GetNumSkillLines() do
      local name, isHeader, isExpanded = GetSkillLineInfo(i)
      if isHeader and not isExpanded then collapsed[name] = true end
    end
    if next(collapsed) and ExpandSkillHeader then ExpandSkillHeader(0) end
  end

  local ranks = {}
  for i = 1, GetNumSkillLines() do
    local name, isHeader, _, skillRank = GetSkillLineInfo(i)
    local key = name and targets[name]
    if not isHeader and key then ranks[key] = skillRank or 0 end
  end

  if next(collapsed) and CollapseSkillHeader then
    for i = GetNumSkillLines(), 1, -1 do
      local name, isHeader = GetSkillLineInfo(i)
      if isHeader and collapsed[name] then CollapseSkillHeader(i) end
    end
  end

  for _, box in ipairs(TT.goalEnchantBoxes) do
    if (ranks.enchanting or 0) >= box.threshold then TT.AutoCompleteGoal(box.id) end
  end
  for _, box in ipairs(TT.goalJcBoxes) do
    if (ranks.jewelcrafting or 0) >= box.threshold then TT.AutoCompleteGoal(box.id) end
  end
  if (ranks.riding or 0) >= 300 or (IsSpellKnown and IsSpellKnown(ARTISAN_RIDING)) then
    TT.AutoCompleteGoal("misc-epic-flier")
  end
end

-- fullScan expands collapsed reputation headers (login only); the
-- frequent UPDATE_FACTION path only reads visible rows.
function TT.Goals_ScanReputation(fullScan)
  if TT.Run().goals["misc-exalted-rep"] then return end
  if not (GetNumFactions and GetFactionInfo) then return end

  local expanded = {}
  if fullScan and ExpandFactionHeader then
    local i = 1
    while i <= GetNumFactions() do
      local name, _, _, _, _, _, _, _, isHeader, isCollapsed = GetFactionInfo(i)
      if isHeader and isCollapsed then
        ExpandFactionHeader(i)
        expanded[name] = true
      end
      i = i + 1
    end
  end

  local exalted = false
  for i = 1, GetNumFactions() do
    local _, _, standingId = GetFactionInfo(i)
    if standingId == 8 then
      exalted = true
      break
    end
  end

  if next(expanded) and CollapseFactionHeader then
    for i = GetNumFactions(), 1, -1 do
      local name, _, _, _, _, _, _, _, isHeader = GetFactionInfo(i)
      if isHeader and expanded[name] then CollapseFactionHeader(i) end
    end
  end

  if exalted then TT.AutoCompleteGoal("misc-exalted-rep") end
end

function TT.Goals_CheckHonorKills()
  if TT.Run().goals["misc-1k-hk"] then return end
  if not GetPVPLifetimeStats then return end
  local hk = GetPVPLifetimeStats()
  if (hk or 0) >= 1000 then TT.AutoCompleteGoal("misc-1k-hk") end
end

local WEAPON_SLOTS = { 16, 17, 18 } -- main hand, off hand, ranged

function TT.Goals_CheckEpicWeapon()
  if TT.Run().goals["misc-classic-dungs"] then return end
  if not GetInventoryItemQuality then return end
  for _, slot in ipairs(WEAPON_SLOTS) do
    local quality = GetInventoryItemQuality("player", slot)
    if quality and quality >= 4 then
      TT.AutoCompleteGoal("misc-classic-dungs")
      return
    end
  end
end

function TT.RunGoalScans(atLogin)
  if not TT.db then return end
  TT.Goals_ScanSkills(atLogin)
  TT.Goals_ScanReputation(atLogin)
  TT.Goals_CheckHonorKills()
  TT.Goals_CheckEpicWeapon()
  CheckHeroicsGoal()
end

---------------------------------------------------------------------------
-- Boss-kill detection + group sync (KILL/KILLH ride the addon's normal
-- comm protocol; see TT.OnAddonMessage)
---------------------------------------------------------------------------

function TT.IsHeroicDifficulty()
  local difficulty = GetInstanceInfo and select(3, GetInstanceInfo()) or nil
  if difficulty == nil and GetDungeonDifficulty then
    difficulty = GetDungeonDifficulty()
  end
  return difficulty == 2
end

-- Everything a kill can credit: dungeon completion, heroic progress and
-- kill goals. Used by both local detection and group sync.
function TT.Goals_HandleKill(npcId, heroic)
  local run = TT.Run()
  local dungeon = TT.FINAL_BOSSES[npcId]
  if dungeon then
    TT.CompleteDungeon(dungeon, true)
    if heroic and not run.dungeonsHeroic[dungeon] then
      run.dungeonsHeroic[dungeon] = true
      local cleared, total = TT.HeroicsCleared()
      TT.Msg(("%s cleared on Heroic (%d/%d)."):format(dungeon, cleared, total))
      CheckHeroicsGoal()
      TT.Refresh()
    end
  end
  local goal = TT.goalKills[npcId]
  if goal then
    TT.AutoCompleteGoal(goal)
  end
end

-- true if crediting this npc would change anything (keeps group sync
-- chatter quiet when we already have the credit)
local function killIsNews(npcId, heroic)
  local run = TT.Run()
  local dungeon = TT.FINAL_BOSSES[npcId]
  if dungeon and not run.dungeons[dungeon] then return true end
  if dungeon and heroic and not run.dungeonsHeroic[dungeon] then return true end
  local goal = TT.goalKills[npcId]
  if goal and not run.goals[goal] then return true end
  return false
end

-- Called from Core's combat-log handler for every UNIT_DIED npc id -
-- BEFORE the bounty bookkeeping's early returns, so repeat kills still
-- earn heroic credit.
function TT.Goals_OnKill(npcId)
  if not TT.FINAL_BOSSES[npcId] and not (TT.goalKills and TT.goalKills[npcId]) then
    return
  end
  local heroic = TT.FINAL_BOSSES[npcId] and TT.IsHeroicDifficulty() or false
  -- broadcast even if we already have the credit: others may not (addon
  -- messages reach dead/released members that combat-log range missed)
  local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or nil
  if channel then
    TT.CommSend(heroic and "KILLH" or "KILL", tostring(npcId), channel)
  end
  TT.Goals_HandleKill(npcId, heroic)
end

-- A group member's addon reported a kill (already channel-checked and
-- self-filtered in TT.OnAddonMessage; lenient on protocol version - a
-- stale peer's boss kill is still true).
function TT.Goals_OnGroupKill(heroic, npcId, sender)
  if not npcId then return end
  if killIsNews(npcId, heroic) then
    TT.Msg("Boss kill shared by " .. sender .. ".")
    TT.Goals_HandleKill(npcId, heroic)
  end
end

---------------------------------------------------------------------------
-- Events (own frame; Core's loader handles combat log + comms dispatch)
---------------------------------------------------------------------------

local gf = CreateFrame("Frame")
gf:RegisterEvent("PLAYER_LOGIN")
gf:RegisterEvent("SKILL_LINES_CHANGED")
gf:RegisterEvent("CHAT_MSG_SKILL")
gf:RegisterEvent("UPDATE_FACTION")
gf:RegisterEvent("PLAYER_PVP_KILLS_CHANGED")
gf:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

gf:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    -- the full scan expands/collapses headers, which needs the skill and
    -- faction data settled - the delay is load-bearing
    if C_Timer and C_Timer.After then
      C_Timer.After(3, function() TT.RunGoalScans(true) end)
    end
    return
  end
  if not TT.db then return end

  if event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
    TT.Goals_ScanSkills(false)
  elseif event == "UPDATE_FACTION" then
    TT.Goals_ScanReputation(false)
  elseif event == "PLAYER_PVP_KILLS_CHANGED" then
    TT.Goals_CheckHonorKills()
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    TT.Goals_CheckEpicWeapon()
  end
end)
