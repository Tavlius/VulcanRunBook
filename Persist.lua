-- RunBook: saved-data safety (Vulcan Suite).
--
-- REMOVE WHEN FIXED. The World of Warcraft: Forever client has been reported to
-- write add-on saved data to disk but not load it back, and then overwrite the
-- good file at the next logout or /reload. Add-ons can't read or write files, so
-- this module does what is possible from inside the game:
--   * warns when a load failed. (RunBook already keeps a copy of the account
--     data in each character's file and merges it back in; this says so in plain
--     words, says what may still be missing, and spots a character file that
--     didn't load, using a list of characters kept in the account file);
--   * makes a backup string of all account data (/runbook backup) and restores
--     one (/runbook restore), with checks and a preview before anything changes.
--     Backups are compressed with LibDeflate (Libs\LibDeflate, zlib License).
-- (A registered CVar would make a better marker, but on client build 70205
-- registered CVars come back empty after a full restart.)
--
-- To retire it: delete this file and its TOC line (and Libs\LibDeflate if nothing
-- else uses it). Data.lua, Commands.lua and History.lua only reach it through
-- `ns.Persist` / `ns.extra*` guards.
local _, ns = ...
local P = {}
ns.Persist = P

local TAG = "VulcanRunBook"         -- names the add-on inside every backup string
local FORMAT = 1                    -- bump when the backup payload changes shape
local MAX_INPUT = 4 * 1024 * 1024   -- longest paste worth reading
local MAX_RAW = 8 * 1024 * 1024     -- largest data a backup may unpack to (checked while unpacking)
local MAX_DEPTH = 20
local OFFER_EVERY = 7 * 24 * 3600   -- offer a backup at most once a week
local MAX_CHARS = 200               -- characters remembered for the cross-check

-- Other Vulcan add-ons, so a backup pasted into the wrong one says where it goes.
local SUITE = {
  VulcanGrindWatch = "Vulcan GrindWatch", VulcanRunBook = "Vulcan RunBook",
  VulcanDuoQuest = "Vulcan DuoQuest", VulcanSimBench = "Vulcan SimBench",
}

---------------------------------------------------------------------------
-- Serializer: plain data only (tables, strings, finite numbers, booleans).
-- Reading never runs pasted text as code.
---------------------------------------------------------------------------
local function KeyOrder(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta == "number" end
  return a < b
end

local function Write(v, out, depth)
  local t = type(v)
  if t == "string" then
    out[#out + 1] = "S" .. #v .. ":" .. v
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then error("a number isn't finite", 0) end
    out[#out + 1] = "N" .. string.format("%.17g", v) .. ";"
  elseif t == "boolean" then
    out[#out + 1] = v and "T" or "F"
  elseif t == "table" then
    if depth > MAX_DEPTH then error("data nested too deeply", 0) end
    out[#out + 1] = "{"
    local keys = {}
    for k in pairs(v) do
      local kt = type(k)
      if kt ~= "string" and kt ~= "number" then error("a " .. kt .. " key can't be saved", 0) end
      keys[#keys + 1] = k
    end
    table.sort(keys, KeyOrder)
    for _, k in ipairs(keys) do
      Write(k, out, depth + 1)
      Write(v[k], out, depth + 1)
    end
    out[#out + 1] = "}"
  else
    error("a " .. t .. " can't be saved", 0)
  end
end

function P.Serialize(v)
  local out = {}
  Write(v, out, 0)
  return table.concat(out)
end

-- Returns value, next position; or nil when the text is malformed.
local function Read(s, i, depth)
  local c = s:sub(i, i)
  if c == "S" then
    local len, j = s:match("^(%d+):()", i + 1)
    if not len or #len > 9 then return nil end
    local last = j + tonumber(len) - 1
    if last > #s then return nil end
    return s:sub(j, last), last + 1
  elseif c == "N" then
    local num, j = s:match("^([%d%.eE%+%-]+);()", i + 1)
    local n = num and #num <= 32 and tonumber(num)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n, j
  elseif c == "T" then
    return true, i + 1
  elseif c == "F" then
    return false, i + 1
  elseif c == "{" then
    if depth > MAX_DEPTH then return nil end
    local t = {}
    i = i + 1
    while true do
      if s:sub(i, i) == "}" then return t, i + 1 end
      local k, v
      k, i = Read(s, i, depth + 1)
      if k == nil or (type(k) ~= "string" and type(k) ~= "number") then return nil end
      v, i = Read(s, i, depth + 1)
      if v == nil then return nil end
      t[k] = v
    end
  end
  return nil
end

function P.Deserialize(s)
  local v, nextPos = Read(s, 1, 0)
  if v == nil or nextPos ~= #s + 1 then return nil end
  return v
end

---------------------------------------------------------------------------
-- Checksum and text encoding (Lua 5.1 has no bit operators: plain arithmetic)
---------------------------------------------------------------------------
function P.Adler32(s)
  local a, b = 1, 0
  for i = 1, #s do
    a = (a + s:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return b * 65536 + a
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, 64 do B64_INDEX[B64:byte(i)] = i - 1 end

function P.Base64Encode(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local d1, d2 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64
    local d3, d4 = math.floor(n / 64) % 64, n % 64
    out[#out + 1] = B64:sub(d1 + 1, d1 + 1) .. B64:sub(d2 + 1, d2 + 1)
      .. (b and B64:sub(d3 + 1, d3 + 1) or "=") .. (c and B64:sub(d4 + 1, d4 + 1) or "=")
  end
  return table.concat(out)
end

function P.Base64Decode(s)
  if #s % 4 ~= 0 then return nil end
  local pad = s:match("(=*)$")
  if #pad > 2 then return nil end
  local body = s:sub(1, #s - #pad)
  if body:find("[^%w%+/]") then return nil end
  body = body .. string.rep("A", #pad)
  local out = {}
  for i = 1, #body, 4 do
    local n = 0
    for j = 0, 3 do n = n * 64 + B64_INDEX[body:byte(i + j)] end
    out[#out + 1] = string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
  end
  local raw = table.concat(out)
  return raw:sub(1, #raw - #pad)
end

---------------------------------------------------------------------------
-- Backup strings: TAG-backup:FORMAT:LENGTH:ADLER32:BASE64(DEFLATE(data))
-- LENGTH and ADLER32 describe the data before compression.
---------------------------------------------------------------------------
local function CopyData(v, depth)
  if type(v) ~= "table" then return v end
  if depth > MAX_DEPTH then return nil end
  local t = {}
  for k, val in pairs(v) do
    if type(k) == "string" or type(k) == "number" then t[k] = CopyData(val, depth + 1) end
  end
  return t
end

-- This character's key, only when the realm is known: a bare name could match a
-- same-named character on another realm.
local function CharKey()
  local key = ns.CharKey and ns.CharKey()
  if type(key) ~= "string" or not key:find("-", 1, true) then return nil end
  return key
end
P.CharKey = CharKey

-- All account data: settings, every run (full and short), instance entries and
-- remembered deletions. The diagnostics log is left out (troubleshooting only),
-- and so is the run in progress (it joins the history when it ends).
function P.MakeBackup()
  local db = CopyData(VulcanRunBookDB or {}, 0)
  db.debugLog = nil
  db.persistChars = nil
  local payload = { addon = TAG, format = FORMAT, made = time(), char = CharKey() or "?", db = db }
  local raw = P.Serialize(payload)
  local packed = ns.LibDeflate:CompressDeflate(raw, { level = 5 })
  return string.format("%s-backup:%d:%d:%08x:%s", TAG, FORMAT, #raw, P.Adler32(raw), P.Base64Encode(packed))
end

local DAMAGED = "This backup is incomplete or damaged. It's one long line: copy all of it and try again."

-- text -> payload, or nil + a message saying what's wrong. Nothing is changed.
function P.ParseBackup(text)
  if type(text) ~= "string" then return nil, "Paste a backup string first." end
  if #text > MAX_INPUT then return nil, "That's far longer than any RunBook backup." end
  local s = text:gsub("%s+", "")
  if s == "" then return nil, "Paste a backup string first." end
  local tag = s:match("^(%a+)%-backup:")
  if not tag then
    if s:find("%-backup:") then return nil, DAMAGED end
    return nil, "That isn't a RunBook backup string."
  end
  if tag ~= TAG then
    if SUITE[tag] then return nil, "That's a backup from " .. SUITE[tag] .. ". Paste it into that add-on instead." end
    return nil, "That isn't a RunBook backup string."
  end
  local format = tonumber(s:match("^%a+%-backup:(%d+):") or "")
  if not format then return nil, DAMAGED end
  if format > FORMAT then
    return nil, string.format("This backup was made by a newer RunBook (format %d). Update RunBook, then try again.",
      format)
  end
  if format ~= FORMAT then return nil, string.format("This backup uses an unknown format (%d).", format) end
  local len, sum, body = s:match("^%a+%-backup:%d+:(%d+):(%x+):([%w%+/=]+)$")
  if not len or #sum ~= 8 or tonumber(len) > MAX_RAW then return nil, DAMAGED end
  local packed = P.Base64Decode(body)
  if not packed then return nil, DAMAGED end
  local ok, raw = pcall(ns.LibDeflate.DecompressDeflate, ns.LibDeflate, packed, MAX_RAW)
  if not ok or type(raw) ~= "string" or #raw ~= tonumber(len) or P.Adler32(raw) ~= tonumber(sum, 16) then
    return nil, DAMAGED
  end
  local payload = P.Deserialize(raw)
  if type(payload) ~= "table" or payload.addon ~= TAG or payload.format ~= FORMAT or type(payload.db) ~= "table" then
    return nil, DAMAGED
  end
  return payload
end

local function Safe(s) return (tostring(s):gsub("|", "||")) end

local function CountRuns(list)
  local n, oldest, newest = 0, nil, nil
  for _, r in ipairs(type(list) == "table" and list or {}) do
    if type(r) == "table" then
      n = n + 1
      local t = tonumber(r.startedAt)
      if t and t > 0 then
        oldest = math.min(oldest or t, t)
        newest = math.max(newest or t, t)
      end
    end
  end
  return n, oldest, newest
end

-- What a restore would do, in plain words (shown before you confirm).
function P.PreviewLines(payload)
  local lines = {}
  local made = type(payload.made) == "number" and date("%Y-%m-%d %H:%M", payload.made) or "unknown time"
  lines[#lines + 1] = string.format("Backup made %s on %s.", made, Safe(payload.char))
  local full, o1, n1 = CountRuns(payload.db.history)
  local short, o2, n2 = CountRuns(payload.db.old)
  local oldest = math.min(o1 or math.huge, o2 or math.huge)
  local newest = math.max(n1 or 0, n2 or 0)
  local range = oldest < math.huge
    and string.format(", %s to %s", date("%Y-%m-%d", oldest), date("%Y-%m-%d", newest)) or ""
  lines[#lines + 1] = string.format("Runs: %d in full and %d older ones in short form%s.", full, short, range)
  lines[#lines + 1] = "Settings, instance-cap entries and remembered deletions."
  lines[#lines + 1] = "Runs you have now that aren't in the backup are kept (this character's copy is merged back in)."
  lines[#lines + 1] = "Settings are replaced by the backup's. Restoring reloads the UI."
  return lines
end

-- Puts the backup in place and reloads. Loading merges this character's copy
-- (refreshed at the reload's logout) back in, so runs made since the backup stay.
function P.Restore(payload)
  local db = CopyData(payload.db, 0)
  local old = type(VulcanRunBookDB) == "table" and VulcanRunBookDB or {}
  db.debugLog = old.debugLog          -- the log isn't in backups: keep the current one
  db.persistChars = old.persistChars  -- markers describe this install, not the backup
  -- Marked as loaded account data, so the settings in it are used as they are.
  db.savedAt = math.max(tonumber(db.savedAt) or 0, ns.ServerTime and ns.ServerTime() or time(), 1)
  VulcanRunBookDB = db
  P.restored = true
  if ReloadUI then ReloadUI() end
end

---------------------------------------------------------------------------
-- Load-failure detection
---------------------------------------------------------------------------
-- Called by Data.lua with the raw saved globals, before anything fills them in.
-- Each character's file holds a copy of the account data (mirror); the account
-- file lists the characters that have saved data. One missing while the other
-- says it should exist means the client failed to load it. (Both missing at once
-- looks exactly like a first install, so that case can't be told apart.)
-- The character check needs this character's realm, which can be unreadable while the
-- game is still loading. Then CheckLoad leaves P.charCheck (the list it loaded) and the
-- check runs again at PLAYER_LOGIN.
local function KeySet(list)
  if type(list) ~= "table" then return nil end
  local out = {}
  for k in pairs(list) do if type(k) == "string" then out[k] = true end end
  return out
end
function P.CheckLoad(rawDB, rawChar)
  local key = CharKey()
  local accountFailed = type(rawDB) ~= "table" and type(rawChar) == "table" and type(rawChar.mirror) == "table"
  P.charCheck = type(rawChar) ~= "table" and type(rawDB) == "table" and KeySet(rawDB.persistChars) or nil
  local charFailed = P.charCheck ~= nil and key ~= nil and P.charCheck[key] == true
  if key then P.charCheck = nil end
  P.failure = (accountFailed or charFailed) and { account = accountFailed, char = charFailed } or nil
  return P.failure
end

-- Written at logout, just before the client saves.
local function WriteMarkers()
  local db = VulcanRunBookDB
  local key = CharKey()
  if type(db) ~= "table" or not key then return end
  if type(db.persistChars) ~= "table" then db.persistChars = {} end
  db.persistChars[key] = time()
  local keys = {}
  for k, v in pairs(db.persistChars) do
    if type(k) ~= "string" or type(v) ~= "number" then db.persistChars[k] = nil else keys[#keys + 1] = k end
  end
  if #keys > MAX_CHARS then  -- forget the characters not seen for longest
    table.sort(keys, function(a, b) return db.persistChars[a] < db.persistChars[b] end)
    for i = 1, #keys - MAX_CHARS do db.persistChars[keys[i]] = nil end
  end
end
ns.On("PLAYER_LOGOUT", WriteMarkers)

function P.WarningLines(f)
  local lines = { "RunBook couldn't load part of your saved data.", "" }
  lines[#lines + 1] = "This is a known problem with the World of Warcraft: Forever client: add-on data is"
  lines[#lines + 1] = "written to disk but sometimes not loaded back. The file on disk is probably still fine,"
  lines[#lines + 1] = "but the game will overwrite it the next time you log out or /reload."
  lines[#lines + 1] = ""
  if f.account then
    lines[#lines + 1] = "Your account data (run history and settings) didn't load. RunBook used this"
    lines[#lines + 1] = "character's own copy instead, so your runs up to this character's last logout are back."
    lines[#lines + 1] = "Runs your OTHER characters saved since then are only in the file on disk."
    lines[#lines + 1] = ""
  end
  if f.char then
    lines[#lines + 1] = "This character's own file didn't load: a run in progress and this character's copy"
    lines[#lines + 1] = "of your history. Your account data loaded normally, so your history is safe."
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = "Before you log out or /reload:"
  lines[#lines + 1] = "1. Alt-Tab out of the game and copy this file somewhere safe:"
  if f.account then
    lines[#lines + 1] = "   WTF\\Account\\<your account>\\SavedVariables\\VulcanRunBook.lua  (history and settings)"
  end
  if f.char then
    lines[#lines + 1] = "   WTF\\Account\\<your account>\\<realm>\\<character>\\SavedVariables\\VulcanRunBook.lua"
      .. "  (this character)"
  end
  lines[#lines + 1] = "2. Then either exit the game fully, copy the file back over the new one and start again,"
  lines[#lines + 1] = "   or, if you made a backup string with /runbook backup, type /runbook restore and paste it."
  return lines
end

function P.ShowWarning()
  local f = P.failure
  if not f then return end
  ns.Print("|cffff4040saved data didn't fully load.|r This is a known Forever client problem, and the file "
    .. "will be overwritten at your next logout or /reload. Read the window that just opened before you do either.")
  if UIErrorsFrame then
    pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, "RunBook: saved data didn't load - see chat", 1, 0.25, 0.25)
  end
  ns.ShowCopy("RunBook: saved data didn't load", P.WarningLines(f))
end
ns.Listen("READY", P.ShowWarning)

ns.On("PLAYER_LOGIN", function()
  local pending, key = P.charCheck, CharKey()
  P.charCheck = nil
  if not (pending and key and pending[key]) then return end
  P.failure = P.failure or { account = false }
  P.failure.char = true
  P.ShowWarning()
end)

---------------------------------------------------------------------------
-- Offering a backup (when a run ends, at most once a week)
---------------------------------------------------------------------------
ns.Listen("RUN_END", function()
  local db = ns.DB
  if not db then return end
  local now = time()
  local last = math.max(tonumber(db.persistOffered) or 0, tonumber(db.persistBackedUp) or 0)
  if now - last < OFFER_EVERY then return end
  db.persistOffered = now
  ns.Print("tip: /runbook backup copies all your runs and settings as text you can keep outside the game, "
    .. "in case the Forever client loses saved data.")
end)

---------------------------------------------------------------------------
-- The restore window: paste, read what it holds, then confirm.
---------------------------------------------------------------------------
local pasteFrame

local function BuildPasteFrame()
  local f = CreateFrame("Frame", "VulcanRunBookRestoreFrame", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(560, 380)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.92)
    f:SetBackdropBorderColor(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], 1)
  end
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("RunBook: restore from a backup string  |cff888888(paste with Ctrl+V)|r")
  title:SetTextColor(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3])

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)

  local scroll = CreateFrame("ScrollFrame", "VulcanRunBookRestoreScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -32)
  scroll:SetPoint("BOTTOMRIGHT", -30, 150)
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(true)
  box:SetMaxLetters(0)
  box:SetFontObject(ChatFontNormal)
  box:SetWidth(510)
  box:SetScript("OnEscapePressed", function() f:Hide() end)
  scroll:SetScrollChild(box)

  local info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  info:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 140)
  info:SetPoint("RIGHT", -12, 0)
  info:SetJustifyH("LEFT")
  info:SetJustifyV("TOP")

  local restore = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  restore:SetSize(120, 22)
  restore:SetPoint("BOTTOMRIGHT", -12, 10)
  restore:SetText("Restore")
  local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  cancel:SetSize(90, 22)
  cancel:SetPoint("RIGHT", restore, "LEFT", -8, 0)
  cancel:SetText("Cancel")
  cancel:SetScript("OnClick", function() f:Hide() end)

  local function Update()
    local payload, err = P.ParseBackup(box:GetText())
    f.payload = payload
    if payload then
      info:SetText(table.concat(P.PreviewLines(payload), "\n"))
      restore:Enable()
    else
      info:SetText("|cffff8080" .. err .. "|r")
      restore:Disable()
    end
  end
  box:SetScript("OnTextChanged", function() Update() end)
  restore:SetScript("OnClick", function() if f.payload then P.Restore(f.payload) end end)

  if UISpecialFrames then table.insert(UISpecialFrames, "VulcanRunBookRestoreFrame") end
  f.box, f.info, f.restore, f.cancel, f.Update = box, info, restore, cancel, Update
  pasteFrame = f
end

function P.ShowRestore()
  if not pasteFrame then BuildPasteFrame() end
  pasteFrame.box:SetText("")
  pasteFrame.Update()
  pasteFrame:Show()
  pasteFrame:Raise()
  pasteFrame.box:SetFocus()
  return pasteFrame
end

function P.ShowBackup()
  local ok, text = pcall(P.MakeBackup)
  if not ok then
    ns.Print("couldn't make a backup: " .. tostring(text))
    return nil
  end
  ns.DB.persistBackedUp = time()
  ns.ShowCopy("RunBook backup: copy it and keep it somewhere safe", { text })
  ns.Print(string.format("backup ready (%d characters). Ctrl+C copies it; /runbook restore puts it back.", #text))
  return text
end

function P.CheckLine()
  if not P.failure then return "saved data: loaded normally" end
  return "saved data: |cffff4040didn't fully load this session|r (see /runbook backup and /runbook restore)"
end

---------------------------------------------------------------------------
-- Commands, help and buttons (picked up by Commands.lua / History.lua)
---------------------------------------------------------------------------
ns.extraCommands = {
  backup = function() P.ShowBackup() end,
  restore = function() P.ShowRestore() end,
}
ns.extraHelp = {
  "|cffffff00backup|r all your runs and settings as text to keep outside the game   |cffffff00restore|r paste one back",
}
ns.extraHistoryButtons = {
  { label = "Backup", run = function() P.ShowBackup() end },
  { label = "Restore", run = function() P.ShowRestore() end },
}
