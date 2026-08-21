-- Tavern League TCG trading: whisper-based card trades between two addon
-- users on the same faction + realm.
--
-- Wire protocol (frozen in v1): "1:VERB:payload" over WHISPER.
--   T_REQ    nonce            propose a session; echoing it back = accept
--   T_OFFER  nonce;give=item:2589.f0.x2,...;want=   full-replace offer
--   T_ACCEPT nonce;hash       hash = checksum over BOTH canonical offers
--   T_LOCK   nonce;hash       phase 1: both sides saw matching accepts
--   T_COMMIT nonce;hash       phase 2: on matching LOCKs; both-commits apply
--   T_ABORT  nonce;reason     any state; inactivity times out the session
--
-- There is no server, so atomicity is best-effort: each side applies its
-- own collection changes only after it has both sent and received T_COMMIT.
-- Addon whispers are the game's reliable chat channel, so in practice the
-- risky window is a partner going offline mid-commit.
--
-- Practice mode: a local simulated partner ("Tavern Keeper") feeds the
-- SAME inbound handler through timers, exercising the full state machine
-- and UI solo - but the final apply is skipped, so no cards move.

local ADDON, TT = ...

local MAX_SLOTS = 8      -- offer entries per side (fits the 255-byte limit)
local TIMEOUT = 45       -- seconds of inactivity before auto-abort
local BOT_NAME = "Tavern Keeper"

local session = nil
local pendingReq = nil   -- incoming request awaiting the popup
local ui = {}

---------------------------------------------------------------------------
-- Offer wire format
---------------------------------------------------------------------------

local function serializeOffer(offer)
  local counts, order = {}, {}
  for _, e in ipairs(offer) do
    local id = e.k .. "." .. (e.f and "f1" or "f0")
    if not counts[id] then
      counts[id] = 0
      order[#order + 1] = id
    end
    counts[id] = counts[id] + 1
  end
  local parts = {}
  for _, id in ipairs(order) do
    parts[#parts + 1] = id .. ".x" .. counts[id]
  end
  return table.concat(parts, ",")
end

local function parseOffer(s)
  local offer = {}
  if not s or s == "" then return offer end
  for entry in s:gmatch("[^,]+") do
    local key, foil, count = entry:match("^(%a+:%d+)%.f([01])%.x(%d+)$")
    count = tonumber(count)
    if not key or not TT.cardIndex[key] or not count or count < 1 or count > MAX_SLOTS then
      return nil
    end
    for _ = 1, count do
      offer[#offer + 1] = { k = key, f = (foil == "1") }
      if #offer > MAX_SLOTS then return nil end
    end
  end
  return offer
end

-- Deterministic on both clients: sides ordered by name so the same string
-- (and hash) is computed regardless of who runs it.
local function computeHash()
  local me = UnitName("player") or "?"
  local them = session.partnerShort or session.partner
  local mine = me .. ">" .. serializeOffer(session.myOffer)
  local theirs = them .. ">" .. serializeOffer(session.theirOffer)
  local canonical
  if me:lower() < them:lower() then
    canonical = mine .. "|" .. theirs
  else
    canonical = theirs .. "|" .. mine
  end
  local h = 5381
  for i = 1, #canonical do
    h = (h * 33 + canonical:byte(i)) % 2147483647
  end
  return tostring(h)
end

local function newNonce()
  return tostring(math.random(100000, 999999)) ..
    tostring(math.floor((GetTime() * 100) % 10000))
end

---------------------------------------------------------------------------
-- Transport (practice mode swaps the wire for local timers)
---------------------------------------------------------------------------

local botHandle -- forward declaration

local function send(verb, payload)
  if not session then return end
  session.lastActivity = GetTime()
  if session.practice then
    botHandle(verb, payload)
  else
    TT.CommSend(verb, payload, "WHISPER", session.partner)
  end
end

local function sendTo(target, verb, payload)
  TT.CommSend(verb, payload, "WHISPER", target)
end

---------------------------------------------------------------------------
-- Session lifecycle
---------------------------------------------------------------------------

local function clearSession()
  session = nil
  if TT.Trade_Refresh then TT.Trade_Refresh() end
end

local function endTrade(msg)
  TT.Msg(msg)
  clearSession()
end

function TT.Trade_Abort(reason, silent)
  if not session then return end
  if not silent then
    send("T_ABORT", session.nonce .. ";" .. (reason or "cancelled"))
  end
  endTrade("Trade cancelled (" .. (reason or "cancelled") .. ").")
end

local function resetAccepts()
  if not session then return end
  session.myAccept = false
  session.theirAccept = false
  session.theirAcceptHash = nil
end

local function tradeBlocked()
  if not TT.db then return "not ready" end
  if TT.cdb.hardmode then
    return "Hardmode characters cannot trade - that's the point of Hardmode!"
  end
  return nil
end

---------------------------------------------------------------------------
-- Applying a completed trade
---------------------------------------------------------------------------

local function applyTrade()
  local p = TT.Profile()
  local me = UnitName("player")
  local partner = session.partnerShort or session.partner

  if session.practice then
    TT.LogEvent("event", ("Practice trade with %s completed (no cards moved)."):format(partner))
    endTrade("|cff00ff88Practice trade complete!|r The full handshake worked - no cards moved.")
    TT.Refresh()
    return
  end

  -- give: remove from collection + attribution follows the physical cards
  for _, e in ipairs(session.myOffer) do
    local col = p.collection[e.k]
    if col then
      local field = e.f and "f" or "n"
      col[field] = math.max(0, (col[field] or 0) - 1)
      if (col.n or 0) == 0 and (col.f or 0) == 0 then
        p.collection[e.k] = nil
        p.firstSeen[e.k] = nil
        p.fresh[e.k] = nil
      end
      TT.LedgerRemove(p, me, e.k, e.f, 1)
    end
  end

  -- receive: add to collection, attributed to the receiving character
  for _, e in ipairs(session.theirOffer) do
    local col = p.collection[e.k] or { n = 0, f = 0 }
    if (col.n + col.f) == 0 then
      p.firstSeen[e.k] = time()
      p.fresh[e.k] = true
    end
    if e.f then col.f = col.f + 1 else col.n = col.n + 1 end
    p.collection[e.k] = col
    TT.AddContribution(me, e.k, e.f)
  end

  p.stats.trades = (p.stats.trades or 0) + 1
  TT.LogEvent("event", ("Trade with %s: gave %d card(s), received %d card(s)."):format(
    partner, #session.myOffer, #session.theirOffer))
  TT.PlaySoundKit("IG_QUEST_LOG_OPEN")
  endTrade(("|cff00ff88Trade complete!|r Gave %d, received %d card(s)."):format(
    #session.myOffer, #session.theirOffer))
  TT.Refresh()
end

---------------------------------------------------------------------------
-- Handshake driver
---------------------------------------------------------------------------

local function advance()
  if not session or not session.active then return end
  local myHash = computeHash()

  if session.theirAccept and session.theirAcceptHash ~= myHash then
    -- offers changed in flight: their accept no longer matches
    session.theirAccept = false
    session.theirAcceptHash = nil
  end

  if session.myAccept and session.theirAccept then
    if not session.myLock then
      session.myLock = true
      session.lockHash = myHash
      send("T_LOCK", session.nonce .. ";" .. myHash)
    end
    if session.myLock and session.theirLock and not session.myCommit then
      session.myCommit = true
      send("T_COMMIT", session.nonce .. ";" .. myHash)
    end
    if session.myCommit and session.theirCommit then
      applyTrade()
      return
    end
  end
  if TT.Trade_Refresh then TT.Trade_Refresh() end
end

---------------------------------------------------------------------------
-- Public actions (UI + slash call these)
---------------------------------------------------------------------------

function TT.Trade_Propose(target)
  local blocked = tradeBlocked()
  if blocked then TT.Msg(blocked); return end
  if session then TT.Msg("Finish or cancel the current trade first."); return end
  target = (target or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if target == "" then TT.Msg("Enter a character name to trade with."); return end
  if target:lower() == (UnitName("player") or ""):lower() then
    TT.Msg("You can't trade with yourself - try the Practice Trade button.")
    return
  end
  session = {
    partner = target,
    partnerShort = Ambiguate and Ambiguate(target, "short") or target,
    nonce = newNonce(),
    initiator = true,
    active = false,
    practice = false,
    myOffer = {}, theirOffer = {},
    myAccept = false, theirAccept = false,
    myLock = false, theirLock = false,
    myCommit = false, theirCommit = false,
    lastActivity = GetTime(),
  }
  send("T_REQ", session.nonce)
  TT.Msg("Trade request sent to " .. target .. "...")
  if TT.Trade_Refresh then TT.Trade_Refresh() end
end

function TT.Trade_StartPractice()
  local blocked = tradeBlocked()
  if blocked then TT.Msg(blocked); return end
  if session then TT.Msg("Finish or cancel the current trade first."); return end
  session = {
    partner = BOT_NAME,
    partnerShort = BOT_NAME,
    nonce = newNonce(),
    initiator = true,
    active = false,
    practice = true,
    myOffer = {}, theirOffer = {},
    myAccept = false, theirAccept = false,
    myLock = false, theirLock = false,
    myCommit = false, theirCommit = false,
    lastActivity = GetTime(),
  }
  send("T_REQ", session.nonce)
  TT.Msg("Practice trade started - the Tavern Keeper will play along. No cards will move.")
  if TT.Trade_Refresh then TT.Trade_Refresh() end
end

-- Binder cells call this on click while a trade is open.
function TT.Trade_TryAdd(cardKey, foil)
  if not session or not session.active then return end
  if session.myLock then TT.Msg("The trade is locked - cancel to change your offer."); return end
  if #session.myOffer >= MAX_SLOTS then
    TT.Msg("Your offer is full (" .. MAX_SLOTS .. " cards max).")
    return
  end
  local col = TT.Profile().collection[cardKey]
  local owned = col and (foil and (col.f or 0) or (col.n or 0)) or 0
  local offered = 0
  for _, e in ipairs(session.myOffer) do
    if e.k == cardKey and e.f == foil then offered = offered + 1 end
  end
  if offered >= owned then
    TT.Msg(foil and "You have no spare foil copy of that card."
      or "You have no spare copy of that card.")
    return
  end
  session.myOffer[#session.myOffer + 1] = { k = cardKey, f = foil }
  resetAccepts()
  send("T_OFFER", session.nonce .. ";give=" .. serializeOffer(session.myOffer) .. ";want=")
  TT.PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
  if TT.Trade_Refresh then TT.Trade_Refresh() end
end

function TT.Trade_RemoveSlot(index)
  if not session or not session.active or session.myLock then return end
  if not session.myOffer[index] then return end
  table.remove(session.myOffer, index)
  resetAccepts()
  send("T_OFFER", session.nonce .. ";give=" .. serializeOffer(session.myOffer) .. ";want=")
  if TT.Trade_Refresh then TT.Trade_Refresh() end
end

function TT.Trade_ToggleAccept()
  if not session or not session.active or session.myLock then return end
  session.myAccept = not session.myAccept
  if session.myAccept then
    send("T_ACCEPT", session.nonce .. ";" .. computeHash())
  else
    -- withdrawing = re-sending the offer, which resets accepts on both ends
    send("T_OFFER", session.nonce .. ";give=" .. serializeOffer(session.myOffer) .. ";want=")
  end
  advance()
end

function TT.Trade_AcceptIncoming()
  if not pendingReq then return end
  local req = pendingReq
  pendingReq = nil
  if session then
    sendTo(req.sender, "T_ABORT", req.nonce .. ";busy")
    return
  end
  session = {
    partner = req.sender,
    partnerShort = req.senderShort,
    nonce = req.nonce,
    initiator = false,
    active = true,
    practice = false,
    myOffer = {}, theirOffer = {},
    myAccept = false, theirAccept = false,
    myLock = false, theirLock = false,
    myCommit = false, theirCommit = false,
    lastActivity = GetTime(),
  }
  send("T_REQ", session.nonce)  -- echo = accepted
  TT.Msg("Trading with " .. req.senderShort .. ". Open your Binder and click cards to offer them.")
  if TT.ToggleFrame and TavernLeagueTCGFrame and not TavernLeagueTCGFrame:IsShown() then
    TT.ToggleFrame()
  end
  if TT.ShowTab then TT.ShowTab("trade") end
end

function TT.Trade_DeclineIncoming()
  if not pendingReq then return end
  sendTo(pendingReq.sender, "T_ABORT", pendingReq.nonce .. ";declined")
  pendingReq = nil
end

---------------------------------------------------------------------------
-- Inbound messages (Core routes whisper trade verbs here)
---------------------------------------------------------------------------

function TT.Trade_OnMessage(verb, payload, sender, shortSender, version)
  if version and version ~= tostring(TT.PROTOCOL) then
    if verb == "T_REQ" then
      local nonce = payload:match("^(%w+)")
      sendTo(sender, "T_ABORT", (nonce or "0") .. ";version")
    end
    return
  end

  if verb == "T_REQ" then
    local nonce = payload:match("^(%w+)$")
    if not nonce then return end
    if session then
      if session.nonce == nonce and shortSender == (session.partnerShort or session.partner) then
        -- our proposal was accepted (echo)
        if not session.active then
          session.active = true
          session.lastActivity = GetTime()
          TT.Msg((session.partnerShort or session.partner) ..
            " accepted! Open your Binder and click cards to offer them.")
          if TT.ShowTab then TT.ShowTab("trade") end
        end
      else
        sendTo(sender, "T_ABORT", nonce .. ";busy")
      end
      return
    end
    local blocked = tradeBlocked()
    if blocked then
      sendTo(sender, "T_ABORT", nonce .. ";hardmode")
      return
    end
    pendingReq = { sender = sender, senderShort = shortSender, nonce = nonce }
    StaticPopup_Show("TAVERNLEAGUETCG_TRADEREQ", shortSender)
    return
  end

  -- everything else needs a matching live session
  if not session then return end
  if shortSender ~= (session.partnerShort or session.partner) then return end
  local nonce, rest = payload:match("^(%w+);(.*)$")
  if nonce ~= session.nonce then return end
  session.lastActivity = GetTime()

  if verb == "T_OFFER" then
    if session.myLock then return end -- locked: offers are frozen
    local give = rest:match("^give=([^;]*);want=")
    local offer = parseOffer(give)
    if not offer then
      TT.Trade_Abort("bad offer data")
      return
    end
    session.theirOffer = offer
    resetAccepts()
    session.active = true
    if TT.Trade_Refresh then TT.Trade_Refresh() end

  elseif verb == "T_ACCEPT" then
    session.theirAccept = true
    session.theirAcceptHash = rest
    advance()

  elseif verb == "T_LOCK" then
    if rest == computeHash() then
      session.theirLock = true
      advance()
    else
      TT.Trade_Abort("offer mismatch")
    end

  elseif verb == "T_COMMIT" then
    if rest == computeHash() then
      session.theirCommit = true
      advance()
    else
      TT.Trade_Abort("offer mismatch")
    end

  elseif verb == "T_ABORT" then
    local reason = rest ~= "" and rest or "cancelled"
    if reason == "busy" then
      endTrade((session.partnerShort or session.partner) .. " is busy in another trade.")
    elseif reason == "declined" then
      endTrade((session.partnerShort or session.partner) .. " declined the trade.")
    elseif reason == "version" then
      endTrade((session.partnerShort or session.partner) .. " runs an incompatible addon version.")
    elseif reason == "hardmode" then
      endTrade((session.partnerShort or session.partner) .. " is a Hardmode character and cannot trade.")
    else
      endTrade("Trade cancelled by " .. (session.partnerShort or session.partner) ..
        " (" .. reason .. ").")
    end
  end
end

---------------------------------------------------------------------------
-- Practice partner: replies through timers into the same inbound handler
---------------------------------------------------------------------------

local function botReply(verb, payload, delay)
  C_Timer.After(delay or 0.8, function()
    if session and session.practice then
      TT.Trade_OnMessage(verb, payload, BOT_NAME, BOT_NAME, tostring(TT.PROTOCOL))
    end
  end)
end

local function botMakeOffer()
  local entries = {}
  for _ = 1, math.random(1, 3) do
    local ptype = TT.PACK_TYPES[math.random(#TT.PACK_TYPES)]
    local bucket = TT.poolByType[ptype.key][math.random(1, 3)]
    if bucket and #bucket > 0 then
      local row = bucket[math.random(#bucket)]
      entries[#entries + 1] = { k = TT.CardKey(row), f = (math.random(10) == 1) }
    end
  end
  return serializeOffer(entries)
end

botHandle = function(verb, payload)
  if verb == "T_REQ" then
    botReply("T_REQ", session.nonce, 1.0)
    botReply("T_OFFER", session.nonce .. ";give=" .. botMakeOffer() .. ";want=", 2.2)
  elseif verb == "T_ACCEPT" then
    -- the Keeper agrees with whatever both offers currently are
    local hash = payload:match("^%w+;(.*)$")
    botReply("T_ACCEPT", session.nonce .. ";" .. (hash or ""), 1.2)
  elseif verb == "T_LOCK" then
    local hash = payload:match("^%w+;(.*)$")
    botReply("T_LOCK", session.nonce .. ";" .. (hash or ""), 0.6)
  elseif verb == "T_COMMIT" then
    local hash = payload:match("^%w+;(.*)$")
    botReply("T_COMMIT", session.nonce .. ";" .. (hash or ""), 0.6)
  elseif verb == "T_ABORT" then
    -- player cancelled; nothing to do
  end
end

---------------------------------------------------------------------------
-- Inactivity timeout
---------------------------------------------------------------------------

local watchdog = CreateFrame("Frame")
watchdog.elapsed = 0
watchdog:SetScript("OnUpdate", function(self, elapsed)
  self.elapsed = self.elapsed + elapsed
  if self.elapsed < 5 then return end
  self.elapsed = 0
  if session and GetTime() - session.lastActivity > TIMEOUT then
    TT.Trade_Abort("timeout")
  end
end)

---------------------------------------------------------------------------
-- Incoming-request popup
---------------------------------------------------------------------------

StaticPopupDialogs.TAVERNLEAGUETCG_TRADEREQ = {
  text = "%s wants to trade Tavern League cards with you.",
  button1 = "Trade",
  button2 = DECLINE,
  OnAccept = function() TT.Trade_AcceptIncoming() end,
  OnCancel = function() TT.Trade_DeclineIncoming() end,
  timeout = 30,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Trade tab UI (UI.lua calls Trade_BuildUI with the page frame)
---------------------------------------------------------------------------

local GOLD = { r = 1, g = 0.82, b = 0 }
local BOX_BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 8,
  insets = { left = 2, right = 2, top = 2, bottom = 2 },
}
local PANEL_BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function createSlot(parent, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(52, 52)
  b:SetBackdrop(BOX_BACKDROP)
  b:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
  b:SetBackdropBorderColor(0.35, 0.35, 0.35)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 3, -3)
  b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  -- foil copies shimmer gold instead of carrying a text tag
  b.foilGlow = b:CreateTexture(nil, "ARTWORK", nil, 2)
  b.foilGlow:SetPoint("TOPLEFT", 3, -3)
  b.foilGlow:SetPoint("BOTTOMRIGHT", -3, 3)
  b.foilGlow:SetColorTexture(1, 0.85, 0.3, 1)
  b.foilGlow:SetBlendMode("ADD")
  b.foilGlow:SetAlpha(0)
  if onClick then b:SetScript("OnClick", onClick) end
  b:SetScript("OnEnter", function(self)
    if not self.cardKey then return end
    local row = TT.cardIndex[self.cardKey]
    if not row then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local r, g, bl = TT.RarityColor(row.r)
    GameTooltip:SetText(row.n or ("Item " .. row.i), r, g, bl)
    if self.isMine then
      GameTooltip:AddLine("Click to remove from your offer.", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function fillSlot(slot, entry)
  if entry then
    local row = TT.cardIndex[entry.k]
    slot.cardKey = entry.k
    slot.icon:SetTexture(row and TT.categories[row.kind or "item"].GetIconNow(row) or TT.QUESTION_MARK)
    slot.icon:Show()
    local r, g, b = TT.RarityColor(row and row.r or 1)
    slot:SetBackdropBorderColor(r, g, b)
    slot.foilGlow:SetAlpha(entry.f and 0.3 or 0)
  else
    slot.cardKey = nil
    slot.icon:Hide()
    slot:SetBackdropBorderColor(0.35, 0.35, 0.35)
    slot.foilGlow:SetAlpha(0)
  end
end

function TT.Trade_BuildUI(page)
  -- idle view -----------------------------------------------------------
  ui.idle = CreateFrame("Frame", nil, page)
  ui.idle:SetAllPoints(page)

  local h = ui.idle:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  h:SetPoint("TOP", 0, -30)
  h:SetText("Card Trading")
  h:SetTextColor(GOLD.r, GOLD.g, GOLD.b)

  local desc = ui.idle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  desc:SetPoint("TOP", 0, -56)
  desc:SetWidth(520)
  desc:SetTextColor(0.7, 0.7, 0.7)
  desc:SetText("Trade cards with another Tavern League player on your realm and faction. " ..
    "Both of you need the addon. Hardmode characters cannot trade.")

  ui.nameBox = CreateFrame("EditBox", nil, ui.idle, "InputBoxTemplate")
  ui.nameBox:SetSize(160, 22)
  ui.nameBox:SetPoint("TOP", -70, -110)
  ui.nameBox:SetAutoFocus(false)
  ui.nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  ui.nameBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    TT.Trade_Propose(self:GetText())
  end)

  local proposeBtn = CreateFrame("Button", nil, ui.idle, "UIPanelButtonTemplate")
  proposeBtn:SetSize(90, 22)
  proposeBtn:SetPoint("LEFT", ui.nameBox, "RIGHT", 6, 0)
  proposeBtn:SetText("Propose")
  proposeBtn:SetScript("OnClick", function() TT.Trade_Propose(ui.nameBox:GetText()) end)

  local targetBtn = CreateFrame("Button", nil, ui.idle, "UIPanelButtonTemplate")
  targetBtn:SetSize(110, 22)
  targetBtn:SetPoint("LEFT", proposeBtn, "RIGHT", 6, 0)
  targetBtn:SetText("Use My Target")
  targetBtn:SetScript("OnClick", function()
    if UnitExists("target") and UnitIsPlayer("target") then
      ui.nameBox:SetText(UnitName("target") or "")
    else
      TT.Msg("Target a player first.")
    end
  end)

  local practiceBtn = CreateFrame("Button", nil, ui.idle, "UIPanelButtonTemplate")
  practiceBtn:SetSize(240, 26)
  practiceBtn:SetPoint("TOP", 0, -160)
  practiceBtn:SetText("Practice Trade (solo, no cards move)")
  practiceBtn:SetScript("OnClick", TT.Trade_StartPractice)

  -- active view ---------------------------------------------------------
  ui.active = CreateFrame("Frame", nil, page)
  ui.active:SetAllPoints(page)
  ui.active:Hide()

  ui.status = ui.active:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ui.status:SetPoint("TOP", 0, -14)
  ui.status:SetTextColor(GOLD.r, GOLD.g, GOLD.b)

  local hint = ui.active:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOP", 0, -34)
  hint:SetWidth(600)
  hint:SetTextColor(0.6, 0.6, 0.6)
  hint:SetText("Open your Binder and click a card to offer it (Ctrl-click offers your foil copy). " ..
    "Click a card below to take it back.")

  local function buildOfferPanel(x, title)
    local panel = CreateFrame("Frame", nil, ui.active, "BackdropTemplate")
    panel:SetSize(280, 190)
    panel:SetPoint("TOP", x, -70)
    panel:SetBackdrop(PANEL_BACKDROP)
    panel:SetBackdropColor(0.05, 0.05, 0.08, 0.9)
    panel:SetBackdropBorderColor(0.3, 0.3, 0.3)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOP", 0, -8)
    panel.title:SetText(title)
    panel.title:SetTextColor(GOLD.r, GOLD.g, GOLD.b)
    panel.slots = {}
    for i = 1, MAX_SLOTS do
      local col = (i - 1) % 4
      local row = math.floor((i - 1) / 4)
      local slot = createSlot(panel, function()
        TT.Trade_RemoveSlot(i)
      end)
      slot:SetPoint("TOPLEFT", 20 + col * 62, -30 - row * 62)
      panel.slots[i] = slot
    end
    return panel
  end

  ui.givePanel = buildOfferPanel(-150, "You Give")
  for _, slot in ipairs(ui.givePanel.slots) do slot.isMine = true end
  ui.recvPanel = buildOfferPanel(150, "You Receive")
  for _, slot in ipairs(ui.recvPanel.slots) do
    slot:SetScript("OnClick", nil)
  end

  ui.theirState = ui.active:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.theirState:SetPoint("TOP", ui.recvPanel, "BOTTOM", 0, -6)

  ui.acceptBtn = CreateFrame("Button", nil, ui.active, "UIPanelButtonTemplate")
  ui.acceptBtn:SetSize(150, 28)
  ui.acceptBtn:SetPoint("BOTTOM", -85, 60)
  ui.acceptBtn:SetText("Accept Trade")
  ui.acceptBtn:SetScript("OnClick", TT.Trade_ToggleAccept)

  ui.cancelBtn = CreateFrame("Button", nil, ui.active, "UIPanelButtonTemplate")
  ui.cancelBtn:SetSize(150, 28)
  ui.cancelBtn:SetPoint("BOTTOM", 85, 60)
  ui.cancelBtn:SetText("Cancel Trade")
  ui.cancelBtn:SetScript("OnClick", function() TT.Trade_Abort("cancelled") end)
end

function TT.Trade_Refresh()
  if not ui.idle then return end
  local active = session ~= nil
  ui.idle:SetShown(not active)
  ui.active:SetShown(active)
  if not active then return end

  local partner = session.partnerShort or session.partner
  local tag = session.practice and "  |cff888888(practice)|r" or ""
  if not session.active then
    ui.status:SetText("Waiting for " .. partner .. " to accept..." .. tag)
  elseif session.myLock then
    ui.status:SetText("Finalizing trade with " .. partner .. "..." .. tag)
  elseif session.myAccept then
    ui.status:SetText("Accepted - waiting for " .. partner .. tag)
  else
    ui.status:SetText("Trading with " .. partner .. tag)
  end

  ui.recvPanel.title:SetText("You Receive (from " .. partner .. ")")
  for i = 1, MAX_SLOTS do
    fillSlot(ui.givePanel.slots[i], session.myOffer[i])
    fillSlot(ui.recvPanel.slots[i], session.theirOffer[i])
  end

  ui.theirState:SetText(session.theirAccept
    and ("|cff00ff00" .. partner .. " has accepted|r")
    or (partner .. " has not accepted yet"))

  ui.acceptBtn:SetText(session.myAccept and "Un-Accept" or "Accept Trade")
  ui.acceptBtn:SetEnabled(session.active and not session.myLock)
end

-- Is a trade open and editable? (binder uses this to hint clicks)
function TT.Trade_IsOpen()
  return session ~= nil and session.active and not session.myLock
end
