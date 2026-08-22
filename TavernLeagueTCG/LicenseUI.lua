-- Tavern League TCG: the Tavern tab - the license deck browser, the
-- draw/draft launcher and (next update) the goals checklist and dungeon
-- tracker. Follows the Trade.lua pattern: UI.lua creates the page frame
-- and calls TT.License_BuildUI / TT.License_Refresh defensively.

local ADDON, TT = ...

local ui = {}
local GOLD = { r = 1, g = 0.82, b = 0 }

---------------------------------------------------------------------------
-- Deck browser: one small icon cell per license card, grouped by section.
-- Drawn cards glow, eligible cards wait in gray, locked cards sit dark.
---------------------------------------------------------------------------

local CELL, CELL_GAP, PER_ROW = 30, 4, 21

local function CreateDeckCell(parent)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(CELL, CELL)
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  b:SetBackdropColor(0.05, 0.05, 0.08, 1)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 2, -2)
  b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b:SetScript("OnEnter", function(self)
    local card = self.card
    if not card then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(card.name, 1, 0.82, 0)
    local state
    if TT.IsDrawn(card.id) then
      state = "|cff20ff20Earned|r"
    elseif card.minLevel > (UnitLevel("player") or 1) then
      state = ("Unlocks at level %d"):format(card.minLevel)
    else
      state = "In the deck - draw to earn it"
    end
    GameTooltip:AddLine(state, 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

-- Lay the whole deck out once per login (the deck itself never changes
-- mid-session); Refresh only repaints states.
local function BuildDeckGrid()
  local grid = ui.deckGrid
  ui.cells = ui.cells or {}
  for _, c in ipairs(ui.cells) do c:Hide() end

  local sections = {
    { label = "GEAR SLOTS", match = function(c) return c.type == "gear" end },
    { label = "TALENTS", match = function(c) return c.type == "talent" end },
    { label = "PROFESSIONS & UNLOCKS",
      match = function(c) return c.type == "profession" or c.type == "general" end },
    { label = "CLASS ABILITIES", match = function(c) return c.type == "ability" end },
  }

  local maxLevel = TT.MAX_LEVEL or 60
  local y = 0
  local cellIdx = 0
  ui.headers = ui.headers or {}
  local headerIdx = 0

  for _, sec in ipairs(sections) do
    local cards = {}
    for _, card in ipairs(TT.licenseCards or {}) do
      -- gated cards and cards that can never be eligible on this client
      -- (e.g. TBC talents on Era) don't exist here
      if sec.match(card) and not TT.IsLicenseGated(card)
          and card.minLevel <= maxLevel then
        cards[#cards + 1] = card
      end
    end
    if #cards > 0 then
      headerIdx = headerIdx + 1
      local h = ui.headers[headerIdx]
      if not h then
        h = grid:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ui.headers[headerIdx] = h
      end
      h:SetPoint("TOPLEFT", 0, -y)
      h:SetText(sec.label)
      h:SetTextColor(0.55, 0.5, 0.35)
      h:Show()
      y = y + 16

      for i, card in ipairs(cards) do
        cellIdx = cellIdx + 1
        local cell = ui.cells[cellIdx]
        if not cell then
          cell = CreateDeckCell(grid)
          ui.cells[cellIdx] = cell
        end
        local col = (i - 1) % PER_ROW
        local row = math.floor((i - 1) / PER_ROW)
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", col * (CELL + CELL_GAP),
          -(y + row * (CELL + CELL_GAP)))
        cell.card = card
        cell:Show()
      end
      y = y + (math.ceil(#cards / PER_ROW)) * (CELL + CELL_GAP) + 8
    end
  end
  for i = headerIdx + 1, #ui.headers do ui.headers[i]:Hide() end
  for i = cellIdx + 1, #ui.cells do ui.cells[i]:Hide() end
end

local function RefreshDeckGrid()
  local level = UnitLevel("player") or 1
  for _, cell in ipairs(ui.cells or {}) do
    if cell:IsShown() and cell.card then
      local card = cell.card
      cell.icon:SetTexture(TT.GetLicenseIcon(card))
      if TT.IsDrawn(card.id) then
        cell.icon:SetDesaturated(false)
        cell.icon:SetAlpha(1)
        cell:SetBackdropBorderColor(GOLD.r, GOLD.g, GOLD.b)
      elseif card.minLevel <= level then
        cell.icon:SetDesaturated(true)
        cell.icon:SetAlpha(0.65)
        cell:SetBackdropBorderColor(0.35, 0.35, 0.4)
      else
        cell.icon:SetDesaturated(true)
        cell.icon:SetAlpha(0.25)
        cell:SetBackdropBorderColor(0.18, 0.18, 0.22)
      end
    end
  end
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------

function TT.License_BuildUI(page)
  ui.page = page

  ui.header = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ui.header:SetPoint("TOPLEFT", 12, -10)
  ui.header:SetTextColor(GOLD.r, GOLD.g, GOLD.b)

  ui.subHeader = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.subHeader:SetPoint("TOPLEFT", ui.header, "BOTTOMLEFT", 0, -4)
  ui.subHeader:SetTextColor(0.7, 0.7, 0.7)

  -- main action: draw (Challenge) or draft (League), or resume either
  local function MakeButton(w, label, onClick)
    local b = CreateFrame("Button", nil, page, "BackdropTemplate")
    b:SetSize(w, 30)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    b:SetBackdropColor(0.12, 0.10, 0.05, 1)
    b:SetBackdropBorderColor(GOLD.r, GOLD.g, GOLD.b)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("CENTER")
    b.SetText = function(self, t) self.text:SetText(t) end
    b:SetScript("OnClick", onClick)
    b:SetScript("OnDisable", function(self) self.text:SetTextColor(0.4, 0.4, 0.4) end)
    b:SetScript("OnEnable", function(self) self.text:SetTextColor(1, 0.82, 0) end)
    return b
  end

  ui.actionBtn = MakeButton(230, "", function()
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
  ui.actionBtn:SetPoint("TOPRIGHT", -12, -12)

  ui.bonusBtn = MakeButton(150, "", function()
    if TT.DrawLicenses(true) then TT.UI_ShowDrawOverlay() end
  end)
  ui.bonusBtn:SetPoint("TOPRIGHT", ui.actionBtn, "BOTTOMRIGHT", 0, -6)

  ui.undoBtn = MakeButton(150, "Undo last pick", function()
    TT.UndoLicenseChoice()
    if TT.Run().pendingDraw then TT.UI_ShowDrawOverlay() end
  end)
  ui.undoBtn:SetPoint("TOPRIGHT", ui.bonusBtn, "BOTTOMRIGHT", 0, -6)

  ui.deckGrid = CreateFrame("Frame", nil, page)
  ui.deckGrid:SetPoint("TOPLEFT", 14, -118)
  ui.deckGrid:SetPoint("BOTTOMRIGHT", -14, 30)

  ui.goalsNote = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.goalsNote:SetPoint("BOTTOM", 0, 10)
  ui.goalsNote:SetTextColor(0.45, 0.45, 0.45)
  ui.goalsNote:SetText("Tavern goals and the dungeon tracker arrive later in this update.")

  ui.built = false
end

function TT.License_Refresh()
  if not ui.page or not ui.page:IsShown() then return end
  local run = TT.Run()
  local licActive = TT.LicenseLayerActive()

  if not ui.built and TT.licenseCards then
    BuildDeckGrid()
    ui.built = true
  end

  local drawn = 0
  for _ in pairs(run.drawn) do drawn = drawn + 1 end
  local total = 0
  local maxLevel = TT.MAX_LEVEL or 60
  for _, card in ipairs(TT.licenseCards or {}) do
    if not TT.IsLicenseGated(card) and card.minLevel <= maxLevel then
      total = total + 1
    end
  end
  ui.header:SetText(("Licenses - %d of %d earned"):format(drawn, total))

  if not licActive then
    ui.subHeader:SetText("This format plays without the license layer - the deck is on display only.")
    ui.actionBtn:Hide()
    ui.bonusBtn:Hide()
    ui.undoBtn:Hide()
  elseif TT.FormatFlag("drafts") then
    ui.subHeader:SetText(("Draft packs banked: |cffffd100%d|r - one per level; keep one card of five."):format(
      run.draftPacks or 0))
    ui.actionBtn:Show()
    if run.pendingDraft or run.pendingDraw then
      ui.actionBtn:SetText("Resume your draft")
      ui.actionBtn:SetEnabled(true)
    else
      ui.actionBtn:SetText(("Open draft pack (%d banked)"):format(run.draftPacks or 0))
      ui.actionBtn:SetEnabled((run.draftPacks or 0) > 0)
    end
    ui.bonusBtn:Hide()
    ui.undoBtn:Hide()               -- draft picks are final
  else
    ui.subHeader:SetText(("Draws banked: |cffffd100%d|r  Bonus draws: |cffffd100%d|r"):format(
      run.drawCredits or 0, run.bonusDraws or 0))
    ui.actionBtn:Show()
    if run.pendingDraw then
      ui.actionBtn:SetText("Resume your draw")
      ui.actionBtn:SetEnabled(true)
    else
      ui.actionBtn:SetText(("Draw licenses (%d banked)"):format(run.drawCredits or 0))
      ui.actionBtn:SetEnabled((run.drawCredits or 0) > 0)
    end
    ui.bonusBtn:SetShown((run.bonusDraws or 0) > 0)
    ui.bonusBtn:SetText(("Bonus draw (%d)"):format(run.bonusDraws or 0))
    ui.undoBtn:SetShown(run.lastUndo ~= nil)
  end

  RefreshDeckGrid()
end
