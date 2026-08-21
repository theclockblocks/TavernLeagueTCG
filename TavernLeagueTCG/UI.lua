-- Tavern League TCG UI: main window (Packs | Binder | Locked), the
-- three-stage pack opening overlay, the paginated binder and the minimap
-- button. 100% Lua, BackdropTemplate everywhere, no libraries.

local ADDON, TT = ...

local ui = {
  binderCells = {},   -- 12 fixed cells, retextured per page
  revealCards = {},   -- 8 card frames in the pack overlay
  packChoices = {},   -- 3 sealed pack frames
  violationRows = {}, -- 15 fixed font strings
}

local GOLD = { r = 1, g = 0.82, b = 0 }

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

local FOIL_TEXTURE = "Interface\\Cooldown\\star4"

---------------------------------------------------------------------------
-- Tiny tween engine: one shared OnUpdate driver for flips, rips, bobs and
-- foil glows. Zero AnimationGroup API risk across clients.
---------------------------------------------------------------------------

local animator = CreateFrame("Frame")
local tweens = {}     -- one-shot: { t, duration, step(progress), done() }
local loopers = {}    -- continuous: [key] = step(totalTime)

animator:SetScript("OnUpdate", function(self, elapsed)
  local now = GetTime()
  for i = #tweens, 1, -1 do
    local tw = tweens[i]
    local p = (now - tw.t0) / tw.duration
    if p >= 1 then
      tw.step(1)
      table.remove(tweens, i)
      if tw.done then tw.done() end
    else
      tw.step(p)
    end
  end
  for _, step in pairs(loopers) do
    step(now)
  end
  if #tweens == 0 and next(loopers) == nil then
    self:Hide()
  end
end)

local function StartTween(duration, step, done)
  tweens[#tweens + 1] = { t0 = GetTime(), duration = duration, step = step, done = done }
  animator:Show()
end

local function StartLoop(key, step)
  loopers[key] = step
  animator:Show()
end

local function StopLoop(key)
  loopers[key] = nil
end

---------------------------------------------------------------------------
-- Widget helpers
---------------------------------------------------------------------------

local function AttachTooltip(widget)
  widget:SetScript("OnEnter", function(self)
    if not self.tooltipText then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tooltipText, 1, 1, 1)
    if self.tooltipSub then
      GameTooltip:AddLine(self.tooltipSub, 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function CreatePanel(parent, w, h)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  if w then f:SetSize(w, h) end
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

local function CreateActionButton(parent, w, h, text, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

---------------------------------------------------------------------------
-- Card helpers
---------------------------------------------------------------------------

local function CardIcon(key)
  local row = TT.cardIndex and TT.cardIndex[key]
  if not row then return TT.QUESTION_MARK end
  local cat = TT.categories[row.kind or "item"]
  return (cat and cat.GetIconNow(row)) or TT.QUESTION_MARK
end

local function CardName(key)
  local row = TT.cardIndex and TT.cardIndex[key]
  if not row then return nil end
  return row.n or TT.ItemName(row.i)
end

local function CardRarity(key)
  local row = TT.cardIndex and TT.cardIndex[key]
  return row and row.r or 1
end

---------------------------------------------------------------------------
-- 3D creature card art: owned creature cards render the NPC's live game
-- model in the card window via a lazily-created PlayerModel child. The
-- per-set icon stays underneath as loading/fallback art; a dark backdrop
-- appears only once real geometry loads, so an NPC the client can't
-- resolve degrades back to the icon instead of an empty hole. Model data
-- for unseen NPCs can arrive async, hence the OnModelLoaded hook plus a
-- couple of retries.
---------------------------------------------------------------------------

local function CardModel_Frame(m)
  -- camera framing only sticks once geometry exists
  if m.SetPortraitZoom then
    m:SetPortraitZoom(TT.MODEL.portraitZoom)
  elseif m.SetCamera then
    m:SetCamera(0)
  end
  m.facing = TT.MODEL.facing
  m:SetFacing(m.facing)
end

-- Drag-to-rotate: the model captures the mouse, so plain clicks and hover
-- are forwarded to the card underneath - only real drags spin the model.
local function CardModel_DragStart(m)
  m.dragging = true
  m.dragX = GetCursorPosition()
  m:SetScript("OnUpdate", function(self)
    local x = GetCursorPosition()
    self.facing = (self.facing or TT.MODEL.facing)
      + (x - self.dragX) * TT.MODEL.dragSpeed
    self.dragX = x
    self:SetFacing(self.facing)
  end)
end

local function CardModel_DragStop(m)
  m.dragging = false
  m.dragEnded = GetTime()
  m:SetScript("OnUpdate", nil)
end

local function CardModel_MouseUp(m, button)
  -- ignore the release that ends a rotation drag, whichever order the
  -- client fires OnDragStop/OnMouseUp in
  if m.dragging or (m.dragEnded and GetTime() - m.dragEnded < 0.05) then return end
  local onClick = m.cell:GetScript("OnClick")
  if onClick then onClick(m.cell, button) end
end

local function CardModel_Loaded(m)
  m.loaded = true
  m.cell.modelBg:Show()
  CardModel_Frame(m)
end

local function CardModel_ScheduleRetry(m)
  local id = m.npcId
  m.pendingRetry = true
  C_Timer.After(0.8, function()
    m.pendingRetry = false
    if m.npcId ~= id or m.loaded or not m:IsVisible() then return end
    -- clients without OnModelLoaded: detect a quiet success by file id
    if m.GetModelFileID and m:GetModelFileID() then
      CardModel_Loaded(m)
      return
    end
    if m.retries >= 2 then return end
    m.retries = m.retries + 1
    m:ClearModel()
    m:SetCreature(id)
    CardModel_ScheduleRetry(m)
  end)
end

local function EnsureCardModel(c)
  if c.model then return c.model end
  -- dark window backdrop, revealed only when a model actually loads
  c.modelBg = c:CreateTexture(nil, "ARTWORK", nil, 2)
  c.modelBg:SetPoint("TOPLEFT", c.icon, "TOPLEFT")
  c.modelBg:SetPoint("BOTTOMRIGHT", c.icon, "BOTTOMRIGHT")
  c.modelBg:SetColorTexture(unpack(TT.MODEL.bg))
  c.modelBg:Hide()

  local m = CreateFrame("PlayerModel", nil, c)
  m:SetPoint("TOPLEFT", c.icon, "TOPLEFT")
  m:SetPoint("BOTTOMRIGHT", c.icon, "BOTTOMRIGHT")
  m:SetFrameLevel(c:GetFrameLevel() + 1)
  m.cell = c
  if m:HasScript("OnModelLoaded") then
    m:SetScript("OnModelLoaded", CardModel_Loaded)
  end

  -- spin the creature by dragging; clicks and hover fall through to the card
  m:EnableMouse(true)
  m:RegisterForDrag("LeftButton")
  m:SetScript("OnDragStart", CardModel_DragStart)
  m:SetScript("OnDragStop", CardModel_DragStop)
  m:SetScript("OnMouseUp", CardModel_MouseUp)
  m:SetScript("OnEnter", function(self)
    local onEnter = self.cell:GetScript("OnEnter")
    if onEnter then onEnter(self.cell) end
  end)
  m:SetScript("OnLeave", function(self)
    local onLeave = self.cell:GetScript("OnLeave")
    if onLeave then onLeave(self.cell) end
  end)

  m:Hide()
  c.model = m
  return m
end

local function SetCardModel(c, npcId)
  local m = EnsureCardModel(c)
  if m.npcId == npcId then
    m:Show()
    if m.loaded then
      c.modelBg:Show()
    elseif not m.pendingRetry then
      -- earlier attempt came up empty (NPC not cached yet) - try again
      m:ClearModel()
      m:SetCreature(npcId)
      CardModel_ScheduleRetry(m)
    end
    return
  end
  m.npcId = npcId
  m.loaded = false
  m.retries = 0
  c.modelBg:Hide()
  m:Show()
  m:ClearModel()
  m:SetCreature(npcId)
  CardModel_ScheduleRetry(m)
end

local function ClearCardModel(c)
  if not c.model then return end
  c.model:Hide()
  c.modelBg:Hide()
end

---------------------------------------------------------------------------
-- Frame construction
---------------------------------------------------------------------------

local frame

function TT.ToggleFrame()
  if not frame then return end
  if frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
    TT.Refresh()
  end
end

function TT.ShowTab(which)
  ui.activeTab = which
  ui.packsPage:SetShown(which == "packs")
  ui.binderPage:SetShown(which == "binder")
  ui.lockedPage:SetShown(which == "locked")
  ui.tradePage:SetShown(which == "trade")
  ui.packsTab:SetEnabled(which ~= "packs")
  ui.binderTab:SetEnabled(which ~= "binder")
  ui.lockedTab:SetEnabled(which ~= "locked")
  ui.tradeTab:SetEnabled(which ~= "trade")
  TT.Refresh()
end

local function BuildToolbar()
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT", 10, -30)
  bar:SetPoint("TOPRIGHT", -10, -30)
  bar:SetHeight(30)

  ui.creditsText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ui.creditsText:SetPoint("LEFT", 4, 0)
  ui.creditsText:SetTextColor(GOLD.r, GOLD.g, GOLD.b)

  ui.profileText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.profileText:SetPoint("LEFT", ui.creditsText, "RIGHT", 16, 0)
  ui.profileText:SetTextColor(0.7, 0.7, 0.7)

  ui.packsTab = CreateActionButton(bar, 78, 20, "Packs", function() TT.ShowTab("packs") end)
  ui.packsTab:SetPoint("RIGHT", -246, 0)
  ui.binderTab = CreateActionButton(bar, 78, 20, "Binder", function() TT.ShowTab("binder") end)
  ui.binderTab:SetPoint("RIGHT", -164, 0)
  ui.lockedTab = CreateActionButton(bar, 78, 20, "Locked", function() TT.ShowTab("locked") end)
  ui.lockedTab:SetPoint("RIGHT", -82, 0)
  ui.tradeTab = CreateActionButton(bar, 78, 20, "Trade", function() TT.ShowTab("trade") end)
  ui.tradeTab:SetPoint("RIGHT", 0, 0)
end

---------------------------------------------------------------------------
-- Packs page
---------------------------------------------------------------------------

local function BuildPacksPage(page)
  local panel = CreatePanel(page)
  panel:SetAllPoints(page)

  ui.bigCredits = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  ui.bigCredits:SetPoint("TOP", 0, -60)
  ui.bigCredits:SetTextColor(GOLD.r, GOLD.g, GOLD.b)

  local creditsLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  creditsLabel:SetPoint("TOP", ui.bigCredits, "BOTTOM", 0, -4)
  creditsLabel:SetText("CREDITS")
  creditsLabel:SetTextColor(0.6, 0.6, 0.6)

  ui.statsLine = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.statsLine:SetPoint("TOP", creditsLabel, "BOTTOM", 0, -14)
  ui.statsLine:SetTextColor(0.75, 0.75, 0.75)

  ui.earnLine = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.earnLine:SetPoint("TOP", ui.statsLine, "BOTTOM", 0, -4)
  ui.earnLine:SetTextColor(0.55, 0.55, 0.55)

  ui.openPackBtn = CreateActionButton(panel, 220, 36,
    "Open Pack - " .. TT.FormatNumber(TT.ECON.packPrice) .. "c", function()
      if TT.BuyPack() then TT.UI_ShowPackOverlay() end
    end)
  ui.openPackBtn:SetPoint("TOP", ui.earnLine, "BOTTOM", 0, -26)

  ui.resumePackBtn = CreateActionButton(panel, 220, 28, "Resume opening your pack",
    function() TT.UI_ShowPackOverlay() end)
  ui.resumePackBtn:SetPoint("TOP", ui.openPackBtn, "BOTTOM", 0, -8)
  ui.resumePackBtn:Hide()

  local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("BOTTOM", 0, 18)
  hint:SetWidth(560)
  hint:SetTextColor(0.5, 0.5, 0.5)
  hint:SetText("Earn credits from experience, level-ups, killing blows and quest turn-ins. " ..
    "All characters on this realm share the collection - roll on a new realm for a fresh run.")
end

---------------------------------------------------------------------------
-- Pack opening overlay: selection -> rip -> reveal
---------------------------------------------------------------------------

local PACK_TINTS = {
  { 0.55, 0.15, 0.15 },
  { 0.15, 0.25, 0.55 },
  { 0.15, 0.45, 0.20 },
  { 0.40, 0.18, 0.50 },
}

-- x-offset from stage center for pack choice i (used by layout + bobbing)
local function PackChoiceX(i)
  local W, GAP = 140, 32
  local n = #TT.PACK_TYPES
  local totalW = n * W + (n - 1) * GAP
  return -totalW / 2 + (i - 1) * (W + GAP)
end

local function CreateSealedPack(parent, index)
  local ptype = TT.PACK_TYPES[index]
  local p = CreateFrame("Button", nil, parent, "BackdropTemplate")
  p:SetSize(140, 230)
  p:SetBackdrop(PANEL_BACKDROP)
  p:SetBackdropColor(unpack(PACK_TINTS[index]))
  p:SetBackdropBorderColor(GOLD.r, GOLD.g, GOLD.b)
  p.packType = ptype.key

  -- the card back art fills the pack; a subtle per-pack tint keeps the
  -- three choices visually distinct
  p.art = p:CreateTexture(nil, "ARTWORK")
  p.art:SetPoint("TOPLEFT", 3, -3)
  p.art:SetPoint("BOTTOMRIGHT", -3, 3)
  p.art:SetTexture(TT.CARD_BACK_TEX)
  p.art:SetVertexColor(unpack(TT.LAYOUT.packArtTints[index]))

  -- the pick is a real choice now: label each pack with its type
  p.label = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  p.label:SetPoint("TOP", p, "BOTTOM", 0, -8)
  p.label:SetText(ptype.label)
  p.label:SetTextColor(GOLD.r, GOLD.g, GOLD.b)

  p.sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  p.sub:SetPoint("TOP", p.label, "BOTTOM", 0, -2)
  p.sub:SetText(ptype.sub)
  p.sub:SetTextColor(0.6, 0.6, 0.6)

  p:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(1, 1, 1)
  end)
  p:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(GOLD.r, GOLD.g, GOLD.b)
  end)
  return p
end

local function CreateRevealCard(parent)
  local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
  c:SetSize(110, 190)
  c:SetBackdrop(PANEL_BACKDROP)

  -- rotating glow BEHIND the card (foil + climax suspense)
  c.glow = parent:CreateTexture(nil, "ARTWORK")
  c.glow:SetSize(190, 190)
  c.glow:SetPoint("CENTER", c, "CENTER")
  c.glow:SetTexture(FOIL_TEXTURE)
  c.glow:SetVertexColor(1, 0.85, 0.3, 0)
  c.glow:SetBlendMode("ADD")

  -- face-down: the card back art fills the card
  c.back = c:CreateTexture(nil, "ARTWORK")
  c.back:SetPoint("TOPLEFT", 3, -3)
  c.back:SetPoint("BOTTOMRIGHT", -3, 3)
  c.back:SetTexture(TT.CARD_BACK_TEX)

  -- face-up: the card front frame, with the item icon inside the frame's
  -- gold window and the name in the open band beneath it. All positions
  -- come from TT.LAYOUT (Data.lua) so new art only needs re-measuring.
  local m = TT.CardFaceMetrics(110, 190, 3)
  c.front = c:CreateTexture(nil, "ARTWORK")
  c.front:SetPoint("TOPLEFT", 3, -3)
  c.front:SetPoint("BOTTOMRIGHT", -3, 3)
  c.front:SetTexture(TT.CARD_FRONT_TEX)
  c.front:Hide()

  c.icon = c:CreateTexture(nil, "ARTWORK", nil, 1)
  c.icon:SetPoint("TOPLEFT", m.iconLeft, -m.iconTop)
  c.icon:SetPoint("BOTTOMRIGHT", -m.iconRight, m.iconBottom)
  c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  c.icon:Hide()

  c.name = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  c.name:SetPoint("TOP", c, "TOP", 0, -m.nameTop)
  c.name:SetWidth(92)

  return c
end

local function SetCardFaceDown(c)
  c:SetBackdropColor(0.10, 0.09, 0.14, 1)
  c:SetBackdropBorderColor(0.35, 0.32, 0.45)
  c.back:Show()
  c.front:Hide()
  c.icon:Hide()
  ClearCardModel(c)
  c.name:SetText("")
  c.glow:SetVertexColor(1, 0.85, 0.3, 0)
  c.faceUp = false
end

local function SetCardFaceUp(c, cardData)
  local key, foil = cardData.k, cardData.f
  local tier = CardRarity(key)
  local r, g, b = TT.RarityColor(tier)

  c:SetBackdropColor(0.08, 0.08, 0.10, 1)
  c:SetBackdropBorderColor(r, g, b)
  c.back:Hide()
  c.front:Show()
  c.icon:SetTexture(CardIcon(key))
  c.icon:Show()

  -- creature cards wear their live 3D model over the fallback icon
  local row = TT.cardIndex and TT.cardIndex[key]
  if row and (row.kind or "item") == "npc" then
    SetCardModel(c, row.i)
  else
    ClearCardModel(c)
  end

  local name = CardName(key)
  c.pendingKey = name and nil or key
  c.name:SetText(name or "...")
  c.name:SetTextColor(r, g, b)

  if foil then
    local loopKey = "foil" .. tostring(c)
    StartLoop(loopKey, function(now)
      if not c:IsVisible() then StopLoop(loopKey); return end
      c.glow:SetRotation(now * 0.8)
      c.glow:SetVertexColor(1, 0.85, 0.3, 0.35 + 0.25 * math.sin(now * 3))
    end)
  end
  c.faceUp = true
end

local overlay

local function OverlayShowStage(stage)
  ui.selectStage:SetShown(stage == "select")
  ui.revealStage:SetShown(stage == "reveal")
end

local function UpdateRevealClickability()
  local p = TT.Profile()
  local pack = p.pendingPack
  if not pack then return end
  local nextIdx = pack.revealed + 1
  for i, c in ipairs(ui.revealCards) do
    if i == nextIdx and not ui.revealLockout then
      c:Enable()
      if not c.faceUp then
        c:SetBackdropBorderColor(GOLD.r, GOLD.g, GOLD.b)
      end
    else
      c:Disable()
    end
  end
  ui.doneBtn:SetShown(pack.revealed >= #pack.cards)
  if pack.revealed >= #pack.cards then
    local newCards = 0
    local best = 0
    for _, cd in ipairs(pack.cards) do
      local tier = CardRarity(cd.k)
      if tier > best then best = tier end
    end
    ui.summaryText:SetText(("Best pull: |cffffd100%s|r%s"):format(
      TT.RarityLabel(best), pack.god and "  -  |cffff8000GOD PACK|r" or ""))
    ui.summaryText:Show()
  else
    ui.summaryText:Hide()
  end
end

-- Climax beat before card 8 becomes clickable: pulsing glow + short lockout.
local function ClimaxSuspense(c)
  ui.revealLockout = true
  UpdateRevealClickability()
  TT.PlaySoundKit("IG_QUEST_LIST_OPEN")
  local loopKey = "suspense"
  StartLoop(loopKey, function(now)
    if not c:IsVisible() then StopLoop(loopKey); return end
    c.glow:SetRotation(now * 1.6)
    c.glow:SetVertexColor(1, 0.85, 0.3, 0.4 + 0.3 * math.sin(now * 6))
  end)
  StartTween(0.9, function() end, function()
    ui.revealLockout = false
    UpdateRevealClickability()
  end)
  c.suspenseLoop = loopKey
end

local function FlipCard(c, idx, cardData)
  local w = c:GetWidth()
  ui.revealLockout = true
  UpdateRevealClickability()
  local isClimax = (idx == TT.ECON.cardsPerPack)
  local dur = isClimax and 0.22 or 0.12

  StartTween(dur, function(pr)
    c:SetWidth(math.max(2, w * (1 - pr)))
  end, function()
    if c.suspenseLoop then StopLoop(c.suspenseLoop); c.suspenseLoop = nil end
    SetCardFaceUp(c, cardData)
    StartTween(dur, function(pr)
      c:SetWidth(math.max(2, w * pr))
    end, function()
      c:SetWidth(w)
      ui.revealLockout = false

      local tier = CardRarity(cardData.k)
      local pack = TT.Profile().pendingPack
      if pack and pack.god and idx == 1 then
        if RaidNotice_AddMessage and RaidWarningFrame then
          RaidNotice_AddMessage(RaidWarningFrame, "GOD PACK!", ChatTypeInfo["RAID_WARNING"])
        end
        TT.PlaySoundKit("RAID_WARNING")
      elseif isClimax and tier >= 3 then
        TT.PlaySoundKit("RAID_WARNING")
        local flashW = ui.climaxFlash
        local r, g, b = TT.RarityColor(tier)
        flashW:SetColorTexture(r, g, b, 0.35)
        flashW:Show()
        StartTween(0.5, function(pr) flashW:SetAlpha(0.35 * (1 - pr)) end,
          function() flashW:Hide(); flashW:SetAlpha(1) end)
      elseif tier >= 4 or cardData.f then
        TT.PlaySoundKit("IG_QUEST_LOG_OPEN")
      else
        TT.PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
      end

      -- climax suspense beat before the final card unlocks
      if idx == TT.ECON.cardsPerPack - 1 then
        ClimaxSuspense(ui.revealCards[TT.ECON.cardsPerPack])
      else
        UpdateRevealClickability()
      end
    end)
  end)
end

local function OnRevealCardClick(c, idx)
  local pack = TT.Profile().pendingPack
  if not pack or ui.revealLockout then return end
  if idx ~= pack.revealed + 1 then return end
  local revealedIdx, cardData = TT.RevealNext()
  if not revealedIdx then return end
  FlipCard(c, revealedIdx, cardData)
end

local function BuildRevealStage(parent)
  local stage = CreateFrame("Frame", nil, parent)
  stage:SetAllPoints(parent)
  ui.revealStage = stage

  local title = CreateHeader(stage, "Flip the cards - left to right, save the last for the big one")
  title:SetPoint("TOP", 0, -18)

  local COLS, W, H, GAP = 4, 110, 190, 14
  local gridW = COLS * W + (COLS - 1) * GAP
  for i = 1, TT.ECON.cardsPerPack do
    local col = (i - 1) % COLS
    local row = math.floor((i - 1) / COLS)
    local c = CreateRevealCard(stage)
    c:SetPoint("TOPLEFT", stage, "TOP", -gridW / 2 + col * (W + GAP),
      -46 - row * (H + GAP))
    local idx = i
    c:SetScript("OnClick", function(self) OnRevealCardClick(self, idx) end)
    ui.revealCards[i] = c
  end

  ui.climaxFlash = stage:CreateTexture(nil, "OVERLAY")
  ui.climaxFlash:SetAllPoints(stage)
  ui.climaxFlash:Hide()

  ui.summaryText = stage:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ui.summaryText:SetPoint("BOTTOM", 0, 48)
  ui.summaryText:Hide()

  ui.doneBtn = CreateActionButton(stage, 160, 30, "Add to Binder", function()
    local newCount = TT.FinishPack()
    for _, c in ipairs(ui.revealCards) do
      StopLoop("foil" .. tostring(c))
    end
    StopLoop("suspense")
    overlay:Hide()
    if newCount and newCount > 0 then
      TT.Msg(newCount .. " new card" .. (newCount == 1 and "" or "s") .. " added to the binder!")
    end
    TT.Refresh()
  end)
  ui.doneBtn:SetPoint("BOTTOM", 0, 16)
  ui.doneBtn:Hide()
end

local function EnterRevealStage()
  OverlayShowStage("reveal")
  local pack = TT.Profile().pendingPack
  if not pack or not pack.cards then overlay:Hide(); return end
  for i, c in ipairs(ui.revealCards) do
    StopLoop("foil" .. tostring(c))
    if i <= pack.revealed then
      SetCardFaceUp(c, pack.cards[i])
    else
      SetCardFaceDown(c)
    end
  end
  ui.revealLockout = false
  -- resuming right before the climax card re-arms the suspense beat
  if pack.revealed == TT.ECON.cardsPerPack - 1 then
    ClimaxSuspense(ui.revealCards[TT.ECON.cardsPerPack])
  end
  UpdateRevealClickability()
end

local function OnPackChosen(chosen)
  -- the pick decides which pool the pack rolls from; contents are rolled
  -- and persisted here, before any reveal
  if not TT.PickPackType(chosen.packType) then return end
  TT.PlaySoundKit("IG_BACKPACK_OPEN")
  StopLoop("packbob")
  ui.selectLockout = true

  for _, p in ipairs(ui.packChoices) do
    p:Disable()
    if p ~= chosen then
      StartTween(0.35, function(pr)
        p:SetAlpha(1 - pr)
      end, function() p:Hide(); p:SetAlpha(1) end)
    end
  end

  -- the chosen pack flares, rises and fades open
  chosen:SetBackdropBorderColor(1, 1, 1)
  local point, rel, relPoint, x0, y0 = chosen:GetPoint(1)
  StartTween(0.55, function(pr)
    chosen:ClearAllPoints()
    chosen:SetPoint(point, rel, relPoint, x0, y0 + 45 * pr)
    chosen:SetAlpha(1 - pr * pr)
  end, function()
    chosen:Hide()
    chosen:SetAlpha(1)
    ui.selectLockout = false
    EnterRevealStage()
  end)
end

local function BuildSelectStage(parent)
  local stage = CreateFrame("Frame", nil, parent)
  stage:SetAllPoints(parent)
  ui.selectStage = stage

  local title = CreateHeader(stage, "Pick your pack - the choice decides what's inside")
  title:SetPoint("TOP", 0, -30)

  for i = 1, #TT.PACK_TYPES do
    local p = CreateSealedPack(stage, i)
    p:SetPoint("TOPLEFT", stage, "TOP", PackChoiceX(i), -90)
    p:SetScript("OnClick", function(self)
      if not ui.selectLockout then OnPackChosen(self) end
    end)
    ui.packChoices[i] = p
  end

  local sub = stage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("BOTTOM", 0, 40)
  sub:SetTextColor(0.55, 0.55, 0.55)
  sub:SetText("Same odds in every pack - the type picks the pool.")
end

local function EnterSelectStage()
  OverlayShowStage("select")
  ui.selectLockout = false
  for i, p in ipairs(ui.packChoices) do
    p:SetAlpha(1)
    p:SetBackdropBorderColor(GOLD.r, GOLD.g, GOLD.b)
    p:Enable()
    p:Show()
  end
  StartLoop("packbob", function(now)
    if not ui.selectStage:IsVisible() then StopLoop("packbob"); return end
    for i, p in ipairs(ui.packChoices) do
      local off = 6 * math.sin(now * 1.4 + i * 2.1)
      p:ClearAllPoints()
      p:SetPoint("TOPLEFT", ui.selectStage, "TOP", PackChoiceX(i), -90 + off)
    end
  end)
end

local function BuildPackOverlay()
  overlay = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  overlay:SetPoint("TOPLEFT", 4, -26)
  overlay:SetPoint("BOTTOMRIGHT", -4, 4)
  overlay:SetBackdrop(PANEL_BACKDROP)
  overlay:SetBackdropColor(0.02, 0.02, 0.04, 0.97)
  overlay:SetBackdropBorderColor(GOLD.r, GOLD.g, GOLD.b)
  overlay:SetFrameLevel(frame:GetFrameLevel() + 20)
  overlay:EnableMouse(true)   -- eats clicks on everything behind it
  overlay:Hide()

  BuildSelectStage(overlay)
  BuildRevealStage(overlay)
end

function TT.UI_ShowPackOverlay()
  if not frame then return end
  local pack = TT.Profile().pendingPack
  if not pack then return end
  frame:Show()
  overlay:Show()
  if pack.cards then
    EnterRevealStage()
  else
    EnterSelectStage()
  end
end

---------------------------------------------------------------------------
-- Binder page
---------------------------------------------------------------------------

local BINDER_COLS, BINDER_ROWS = 6, 2
local BINDER_PAGE_SIZE = BINDER_COLS * BINDER_ROWS

local OWN_FILTERS = {
  { key = "all", label = "All Cards" },
  { key = "owned", label = "Owned" },
  { key = "missing", label = "Missing" },
}

local function CycleIndex(list, key)
  for i, e in ipairs(list) do
    if e.key == key then return i end
  end
  return 1
end

local function BuildBinderList()
  local b = TT.cdb.binder
  local p = TT.Profile()
  local search = (b.search or ""):lower()
  local out = {}
  for _, row in ipairs(TT.pool or {}) do
    if not TT.IsGated(row) then
      local key = TT.CardKey(row)
      local col = p.collection[key]
      local owned = col ~= nil and ((col.n or 0) + (col.f or 0)) > 0
      local ok = true
      if b.own == "owned" and not owned then ok = false end
      if b.own == "missing" and owned then ok = false end
      if ok and b.rarity ~= 0 and row.r ~= b.rarity then ok = false end
      if ok and b.bucket ~= "all" and TT.SlotBucket(row) ~= b.bucket then ok = false end
      if ok and search ~= "" then
        local cat = TT.categories[row.kind or "item"]
        local name = cat and cat.GetNameNow(row)
        if not (name and name:lower():find(search, 1, true)) then ok = false end
      end
      if ok then out[#out + 1] = row end
    end
  end
  return out
end

local function CreateBinderCell(parent)
  -- a miniature card face: front-frame art, item icon in the art's gold
  -- window, name in the band below. Positions come from TT.LAYOUT.
  local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
  c:SetSize(116, 200)
  c:SetBackdrop(BOX_BACKDROP)
  c:SetBackdropColor(0.05, 0.05, 0.08, 1)

  local m = TT.CardFaceMetrics(116, 200, 2)
  c.front = c:CreateTexture(nil, "ARTWORK")
  c.front:SetPoint("TOPLEFT", 2, -2)
  c.front:SetPoint("BOTTOMRIGHT", -2, 2)
  c.front:SetTexture(TT.CARD_FRONT_TEX)

  c.icon = c:CreateTexture(nil, "ARTWORK", nil, 1)
  c.icon:SetPoint("TOPLEFT", m.iconLeft, -m.iconTop)
  c.icon:SetPoint("BOTTOMRIGHT", -m.iconRight, m.iconBottom)
  c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  c.name = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  c.name:SetPoint("TOP", c, "TOP", 0, -m.nameTop)
  c.name:SetWidth(94)
  if c.name.SetMaxLines then c.name:SetMaxLines(2) end

  -- badges and the foil sheen live on a child frame two levels up so they
  -- stay visible above the 3D creature model (which sits one level up)
  local overlayFrame = CreateFrame("Frame", nil, c)
  overlayFrame:SetAllPoints(c)
  overlayFrame:SetFrameLevel(c:GetFrameLevel() + 2)

  c.count = overlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  c.count:SetPoint("BOTTOMRIGHT", c.icon, "BOTTOMRIGHT", -3, 3)
  c.count:SetTextColor(1, 0.82, 0)

  -- foil cards pulse a golden sheen and radiate an aura past the card edges
  c.foilGlow = overlayFrame:CreateTexture(nil, "ARTWORK", nil, 2)
  c.foilGlow:SetPoint("TOPLEFT", 2, -2)
  c.foilGlow:SetPoint("BOTTOMRIGHT", -2, 2)
  c.foilGlow:SetColorTexture(1, 0.85, 0.3, 1)
  c.foilGlow:SetBlendMode("ADD")
  c.foilGlow:SetAlpha(0)

  c.aura = c:CreateTexture(nil, "BACKGROUND", nil, -1)
  c.aura:SetPoint("CENTER")
  c.aura:SetSize(116 * TT.LAYOUT.auraScale, 200 * TT.LAYOUT.auraScale)
  c.aura:SetTexture(FOIL_TEXTURE)
  c.aura:SetBlendMode("ADD")
  c.aura:SetVertexColor(1, 0.85, 0.3, 0)

  c.newTag = overlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  c.newTag:SetPoint("TOPLEFT", c.icon, "TOPLEFT", 3, -3)
  c.newTag:SetText("NEW")
  c.newTag:SetTextColor(0.3, 1, 0.3)

  c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  c:SetScript("OnClick", function(self, button)
    if not self.cardKey then return end
    if button == "LeftButton" then
      if TT.Trade_IsOpen and TT.Trade_IsOpen() then
        TT.Trade_TryAdd(self.cardKey, IsControlKeyDown())
      end
      return
    end
    -- right-click: sell a spare copy back for credits (Ctrl for foil)
    local key = self.cardKey
    local row = TT.cardIndex[key]
    if not row then return end
    local p = TT.Profile()
    local col = p.collection[key]
    local total = col and ((col.n or 0) + (col.f or 0)) or 0
    if total > 1 then
      local foil = IsControlKeyDown()
      local field = foil and "f" or "n"
      if (col[field] or 0) < 1 then
        TT.Msg(foil and "No foil copy to sell (Ctrl sells foils)."
          or "Only foil copies spare - Ctrl-right-click to sell a foil.")
        return
      end
      local credits = TT.ECON.sellValue[row.r] * (foil and TT.ECON.foilSellMult or 1)
      TT._sellKey = key
      TT._sellFoil = foil
      StaticPopup_Show("TAVERNLEAGUETCG_SELL",
        ("Sell a %s|cffffd100%s|r spare?\n\nPays %s credits. You keep %d cop%s."):format(
          foil and "FOIL " or "", row.n or key, TT.FormatNumber(credits),
          total - 1, total - 1 == 1 and "y" or "ies"))
    elseif total == 1 then
      TT.Msg("That's your only copy - selling always keeps at least one.")
    end
  end)
  c:SetScript("OnEnter", function(self)
    if not self.cardKey then return end
    local row = TT.cardIndex[self.cardKey]
    if not row then return end
    ui.hoverCell = self
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.itemId then
      -- full item tooltips need the client cache; show a light card tooltip
      -- until the data arrives (TT.ItemName kicks off the load, and
      -- UI_OnItemCached re-runs this handler in place when it lands)
      if TT.ItemName(self.itemId) then
        GameTooltip:SetHyperlink("item:" .. self.itemId)
      else
        local r, g, b = TT.RarityColor(row.r)
        GameTooltip:SetText(row.n or ("Item " .. self.itemId), r, g, b)
        GameTooltip:AddLine("Item details loading...", 0.6, 0.6, 0.6)
      end
    else
      -- creature card: everything we know ships with the pool
      local r, g, b = TT.RarityColor(row.r)
      GameTooltip:SetText(row.n or "?", r, g, b)
      GameTooltip:AddLine(TT.NPC_SET_LABELS[row.s] or "Creature", 0.8, 0.8, 0.8)
      if self.model and self.model:IsShown() then
        GameTooltip:AddLine("Drag the art to rotate", 0.5, 0.5, 0.5)
      end
    end
    if TT.Trade_IsOpen and TT.Trade_IsOpen() then
      GameTooltip:AddLine("Click: add to trade offer (Ctrl: foil copy)", 0.3, 1, 0.3)
    end
    local col = TT.Profile().collection[self.cardKey]
    local total = col and ((col.n or 0) + (col.f or 0)) or 0
    if total > 1 then
      GameTooltip:AddLine(("Right-click: sell a spare for %s credits (Ctrl: foil, x%d)"):format(
        TT.FormatNumber(TT.ECON.sellValue[row.r]), TT.ECON.foilSellMult), 0.6, 0.7, 1)
    end
    GameTooltip:Show()
  end)
  c:SetScript("OnLeave", function()
    ui.hoverCell = nil
    GameTooltip:Hide()
  end)
  return c
end

local function RefreshBinder()
  if not ui.binderPage:IsShown() then return end
  local b = TT.cdb.binder
  local p = TT.Profile()
  local list = BuildBinderList()
  local pages = math.max(1, math.ceil(#list / BINDER_PAGE_SIZE))
  if b.page > pages then b.page = pages end
  if b.page < 1 then b.page = 1 end

  local owned, foils = TT.OwnedCounts()
  ui.binderHeader:SetText(("Owned %s / %s   (foil %s)"):format(
    TT.FormatNumber(owned), TT.FormatNumber(TT.poolCount or 0), TT.FormatNumber(foils)))
  ui.binderPageText:SetText(("Page %d / %d"):format(b.page, pages))
  ui.binderPrev:SetEnabled(b.page > 1)
  ui.binderNext:SetEnabled(b.page < pages)

  ui.ownFilterBtn:SetText(OWN_FILTERS[CycleIndex(OWN_FILTERS, b.own)].label)
  ui.rarityFilterBtn:SetText(b.rarity == 0 and "All Rarities" or TT.RarityLabel(b.rarity))
  local bucketIdx = 1
  for i, e in ipairs(TT.SLOT_BUCKETS) do
    if e.key == b.bucket then bucketIdx = i end
  end
  ui.bucketFilterBtn:SetText(TT.SLOT_BUCKETS[bucketIdx].label)

  local offset = (b.page - 1) * BINDER_PAGE_SIZE
  local pageRows = {}

  -- NEW badges last until the player has actually viewed the card: when
  -- the page/filters change, everything shown on the previous view is
  -- marked seen (the binder's OnHide does the same for the current page)
  local sig = table.concat({ b.page, b.own, b.rarity, b.bucket, b.search }, "|")
  if ui.freshSig and ui.freshSig ~= sig then
    for k in pairs(ui.freshKeys or {}) do p.fresh[k] = nil end
    ui.freshKeys = {}
  end
  ui.freshSig = sig
  ui.freshKeys = ui.freshKeys or {}
  for i = 1, BINDER_PAGE_SIZE do
    local cell = ui.binderCells[i]
    local row = list[offset + i]
    if row then
      local key = TT.CardKey(row)
      local col = p.collection[key]
      local n, f = (col and col.n or 0), (col and col.f or 0)
      local ownedCard = (n + f) > 0
      local r, g, bl = TT.RarityColor(row.r)

      local isNpc = (row.kind or "item") == "npc"
      cell.itemId = (not isNpc) and row.i or nil
      cell.cardKey = key
      if isNpc and ownedCard then
        -- live 3D model; the set icon underneath covers the load gap
        cell.icon:SetTexture(CardIcon(key))
        SetCardModel(cell, row.i)
      else
        -- unowned creatures are a mystery: "?" until you pull the card
        ClearCardModel(cell)
        cell.icon:SetTexture(isNpc and TT.QUESTION_MARK or CardIcon(key))
      end
      cell.icon:SetDesaturated(not ownedCard)
      cell.icon:SetAlpha(ownedCard and 1 or 0.4)
      -- missing cards render as ghost cards: whole face desaturated
      cell.front:SetDesaturated(not ownedCard)
      cell.front:SetAlpha(ownedCard and 1 or 0.5)
      cell:SetBackdropBorderColor(r, g, bl, ownedCard and 1 or 0.35)

      local name = CardName(row.i and key)
      cell.name:SetText(name or "...")
      if ownedCard then
        cell.name:SetTextColor(r, g, bl)
      else
        cell.name:SetTextColor(0.55, 0.55, 0.55)
      end
      cell.count:SetText(ownedCard and ("x" .. (n + f)) or "")
      cell.isFoil = (f > 0)
      if not cell.isFoil then
        cell.foilGlow:SetAlpha(0)
        cell.aura:SetVertexColor(1, 0.85, 0.3, 0)
      end
      local isFresh = ownedCard and p.fresh[key] == true
      cell.newTag:SetShown(isFresh)
      if isFresh then ui.freshKeys[key] = true end
      cell:Show()
      if (row.kind or "item") == "item" then
        pageRows[#pageRows + 1] = row
      end
    else
      cell.isFoil = false
      cell.foilGlow:SetAlpha(0)
      cell.aura:SetVertexColor(1, 0.85, 0.3, 0)
      ClearCardModel(cell)
      cell:Hide()
    end
  end
  -- warm the item cache for this page so hover tooltips are ready
  TT.PrefetchItems(pageRows)

  -- drive the golden sheen on any visible foil cards
  local anyFoil = false
  for _, cell in ipairs(ui.binderCells) do
    if cell:IsShown() and cell.isFoil then anyFoil = true end
  end
  if anyFoil then
    StartLoop("binderfoil", function(now)
      if not ui.binderPage:IsVisible() then
        StopLoop("binderfoil")
        return
      end
      local L = TT.LAYOUT
      local pulse = math.sin(now * L.foilPulseSpeed)
      local sheen = L.sheenBase + L.sheenSwing * pulse
      local auraA = L.auraBase + L.auraSwing * pulse
      for _, cell in ipairs(ui.binderCells) do
        if cell:IsShown() and cell.isFoil then
          cell.foilGlow:SetAlpha(sheen)
          cell.aura:SetVertexColor(1, 0.85, 0.3, auraA)
        end
      end
    end)
  else
    StopLoop("binderfoil")
  end
end

local function BuildBinderPage(page)
  local panel = CreatePanel(page)
  panel:SetAllPoints(page)

  ui.binderHeader = CreateHeader(panel, "")
  ui.binderHeader:SetPoint("TOPLEFT", 14, -12)

  -- controls row
  ui.ownFilterBtn = CreateActionButton(panel, 90, 20, "All Cards", function()
    local b = TT.cdb.binder
    local idx = CycleIndex(OWN_FILTERS, b.own) % #OWN_FILTERS + 1
    b.own = OWN_FILTERS[idx].key
    b.page = 1
    RefreshBinder()
  end)
  ui.ownFilterBtn:SetPoint("TOPLEFT", 12, -34)

  ui.rarityFilterBtn = CreateActionButton(panel, 96, 20, "All Rarities", function()
    local b = TT.cdb.binder
    b.rarity = (b.rarity + 1) % (TT.MAX_RARITY + 1)
    b.page = 1
    RefreshBinder()
  end)
  ui.rarityFilterBtn:SetPoint("LEFT", ui.ownFilterBtn, "RIGHT", 4, 0)

  ui.bucketFilterBtn = CreateActionButton(panel, 96, 20, "All Types", function()
    local b = TT.cdb.binder
    local idx = 1
    for i, e in ipairs(TT.SLOT_BUCKETS) do
      if e.key == b.bucket then idx = i end
    end
    b.bucket = TT.SLOT_BUCKETS[idx % #TT.SLOT_BUCKETS + 1].key
    b.page = 1
    RefreshBinder()
  end)
  ui.bucketFilterBtn:SetPoint("LEFT", ui.rarityFilterBtn, "RIGHT", 4, 0)

  ui.searchBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  ui.searchBox:SetSize(120, 20)
  ui.searchBox:SetPoint("LEFT", ui.bucketFilterBtn, "RIGHT", 12, 0)
  ui.searchBox:SetAutoFocus(false)
  ui.searchBox:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
      TT.cdb.binder.search = self:GetText() or ""
      TT.cdb.binder.page = 1
      RefreshBinder()
    end
  end)
  ui.searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  ui.searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

  ui.binderNext = CreateActionButton(panel, 60, 20, "Next >", function()
    TT.cdb.binder.page = TT.cdb.binder.page + 1
    RefreshBinder()
  end)
  ui.binderNext:SetPoint("TOPRIGHT", -12, -34)

  ui.binderPageText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.binderPageText:SetPoint("RIGHT", ui.binderNext, "LEFT", -8, 0)

  ui.binderPrev = CreateActionButton(panel, 60, 20, "< Prev", function()
    TT.cdb.binder.page = TT.cdb.binder.page - 1
    RefreshBinder()
  end)
  ui.binderPrev:SetPoint("RIGHT", ui.binderPageText, "LEFT", -8, 0)

  -- 6x2 card grid
  local GAP = 8
  for i = 1, BINDER_PAGE_SIZE do
    local col = (i - 1) % BINDER_COLS
    local row = math.floor((i - 1) / BINDER_COLS)
    local cell = CreateBinderCell(panel)
    cell:SetPoint("TOPLEFT", 14 + col * (116 + GAP), -62 - row * (200 + GAP))
    ui.binderCells[i] = cell
  end

  -- closing the binder (or switching tabs) marks the viewed page as seen
  page:SetScript("OnHide", function()
    if not TT.db then return end
    local prof = TT.Profile()
    for k in pairs(ui.freshKeys or {}) do prof.fresh[k] = nil end
    ui.freshKeys = {}
    ui.freshSig = nil
  end)
end

---------------------------------------------------------------------------
-- Locked page
---------------------------------------------------------------------------

local function RefreshLocked()
  if not ui.lockedPage:IsShown() then return end
  local p = TT.Profile()

  ui.lockScope:SetText(TT.ProfileLabel())
  if p.lockedMode then
    ui.lockState:SetText("TCG LOCKED MODE: ON")
    ui.lockState:SetTextColor(1, 0.27, 0.27)
    ui.lockSince:SetText(p.lockedModeAt and ("Locked since " .. date("%Y-%m-%d %H:%M", p.lockedModeAt)) or "")
    ui.enableLockBtn:Hide()
  else
    ui.lockState:SetText("Collector mode (no restrictions)")
    ui.lockState:SetTextColor(0.3, 1, 0.3)
    ui.lockSince:SetText("")
    ui.enableLockBtn:Show()
  end

  if TT.cdb.hardmode then
    ui.hardmodeBtn:Hide()
    ui.hardmodeState:SetText("HARDMODE character" ..
      (TT.cdb.hardmodeAt and (" since " .. date("%Y-%m-%d", TT.cdb.hardmodeAt)) or ""))
    ui.hardmodeState:SetTextColor(1, 0.27, 0.27)
  else
    ui.hardmodeBtn:Show()
    ui.hardmodeState:SetText("")
  end

  for i = 1, 15 do
    local rowFS = ui.violationRows[i]
    local entry = p.violations[i]
    if entry then
      local when = date("%m-%d %H:%M", entry.t or 0)
      local text
      if entry.kind == "violation" then
        local row = entry.item and TT.cardIndex and TT.cardIndex["item:" .. entry.item]
        local name = (row and row.n) or (entry.item and TT.ItemName(entry.item))
        text = ("|cffff4444[%s]|r %s equipped %s (uncarded)"):format(
          when, entry.char or "?", name or ("item " .. tostring(entry.item)))
      else
        text = ("|cffaaaaaa[%s]|r %s"):format(when, entry.text or "")
      end
      rowFS:SetText(text)
      rowFS:Show()
    else
      rowFS:Hide()
    end
  end
end

local function BuildLockedPage(page)
  local panel = CreatePanel(page)
  panel:SetAllPoints(page)

  ui.lockScope = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ui.lockScope:SetPoint("TOPLEFT", 16, -14)
  ui.lockScope:SetTextColor(GOLD.r, GOLD.g, GOLD.b)

  ui.lockState = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ui.lockState:SetPoint("TOPLEFT", 16, -38)

  ui.lockSince = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.lockSince:SetPoint("TOPLEFT", 16, -56)
  ui.lockSince:SetTextColor(0.6, 0.6, 0.6)

  ui.enableLockBtn = CreateActionButton(panel, 190, 26, "Enable TCG Locked Mode", function()
    StaticPopup_Show("TAVERNLEAGUETCG_LOCKMODE", TT.ProfileLabel())
  end)
  ui.enableLockBtn:SetPoint("TOPRIGHT", -16, -14)

  ui.hardmodeBtn = CreateActionButton(panel, 190, 22, "Go Hardmode (this character)", function()
    StaticPopup_Show("TAVERNLEAGUETCG_HARDMODE", UnitName("player"))
  end)
  ui.hardmodeBtn:SetPoint("TOPRIGHT", -16, -44)

  ui.hardmodeState = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.hardmodeState:SetPoint("TOPRIGHT", -16, -50)

  local rules = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rules:SetPoint("TOPLEFT", 16, -78)
  rules:SetPoint("RIGHT", -16, 0)
  rules:SetJustifyH("LEFT")
  rules:SetTextColor(0.6, 0.6, 0.6)
  rules:SetText("Locked mode: gear may only be equipped if the run owns its card. Items with no " ..
    "card in the pool are always free. Gear you were wearing when the lock first saw this " ..
    "character is grandfathered. Violations are warned and recorded below - the honor system, " ..
    "with receipts. Turning the mode off requires /tltcg unlock CONFIRM and is logged forever.")

  local logHeader = CreateHeader(panel, "Event & Violation Log")
  logHeader:SetPoint("TOPLEFT", 16, -150)

  for i = 1, 15 do
    local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 16, -170 - (i - 1) * 16)
    fs:SetPoint("RIGHT", -16, 0)
    fs:SetJustifyH("LEFT")
    fs:Hide()
    ui.violationRows[i] = fs
  end
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

function TT.UI_Refresh()
  if not frame or not frame:IsShown() then return end
  local p = TT.Profile()

  ui.creditsText:SetText(TT.FormatNumber(p.credits) .. "c")
  ui.profileText:SetText(TT.ProfileLabel() .. (p.lockedMode and "  |cffff4444[LOCKED]|r" or ""))

  ui.bigCredits:SetText(TT.FormatNumber(p.credits))
  ui.statsLine:SetText(("Free packs: %d   Packs opened: %d   God packs: %d   Pity: %d/%d"):format(
    p.freePacks or 0, p.stats.packs or 0, p.stats.gods or 0, p.pity or 0, TT.ECON.pityEpic))
  ui.earnLine:SetText(("Earned - XP %s | Kills %s | Quests %s | Levels %s | Skills %s"):format(
    TT.FormatNumber(p.stats.xp or 0), TT.FormatNumber(p.stats.kills or 0),
    TT.FormatNumber(p.stats.quests or 0), TT.FormatNumber(p.stats.levels or 0),
    TT.FormatNumber(p.stats.skills or 0)))

  local pending = p.pendingPack ~= nil
  local free = p.freePacks or 0
  if free > 0 then
    ui.openPackBtn:SetText(("Open FREE Pack (%d banked)"):format(free))
  else
    ui.openPackBtn:SetText("Open Pack - " .. TT.FormatNumber(TT.ECON.packPrice) .. "c")
  end
  ui.openPackBtn:SetEnabled(not pending and (free > 0 or p.credits >= TT.ECON.packPrice))
  ui.resumePackBtn:SetShown(pending)

  RefreshBinder()
  RefreshLocked()
  if ui.tradePage:IsShown() and TT.Trade_Refresh then TT.Trade_Refresh() end
end

-- An item's data arrived from the server. Card names ship with the pool,
-- so nothing repaints here (repainting per cache event made the binder
-- flicker) - but if the player is hovering that exact card, upgrade its
-- "loading..." tooltip to the full item tooltip in place.
function TT.UI_OnItemCached(itemId)
  local cell = ui.hoverCell
  if cell and cell.itemId == itemId and cell:IsMouseOver() then
    local enter = cell:GetScript("OnEnter")
    if enter then enter(cell) end
  end
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------

local minimapButton

local function UpdateMinimapButtonPosition()
  local angle = math.rad(TT.cdb.minimapAngle or 200)
  minimapButton:ClearAllPoints()
  minimapButton:SetPoint("CENTER", Minimap, "CENTER",
    math.cos(angle) * 80, math.sin(angle) * 80)
end

function TT.UpdateMinimapButton()
  if not minimapButton then return end
  minimapButton:SetShown(not TT.cdb.minimapHide)
  UpdateMinimapButtonPosition()
end

local function CreateMinimapButton()
  minimapButton = CreateFrame("Button", "TavernLeagueTCGMinimapButton", Minimap)
  minimapButton:SetSize(32, 32)
  minimapButton:SetFrameStrata("MEDIUM")
  minimapButton:SetFrameLevel(8)
  minimapButton:RegisterForClicks("LeftButtonUp")
  minimapButton:RegisterForDrag("LeftButton")
  minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  icon:SetTexture(TT.CARD_BACK_ICON)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  local border = minimapButton:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  minimapButton:SetScript("OnClick", function() TT.ToggleFrame() end)

  minimapButton:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      TT.cdb.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
      UpdateMinimapButtonPosition()
    end)
  end)
  minimapButton:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Tavern League TCG", 1, 0.82, 0)
    GameTooltip:AddLine("Click: open your binder", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

  TT.UpdateMinimapButton()
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function TT.UI_Init()
  frame = CreateFrame("Frame", "TavernLeagueTCGFrame", UIParent, "BackdropTemplate")
  frame:SetSize(796, 580)
  frame:SetPoint("CENTER")
  frame:SetBackdrop(PANEL_BACKDROP)
  frame:SetBackdropColor(0.03, 0.03, 0.05, 0.95)
  frame:SetBackdropBorderColor(0.5, 0.42, 0.2)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetFrameStrata("HIGH")
  frame:SetClampedToScreen(true)
  frame:Hide()
  frame:SetScript("OnShow", function() TT.Refresh() end)
  tinsert(UISpecialFrames, "TavernLeagueTCGFrame")

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -10)
  local className, classToken = UnitClass("player")
  local color = RAID_CLASS_COLORS and classToken and RAID_CLASS_COLORS[classToken]
  if color and color.colorStr then
    title:SetText("Tavern League TCG  -  |c" .. color.colorStr .. (UnitName("player") or className) .. "|r")
  else
    title:SetText("Tavern League TCG")
  end
  title:SetTextColor(GOLD.r, GOLD.g, GOLD.b)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  BuildToolbar()

  ui.packsPage = CreateFrame("Frame", nil, frame)
  ui.packsPage:SetPoint("TOPLEFT", 8, -66)
  ui.packsPage:SetPoint("BOTTOMRIGHT", -8, 8)

  ui.binderPage = CreateFrame("Frame", nil, frame)
  ui.binderPage:SetPoint("TOPLEFT", 8, -66)
  ui.binderPage:SetPoint("BOTTOMRIGHT", -8, 8)
  ui.binderPage:Hide()

  ui.lockedPage = CreateFrame("Frame", nil, frame)
  ui.lockedPage:SetPoint("TOPLEFT", 8, -66)
  ui.lockedPage:SetPoint("BOTTOMRIGHT", -8, 8)
  ui.lockedPage:Hide()

  ui.tradePage = CreateFrame("Frame", nil, frame)
  ui.tradePage:SetPoint("TOPLEFT", 8, -66)
  ui.tradePage:SetPoint("BOTTOMRIGHT", -8, 8)
  ui.tradePage:Hide()

  BuildPacksPage(ui.packsPage)
  BuildBinderPage(ui.binderPage)
  BuildLockedPage(ui.lockedPage)
  if TT.Trade_BuildUI then TT.Trade_BuildUI(ui.tradePage) end
  BuildPackOverlay()

  TT.ShowTab("packs")
  CreateMinimapButton()

  -- a pack was mid-open when the player logged out: resume it
  if TT.Profile().pendingPack then
    TT.Msg("You have an unopened pack waiting - click the minimap button to resume.")
  end

  TT.Msg("Loaded. /tcg to open. Pool: " .. TT.FormatNumber(TT.poolCount or 0) .. " cards.")
end
