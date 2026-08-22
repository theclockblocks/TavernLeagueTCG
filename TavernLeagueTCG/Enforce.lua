-- Tavern League TCG enforcement (TCG Locked mode): equipping gear requires
-- owning that item's card.
--
--   Equip checks : warn + record a violation when a carded-but-unowned item
--                  is equipped. Since 0.5.0 the auto-unequip lives in
--                  LicenseEnforce.lua (TT.SweepLockedGear serves both the
--                  item-card and license layers); this file keeps the
--                  item-layer visuals and the violation bookkeeping.
--   Paperdoll    : red lock overlay on character-sheet slots in violation
--   Bags         : small lock marker on bag items you could not legally equip
--
-- Overlays are visual only (no EnableMouse) so the player can still unequip
-- the offending item. Nothing here touches action bars or secure frames.

local ADDON, TT = ...

local LOCK_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK"
local overlays = { gear = {}, bags = {} }
local lastWarn = {}   -- [itemId] = GetTime() of last warning

local GetContainerItemIDCompat =
  (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local GetContainerNumSlotsCompat =
  (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local IsEquippableItemCompat =
  (C_Item and C_Item.IsEquippableItem) or IsEquippableItem

-- paperdoll buttons by inventory slot id
local INV_SLOT_BUTTONS = {
  [1] = "CharacterHeadSlot", [2] = "CharacterNeckSlot", [3] = "CharacterShoulderSlot",
  [4] = "CharacterShirtSlot", [5] = "CharacterChestSlot", [6] = "CharacterWaistSlot",
  [7] = "CharacterLegsSlot", [8] = "CharacterFeetSlot", [9] = "CharacterWristSlot",
  [10] = "CharacterHandsSlot", [11] = "CharacterFinger0Slot", [12] = "CharacterFinger1Slot",
  [13] = "CharacterTrinket0Slot", [14] = "CharacterTrinket1Slot", [15] = "CharacterBackSlot",
  [16] = "CharacterMainHandSlot", [17] = "CharacterSecondaryHandSlot",
  [18] = "CharacterRangedSlot", [19] = "CharacterTabardSlot",
}

local function lockedOn()
  return TT.db and TT.Profile().lockedMode
end

-- An item is a violation if it has a card in the pool, the run does not own
-- that card, and this character was not wearing it when the lock began.
function TT.IsItemViolation(itemId)
  if not itemId then return false end
  local row = TT.cardIndex and TT.cardIndex["item:" .. itemId]
  if not row then return false end            -- uncarded items are always free
  if TT.cdb.grandfathered[itemId] then return false end
  return not TT.IsCardOwned("item:" .. itemId)
end

---------------------------------------------------------------------------
-- Grandfathering: the first time each character exists under the lock,
-- snapshot what they are wearing. Covers alts joining a locked realm run.
---------------------------------------------------------------------------

local function SnapshotGrandfathered()
  if TT.cdb.lockSeen then return end
  local count = 0
  for slotId = 1, 19 do
    local itemId = GetInventoryItemID("player", slotId)
    if itemId then
      TT.cdb.grandfathered[itemId] = true
      count = count + 1
    end
  end
  TT.cdb.lockSeen = true
  TT.Msg("Locked mode: " .. count .. " currently equipped item(s) grandfathered for " ..
    UnitName("player") .. ".")
end

-- called by Core when the lock is switched on by this character
function TT.Enforce_OnLockEnabled()
  SnapshotGrandfathered()
  TT.CheckEquipped(false)
end

---------------------------------------------------------------------------
-- Violation recording
---------------------------------------------------------------------------

function TT.RecordViolation(itemId, slotId)
  local now = GetTime()
  if lastWarn[itemId] and now - lastWarn[itemId] < 5 then return end
  lastWarn[itemId] = now

  local row = TT.cardIndex and TT.cardIndex["item:" .. itemId]
  local name = (row and row.n) or TT.ItemName(itemId) or ("item " .. itemId)
  local msg = "TCG VIOLATION: " .. name .. " - you don't own this card!"
  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
  end
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
    PlaySound(SOUNDKIT.RAID_WARNING)
  end
  TT.Warn(msg)
  TT.LogEvent("violation", nil, { item = itemId, slot = slotId })
  if TT.UI_Refresh then TT.UI_Refresh() end
end

-- Sweep all 19 slots. warn=true announces new violations (equip events);
-- warn=false just recomputes overlay state (refresh paths).
function TT.CheckEquipped(warn)
  if not lockedOn() then return end
  for slotId = 1, 19 do
    local itemId = GetInventoryItemID("player", slotId)
    if itemId and TT.IsItemViolation(itemId) and warn then
      TT.RecordViolation(itemId, slotId)
    end
  end
  if TT.Enforce_Update then TT.Enforce_Update() end
end

---------------------------------------------------------------------------
-- Overlays (visual only - never EnableMouse, so unequipping still works)
---------------------------------------------------------------------------

local function CreateLockOverlay(parent, anchorTo, small)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints(anchorTo or parent)
  f:SetFrameLevel((anchorTo or parent):GetFrameLevel() + 5)
  f:EnableMouse(false)

  f.shade = f:CreateTexture(nil, "OVERLAY")
  f.shade:SetAllPoints()
  f.shade:SetColorTexture(0.6, 0, 0, small and 0.25 or 0.45)

  f.lock = f:CreateTexture(nil, "OVERLAY", nil, 1)
  f.lock:SetPoint(small and "TOPRIGHT" or "CENTER", small and -1 or 0, small and -1 or 0)
  f.lock:SetSize(small and 12 or 16, small and 12 or 16)
  f.lock:SetTexture(LOCK_TEXTURE)
  f.lock:SetTexCoord(0, 0.71875, 0, 0.734375)
  f.lock:SetVertexColor(1, 0.35, 0.35)

  f:Hide()
  return f
end

local function UpdatePaperdollOverlays()
  for slotId, buttonName in pairs(INV_SLOT_BUTTONS) do
    local button = _G[buttonName]
    if button then
      local ov = overlays.gear[slotId]
      if not ov then
        ov = CreateLockOverlay(button)
        overlays.gear[slotId] = ov
      end
      local itemId = GetInventoryItemID("player", slotId)
      ov:SetShown(lockedOn() and itemId ~= nil and TT.IsItemViolation(itemId))
    end
  end
end

---------------------------------------------------------------------------
-- Bag overlays: small lock on carded-but-unowned equippables, so you can
-- see at a glance what you can't legally wear yet. Throttled ticker while
-- any container frame is open (robust across page/refresh churn).
---------------------------------------------------------------------------

local function UpdateBagOverlays()
  local anyShown = false
  for f = 1, 6 do
    local containerFrame = _G["ContainerFrame" .. f]
    if containerFrame and containerFrame:IsShown() then
      anyShown = true
      for i = 1, 36 do
        local button = _G["ContainerFrame" .. f .. "Item" .. i]
        if button and button:IsShown() then
          local key = f .. ":" .. i
          local ov = overlays.bags[key]
          if not ov then
            ov = CreateLockOverlay(button, nil, true)
            overlays.bags[key] = ov
          end
          local show = false
          if lockedOn() then
            local bagId = button.GetBagID and button:GetBagID()
              or (button:GetParent() and button:GetParent():GetID())
            local slotId = button:GetID()
            if bagId ~= nil and slotId and slotId > 0 then
              local itemId = GetContainerItemIDCompat and GetContainerItemIDCompat(bagId, slotId)
              if itemId and IsEquippableItemCompat and IsEquippableItemCompat(itemId)
                  and TT.IsItemViolation(itemId) then
                show = true
              end
            end
          end
          ov:SetShown(show)
        end
      end
    end
  end
  if not anyShown then
    for _, ov in pairs(overlays.bags) do ov:Hide() end
  end
  return anyShown
end

local bagTicker = CreateFrame("Frame")
bagTicker.elapsed = 0
bagTicker:SetScript("OnUpdate", function(self, elapsed)
  self.elapsed = self.elapsed + elapsed
  if self.elapsed >= 0.2 then
    self.elapsed = 0
    UpdateBagOverlays()
  end
end)
bagTicker:Hide()

---------------------------------------------------------------------------
-- Master update (wired into TT.Refresh by Core)
---------------------------------------------------------------------------

function TT.Enforce_Update()
  if not TT.db then return end
  UpdatePaperdollOverlays()
  bagTicker:SetShown(lockedOn() and true or false)
  if not lockedOn() then
    for _, ov in pairs(overlays.bags) do ov:Hide() end
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ef = CreateFrame("Frame")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ef:RegisterEvent("BAG_UPDATE_DELAYED")

ef:SetScript("OnEvent", function(self, event, arg1)
  if not TT.db then return end

  if event == "PLAYER_ENTERING_WORLD" then
    -- an alt logging into an already-locked run gets its snapshot here
    if lockedOn() and not TT.cdb.lockSeen then
      SnapshotGrandfathered()
    end
    TT.CheckEquipped(true)
    TT.Enforce_Update()

  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    TT.CheckEquipped(true)

  elseif event == "BAG_UPDATE_DELAYED" then
    if lockedOn() then UpdateBagOverlays() end
  end
end)
