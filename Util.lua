-- RunBook: shared helpers (compatibility shims, event dispatcher, formatting,
-- chat patterns). Display only: nothing here casts, moves, targets or loots.
local ADDON_NAME, ns = ...
ns.name = ADDON_NAME
-- The version from the TOC, where the packager writes the release tag. Running from
-- source it's still the "@project-version@" token, shown as "dev". (Shown in
-- /runbook check only: sync compatibility goes by the protocol number, never this.)
do
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(get or error, ADDON_NAME, "Version")
  ns.VERSION = (ok and type(v) == "string" and v ~= "" and not v:find("@", 1, true)) and v or "dev"
end

---------------------------------------------------------------------------
-- Compatibility
---------------------------------------------------------------------------
-- Forever runs Midnight's addon restrictions: some values come back "secret"
-- and throw if compared, concatenated or used as a table key. plain() turns
-- them into nil so callers just skip them. The secret check must come first:
-- even `v == nil` on a secret value can throw, and type() of a secret string
-- still says "string".
local issecret = issecretvalue or function() return false end
function ns.plain(v)
  if issecret(v) then return nil end
  return v
end
ns.IsSecret = issecret
local plain = ns.plain

-- Calls fn safely and returns its first result as a plain value (or nil).
function ns.Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok then return nil end
  return plain(v)
end

ns.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
ns.GetItemQualityByID = (C_Item and C_Item.GetItemQualityByID) or nil
ns.RequestItemLoad = (C_Item and C_Item.RequestLoadItemDataByID) or nil
ns.SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
ns.SendAddon = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
ns.RegisterPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix

-- Vulcan Suite accent ("ember"), shared by all four add-ons: chat name, titles, borders.
ns.ACCENT = { 0.91, 0.47, 0.17 }
ns.ACCENT_CODE = "|cffe8792b"

function ns.Print(msg)
  print(ns.ACCENT_CODE .. "RunBook|r: " .. tostring(msg))
end

-- Server time is the same for both of you; time() is each PC's own clock,
-- which can be minutes off. If server time can't be read for a moment, the
-- last known difference between the two keeps the result on server time.
local serverOffset = 0
function ns.ServerTime()
  local t = GetServerTime and ns.Call(GetServerTime)
  if type(t) == "number" then
    serverOffset = t - time()
    return t
  end
  return time() + serverOffset
end

-- A short random tag for this session, sent with sync messages so our own
-- echoed messages are recognized even if names come back in another form.
ns.token = string.format("%06x", math.random(0, 0xffffff))

---------------------------------------------------------------------------
-- Internal callbacks (UI and sync listen to these)
---------------------------------------------------------------------------
local callbacks = {}
function ns.Listen(name, fn)
  callbacks[name] = callbacks[name] or {}
  table.insert(callbacks[name], fn)
end

local errorsShown, errorCount = {}, 0
local function ReportError(where, err)
  err = tostring(err)
  if errorsShown[err] or errorCount >= 5 then return end
  errorsShown[err] = true
  errorCount = errorCount + 1
  ns.Print("error in " .. where .. ": " .. err)
end
ns.ReportError = ReportError

-- One listener failing must not stop the others (or the event that fired it).
function ns.Fire(name, ...)
  for _, fn in ipairs(callbacks[name] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok then ReportError(name, err) end
  end
end

---------------------------------------------------------------------------
-- Game event dispatcher (several listeners per event, errors reported once)
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}
ns.eventsSeen = {}  -- [event] = count, for /runbook check

function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    -- Unknown events throw on some builds; skip them quietly.
    pcall(eventFrame.RegisterEvent, eventFrame, event)
  end
  table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  ns.eventsSeen[event] = (ns.eventsSeen[event] or 0) + 1
  for _, fn in ipairs(handlers[event] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok then ReportError(event, err) end
  end
end)

---------------------------------------------------------------------------
-- Diagnostics log (/runbook debug). Off by default. Kept in SavedVariables so it
-- survives a reload and can be copied with /runbook export debug.
---------------------------------------------------------------------------
ns.DEBUG_MAX = 300

function ns.Log(category, fmt, ...)
  local db = ns.DB
  if not db or not db.debug then return end
  local ok, text = pcall(string.format, fmt, ...)
  if not ok then text = tostring(fmt) end
  local clock = date and date("%H:%M:%S") or "?"
  local log = db.debugLog
  log[#log + 1] = string.format("%s (%.1f) %s: %s", clock, GetTime and GetTime() or 0, category, text)
  while #log > ns.DEBUG_MAX do table.remove(log, 1) end
  if db.debugEcho then ns.Print("|cff888888[" .. category .. "]|r " .. text) end
end

-- Cached on first successful read so a later secret value can't make us
-- mistake our own echoed sync messages for a partner's.
local playerName
-- "Name-Realm": your characters on different realms can share a name.
local realmName
function ns.CharKey()
  local n = ns.PlayerName()
  if not n then return nil end
  if not realmName and GetNormalizedRealmName then
    local r = plain(GetNormalizedRealmName())
    if type(r) == "string" and r ~= "" then realmName = r end
  end
  return realmName and (n .. "-" .. realmName) or n
end

-- Your realm as in a message's sender ("Argent Dawn" -> "ArgentDawn"), or nil.
function ns.MyRealm()
  local r = GetNormalizedRealmName and plain(GetNormalizedRealmName()) or nil
  if type(r) ~= "string" or r == "" then return nil end
  return (r:gsub("[%s%-]", ""))
end

function ns.PlayerName()
  if not playerName then
    local n = plain(UnitName("player"))
    if type(n) == "string" and n ~= "" then playerName = n end
  end
  return playerName
end

-- "Mirel-Emberfall" -> "Mirel" (same-realm names are shown short in chat too).
function ns.ShortName(name)
  name = plain(name)
  if type(name) ~= "string" or name == "" then return nil end
  if Ambiguate then
    local short = ns.Call(Ambiguate, name, "short")
    if type(short) == "string" and short ~= "" then return short end
  end
  return (name:match("^[^%-]+")) or name
end

-- Same character name, whatever the case ("mirel" = "Mirel").
-- Names compared without case, including accented letters (Élan = élan).
local function Fold(n)
  n = n:gsub("\195([\128-\158])", function(c)
    local b = c:byte()
    if b == 0x97 then return "\195" .. c end  -- (the multiplication sign)
    return "\195" .. string.char(b + 32)
  end)
  -- Cyrillic capitals: А-П -> а-п, Р-Я -> р-я, Ё -> ё.
  n = n:gsub("\208([\128-\175])", function(c)
    local b = c:byte()
    if b < 0x90 then return "\209" .. string.char(b + 16) end
    if b < 0xA0 then return "\208" .. string.char(b + 32) end
    return "\209" .. string.char(b - 32)
  end)
  return n:lower()
end

ns.Fold = Fold

-- Two spellings of one boss's name: the same once folded, or one is a whole
-- part of the other ("VanCleef" in "Edwin VanCleef"; at least 4 letters, on
-- whole words: "Ras" isn't in "Grasp", and "Sneed" isn't in "Sneed's Shredder").
function ns.NameMatch(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then return false end
  local fa, fb = Fold(a), Fold(b)
  if fa == fb then return true end
  if #fa > #fb then fa, fb = fb, fa end
  if #fa < 4 then return false end
  local from = 1
  while true do
    local i, j = fb:find(fa, from, true)
    if not i then return false end
    local before, after = fb:sub(i - 1, i - 1), fb:sub(j + 1, j + 1)
    if (i == 1 or before:match("[%s,]")) and (j == #fb or after:match("[%s,]")) then return true end
    from = i + 1
  end
end

-- The same name typed a little differently: also with only letters and digits
-- compared ("Bael'Gar", "Baelgar").
function ns.NameSimilar(a, b)
  if ns.NameMatch(a, b) then return true end
  if type(a) ~= "string" or type(b) ~= "string" then return false end
  local fa, fb = Fold(a):gsub("[%s%p]", ""), Fold(b):gsub("[%s%p]", "")
  return fa ~= "" and fa == fb
end

-- A dungeon's name for matching a reset message to a run: "The Deadmines" and
-- "Deadmines" are the same (the message and the instance info may differ).
function ns.DungeonKey(name)
  if type(name) ~= "string" then return "" end
  local k = Fold(name):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  return (k:gsub("^the ", ""))
end

-- A saved run changed (a note, a boss taken back, your partner's numbers): when
-- two saved copies of it meet, the one changed last is kept.
function ns.Touch(run)
  if type(run) == "table" and run.ended then run.modified = ns.ServerTime() end
end

function ns.SameName(a, b)
  return type(a) == "string" and type(b) == "string" and (a == b or Fold(a) == Fold(b))
end

-- Is this unit token you? ("player", or your own raidN slot in a raid.)
function ns.IsPlayerUnit(unit)
  if unit == "player" then return true end
  local same = UnitIsUnit and ns.Call(UnitIsUnit, unit, "player")
  if same ~= nil then return same == true end
  -- The comparison can be hidden in instances: then by name and realm (a
  -- hidden name isn't you).
  -- In a raid, your own slot.
  if UnitInRaid then
    local idx = ns.Call(UnitInRaid, "player")
    if type(idx) == "number" then return unit == "raid" .. idx end
  end
  if not UnitName then return false end
  local ok, name, realm = pcall(UnitName, unit)
  if not ok then return false end
  name, realm = ns.plain(name), ns.plain(realm)
  -- Someone from another realm with your name isn't you. (Compared with what
  -- the client gives for you: some builds put something else there.)
  local okMe, _, myExtra = pcall(UnitName, "player")
  myExtra = okMe and ns.plain(myExtra) or nil
  return type(name) == "string" and name == ns.PlayerName() and (realm == nil or realm == "" or realm == myExtra)
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
function ns.Commas(n)
  n = math.floor((n or 0) + 0.5)
  local sign = n < 0 and "-" or ""
  local digits = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return sign .. (digits:gsub("^,", ""))
end

-- Thresholds sit just under the boundary so rounding can't produce "1000.0k".
function ns.Short(n)
  n = n or 0
  local a = math.abs(n)
  if a >= 999950 then return string.format("%.1fm", n / 1e6) end
  if a >= 9999.5 then return string.format("%.1fk", n / 1e3) end
  return ns.Commas(n)
end

-- "14g 20s", "14g", "3s 5c", "7c".
function ns.Money(copper, colored)
  copper = math.floor((copper or 0) + 0.5)
  local sign = copper < 0 and "-" or ""
  copper = math.abs(copper)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local G, Sv, C = "g", "s", "c"
  if colored then
    G, Sv, C = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"
  end
  if g > 0 then
    if s == 0 then return string.format("%s%s%s", sign, ns.Commas(g), G) end
    return string.format("%s%s%s %d%s", sign, ns.Commas(g), G, s, Sv)
  end
  if s > 0 then
    if c == 0 then return string.format("%s%d%s", sign, s, Sv) end
    return string.format("%s%d%s %d%s", sign, s, Sv, c, C)
  end
  return string.format("%s%d%s", sign, c, C)
end

-- A run's gold as it's shown (live window, details, the end line): to the
-- silver from a silver up, so shown shares add up to the shown total.
function ns.ShownMoney(copper)
  copper = math.floor((copper or 0) + 0.5)
  if copper >= 100 then return math.floor(copper / 100 + 0.5) * 100 end
  return copper
end

-- A shown amount, exactly: "2g 57s", "6 silver", "3s 50c", "50 copper" (copper
-- only when a share under a silver is in it).
function ns.ShownMoneyText(v, colored)
  if v >= 10000 then
    return ns.Money(v, colored) .. (v % 100 ~= 0 and (" " .. (v % 100) .. (colored and "|cffeda55fc|r" or "c")) or "")
  end
  if v >= 100 and v % 100 ~= 0 then return ns.Money(v, colored) end
  return ns.PlainMoney(v)
end

-- Run clock: "4:07", "32:10", "1:02:45".
function ns.Clock(sec)
  sec = math.max(0, math.floor((sec or 0) + 0.5))
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
  return string.format("%d:%02d", m, s)
end

-- Split difference vs your best: "-0:42" (ahead, green) or "+1:05" (behind, red).
-- Rounded first, so a 0.4s gap reads as an even split, not "-0:00".
function ns.Delta(sec, colored)
  sec = math.floor((sec or 0) + 0.5)
  local text
  if sec == 0 then
    text = "±0:00"
    return colored and ("|cffffffff" .. text .. "|r") or text
  end
  text = (sec < 0 and "-" or "+") .. ns.Clock(math.abs(sec))
  if not colored then return text end
  return (sec < 0 and "|cff40ff40" or "|cffff5050") .. text .. "|r"
end

function ns.Plural(n, word, words)
  return n .. " " .. (n == 1 and word or (words or (word .. "s")))
end

-- Cuts text to at most maxBytes without splitting a UTF-8 character.
function ns.Truncate(text, maxBytes)
  local out, used = {}, 0
  for ch in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if used + #ch > maxBytes then break end
    out[#out + 1] = ch
    used = used + #ch
  end
  return table.concat(out)
end

-- Like Truncate, but adds "..." when it had to cut.
-- "Scarlet Monastery - Cathedral" -> "SM Cathedral" (for short lines); other
-- names as they are.
function ns.ShortLabel(run)
  local label = tostring(run.label or run.name or "?")
  local name, wing = label:match("^(.-) %- (.+)$")
  if not name then return label end
  -- First letter of each word (a whole UTF-8 character, for other languages).
  local initials = ""
  for word in name:gmatch("%S+") do
    initials = initials .. (word:match("^[%z\1-\127\194-\244][\128-\191]*") or "")
  end
  return initials .. " " .. wing
end

-- Characters, not bytes ("·" is two bytes, one on screen).
function ns.Len(text)
  return select(2, tostring(text):gsub("[^\128-\191]", ""))
end

function ns.Ellipsis(text, maxBytes)
  text = tostring(text)
  if #text <= maxBytes then return text end
  return ns.Truncate(text, maxBytes - 3) .. "..."
end

-- Chat can't carry color codes, so reports strip them (item links keep theirs:
-- this is only used on text that has no links).
function ns.StripColors(text)
  return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cnIQ%d+:", ""):gsub("|r", ""))
end

-- Note text: item links become "[Name]" and any other "|" becomes "/", so the
-- text can't break chat escapes or the sync message format.
function ns.CleanText(text)
  text = tostring(text or "")
  text = text:gsub("|c[^|]*|H.-|h(%[.-%])|h|r", "%1"):gsub("|H.-|h(%[.-%])|h", "%1")
  text = text:gsub("|+", "/"):gsub("^%s+", ""):gsub("%s+$", "")
  return text
end

-- "[Cruel Barb]" from an item link, or the text itself if it isn't one.
function ns.LinkName(link)
  if type(link) ~= "string" then return "?" end
  return link:match("|h%[(.-)%]|h") or link
end

---------------------------------------------------------------------------
-- Item quality: from the link color (works before the item is cached), then
-- from item data.
---------------------------------------------------------------------------
local HEX_QUALITY = {
  ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3,
  ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7,
}
ns.QUALITY_HEX = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80", "00ccff" }

function ns.LinkQuality(link)
  if type(link) ~= "string" then return nil end
  local q = link:match("|cnIQ(%d+):")
  if q then return tonumber(q) end
  local hex = link:match("|cff(%x%x%x%x%x%x)")
  return hex and HEX_QUALITY[hex:lower()] or nil
end

function ns.ItemQuality(itemID, link)
  local q = ns.LinkQuality(link)
  if q then return q end
  local v = ns.Call(ns.GetItemQualityByID, itemID)
  if type(v) == "number" then return v end
  if ns.GetItemInfo then
    local ok, _, _, quality = pcall(ns.GetItemInfo, itemID)
    quality = ok and plain(quality) or nil
    if type(quality) == "number" then return quality end
  end
  return nil
end

-- Item name from item data, or nil while it hasn't loaded.
function ns.ItemName(itemID)
  local n = ns.Call(ns.GetItemInfo, itemID)
  return type(n) == "string" and n or nil
end

-- "[Name]" in its quality color, for windows (not a link, so it can't be
-- clicked by accident or break the line layout).
function ns.ColoredName(drop)
  local hex = ns.QUALITY_HEX[drop.q or 1] or "ffffff"
  return "|cff" .. hex .. "[" .. tostring(drop.name or "?") .. "]|r"
end

---------------------------------------------------------------------------
-- Chat message patterns, built from the client's own localized strings
---------------------------------------------------------------------------
-- "%s receives loot: %sx%d." -> "^(.+) receives loot: (.+)x(%d+)%."
function ns.FormatToPattern(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local p = fmt
  -- Korean grammar choices ("|1이;가;"): the client picks one before showing it.
  p = p:gsub("|1[^;]*;[^;]*;", "\003")
  p = p:gsub("%%%d+%$s", "\001"):gsub("%%%d+%$d", "\002")
  p = p:gsub("%%s", "\001"):gsub("%%d", "\002")
  p = p:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("\001", "(.+)"):gsub("\002", "(%%d+)"):gsub("\003", ".-")
  -- No end anchor: some clients append text after the period.
  return "^" .. p
end

-- Multi-quantity first: the single pattern would also match "...x3.".
ns.LOOT_PATTERNS = {}
for _, spec in ipairs({
  { LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.", "self" },
  { LOOT_ITEM_SELF or "You receive loot: %s.", "self" },
  { LOOT_ITEM_MULTIPLE or "%s receives loot: %sx%d.", "other" },
  { LOOT_ITEM or "%s receives loot: %s.", "other" },
}) do
  local pat = ns.FormatToPattern(spec[1])
  if pat then ns.LOOT_PATTERNS[#ns.LOOT_PATTERNS + 1] = { pat = pat, who = spec[2] } end
end

-- Returns looter ("self" or their name), item link, item ID, quantity; or nil.
-- The link is told apart from the name by its |Hitem: part, so locales that
-- put the name second still work.
function ns.ParseLoot(msg)
  if type(msg) ~= "string" then return nil end
  for _, p in ipairs(ns.LOOT_PATTERNS) do
    local caps = { msg:match(p.pat) }
    if caps[1] then
      local link, name, qty
      for _, c in ipairs(caps) do
        if c:find("|Hitem:", 1, true) then link = c
        elseif c:match("^%d+$") and not qty then qty = tonumber(c)
        else name = c end
      end
      local itemID = link and tonumber(link:match("|Hitem:(%d+)"))
      if itemID then
        if p.who == "self" then return "self", link, itemID, qty or 1 end
        if name then return name, link, itemID, qty or 1 end
      end
      return nil
    end
  end
  return nil
end

-- "%s has been reset." -> dungeon name, or nil.
do
  local fmt = INSTANCE_RESET_SUCCESS or "%s has been reset."
  local pat = ns.FormatToPattern(fmt)
  -- Korean picks a particle for the name ("|1이;가;"): it's not part of the name.
  local particles = {}
  for a, b in fmt:gmatch("|1([^;]*);([^;]*);") do particles[#particles + 1] = a particles[#particles + 1] = b end
  function ns.ParseReset(msg)
    if type(msg) ~= "string" or not pat then return nil end
    local name = msg:match(pat)
    if name then
      for _, p in ipairs(particles) do
        if p ~= "" and #name > #p and name:sub(-#p) == p then name = name:sub(1, -#p - 1) break end
      end
    end
    return name
  end
  ns.ResetPattern = function(f)  -- (for tests: the same for any format)
    local saved = { fmt, pat, particles }
    fmt, pat, particles = f, ns.FormatToPattern(f), {}
    for a, b in f:gmatch("|1([^;]*);([^;]*);") do particles[#particles + 1] = a particles[#particles + 1] = b end
    return function() fmt, pat, particles = saved[1], saved[2], saved[3] end
  end
end

-- "You have entered too many instances recently." in any of its spellings.
function ns.IsTooManyInstances(msg)
  if type(msg) ~= "string" then return false end
  local any = false
  for _, g in ipairs({ TRANSFER_ABORT_TOO_MANY_INSTANCES, ERR_TOO_MANY_INSTANCES }) do
    if type(g) == "string" and g ~= "" then
      any = true
      if msg:find(g, 1, true) then return true end
    end
  end
  -- (Only if the client has neither string: the English text itself - not
  -- "queued for too many instances", the dungeon finder's.)
  return not any and msg:lower():find("entered too many instances", 1, true) ~= nil
end
