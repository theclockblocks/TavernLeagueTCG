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
-- bars is keyed by the button frame, not a name: a bar addon that discards
-- and rebuilds its buttons should not pin the old ones here forever
setmetatable(overlays.bars, { __mode = "k" })
local pendingSweep = false
local sweeping = false
local lastCastWarn = {}
local warnedBags = {}

-- the license layer's enforcement gate (spells/talents/bags/gear slots):
-- always on in license formats - the format IS the lock
local function licenseOn()
  return TT.db ~= nil and TT.LicenseLayerActive()
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
--   "license" - the slot's license isn't owned (Challenge/League;
--               always enforced, no grandfathering - DeckLocked rules)
--   "card"    - TCG Locked mode is on and the item's card isn't owned
--               (grandfathered items are exempt, via IsItemViolation)
function TT.EquipViolationReason(slotId, itemId)
  if not itemId or not TT.db then return nil end
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
  if not TT.db then return end
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
-- Professions: a locked trade's window will not open, its icons wear the
-- lock, working it in the world is called out, and a trainer will not
-- teach it.
--
-- The deck sells two GENERIC primary slots plus the three secondaries, so
-- which trade fills prof-1 is the player's call: the first primary a run
-- opens claims the first free slot and keeps it, persisted, so the claim
-- survives a relog. Names come from the client's own spell names, which
-- keeps this locale-proof, and anything not in the table (Beast Training,
-- say) is none of our business.
--
-- A trade answers to several names - Herbalism gathers with "Herb
-- Gathering", Mining smelts at a "Smelting" window - so every alias maps
-- to one canonical name and the slot bookkeeping only ever sees that.
---------------------------------------------------------------------------

local PROFESSIONS = {
  -- key: "primary" for the two generic slots, else the license box.
  -- world: worked on something out in the world rather than at a window.
  -- aliases: the client does not always call a trade what its spell is
  --   called - the cast bar reads "Herb Gathering" while the skill line
  --   reads "Herbalism" - and no API hands over a skill line's name, so
  --   both spellings are listed. English only, which costs a non-English
  --   client nothing: the spell-derived names still do the real work.
  { key = "primary",  spells = { 2259 }, aliases = { "Alchemy" } },
  { key = "primary",  spells = { 2018 }, aliases = { "Blacksmithing" } },
  { key = "primary",  spells = { 7411 }, aliases = { "Enchanting" } },
  { key = "primary",  spells = { 4036 }, aliases = { "Engineering" } },
  { key = "primary",  spells = { 2366, 2383 }, world = true,
    aliases = { "Herbalism", "Herb Gathering", "Find Herbs" } },
  { key = "primary",  spells = { 25229 }, aliases = { "Jewelcrafting" } },
  { key = "primary",  spells = { 2108 }, aliases = { "Leatherworking" } },
  { key = "primary",  spells = { 2575, 2580, 2656 }, world = true,
    aliases = { "Mining", "Smelting", "Find Minerals" } },
  { key = "primary",  spells = { 8613 }, world = true,
    aliases = { "Skinning" } },
  { key = "primary",  spells = { 3908 }, aliases = { "Tailoring" } },
  { key = "cooking",  spells = { 2550 }, aliases = { "Cooking" } },
  { key = "firstaid", spells = { 3273 }, aliases = { "First Aid" } },
  { key = "fishing",  spells = { 7620 }, world = true,
    aliases = { "Fishing" } },
}

local profKinds = nil     -- [any name for a trade] = "primary" | license key
local profCanon = nil     -- [any name for a trade] = its canonical name
local profWorld = nil     -- [any name for a trade] = true if worked in the world
local lastProfWarn = {}

local function BuildProfLookup()
  profKinds, profCanon, profWorld = {}, {}, {}
  for _, prof in ipairs(PROFESSIONS) do
    local names = {}
    for _, spellId in ipairs(prof.spells) do
      local name = GetSpellInfo(spellId)
      if name then names[#names + 1] = name end
    end
    -- the skill line does not always share the gathering spell's name and
    -- no API hands it over, so those few are listed by hand (English only,
    -- which costs a non-English client nothing but a slot re-claim)
    for _, alias in ipairs(prof.aliases or {}) do
      names[#names + 1] = alias
    end
    local canon = names[1]
    if canon then
      for _, name in ipairs(names) do
        profKinds[name] = prof.key
        profCanon[name] = canon
        if prof.world then profWorld[name] = true end
      end
    end
  end
end

-- Best effort: the skill lines currently on show. Enough to release a slot
-- claimed by a trade the character has since dropped, and when the scan
-- comes back empty we simply keep every claim.
local function KnownProfessions()
  local known, sawAny = {}, false
  if not (GetNumSkillLines and GetSkillLineInfo) then return known, false end
  for i = 1, GetNumSkillLines() do
    local name, isHeader = GetSkillLineInfo(i)
    if not isHeader and name and profCanon[name] then
      known[profCanon[name]] = true
      sawAny = true
    end
  end
  return known, sawAny
end

-- nil = not a trade we police; a string = the license key that frees it;
-- false = a primary with no slot left to claim, so it stays shut.
--
-- peek answers the same question without writing anything. Painting an
-- icon must never claim a slot: having two trades on the action bar would
-- otherwise spend prof-1 on whichever the repaint happened to reach first,
-- before the player had chosen.
local function ProfessionLicenseKey(profName, peek)
  if not profKinds then BuildProfLookup() end
  local kind = profName and profKinds[profName]
  if not kind then return nil end
  if kind ~= "primary" then return kind end

  local canon = profCanon[profName]
  local run = TT.Run()
  run.profSlots = run.profSlots or {}
  if run.profSlots[canon] then return run.profSlots[canon] end

  local known, sawAny = KnownProfessions()
  local taken = {}
  for name, slot in pairs(run.profSlots) do
    if sawAny and not known[name] then
      -- trade dropped: its slot is free either way, and a real check
      -- also hands it back for good
      if not peek then run.profSlots[name] = nil end
    else
      taken[slot] = true
    end
  end
  for i = 1, 2 do
    local slot = "prof-" .. i
    if not taken[slot] and TT.IsUnlocked(slot) then
      if not peek then run.profSlots[canon] = slot end
      return slot
    end
  end
  return false
end

function TT.IsProfessionLocked(profName, peek)
  -- nothing is locked while the layer is off, and a dormant format must
  -- never claim a slot on the way to saying so
  if not licenseOn() then return false end
  local key = ProfessionLicenseKey(profName, peek)
  if key == nil then return false end
  if key == false then return true end
  return not TT.IsUnlocked(key)
end

function TT.DumpProfNames()
  if not profKinds then BuildProfLookup() end
  return profKinds, profCanon, profWorld
end

-- Worked out in the world rather than at a window: gathering and fishing
-- can only be called out once the cast lands, same as a locked spell.
function TT.IsWorldTradeLocked(name)
  if not profKinds then BuildProfLookup() end
  if not name or not profWorld[name] then return false end
  return TT.IsProfessionLocked(name, true)
end

-- What the spellbook and the action bars paint a lock on: an ability the
-- deck has not dealt, or a trade whose license the run has not earned.
local function IsNameLocked(name)
  if not name then return false end
  return IsSpellLocked(name) or TT.IsProfessionLocked(name, true)
end

-- Shut the window: end the interaction AND hide the frame, on this frame
-- and again on the next. Closing from inside a SHOW event can catch the
-- Blizzard UI mid-open, which leaves the window standing.
local function ShutTradeWindow(close, frame)
  local function shut()
    if close then close() end
    if frame and frame:IsShown() then
      if HideUIPanel then HideUIPanel(frame) else frame:Hide() end
    end
  end
  shut()
  if C_Timer and C_Timer.After then C_Timer.After(0, shut) end
end

local function BlockTradeWindow(profName, close, frame)
  if not licenseOn() or not profName then return end
  if not TT.IsProfessionLocked(profName) then return end
  ShutTradeWindow(close, frame)
  local now = GetTime()
  if lastProfWarn[profName] and now - lastProfWarn[profName] < 5 then return end
  lastProfWarn[profName] = now
  TT.Warn(profName .. " is locked - you don't hold a profession license for it!")
end

-- Never gate this on the frames: Blizzard_TradeSkillUI and Blizzard_CraftUI
-- load on demand, so TradeSkillFrame is still nil the first time a trade
-- announces itself. The APIs answer regardless and name no line - Classic
-- says "UNKNOWN" - while nothing is open, which is gate enough. The line
-- is also not always ready at SHOW, hence the caller's retries.
local function CheckOpenTradeWindows()
  local checked = false
  local name = GetTradeSkillLine and GetTradeSkillLine()
  if name and name ~= "UNKNOWN" and name ~= "" then
    BlockTradeWindow(name, CloseTradeSkill, TradeSkillFrame)
    checked = true
  end
  local craft = (GetCraftDisplaySkillLine and GetCraftDisplaySkillLine())
    or (GetCraftName and GetCraftName())
  if craft and craft ~= "UNKNOWN" and craft ~= ""
      and (not CraftFrame or CraftFrame:IsShown()) then
    BlockTradeWindow(craft, CloseCraft, CraftFrame)
    checked = true
  end
  return checked
end

TT.CheckTradeWindows = CheckOpenTradeWindows

local function CheckTradeWindowsSoon()
  if CheckOpenTradeWindows() then return end
  if not (C_Timer and C_Timer.After) then return end
  for _, delay in ipairs({ 0.1, 0.3, 0.6 }) do
    C_Timer.After(delay, CheckOpenTradeWindows)
  end
end

-- Second line of defence, independent of the trade events: once Blizzard's
-- load-on-demand trade UI exists, every OnShow re-runs the check. Whatever
-- route opened the window, this one sees it.
local hookedFrames = {}

local function HookTradeFrames()
  for _, name in ipairs({ "TradeSkillFrame", "CraftFrame" }) do
    local f = _G[name]
    if f and not hookedFrames[name] then
      hookedFrames[name] = true
      f:HookScript("OnShow", CheckTradeWindowsSoon)
    end
  end
end

---------------------------------------------------------------------------
-- Trainers: a locked trade will not be taught
--
-- BuyTrainerService is a plain API rather than a protected one, so
-- wrapping it refuses the purchase outright instead of complaining once
-- the gold is gone. The service's skill line names the trade; class
-- training and everything else a trainer offers passes straight through.
---------------------------------------------------------------------------

local function TrainerServiceTrade(index)
  local line = GetTrainerServiceSkillLine and GetTrainerServiceSkillLine(index)
  if line and profKinds[line] then return line end
  -- learning a trade lists it under its own name, not a skill line
  local name = GetTrainerServiceInfo and GetTrainerServiceInfo(index)
  if name and profKinds[name] then return name end
  return nil
end

local trainerBlocked = false

local function InstallTrainerBlock()
  if trainerBlocked or type(BuyTrainerService) ~= "function" then return end
  trainerBlocked = true
  local original = BuyTrainerService
  BuyTrainerService = function(index, ...)
    if licenseOn() then
      if not profKinds then BuildProfLookup() end
      local trade = TrainerServiceTrade(index)
      if trade and TT.IsProfessionLocked(trade, true) then
        TT.Warn(trade .. " is locked - earn its license before a trainer will teach it.")
        TT.LogEvent("violation", nil, { trainer = trade })
        return
      end
    end
    return original(index, ...)
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
          locked = name and IsNameLocked(name) or false
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

-- Which action slot is this button driving? Every bar addon answers
-- differently, so try each in turn and give up quietly rather than guess:
-- a button we cannot read simply goes unlocked, as it did before.
local function ButtonActionSlot(button)
  if button.GetPagedID then                       -- Blizzard
    local ok, id = pcall(button.GetPagedID, button)
    if ok and type(id) == "number" then return id end
  end
  if type(button.action) == "number" then return button.action end
  -- LibActionButton parks the slot in _state_action, but only when the
  -- button is actually driving one - for a spell button that field is a
  -- spell id instead, which the caller handles
  if button._state_type == "action" and type(button._state_action) == "number" then
    return button._state_action
  end
  local attr = button.GetAttribute and button:GetAttribute("action")
  if type(attr) == "number" then return attr end
  return nil
end

local function ButtonSpellName(button)
  -- a LibActionButton can hold a spell outright rather than an action slot
  if button._state_type == "spell" and type(button._state_action) == "number" then
    return (GetSpellInfo(button._state_action))
  end
  local action = ButtonActionSlot(button)
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

-- Bars that are not Blizzard's. LibActionButton-1.0 hands over every
-- button it owns, which covers Bartender4, Dominos, ElvUI and anything
-- else built on it in one pass. Forks embed under their own major name
-- (ElvUI ships "LibActionButton-1.0-ElvUI"), so match on the prefix and
-- take whichever ones answer.
local function ForEachLibButton(fn)
  if not (LibStub and LibStub.libs) then return end
  for major, lib in pairs(LibStub.libs) do
    if type(major) == "string" and major:find("^LibActionButton%-1%.0")
        and type(lib) == "table" and lib.GetAllButtons then
      local ok, buttons = pcall(lib.GetAllButtons, lib)
      if ok and type(buttons) == "table" then
        for k, v in pairs(buttons) do
          -- the set is keyed by button, but tolerate a plain list too
          local button = (type(k) == "table" and k) or (type(v) == "table" and v)
          if button then fn(button) end
        end
      end
    end
  end
end

-- ConsolePort's bar is round, so a square tint sits on it badly. The
-- portrait alpha mask is a plain white disc, so drawing it directly and
-- tinting it gives a circle without depending on SetMask being there.
local CIRCLE_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local blizzButtons = nil

local function IsBlizzardButton(button)
  if not blizzButtons then
    blizzButtons = {}
    for _, prefix in ipairs(BAR_PREFIXES) do
      for i = 1, 12 do blizzButtons[prefix .. i] = true end
    end
  end
  local name = button.GetName and button:GetName()
  return name ~= nil and blizzButtons[name] == true
end

local function StyleBarOverlay(ov, round)
  if ov.round == round then return end
  ov.round = round
  ov.lock:ClearAllPoints()
  if round then
    ov.tint:SetTexture(CIRCLE_TEXTURE)
    ov.tint:SetVertexColor(0.8, 0, 0, 0.55)
    ov.lock:SetPoint("CENTER")
  else
    ov.tint:SetColorTexture(0.8, 0, 0, 0.45)
    ov.lock:SetPoint("TOPRIGHT", -1, -1)
  end
end

-- An overlay is a plain Frame child of the button: it inherits the
-- button's position AND its visibility, so a bar the client never lays
-- out (or hides outright) can never strand a lock on the screen. A
-- non-secure child neither taints the button nor needs a combat guard.
local function ApplyBarOverlay(button, round)
  if type(button) ~= "table" or not button.GetFrameLevel then return end
  local ov = overlays.bars[button]
  if not ov then
    if not button.CreateTexture then return end
    ov = CreateFrame("Frame", nil, button)
    ov:SetAllPoints(button)
    ov:SetFrameLevel(button:GetFrameLevel() + 5)
    ov.tint = ov:CreateTexture(nil, "OVERLAY")
    ov.tint:SetAllPoints()
    ov.lock = ov:CreateTexture(nil, "OVERLAY", nil, 1)
    ov.lock:SetSize(12, 12)
    ov.lock:SetTexture(LOCK_TEXTURE)
    ov.lock:SetTexCoord(0, 0.71875, 0, 0.734375)
    ov:Hide()
    overlays.bars[button] = ov
  end
  StyleBarOverlay(ov, round and not IsBlizzardButton(button))
  -- IsVisible, not IsShown: a button on a hidden bar still reports itself
  -- shown, and those phantom bars are the ones that sit in odd corners
  local name = button:IsVisible() and ButtonSpellName(button) or nil
  ov:SetShown(licenseOn() and name ~= nil and IsNameLocked(name))
end

-- ConsolePort replaces the bar wholesale, so while it is loaded anything
-- that is not a Blizzard button by name is taken to be one of its round
-- ones. Blizzard's own buttons stay square either way.
local function ConsolePortLoaded()
  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if not isLoaded then return false end
  local ok, loaded = pcall(isLoaded, "ConsolePort")
  return (ok and loaded) and true or false
end

local function UpdateActionBarOverlays()
  local round = ConsolePortLoaded()
  for _, prefix in ipairs(BAR_PREFIXES) do
    for i = 1, 12 do
      ApplyBarOverlay(_G[prefix .. i], round)
    end
  end
  ForEachLibButton(function(button) ApplyBarOverlay(button, round) end)
end

---------------------------------------------------------------------------
-- Cast violations (protected casts can't be blocked - only called out)
---------------------------------------------------------------------------

-- Violations are named, never prevented: casting and gathering are both
-- protected actions, so the honest enforcement is a loud, logged callout.
-- One warning per spell per 5s covers the pair of events below.
local function RaiseViolation(name, msg, payload)
  local now = GetTime()
  if lastCastWarn[name] and now - lastCastWarn[name] < 5 then return end
  lastCastWarn[name] = now

  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
  end
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
    PlaySound(SOUNDKIT.RAID_WARNING)
  end
  TT.Warn(msg)
  TT.LogEvent("violation", nil, payload)
end

-- Gathering and fishing have a cast bar, so the call goes out the moment
-- the player starts working the node rather than once the ore is in the
-- bag. The successful cast is caught too, in case a trade is instant.
local function OnSpellcastStart(unit, _, spellID)
  if unit ~= "player" or not licenseOn() or not spellID then return end
  local name = GetSpellInfo(spellID)
  if not name or not TT.IsWorldTradeLocked(name) then return end
  RaiseViolation(name, "LICENSE VIOLATION: " .. name
    .. " - you don't hold a license for that trade!", { trade = name })
end

local function OnSpellcastSucceeded(unit, _, spellID)
  if unit ~= "player" or not licenseOn() or not spellID then return end
  local name = GetSpellInfo(spellID)
  if not name then return end

  -- a trade worked in the world - a herb pulled, an ore struck, a cast
  -- line - reads as a violation. Trades with a window are left alone:
  -- that window has already been shut in the player's face.
  local trade = TT.IsWorldTradeLocked(name)
  if not trade and not IsSpellLocked(name) then return end

  RaiseViolation(name, "LICENSE VIOLATION: " .. name
    .. (trade and " - you don't hold a license for that trade!"
               or " - you don't hold its card!"), { spell = spellID })
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
ef:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
ef:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
ef:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
ef:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
ef:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
ef:RegisterEvent("SPELLS_CHANGED")
ef:RegisterEvent("CHARACTER_POINTS_CHANGED")
ef:RegisterEvent("BAG_UPDATE_DELAYED")
ef:RegisterEvent("TRADE_SKILL_SHOW")
ef:RegisterEvent("TRADE_SKILL_UPDATE")
ef:RegisterEvent("CRAFT_SHOW")
ef:RegisterEvent("CRAFT_UPDATE")
ef:RegisterEvent("ADDON_LOADED")

ef:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
  if not TT.db then return end

  if event == "PLAYER_ENTERING_WORLD" then
    TT.LicenseEnforce_Update()
    HookTradeFrames()
    InstallTrainerBlock()
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

  elseif event == "UNIT_SPELLCAST_START" then
    OnSpellcastStart(arg1, arg2, arg3)

  -- SENT carries the target, so the spell id sits one along; some world
  -- interactions raise it without a START
  elseif event == "UNIT_SPELLCAST_SENT" then
    OnSpellcastStart(arg1, nil, arg4)

  elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED"
      or event == "UPDATE_SHAPESHIFT_FORM" or event == "SPELLS_CHANGED" then
    UpdateActionBarOverlays()

  elseif event == "CHARACTER_POINTS_CHANGED" then
    UpdateTalentGate()

  elseif event == "BAG_UPDATE_DELAYED" then
    CheckBagViolations()

  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE"
      or event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
    CheckTradeWindowsSoon()

  elseif event == "ADDON_LOADED" then
    if arg1 == "Blizzard_TalentUI" then
      local tframe = _G.PlayerTalentFrame or _G.TalentFrame
      if tframe then
        tframe:HookScript("OnShow", UpdateTalentGate)
      end
    else
      HookTradeFrames()
    end
  end
end)
