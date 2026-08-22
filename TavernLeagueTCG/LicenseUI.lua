-- Tavern League TCG: the Tavern tab - DeckLocked's board, imported.
-- Gear slots on the left, class abilities pooled by spec in the center
-- (only what you've DRAWN appears - nothing is granted by leveling),
-- talents / professions / general on the right, and Class Packs as the
-- only way in. A second view holds the tavern goals and the dungeon
-- tracker. UI.lua creates the page frame and calls TT.License_BuildUI /
-- TT.License_Refresh defensively (the Trade.lua pattern).

local ADDON, TT = ...

local ui = {
  gear = {},         -- [slotKey] = box
  talents = {},      -- [1..13] = box
  profs = {},        -- [profId] = box
  general = {},      -- [generalId] = box
  abilityPools = {}, -- [subspec] = { box, ... }
}

local GOLD = { r = 1, g = 0.82, b = 0 }
local LOCKED_BORDER = { 0.67, 0, 0 }
local UNLOCKED_BORDER = { 0, 0.67, 0 }

local PANEL_BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local BOX_BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 8,
  insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

---------------------------------------------------------------------------
-- Widget helpers (DeckLocked's visual language: red = locked, green =
-- earned, desaturated icons while waiting)
---------------------------------------------------------------------------

local function SetBoxState(box, unlocked)
  if unlocked then
    box:SetBackdropBorderColor(unpack(UNLOCKED_BORDER))
  else
    box:SetBackdropBorderColor(unpack(LOCKED_BORDER))
  end
  if box.icon then
    box.icon:SetDesaturated(not unlocked)
    box.icon:SetAlpha(unlocked and 1 or 0.55)
  end
  if box.label then
    if unlocked then
      box.label:SetTextColor(0.3, 1, 0.3)
    else
      box.label:SetTextColor(0.8, 0.8, 0.8)
    end
  end
end

local function AttachTooltip(widget)
  widget:SetScript("OnEnter", function(self)
    if not self.tooltipText then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tooltipText, 1, 1, 1)
    if self.tooltipSub then
      GameTooltip:AddLine(self.tooltipSub, 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function CreatePanel(parent, w, h)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetSize(w, h)
  f:SetBackdrop(PANEL_BACKDROP)
  f:SetBackdropColor(0.05, 0.05, 0.08, 0.9)
  f:SetBackdropBorderColor(0.3, 0.3, 0.3)
  return f
end

local function CreateHeader(parent, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetText(text)
  fs:SetTextColor(GOLD.r, GOLD.g, GOLD.b)
  return fs
end

local function CreateIconBox(parent, size, tooltip)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(size, size)
  b:SetBackdrop(BOX_BACKDROP)
  b:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 2, -2)
  b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.tooltipText = tooltip
  AttachTooltip(b)
  SetBoxState(b, false)
  return b
end

local function CreateActionButton(parent, w, h, text, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

---------------------------------------------------------------------------
-- Board: gear panel (left)
---------------------------------------------------------------------------

local function BuildGearPanel(board)
  local panel = CreatePanel(board, 188, 448)
  panel:SetPoint("TOPLEFT", 0, 0)

  local header = CreateHeader(panel, "Gear")
  header:SetPoint("TOP", 0, -8)

  local leftSlots = { "head", "neck", "shoulders", "back", "chest", "wrists", "hands" }
  local rightSlots = { "waist", "legs", "feet", "ring1", "ring2", "trinket1", "trinket2" }
  local bottomSlots = { "mainhand", "offhand", "relic" }

  local bySlot = {}
  for _, card in ipairs(TT.licenseCards or {}) do
    if card.type == "gear" then bySlot[card.slot] = card end
  end

  local function makeGearBox(slot, x, y)
    local card = bySlot[slot]
    if not card then return end
    local b = CreateIconBox(panel, 40, card.name)
    b:SetPoint("TOPLEFT", x, y)
    b.icon:SetTexture(TT.GetLicenseIcon(card))
    b:SetScript("OnClick", function() TT.ToggleLicenseBox(slot) end)
    ui.gear[slot] = b
  end

  for i, slot in ipairs(leftSlots) do
    makeGearBox(slot, 34, -26 - (i - 1) * 46)
  end
  for i, slot in ipairs(rightSlots) do
    makeGearBox(slot, 114, -26 - (i - 1) * 46)
  end
  for i, slot in ipairs(bottomSlots) do
    makeGearBox(slot, 28 + (i - 1) * 46, -356)
  end
end

---------------------------------------------------------------------------
-- Board: abilities + Class Pack controls (center)
---------------------------------------------------------------------------

local function BuildAbilitiesPanel(board)
  local panel = CreatePanel(board, 384, 448)
  panel:SetPoint("TOPLEFT", 192, 0)

  local header = CreateHeader(panel, "Abilities")
  header:SetPoint("TOP", 0, -8)

  -- sections come from the player's class specs; count abilities per
  -- subspec so each pool is exactly big enough
  local sections = TT.licenseSpecList or {}
  local counts = {}
  for _, section in ipairs(sections) do
    counts[section.key] = 0
  end
  for _, card in ipairs(TT.licenseCards or {}) do
    if card.type == "ability" and counts[card.subspec] then
      counts[card.subspec] = counts[card.subspec] + 1
    end
  end

  local PER_ROW = 12
  local ICON_SIZE = 26
  local y = -26
  for _, section in ipairs(sections) do
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 12, y)
    label:SetText(section.label)
    label:SetTextColor(GOLD.r, GOLD.g, GOLD.b)
    y = y - 15

    ui.abilityPools[section.key] = {}
    local rows = math.ceil(math.max(1, counts[section.key]) / PER_ROW)
    for i = 1, counts[section.key] do
      local col = (i - 1) % PER_ROW
      local row = math.floor((i - 1) / PER_ROW)
      local b = CreateIconBox(panel, ICON_SIZE)
      b:SetPoint("TOPLEFT", 12 + col * (ICON_SIZE + 4), y - row * (ICON_SIZE + 4))
      b:Hide()
      ui.abilityPools[section.key][i] = b
    end
    y = y - rows * (ICON_SIZE + 4) - 6
  end

  -- Class Pack controls (a pack is issued every level; goals add bonus
  -- packs; the rip happens in the pack overlay)
  ui.openPackBtn = CreateActionButton(panel, 168, 26, "", function()
    local run = TT.Run()
    if run.pendingDraw then
      TT.UI_ShowDrawOverlay()
    elseif run.pendingDraft then
      TT.UI_ShowDraftOverlay()
    elseif TT.FormatFlag("drafts") then
      if TT.BuildDraftPack() then TT.UI_ShowDraftOverlay() end
    else
      if TT.DrawLicenses(false) then TT.UI_ShowDrawOverlay() end
    end
  end)
  ui.openPackBtn:SetPoint("BOTTOMLEFT", 12, 40)

  ui.bonusPackBtn = CreateActionButton(panel, 120, 26, "", function()
    if TT.DrawLicenses(true) then TT.UI_ShowDrawOverlay() end
  end)
  ui.bonusPackBtn:SetPoint("LEFT", ui.openPackBtn, "RIGHT", 8, 0)

  ui.undoBtn = CreateActionButton(panel, 120, 22, "Undo last pick", function()
    TT.UndoLicenseChoice()
    if TT.Run().pendingDraw then TT.UI_ShowDrawOverlay() end
  end)
  ui.undoBtn:SetPoint("BOTTOMLEFT", 12, 12)

  ui.packHint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.packHint:SetPoint("BOTTOMRIGHT", -12, 16)
  ui.packHint:SetTextColor(0.55, 0.55, 0.55)
end

---------------------------------------------------------------------------
-- Board: talents / professions / general (right)
---------------------------------------------------------------------------

local function BuildRightPanel(board)
  local panel = CreatePanel(board, 196, 448)
  panel:SetPoint("TOPLEFT", 580, 0)

  local header = CreateHeader(panel, "Talents")
  header:SetPoint("TOP", 0, -8)

  local PER_ROW = 4
  for i, card in ipairs(TT.licenseTalents or {}) do
    local col = (i - 1) % PER_ROW
    local row = math.floor((i - 1) / PER_ROW)
    local b = CreateIconBox(panel, 38, card.name)
    b:SetPoint("TOPLEFT", 12 + col * 44, -24 - row * 44)
    b.icon:SetTexture(card.icon)
    local index = i
    b:SetScript("OnClick", function() TT.ToggleLicenseBox("talent-" .. index) end)

    local tp = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tp:SetPoint("BOTTOM", 0, 1)
    tp:SetText("+" .. (card.points or 5))
    ui.talents[i] = b
  end

  ui.talentPoints = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ui.talentPoints:SetPoint("TOP", 0, -206)
  ui.talentPoints:SetTextColor(0.3, 1, 0.3)

  local profHeader = CreateHeader(panel, "Professions")
  profHeader:SetPoint("TOP", 0, -226)

  local profs = {
    { id = "prof-1",   name = "Profession 1", icon = "Interface\\Icons\\Trade_BlackSmithing" },
    { id = "prof-2",   name = "Profession 2", icon = "Interface\\Icons\\Trade_Engineering" },
    { id = "cooking",  name = "Cooking",      icon = "Interface\\Icons\\INV_Misc_Food_15" },
    { id = "fishing",  name = "Fishing",      icon = "Interface\\Icons\\Trade_Fishing" },
    { id = "firstaid", name = "First Aid",    icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
  }
  for i, prof in ipairs(profs) do
    local b = CreateIconBox(panel, 32, prof.name)
    b:SetPoint("TOPLEFT", 10 + (i - 1) * 36, -244)
    b.icon:SetTexture(prof.icon)
    b:SetScript("OnClick", function() TT.ToggleLicenseBox(prof.id) end)
    ui.profs[prof.id] = b
  end

  local genHeader = CreateHeader(panel, "General")
  genHeader:SetPoint("TOP", 0, -292)

  local generalRows = {
    {
      { id = "bag-1", name = "Bag Slot 1", icon = "Interface\\Icons\\INV_Misc_Bag_08" },
      { id = "bag-2", name = "Bag Slot 2", icon = "Interface\\Icons\\INV_Misc_Bag_10" },
      { id = "bag-3", name = "Bag Slot 3", icon = "Interface\\Icons\\INV_Misc_Bag_11" },
      { id = "bag-4", name = "Bag Slot 4", icon = "Interface\\Icons\\INV_Misc_Bag_12" },
    },
    {
      { id = "mount",             name = "Mount",             icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
      { id = "epic-mount",        name = "Epic Mount",        icon = "Interface\\Icons\\Ability_Mount_Charger" },
      { id = "flying-mount",      name = "Flying Mount",      icon = "Interface\\Icons\\Ability_Mount_Gryphon_01" },
      { id = "epic-flying-mount", name = "Epic Flying Mount", icon = "Interface\\Icons\\Ability_Mount_NetherdrakeElite" },
    },
  }
  for r, rowItems in ipairs(generalRows) do
    for i, item in ipairs(rowItems) do
      local b = CreateIconBox(panel, 36, item.name)
      b:SetPoint("TOPLEFT", 22 + (i - 1) * 40, -310 - (r - 1) * 42)
      b.icon:SetTexture(item.icon)
      b:SetScript("OnClick", function() TT.ToggleLicenseBox(item.id) end)
      ui.general[item.id] = b
    end
  end
end

---------------------------------------------------------------------------
-- Goals checklist + dungeon tracker (second view)
---------------------------------------------------------------------------

local function CreateTextRow(parent, width, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, 15)
  b:RegisterForClicks("LeftButtonUp")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("LEFT")
  b.text:SetJustifyH("LEFT")
  b.text:SetWidth(width)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

local function BuildGoalsPanel(panel)
  local goalsHead = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  goalsHead:SetPoint("TOPLEFT", 0, 0)
  goalsHead:SetText("TAVERN GOALS")
  goalsHead:SetTextColor(0.55, 0.5, 0.35)

  ui.goalRows = {}
  local boxes = {}
  for _, group in ipairs({ TT.goalEnchantBoxes, TT.goalJcBoxes, TT.goalMiscBoxes }) do
    for _, box in ipairs(group) do boxes[#boxes + 1] = box end
  end
  for i, box in ipairs(boxes) do
    local row = CreateTextRow(panel, 340, function()
      TT.ToggleGoal(box.id)
    end)
    row:SetPoint("TOPLEFT", 0, -(16 + (i - 1) * 16))
    row.box = box
    row:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(box.name or box.label, 1, 0.82, 0)
      if box.desc then GameTooltip:AddLine(box.desc, 0.8, 0.8, 0.8, true) end
      if box.honor then
        GameTooltip:AddLine("Honor system - check it yourself.", 0.6, 0.6, 0.6)
      else
        GameTooltip:AddLine("Auto-detected.", 0.6, 0.6, 0.6)
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.goalRows[i] = row
  end

  local dungHead = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  dungHead:SetPoint("TOPLEFT", 380, 0)
  dungHead:SetText("DUNGEONS")
  dungHead:SetTextColor(0.55, 0.5, 0.35)
  ui.dungHead = dungHead

  ui.dungeonRows = {}
  local function addColumn(list, x)
    for i, name in ipairs(list) do
      -- manual marking always confirms - one stray click must never
      -- complete a dungeon (kills auto-complete these with no dialog)
      local row = CreateTextRow(panel, 180, function()
        if TT.DUNGEON_BONUS[name] then
          TT.Msg("That row completes on its own when its dungeons are done.")
          return
        end
        local done = TT.Run().dungeons[name]
        TT._dungeonPending = { name = name, un = done and true or false }
        StaticPopup_Show("TAVERNLEAGUETCG_DUNGEON", done
          and ("Un-mark |cffffd100" .. name .. "|r as complete?")
          or ("Mark |cffffd100" .. name .. "|r as complete?"))
      end)
      row:SetPoint("TOPLEFT", x, -(16 + (i - 1) * 14))
      row.dungeon = name
      row.derived = TT.DUNGEON_BONUS[name] ~= nil
      ui.dungeonRows[#ui.dungeonRows + 1] = row
    end
  end
  addColumn(TT.DUNGEONS_ERA, 380)
  if TT.IS_TBC then addColumn(TT.DUNGEONS_TBC, 580) end
end

StaticPopupDialogs.TAVERNLEAGUETCG_DUNGEON = {
  text = "%s",
  button1 = YES,
  button2 = NO,
  OnAccept = function()
    local p = TT._dungeonPending
    TT._dungeonPending = nil
    if not p then return end
    if p.un then
      TT.UncompleteDungeon(p.name)
    else
      TT.CompleteDungeon(p.name)
    end
  end,
  OnCancel = function() TT._dungeonPending = nil end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function RefreshGoalsPanel()
  local run = TT.Run()
  for _, row in ipairs(ui.goalRows or {}) do
    local done = run.goals[row.box.id]
    row.text:SetText((done and "|cff20ff20[x]|r " or "|cff777777[  ]|r ")
      .. (row.box.name or row.box.label))
    row.text:SetTextColor(done and 0.9 or 0.65, done and 0.9 or 0.65, done and 0.9 or 0.65)
  end
  local heroicNote = ""
  if TT.IS_TBC then
    local cleared, total = TT.HeroicsCleared()
    heroicNote = ("   |cff777777heroics %d/%d|r"):format(cleared, total)
  end
  ui.dungHead:SetText("DUNGEONS" .. heroicNote)
  for _, row in ipairs(ui.dungeonRows or {}) do
    local done = run.dungeons[row.dungeon]
    local heroic = run.dungeonsHeroic[row.dungeon]
    local mark = done and "|cff20ff20[x]|r " or "|cff777777[  ]|r "
    row.text:SetText(mark .. row.dungeon
      .. (heroic and " |cffff8000[H]|r" or "")
      .. (row.derived and " |cff777777*|r" or ""))
  end
end

---------------------------------------------------------------------------
-- Page + refresh
---------------------------------------------------------------------------

function TT.License_BuildUI(page)
  ui.page = page

  ui.header = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ui.header:SetPoint("TOPLEFT", 12, -6)
  ui.header:SetTextColor(GOLD.r, GOLD.g, GOLD.b)

  ui.subHeader = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.subHeader:SetPoint("LEFT", ui.header, "RIGHT", 14, 0)
  ui.subHeader:SetTextColor(0.7, 0.7, 0.7)

  ui.viewToggle = CreateActionButton(page, 150, 22, "Goals & dungeons", function()
    ui.showGoals = not ui.showGoals
    TT.License_Refresh()
  end)
  ui.viewToggle:SetPoint("TOPRIGHT", -10, -4)

  ui.board = CreateFrame("Frame", nil, page)
  ui.board:SetPoint("TOPLEFT", 6, -34)
  ui.board:SetSize(776, 448)
  BuildGearPanel(ui.board)
  BuildAbilitiesPanel(ui.board)
  BuildRightPanel(ui.board)

  ui.goalsPanel = CreateFrame("Frame", nil, page)
  ui.goalsPanel:SetPoint("TOPLEFT", 14, -40)
  ui.goalsPanel:SetPoint("BOTTOMRIGHT", -14, 10)
  ui.goalsPanel:Hide()
  BuildGoalsPanel(ui.goalsPanel)
end

local function RefreshAbilities()
  local run = TT.Run()
  for subspec, pool in pairs(ui.abilityPools) do
    local shown = 0
    for _, card in ipairs(TT.licenseCards or {}) do
      if card.type == "ability" and card.subspec == subspec and run.drawn[card.id] then
        shown = shown + 1
        local b = pool[shown]
        if b then
          b.icon:SetTexture(TT.GetLicenseIcon(card))
          b.tooltipText = card.name
          SetBoxState(b, true)
          b:Show()
        end
      end
    end
    for i = shown + 1, #pool do
      pool[i]:Hide()
    end
  end
end

function TT.License_Refresh()
  if not ui.page or not ui.page:IsShown() then return end
  local run = TT.Run()
  local licActive = TT.LicenseLayerActive()

  -- Collection has no license layer: the tab IS the goals page there
  local showGoals = ui.showGoals or not licActive
  ui.board:SetShown(not showGoals)
  ui.goalsPanel:SetShown(showGoals)
  ui.viewToggle:SetShown(licActive)
  ui.viewToggle:SetText(showGoals and "License board" or "Goals & dungeons")

  if showGoals then
    ui.dungHead:SetShown(licActive)
    for _, row in ipairs(ui.dungeonRows or {}) do
      row:SetShown(licActive)
    end
    RefreshGoalsPanel()
  end

  local drawn = 0
  for _ in pairs(run.drawn) do drawn = drawn + 1 end
  ui.header:SetText(licActive and "The Board" or "Tavern Goals")

  if not licActive then
    ui.subHeader:SetText("Goals pay a free card pack in this format.")
    return
  end

  if TT.FormatFlag("drafts") then
    ui.subHeader:SetText(("Draft packs: |cffffd100%d|r banked - one issued per level"):format(
      run.draftPacks or 0))
    if run.pendingDraft or run.pendingDraw then
      ui.openPackBtn:SetText("Resume draft pack")
      ui.openPackBtn:SetEnabled(true)
    else
      ui.openPackBtn:SetText(("Draft pack (%d)"):format(run.draftPacks or 0))
      ui.openPackBtn:SetEnabled((run.draftPacks or 0) > 0)
    end
    ui.bonusPackBtn:Hide()
    ui.undoBtn:Hide()          -- draft picks are final
    ui.packHint:SetText("Keep ONE card of five - a license, or the gear itself.")
  else
    ui.subHeader:SetText(("Class Packs: |cffffd100%d|r banked - one issued per level"):format(
      run.drawCredits or 0))
    if run.pendingDraw then
      ui.openPackBtn:SetText("Resume Class Pack")
      ui.openPackBtn:SetEnabled(true)
    else
      ui.openPackBtn:SetText(("Class Pack (%d)"):format(run.drawCredits or 0))
      ui.openPackBtn:SetEnabled((run.drawCredits or 0) > 0)
    end
    ui.bonusPackBtn:SetShown((run.bonusDraws or 0) > 0)
    ui.bonusPackBtn:SetText(("Bonus Pack (%d)"):format(run.bonusDraws or 0))
    ui.undoBtn:SetShown(run.lastUndo ~= nil)
    ui.packHint:SetText("Three licenses per pack - learn ONE.")
  end

  for slot, b in pairs(ui.gear) do SetBoxState(b, run.unlocked[slot]) end
  for i, b in ipairs(ui.talents) do SetBoxState(b, run.unlocked["talent-" .. i]) end
  ui.talentPoints:SetText(("%d / %d points earned"):format(
    TT.LicenseTalentPoints(), TT.LicenseMaxTalentPoints()))
  for id, b in pairs(ui.profs) do SetBoxState(b, run.unlocked[id]) end
  for id, b in pairs(ui.general) do SetBoxState(b, run.unlocked[id]) end
  RefreshAbilities()
end
