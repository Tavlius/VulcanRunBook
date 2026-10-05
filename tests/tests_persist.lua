-- Saved-data safety (Persist.lua): load-failure warnings, backup and restore.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check, eq = H.check, H.eq

local function fresh(opts) local c = H.boot(opts) c.login() return c end
local function noErrors(c)
  local errs = c.errors()
  check("no runtime errors", #errs == 0, errs[1])
end
local function warned(c) return c.printedMatch("saved data didn't fully load", true) ~= nil end
local function copyFrame() return _G.VulcanRunBookCopyFrame end
-- A user click: a disabled button ignores it, like the client.
local function click(w)
  if not w or not w.enabled then return false end
  if w.scripts.OnClick then w.scripts.OnClick(w, "LeftButton", true) end
  return true
end

local function deepEqual(a, b, path)
  path = path or "value"
  if type(a) ~= type(b) then return false, path .. ": " .. type(a) .. " vs " .. type(b) end
  if type(a) ~= "table" then
    if a == b then return true end
    return false, path .. ": " .. tostring(a) .. " vs " .. tostring(b)
  end
  for k, v in pairs(a) do
    local ok, where = deepEqual(v, b[k], path .. "." .. tostring(k))
    if not ok then return false, where end
  end
  for k in pairs(b) do
    if a[k] == nil then return false, path .. "." .. tostring(k) .. ": missing on the left" end
  end
  return true
end

-- One real run, played through the mock client: bosses, a wipe, a death, drops.
local function playRun(c, name, map)
  c.item(1001, "Cruel Barb", 3, 5000)
  c.item(1002, "Smite's Mighty Hammer", 3, 8000)
  c.item(1003, "Linen Cloth", 1, 10)
  c.enter(name or "Deadmines", map or 36)
  c.tick(60)
  c.encounter(644, "Rhahk'Zor")
  c.lootMsg(nil, 1003, 3)
  c.tick(90)
  c.encounter(643, "Sneed", false)  -- a wipe
  c.die() c.tick(20) c.dead = false c.fire("PLAYER_UNGHOST") c.tick(30)
  c.encounter(643, "Sneed")
  c.lootMsg(nil, 1001)
  c.gainMoney(12345)
  c.tick(120)
  c.encounter(642, "Gilnid")
  c.lootMsg(nil, 1002)
  c.tick(60)
  c.slash("end")
  c.leave()
  c.tick(5)
  return c.history()[1]
end

-- Copies of a real run, each its own run (start times and ids differ).
local function cloneRuns(c, template, n, lite, startAt)
  local list = {}
  for i = 1, n do
    local r = c.ns.Persist.Deserialize(c.ns.Persist.Serialize(template))
    r.id = 100000 + i + (lite and 50000 or 0)
    r.serverStart = (startAt or 1650000000) + i * 7200
    r.startedAt = r.serverStart
    if r.serverEnd then r.serverEnd = r.serverStart + 1800 end
    list[i] = lite and c.ns.Lite(r) or r
  end
  return list
end

-- A first login and a normal logout (saved like the client does: separate copies).
local function firstInstall(opts)
  local c = fresh(opts)
  return c, c.savedCopy()
end

-- 1. A genuine first install warns about nothing; logout writes the marker.
H.group("first install")
do
  local c, saved = firstInstall()
  check("no failure", c.ns.Persist.failure == nil)
  check("no warning", not warned(c))
  check("logout lists this character in the account data",
    type(saved.db.persistChars) == "table" and type(saved.db.persistChars["Tavlius-Realm"]) == "number")
  noErrors(c)
  local c2 = H.boot({ saved = saved }) c2.login()
  check("normal reload: no failure, no warning", c2.ns.Persist.failure == nil and not warned(c2))
  c2.clearPrinted()
  c2.slash("check")
  check("/runbook check says saved data loaded", c2.printedMatch("saved data: loaded normally", true) ~= nil)
end

-- 2. The account file didn't load: this character's copy fills in, and a warning says what may be missing.
H.group("account data didn't load")
do
  local c = fresh()
  playRun(c)
  local saved = c.savedCopy()
  local c2 = H.boot({ saved = { db = nil, char = saved.char } }) c2.login()
  local f = c2.ns.Persist.failure
  check("account failure detected", f and f.account and not f.char)
  check("warned in chat", warned(c2))
  check("runs came back from this character's copy", #c2.history() == 1)
  local frame = copyFrame()
  local text = frame and frame.shown and table.concat(c2.ns.Persist.WarningLines(f), "\n") or ""
  check("warning window opened", frame and frame.shown and frame.title.text:find("saved data didn't load", 1, true) ~= nil)
  check("says other characters' runs may be missing", text:find("Runs your OTHER characters saved since then", 1, true) ~= nil)
  check("names the account file", text:find("\\SavedVariables\\VulcanRunBook.lua", 1, true) ~= nil and text:find("<character>", 1, true) == nil)
  check("says the next save overwrites it", text:find("overwrite it the next time you log out or /reload", 1, true) ~= nil)
  check("points to /runbook restore", text:find("/runbook restore", 1, true) ~= nil)
  c2.clearPrinted()
  c2.slash("check")
  check("/runbook check reports it", c2.printedMatch("didn't fully load this session", true) ~= nil)
  noErrors(c2)
end

-- 3. This character's file didn't load, but the account file lists the character.
H.group("character data didn't load")
do
  local _, saved = firstInstall()
  local c = H.boot({ saved = { db = saved.db, char = nil } }) c.login()
  local f = c.ns.Persist.failure
  check("character failure detected", f and f.char and not f.account)
  local text = table.concat(c.ns.Persist.WarningLines(f), "\n")
  check("names the character file only", text:find("<character>", 1, true) ~= nil and text:find("(history and settings)", 1, true) == nil)
  check("says the history is safe", text:find("your history is safe", 1, true) ~= nil)
  noErrors(c)
end

-- 4. A new character, an unreadable realm, or both files missing: no warning.
H.group("not failures")
do
  local _, saved = firstInstall()
  local c = H.boot({ saved = { db = saved.db, char = nil }, name = "Mirel" }) c.login()
  check("new character on the account: no warning", c.ns.Persist.failure == nil and not warned(c))
  local c2 = H.boot({ saved = { db = saved.db, char = nil }, noRealm = true }) c2.login()
  check("realm unreadable: no guess, no warning", c2.ns.Persist.failure == nil and not warned(c2))
  local c2b = H.boot({ noRealm = true }) c2b.login()
  local s2b = c2b.savedCopy()
  check("realm unreadable at logout: no bare-name marker written",
    type(s2b.db.persistChars) ~= "table" or next(s2b.db.persistChars) == nil)
  check("realm unreadable at logout: no errors", #c2b.errors() == 0, c2b.errors()[1])
  local c3 = H.boot({ saved = { db = nil, char = nil } }) c3.login()
  check("both missing looks like a first install", c3.ns.Persist.failure == nil and not warned(c3))
  saved.db.persistChars = "junk"
  local c4 = H.boot({ saved = { db = saved.db, char = nil } }) c4.login()
  check("damaged marker list: ignored", c4.ns.Persist.failure == nil)
  local s4 = c4.savedCopy()
  check("damaged marker list replaced at logout", type(s4.db.persistChars) == "table")
  noErrors(c4)
end

-- 4b. The realm can be unreadable while the game loads: the character check waits for login.
H.group("late realm")
do
  local _, saved = firstInstall()
  local c = H.boot({ saved = { db = saved.db, char = nil }, noRealm = true })
  c.fire("ADDON_LOADED", "VulcanRunBook")
  check("realm unreadable at load: no verdict yet", c.ns.Persist.failure == nil and not warned(c))
  _G.GetNormalizedRealmName = function() return "Realm" end
  c.fire("PLAYER_LOGIN")
  check("realm readable at login: the character failure is caught then", c.ns.Persist.failure
    and c.ns.Persist.failure.char and warned(c))
  local c2 = H.boot({ saved = { db = saved.db, char = nil }, noRealm = true, name = "Mirel" })
  c2.fire("ADDON_LOADED", "VulcanRunBook")
  _G.GetNormalizedRealmName = function() return "Realm" end
  c2.fire("PLAYER_LOGIN")
  check("late check: a new character is still not a failure", c2.ns.Persist.failure == nil and not warned(c2))
end

-- 5. Round trip through the restore window, and the merge with what you have now.
H.group("backup and restore")
do
  local c = fresh()
  local template = playRun(c)
  c.ns.DB.cap = 4
  local P = c.ns.Persist
  local text = P.ShowBackup()
  check("backup opens the copy window", copyFrame().shown and copyFrame().title.text:find("backup", 1, true) ~= nil)
  check("backup string names the add-on and format", text:match("^VulcanRunBook%-backup:1:%d+:%x%x%x%x%x%x%x%x:") ~= nil)
  check("one line of safe characters", text:find("[^%w%+/=:%-]") == nil)
  local payload = P.ParseBackup(text)
  local expect = {}
  for k, v in pairs(VulcanRunBookDB) do
    if k ~= "debugLog" and k ~= "persistChars" and k ~= "persistBackedUp" then expect[k] = v end
  end
  local got = {}
  for k, v in pairs(payload.db) do if k ~= "persistBackedUp" then got[k] = v end end
  local same, where = deepEqual(got, expect)
  check("account data round-trips exactly", same, where)

  -- After the backup: a new run, and the first run deleted.
  playRun(c, "Wailing Caverns", 43)
  local wcUID = c.ns.RunUID(c.history()[1])
  local dmUID = c.ns.RunUID(template)
  c.slash("delete " .. tostring(template.id) .. " yes")
  check("first run deleted", #c.history() == 1)
  c.ns.DB.cap = 9
  local f = P.ShowRestore()
  check("Restore disabled until a backup is pasted", not f.restore.enabled)
  f.box:SetText(text)
  f.box.scripts.OnTextChanged(f.box, true)
  check("valid backup enables Restore", f.restore.enabled)
  local info = f.info.text
  check("preview counts the runs", info:find("Runs: 1 in full and 0 older ones in short form") ~= nil, info)
  check("preview says current runs are kept", info:find("Runs you have now that aren't in the backup are kept", 1, true) ~= nil)
  check("nothing changed before confirming", (c.reloads or 0) == 0 and c.ns.DB.cap == 9)
  click(f.restore)
  check("confirming reloads the UI once", c.reloads == 1)
  check("the restored data counts as loaded account data", type(VulcanRunBookDB.savedAt) == "number" and VulcanRunBookDB.savedAt > 0)
  local c2 = H.boot({ saved = c.savedCopy() }) c2.login()
  local uids = {}
  for _, r in ipairs(c2.history()) do uids[c2.ns.RunUID(r)] = true end
  check("the run made after the backup is kept", uids[wcUID])
  check("a run deleted after the backup stays deleted", not uids[dmUID])
  eq("settings come from the backup", c2.ns.DB.cap, 4)
  check("no load warning after a restore", c2.ns.Persist.failure == nil and not warned(c2)
    and not c2.printedMatch("Account data didn't load", true))
  noErrors(c2)
end

-- 6. The largest realistic history: 200 full runs and 2000 short ones.
H.group("largest realistic history")
do
  local c = fresh()
  local template = playRun(c)
  c.ns.DB.history = cloneRuns(c, template, c.ns.HISTORY_MAX, false, 1700000000)
  c.ns.DB.old = cloneRuns(c, template, c.ns.OLD_MAX, true, 1600000000)
  local P = c.ns.Persist
  local t0 = os.clock()
  local text = P.MakeBackup()
  local made = os.clock() - t0
  t0 = os.clock()
  local payload, err = P.ParseBackup(text)
  local read = os.clock() - t0
  check("largest backup parses", payload ~= nil, err)
  check("all runs round-trip", payload and deepEqual(payload.db.history, VulcanRunBookDB.history)
    and deepEqual(payload.db.old, VulcanRunBookDB.old))
  check("compressed to well under the paste limit", #text < 1024 * 1024, #text)
  io.write(string.format("largest realistic backup: %d characters (%.2fs to make, %.2fs to read)\n", #text, made, read))
  -- And it survives a reload after restoring (the load checks accept every run).
  P.Restore(payload)
  local c2 = H.boot({ saved = c.savedCopy() }) c2.login()
  eq("full runs after restore", #c2.history(), c2.ns.HISTORY_MAX)
  eq("short runs after restore", #VulcanRunBookDB.old, c2.ns.OLD_MAX)
  noErrors(c2)
end

-- 7. Fuzz: random data through the serializer, the text encoding and whole backups.
H.group("fuzz")
do
  local c = fresh()
  local P = c.ns.Persist
  local x = 99
  local function r(n) x = (x * 1103515245 + 12345) % 2147483648 return x % n end
  local function str(maxLen)
    local t = {}
    for i = 1, r(maxLen + 1) do t[i] = string.char(r(256)) end
    return table.concat(t)
  end
  local function value(depth)
    local kind = r(depth > 4 and 3 or 4)
    if kind == 0 then return str(40) end
    if kind == 1 then
      local picks = { 0, 1, -1, 0.1, 1 / 3, 2 ^ 53, 1e300, -1e-300, r(1000000) - 500000 }
      return picks[r(#picks) + 1]
    end
    if kind == 2 then return r(2) == 1 end
    local t = {}
    for _ = 1, r(6) do t[r(2) == 1 and str(12) or (r(100) - 50)] = value(depth + 1) end
    return t
  end
  local bad = 0
  for i = 1, 300 do
    local v = { data = value(0), n = i }
    if not deepEqual(v, P.Deserialize(P.Serialize(v))) then bad = bad + 1 end
  end
  eq("random tables round-trip", bad, 0)
  bad = 0
  for len = 0, 200 do
    local s = str(len)
    if P.Base64Decode(P.Base64Encode(s)) ~= s then bad = bad + 1 end
  end
  eq("random bytes round-trip the text encoding", bad, 0)
  bad = 0
  for _ = 1, 30 do
    VulcanRunBookDB = { history = {}, old = {}, extra = value(0) }
    local payload = P.ParseBackup(P.MakeBackup())
    local want = { history = {}, old = {}, extra = VulcanRunBookDB.extra }
    if not payload or not deepEqual(payload.db, want) then bad = bad + 1 end
  end
  eq("random backups round-trip (compressed)", bad, 0)
end

-- 8. Rejections: every bad paste says what's wrong and changes nothing.
H.group("rejections")
do
  local c = fresh()
  playRun(c)
  local P = c.ns.Persist
  local good = P.MakeBackup()
  local before = P.Serialize(VulcanRunBookDB)
  local L = c.ns.LibDeflate
  local function wrapRaw(raw, format)
    local packed = L:CompressDeflate(raw)
    return string.format("VulcanRunBook-backup:%d:%d:%08x:%s", format or 1, #raw, P.Adler32(raw), P.Base64Encode(packed))
  end
  local function payloadWith(changes)
    local p = P.ParseBackup(good)
    for k, v in pairs(changes) do p[k] = v end
    return P.Serialize(p)
  end
  local body = good:match(":([%w%+/=]+)$")
  local flipped = body:sub(1, 40) .. (body:sub(41, 41) == "A" and "B" or "A") .. body:sub(42)
  -- A crafted paste that inflates far past the limit (a "decompression bomb").
  local bombRaw = string.rep("A", 9 * 1024 * 1024)
  local bomb = string.format("VulcanRunBook-backup:1:%d:%08x:%s", 100, 1, P.Base64Encode(L:CompressDeflate(bombRaw, { level = 1 })))
  local cases = {
    { "empty paste", "", "Paste a backup string first" },
    { "chat text", "hello there", "isn't a RunBook backup" },
    { "truncated end", good:sub(1, #good - 12), "incomplete or damaged" },
    { "truncated middle", good:sub(1, 60) .. good:sub(200), "incomplete or damaged" },
    { "one character changed", (good:gsub(":[%w%+/=]+$", ":" .. flipped)), "incomplete or damaged" },
    { "wrong length", (good:gsub("^(VulcanRunBook%-backup:1:)(%d+)", function(a, n) return a .. (tonumber(n) + 1) end)), "incomplete or damaged" },
    { "wrong checksum", (good:gsub("^(VulcanRunBook%-backup:1:%d+:)(%x+)", "%100000000")), "incomplete or damaged" },
    { "not compressed data", string.format("VulcanRunBook-backup:1:10:%08x:%s", 1, P.Base64Encode("plain text, not deflate")), "incomplete or damaged" },
    { "inflates past the limit", bomb, "incomplete or damaged" },
    { "length over the limit", (good:gsub("^(VulcanRunBook%-backup:1:)(%d+)", "%199999999999")), "incomplete or damaged" },
    { "GrindWatch backup", (good:gsub("^VulcanRunBook", "VulcanGrindWatch")), "from Vulcan GrindWatch%. Paste it into that add%-on" },
    { "some other add-on", (good:gsub("^VulcanRunBook", "SomeAddon")), "isn't a RunBook backup" },
    { "future format", (good:gsub("^VulcanRunBook%-backup:1:", "VulcanRunBook-backup:2:")), "newer RunBook %(format 2%)" },
    { "unknown old format", (good:gsub("^VulcanRunBook%-backup:1:", "VulcanRunBook-backup:0:")), "unknown format %(0%)" },
    { "far too long", string.rep("A", 5 * 1024 * 1024), "far longer" },
    { "payload for another add-on", wrapRaw(payloadWith({ addon = "VulcanGrindWatch" })), "incomplete or damaged" },
    { "payload without account data", wrapRaw(payloadWith({ db = "x" })), "incomplete or damaged" },
    { "trailing bytes", wrapRaw(P.Serialize({ addon = "VulcanRunBook", format = 1, db = {} }) .. "T"), "incomplete or damaged" },
    { "valid backup with data nested 30 deep", wrapRaw((payloadWith({ deep = "DEEP" }):gsub("S4:DEEP", string.rep("{S1:a", 30) .. "T" .. string.rep("}", 30)))), "incomplete or damaged" },
    { "valid backup with an infinite number", wrapRaw((payloadWith({ big = 12345.5 }):gsub("N12345%.5;", "N1e999;"))), "incomplete or damaged" },
  }
  check("planted payloads are otherwise valid", P.ParseBackup(wrapRaw(payloadWith({ deep = "DEEP", big = 12345.5 }))) ~= nil)
  local f = P.ShowRestore()
  for _, case in ipairs(cases) do
    local name, text, want = case[1], case[2], case[3]
    local payload, err = P.ParseBackup(text)
    check("reject " .. name .. ": refused", payload == nil)
    check("reject " .. name .. ": says why", type(err) == "string" and err:find(want) ~= nil, err)
    f.box:SetText(text)
    f.box.scripts.OnTextChanged(f.box, true)
    check("reject " .. name .. ": Restore stays disabled", not f.restore.enabled and not click(f.restore))
  end
  check("rejections changed nothing", P.Serialize(VulcanRunBookDB) == before and (c.reloads or 0) == 0)
  -- The size cap works inside the decompressor (a bomb stops there, not after inflating),
  -- and reading a backup always passes it.
  local packedBomb = L:CompressDeflate(string.rep("A", 2 * 1024 * 1024), { level = 1 })
  check("the decompressor stops at the cap", L:DecompressDeflate(packedBomb, 256 * 1024) == nil)
  check("without a cap it still works as the original", #(L:DecompressDeflate(packedBomb) or "") == 2 * 1024 * 1024)
  local seenCap
  local real = L.DecompressDeflate
  L.DecompressDeflate = function(self, s, cap) seenCap = cap return real(self, s, cap) end
  P.ParseBackup(good)
  L.DecompressDeflate = real
  check("reading a backup passes the size cap", type(seenCap) == "number" and seenCap > 0 and seenCap <= 16 * 1024 * 1024, seenCap)
  local wrapped = "  " .. good:sub(1, 50) .. "\n" .. good:sub(51, 120) .. " \r\n" .. good:sub(121) .. "\n"
  check("pasted with line breaks still parses", P.ParseBackup(wrapped) ~= nil)
  noErrors(c)
end

-- 9. A backup is offered when a run ends, at most once a week, and not right after you made one.
H.group("backup offer")
do
  local c = fresh()
  local dungeons = { { "Deadmines", 36 }, { "Wailing Caverns", 43 }, { "Shadowfang Keep", 33 }, { "Blackfathom Deeps", 48 } }
  local n = 0
  local function ended()
    c.clearPrinted()
    n = n + 1
    playRun(c, dungeons[n][1], dungeons[n][2])
    return c.printedMatch("tip: /runbook backup", true) ~= nil
  end
  check("first run ended: offered", ended())
  check("next run the same day: not offered", not ended())
  c.wall = c.wall + 8 * 24 * 3600
  check("a week later: offered again", ended())
  c.wall = c.wall + 8 * 24 * 3600
  c.ns.Persist.ShowBackup()
  check("right after a backup: not offered", not ended())
end

-- 10. Commands, help and the history window's buttons reach it.
H.group("commands and buttons")
do
  local c = fresh()
  c.slash("backup")
  check("/runbook backup opens the backup", copyFrame().shown and copyFrame().title.text:find("backup", 1, true) ~= nil)
  c.slash("restore")
  check("/runbook restore opens the restore window", _G.VulcanRunBookRestoreFrame and _G.VulcanRunBookRestoreFrame.shown)
  c.clearPrinted()
  c.slash("help")
  check("help lists backup and restore", c.printedMatch("backup", true) ~= nil and c.printedMatch("restore", true) ~= nil)
  copyFrame():Hide()
  _G.VulcanRunBookRestoreFrame:Hide()
  c.slash("history")
  local buttons = {}
  for _, fr in ipairs(c.frames) do
    if fr.kind == "Button" and fr.parent == _G.VulcanRunBookHistoryFrame and fr.text then buttons[fr.text] = fr end
  end
  check("history window has Backup and Restore buttons", buttons.Backup ~= nil and buttons.Restore ~= nil)
  click(buttons.Backup)
  check("Backup button opens the backup", copyFrame().shown)
  click(buttons.Restore)
  check("Restore button opens the restore window", _G.VulcanRunBookRestoreFrame.shown)
  noErrors(c)
end

-- 11. Version: from source the TOC token shows as "dev"; a release shows its tag.
H.group("version")
do
  local c = fresh()
  eq("from source: dev", c.ns.VERSION, "dev")
  c.clearPrinted()
  c.slash("check")
  check("/runbook check shows dev", c.printedMatch("version dev", true) ~= nil)
  local c2 = fresh({ tocVersion = "v1.1.0" })
  eq("packaged: the tag", c2.ns.VERSION, "v1.1.0")
end

os.exit(H.summary() and 0 or 1)
