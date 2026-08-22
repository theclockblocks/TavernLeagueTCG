-- Tavern League TCG: hard enforcement, ported from DeckLocked.
--
--   Gear    : lock overlays on the character sheet + auto-unequip of
--             anything in violation (out of combat; queued in combat).
--             ONE sweep serves both layers: slot licenses
--             (Challenge/League) and item cards (Collection/League).
--   Spells  : locked abilities grayed and un-clickable in the spellbook,
--             red-tinted on action bars, callout when cast anyway
--   Bags    : lock overlays on the bag bar + equipped-bag warnings
--   Talents : talent frame blocked beyond earned points
--
-- WoW addons cannot hard-block protected actions (casting), so casting a
-- locked spell still works - it just gets called out. The overlay
-- parenting here is deliberate and taint-safe (spellbook overlays live
-- on SpellBookFrame, action-bar overlays on UIParent, click-through):
-- do not "improve" it.
--
-- License state reads ONLY through TT.IsDrawn/TT.IsUnlocked - the active
-- run can change mid-session (hardmode), and accessors re-resolve.

local ADDON, TT = ...

local LOCK_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK"
local overlays = { gear = {}, bags = {}, book = {}, bars = {} }
local pendingSweep = false
local sweeping = false
local lastCastWarn = {}
local warnedBags = {}

-- the license layer's enforcement gate (spells/talents/bags/gear slots)
local function licenseOn()
  return TT.db and TT.Profile().lockedMode and TT.LicenseLayerActive()
end

---------------------------------------------------------------------------
-- Ability name lookup (rank-proof: all ranks of a spell share its name)
---------------------------------------------------------------------------

local abilityByName = nil

local function BuildAbilityLookup()
  abilityByName = {}
  for _, card in ipairs(TT.licenseCards or {}) do
    if card.type == "ability" then
      abilityByName[card.name:lower()] = card
      -- also index the client's real spell name(s): covers cards whose
      -- display name differs (e.g. faction pairs like "Seal of
      -- Blood/Vengeance", where spell2 is the other faction's spell)
      for _, spellId in ipairs({ card.spell, card.spell2 }) do
        local realName = GetSpellInfo(spellId)
        if realName then
          abilityByName[realName:lower()] = card
        end
      end
    end
  end
end

-- Returns the deck card a spell name belongs to, or nil if the spell is
-- not part of the challenge (racials, professions, etc.)
local function FindAbilityCard(name)
  if not name then return nil end
  if not abilityByName then BuildAbilityLookup() end
  local card = abilityByName[name:lower()]
  if card then return card end
  -- "Create Healthstone (Minor)" -> "Create Healthstone"
  local base = name:gsub("%s*%b()$", "")
  card = abilityByName[base:lower()]
  if card then return card end
  -- "Instant Poison IV" -> "Instant Poison"
  base = base:gsub("%s+[IVX]+$", "")
  card = abilityByName[base:lower()]
  if card then return card end
  -- "Teleport: Ironforge" -> "Teleport"
  local prefix = name:match("^(.-):")
  if prefix then
    card = abilityByName[prefix:lower()]
  end
  return card
end

local function IsSpellLocked(name)
  local card = FindAbilityCard(name)
  return card and not TT.IsDrawn(card.id) and not TT.IsLicenseGated(card)
end

---------------------------------------------------------------------------
-- Overlay factory
---------------------------------------------------------------------------

-- clickBlock: overlay eats mouse clicks (only for non-protected UI)
local function CreateLockOverlay(parent, anchorTo, clickBlock)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints(anchorTo or parent)
  f:SetFrameLevel((anchorTo or parent):GetFrameLevel() + 5)
  f:EnableMouse(clickBlock and true or false)

  f.shade = f:CreateTexture(nil, "OVERLAY")
  f.shade:SetAllPoints()
  f.shade:SetColorTexture(0, 0, 0, 0.7)

  f.lock = f:CreateTexture(nil, "OVERLAY", nil, 1)
  f.lock:SetPoint("CENTER")
  f.lock:SetSize(16, 16)
  f.lock:SetTexture(LOCK_TEXTURE)
  f.lock:SetTexCoord(0, 0.71875, 0, 0.734375)
  f.lock:SetVertexColor(1, 0.35, 0.35)

  if clickBlock then
    f:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Locked by Tavern League", 1, 0.3, 0.3)
      GameTooltip:AddLine("Earn the license card to unlock.", 0.8, 0.8, 0.8)
      GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  f:Hide()
  return f
end

---------------------------------------------------------------------------
-- Gear: character sheet overlays + the unified auto-unequip sweep
---------------------------------------------------------------------------

local gearCards = nil     -- [licenseSlotKey] = card, built once per deck
local slotIdToKey = nil   -- [inventorySlotId] = licenseSlotKey

local function BuildGearCards()
  gearCards = {}
  slotIdToKey = {}
  for _, card in ipairs(TT.licenseCards or {}) do
    if card.type == "gear" then
      gearCards[card.slot] = card
      local slotId = GetInventorySlotInfo(card.invSlot)
      if slotId then slotIdToKey[slotId] = card.slot end
    end
  end
end

local function UpdateGearOverlays()
  if not gearCards then BuildGearCards() end
  for slotKey, card in pairs(gearCards) do
    local button = _G["Character" .. card.invSlot]
    if button then
      local ov = overlays.gear[slotKey]
      if not ov then
        ov = CreateLockOverlay(button, nil, true)
        overlays.gear[slotKey] = ov
      end
      ov:SetShown(licenseOn() and not TT.IsUnlocked(slotKey))
    end
  end
end

-- Why must this inventory slot be emptied? nil = it's fine.
--   "license" - the slot's license isn't owned (Challenge/League)
--   "card"    - the item's card isn't owned (Collection/League)
-- Grandfathered items are exempt from BOTH layers (spec: what you wore
-- when the lock first saw you stays yours).
function TT.EquipViolationReason(slotId, itemId)
  if not itemId or not (TT.db and TT.Profile().lockedMode) then return nil end
  if TT.cdb.grandfathered[itemId] then return nil end
  if TT.LicenseLayerActive() then
    if not gearCards then BuildGearCards() end
    local slotKey = slotIdToKey[slotId]
    if slotKey and not TT.IsUnlocked(slotKey) then return "license" end
  end
  if TT.ItemLayerActive() and TT.IsItemViolation(itemId) then
    return "card"
  end
  return nil
end

local ContainerIDToInventoryIDCompat =
  (C_Container and C_Container.ContainerIDToInventoryID) or ContainerIDToInventoryID

function TT.SweepLockedGear()
  if sweeping then return end
  if not (TT.db and TT.Profile().lockedMode) then return end
  if not TT.LicenseLayerActive() and not TT.ItemLayerActive() then return end
  if InCombatLockdown() then
    pendingSweep = true
    return
  end
  if not gearCards then BuildGearCards() end
  sweeping = true

  for slotId = 1, 19 do
    local itemId = GetInventoryItemID("player", slotId)
    local reason = TT.EquipViolationReason(slotId, itemId)
    if reason then
      ClearCursor()
      PickupInventoryItem(slotId)
      if CursorHasItem() then
        PutItemInBackpack()
        for bag = 1, 4 do
          if CursorHasItem() and ContainerIDToInventoryIDCompat then
            PutItemInBag(ContainerIDToInventoryIDCompat(bag))
          end
        end
        local slotKey = slotIdToKey[slotId]
        local what = (reason == "license")
          and ((slotKey and gearCards[slotKey] and gearCards[slotKey].name) or "that slot")
          or ((TT.cardIndex["item:" .. itemId] or {}).n or ("item " .. itemId))
        if CursorHasItem() then
          PickupInventoryItem(slotId) -- no room anywhere: put it back
          ClearCursor()
          TT.Warn("No bag space to remove the item locked in " .. what .. "!")
        elseif reason == "license" then
          TT.Warn("Unequipped: no license for " .. what .. ".")
          TT.LogEvent("violation", nil, { item = itemId, slot = slotId, why = reason })
        else
          -- item-card violations already have a throttled warn+log path
          TT.RecordViolation(itemId, slotId)
          TT.Msg("Unequipped " .. what .. ".")
        end
      end
    end
  end

  sweeping = false
end

---------------------------------------------------------------------------
-- Bags: bag bar overlays + equipped-bag warnings (license layer)
---------------------------------------------------------------------------

local GetContainerNumSlotsCompat =
  (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots

local function UpdateBagOverlays()
  for i = 1, 4 do
    -- CharacterBag0Slot holds container bag 1, Bag1Slot bag 2, etc.
    local button = _G["CharacterBag" .. (i - 1) .. "Slot"]
    if button then
      local ov = overlays.bags[i]
      if not ov then
        ov = CreateLockOverlay(button, nil, true)
        overlays.bags[i] = ov
      end
      ov:SetShown(licenseOn() and not TT.IsUnlocked("bag-" .. i))
    end
  end
end

local function CheckBagViolations()
  if not licenseOn() then return end
  for i = 1, 4 do
    if not TT.IsUnlocked("bag-" .. i) then
      local slots = GetContainerNumSlotsCompat and GetContainerNumSlotsCompat(i)
      if slots and slots > 0 and not warnedBags[i] then
        warnedBags[i] = true
        TT.Warn("Bag slot " .. i .. " is locked - remove that bag!")
      end
    else
      warnedBags[i] = nil
    end
  end
end

---------------------------------------------------------------------------
-- Spellbook: gray + block locked spells
---------------------------------------------------------------------------

local function GetBookSlot(button)
  if SpellBook_GetSpellBookSlot then
    local ok, slot = pcall(SpellBook_GetSpellBookSlot, button)
    if ok then return slot end
  end
  return nil
end

local function UpdateSpellbookOverlays()
  if not SpellBookFrame or not SpellBookFrame:IsShown() then return end
  local isPlayerBook = (SpellBookFrame.bookType == BOOKTYPE_SPELL) or (SpellBookFrame.bookType == "spell")

  for i = 1, 12 do
    local button = _G["SpellButton" .. i]
    if button then
      local ov = overlays.book[i]
      if not ov then
        -- parented to SpellBookFrame (insecure), anchored over the button
        ov = CreateLockOverlay(SpellBookFrame, button, true)
        overlays.book[i] = ov
      end

      local locked = false
      if licenseOn() and isPlayerBook and button:IsShown() then
        local slot = GetBookSlot(button)
        if slot then
          local name = GetSpellBookItemName(slot, "spell")
          locked = name and IsSpellLocked(name) or false
        end
      end
      ov:SetShown(locked)
    end
  end
end

-- Throttled updater while the book is open: survives page turns, tab
-- switches and any internal Blizzard refresh without fragile hooks.
local bookTicker = CreateFrame("Frame")
bookTicker.elapsed = 0
bookTicker:SetScript("OnUpdate", function(self, elapsed)
  self.elapsed = self.elapsed + elapsed
  if self.elapsed >= 0.2 then
    self.elapsed = 0
    UpdateSpellbookOverlays()
  end
end)
bookTicker:Hide()

---------------------------------------------------------------------------
-- Action bars: red lock tint on buttons holding locked spells
---------------------------------------------------------------------------

local BAR_PREFIXES = {
  "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
  "MultiBarLeftButton", "MultiBarRightButton",
  "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

local function ButtonSpellName(button)
  local action = (button.GetPagedID and button:GetPagedID()) or button.action
  if not action then return nil end
  local kind, id = GetActionInfo(action)
  if kind == "spell" and id then
    local name = GetSpellInfo(id)
    return name
  elseif kind == "macro" and id and GetMacroSpell then
    local spellId = GetMacroSpell(id)
    if spellId then return (GetSpellInfo(spellId)) end
  end
  return nil
end

local function UpdateActionBarOverlays()
  for _, prefix in ipairs(BAR_PREFIXES) do
    for i = 1, 12 do
      local button = _G[prefix .. i]
      if button then
        local key = prefix .. i
        local ov = overlays.bars[key]
        if not ov then
          -- parented to UIParent, click-through: never taints secure buttons
          ov = CreateFrame("Frame", nil, UIParent)
          if not InCombatLockdown() then
            ov:SetAllPoints(button)
          end
          ov:SetFrameStrata("HIGH")
          ov.tint = ov:CreateTexture(nil, "OVERLAY")
          ov.tint:SetAllPoints()
          ov.tint:SetColorTexture(0.8, 0, 0, 0.45)
          ov.lock = ov:CreateTexture(nil, "OVERLAY", nil, 1)
          ov.lock:SetPoint("TOPRIGHT", -1, -1)
          ov.lock:SetSize(12, 12)
          ov.lock:SetTexture(LOCK_TEXTURE)
          ov.lock:SetTexCoord(0, 0.71875, 0, 0.734375)
          ov:Hide()
          overlays.bars[key] = ov
        end
        local name = button:IsShown() and ButtonSpellName(button) or nil
        ov:SetShown(licenseOn() and name ~= nil and IsSpellLocked(name))
      end
    end
  end
end

---------------------------------------------------------------------------
-- Cast violations (protected casts can't be blocked - only called out)
---------------------------------------------------------------------------

local function OnSpellcastSucceeded(unit, _, spellID)
  if unit ~= "player" or not licenseOn() or not spellID then return end
  local name = GetSpellInfo(spellID)
  if not name or not IsSpellLocked(name) then return end

  local now = GetTime()
  if lastCastWarn[name] and now - lastCastWarn[name] < 5 then return end
  lastCastWarn[name] = now

  local msg = "LICENSE VIOLATION: " .. name .. " - you don't hold its card!"
  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
  end
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
    PlaySound(SOUNDKIT.RAID_WARNING)
  end
  TT.Warn(msg)
  TT.LogEvent("violation", nil, { spell = spellID })
end

---------------------------------------------------------------------------
-- Talents: gate the talent frame on earned points
---------------------------------------------------------------------------

local talentOverlay = nil

local function SpentTalentPoints()
  if not GetNumTalentTabs then return 0 end
  local total = 0
  for i = 1, GetNumTalentTabs() do
    -- Era and TBC clients disagree on which return is "points spent"
    local a, b, c, d, e = GetTalentTabInfo(i)
    local spent = (type(c) == "number" and c) or (type(e) == "number" and e) or 0
    total = total + spent
  end
  return total
end

local function UpdateTalentGate()
  local tframe = _G.PlayerTalentFrame or _G.TalentFrame
  if not tframe then return end

  if not talentOverlay then
    talentOverlay = CreateFrame("Frame", nil, tframe)
    talentOverlay:SetPoint("TOPLEFT", 20, -70)
    talentOverlay:SetPoint("BOTTOMRIGHT", -40, 80)
    talentOverlay:SetFrameLevel(tframe:GetFrameLevel() + 10)
    talentOverlay:EnableMouse(true)

    local shade = talentOverlay:CreateTexture(nil, "OVERLAY")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.8)

    talentOverlay.text = talentOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    talentOverlay.text:SetPoint("CENTER", 0, 20)
    talentOverlay.text:SetWidth(260)
    talentOverlay.text:SetTextColor(1, 0.3, 0.3)

    talentOverlay.sub = talentOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    talentOverlay.sub:SetPoint("TOP", talentOverlay.text, "BOTTOM", 0, -10)
    talentOverlay.sub:SetWidth(260)
    talentOverlay.sub:SetTextColor(0.8, 0.8, 0.8)
    talentOverlay:Hide()
  end

  local earned = TT.LicenseTalentPoints()
  local spent = SpentTalentPoints()

  if licenseOn() and spent >= earned then
    talentOverlay.text:SetText("Talents locked by Tavern League")
    talentOverlay.sub:SetText("Spent " .. spent .. " / earned " .. earned ..
      ".\nEarn talent cards to unlock more points.")
    talentOverlay:Show()
  else
    talentOverlay:Hide()
  end

  if licenseOn() and spent > earned then
    TT.Warn("You have spent " .. spent .. " talent points but only earned " .. earned .. "!")
  end
end

---------------------------------------------------------------------------
-- Master update (called from TT.Refresh via Core)
---------------------------------------------------------------------------

function TT.LicenseEnforce_Update()
  if not TT.db then return end
  abilityByName = nil -- deck state changed: rebuild lookup lazily
  gearCards = nil     -- hardmode/class edge: rebuild the slot maps too
  UpdateGearOverlays()
  UpdateBagOverlays()
  UpdateSpellbookOverlays()
  UpdateActionBarOverlays()
  UpdateTalentGate()
  CheckBagViolations()
  TT.SweepLockedGear()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ef = CreateFrame("Frame")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ef:RegisterEvent("PLAYER_REGEN_ENABLED")
ef:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ef:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
ef:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
ef:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
ef:RegisterEvent("SPELLS_CHANGED")
ef:RegisterEvent("CHARACTER_POINTS_CHANGED")
ef:RegisterEvent("BAG_UPDATE_DELAYED")
ef:RegisterEvent("ADDON_LOADED")

ef:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
  if not TT.db then return end

  if event == "PLAYER_ENTERING_WORLD" then
    TT.LicenseEnforce_Update()
    if SpellBookFrame then
      SpellBookFrame:HookScript("OnShow", function() bookTicker:Show() end)
      SpellBookFrame:HookScript("OnHide", function() bookTicker:Hide() end)
    end
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")

  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    if not sweeping then
      TT.SweepLockedGear()
    end

  elseif event == "PLAYER_REGEN_ENABLED" then
    if pendingSweep then
      pendingSweep = false
      TT.SweepLockedGear()
    end
    UpdateActionBarOverlays()

  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    OnSpellcastSucceeded(arg1, arg2, arg3)

  elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED"
      or event == "UPDATE_SHAPESHIFT_FORM" or event == "SPELLS_CHANGED" then
    UpdateActionBarOverlays()

  elseif event == "CHARACTER_POINTS_CHANGED" then
    UpdateTalentGate()

  elseif event == "BAG_UPDATE_DELAYED" then
    CheckBagViolations()

  elseif event == "ADDON_LOADED" and arg1 == "Blizzard_TalentUI" then
    local tframe = _G.PlayerTalentFrame or _G.TalentFrame
    if tframe then
      tframe:HookScript("OnShow", UpdateTalentGate)
    end
  end
end)
