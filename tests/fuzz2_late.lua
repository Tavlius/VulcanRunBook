-- Randomized lifecycle fuzzer: interleaves zoning, ticks, deaths, boss events,
-- loot (shown and hidden), bag changes, coin/XP, partner sync, slash commands,
-- reloads, relogs, character switches and failed account loads, and checks
-- invariants after every step. Usage: lua5.1 fuzz.lua <seed> <steps>
-- (SMALLCAP=1 shrinks the history limits to exercise short-form runs).
package.path = "./?.lua;" .. package.path
local H = require("harness")
local function P(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end io.write(table.concat(t, " "), "\n") end

local SEED = tonumber(arg[1]) or 1
local STEPS = tonumber(arg[2]) or 400
local VERBOSE = arg[3] == "v"
NOANON = os.getenv("NOANON") ~= nil
goneUIDs = {}
KNOWN = os.getenv("KNOWN") ~= nil
math.randomseed(SEED)
local R = math.random

local DUNGEONS = {
  { "Deadmines", 36 }, { "Wailing Caverns", 43 }, { "Scarlet Monastery", 189 }, { "Molten Core", 409 },
}
local BOSSES = { [36] = { { 1, "Rhahk'Zor" }, { 2, "Sneed" }, { 3, "Gilnid" }, { 4, "Van Cleef" } },
  [43] = { { 11, "Kresh" }, { 12, "Mutanus" } }, [189] = { { 21, "Herod" }, { 22, "Mograine" } }, [409] = { { 31, "Lucifron" }, { 32, "Ragnaros" } } }

local c
local log = {}
local function L(s) log[#log + 1] = s if VERBOSE then P(s) end end

local function setupItems(cl)
  cl.item(100, "Cruel Barb", 3, 5000)
  cl.item(101, "Linen Cloth", 1, 15)
  cl.item(103, "Lucky Charm", 2, 300)
  cl.item(104, "Smite's Hammer", 4, 20000)
  cl.item(105, "Slow Item", 3, 777, false)  -- not cached
  cl.mapGroups = { [302] = 50, [303] = 50, [304] = 50, [305] = 50 }
  cl.mapNames = { [302] = "Scarlet Monastery", [303] = "Scarlet Monastery" }
  cl.groupFloors = { [50] = { { mapID = 302, name = "Graveyard" }, { mapID = 303, name = "Library" },
    { mapID = 304, name = "Armory" }, { mapID = 305, name = "Cathedral" } } }
end
FLOOR = { m302 = "Graveyard", m303 = "Library", m304 = "Armory", m305 = "Cathedral" }

local function copy(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[copy(k)] = copy(x) end
  return o
end

c = H.boot({ name = "Tavlius" })
if os.getenv("SMALLCAP") then c.ns.HISTORY_MAX = 4 c.ns.OLD_MAX = 6 end
setupItems(c)
c.login()

local errorsSeen = 0
local failures = {}
local function fail(msg)
  failures[#failures + 1] = msg
  P("SEED " .. SEED .. " FAIL: " .. msg)
  P("  last ops: " .. table.concat(log, " ; ", math.max(1, #log - 15)))
  os.exit(1)
end

local function allRuns(ns)
  local out = {}
  if ns.run then out[#out + 1] = ns.run end
  for _, r in ipairs(_G.VulcanRunBookDB.history) do out[#out + 1] = r end
  return out
end

local function checkInvariants(tag)
  local errs = c.errors()
  if #errs > errorsSeen then fail(tag .. " lua error: " .. errs[#errs]) end
  local ns = c.ns
  local db = _G.VulcanRunBookDB
  local uids, ids = {}, {}
  for _, r in ipairs(db.history) do
    local u = ns.RunUID(r)
    if uids[u] then fail(tag .. " duplicate uid " .. u) end
    uids[u] = true
    if type(r.id) ~= "number" then fail(tag .. " history run without id") end
    if ids[r.id] then fail(tag .. " duplicate id " .. tostring(r.id)) end
    ids[r.id] = true
    if r == ns.run then fail(tag .. " run in progress is also in history") end
    if not r.ended then fail(tag .. " history run not ended") end
  end
  if ns.run then
    if uids[ns.RunUID(ns.run)] then fail(tag .. " run in progress uid also in history") end
    if ns.run.id and ids[ns.run.id] then fail(tag .. " run in progress id also in history " .. ns.run.id) end
    if ns.run.ended then fail(tag .. " run in progress marked ended") end
  end
  for _, r in ipairs(db.history) do
    if goneUIDs[ns.RunUID(r)] and not (KNOWN and r.keepAfterClear) then fail(tag .. " deleted/cleared run came back: " .. ns.RunUID(r) .. " keep " .. tostring(r.keepAfterClear) .. " end " .. tostring(r.serverEnd) .. " cleared " .. db.clearedAt .. " why " .. tostring(goneUIDs[ns.RunUID(r)])) end
  end
  for _, r in ipairs(db.old) do
    if goneUIDs[ns.RunUID(r)] then fail(tag .. " deleted/cleared run came back (old): " .. ns.RunUID(r)) end
    local u = ns.RunUID(r)
    if uids[u] then fail(tag .. " uid in history and old " .. u) end
    uids[u] = true
  end
  for _, r in ipairs(allRuns(ns)) do
    for _, k in ipairs({ "elapsed", "coin", "loot", "lootAH", "xp", "unpriced" }) do
      if type(r[k]) ~= "number" or r[k] < 0 then fail(tag .. " bad total " .. k .. "=" .. tostring(r[k])) end
    end
    if r.lootAH < r.loot then fail(tag .. " lootAH < loot") end
    for _, k in ipairs({ "bosses", "drops", "deaths", "wipes" }) do
      for _, it in ipairs(r[k]) do
        if type(it.t) ~= "number" or it.t < 0 then fail(tag .. " bad t in " .. k) end
        if it.t > r.elapsed + 1.01 then fail(tag .. string.format(" %s t %s > elapsed %.1f (%s)", k, it.t, r.elapsed, r.label)) end
      end
    end
    for i = 2, #r.bosses do
      if r.bosses[i].t < r.bosses[i - 1].t then fail(tag .. " boss times go backwards in " .. r.label) end
    end
    for i = 2, #r.bosses do
      local a, b = r.bosses[i-1], r.bosses[i]
      if a.t == b.t and (a.anonymous or b.anonymous) and not a.manual and not b.manual and a.src ~= "sync" and b.src ~= "sync" then fail(tag .. " one kill recorded twice: " .. a.name .. " & " .. b.name .. " in " .. r.label) end
    end
    -- the same boss twice in one run
    local seenB = {}
    for _, b in ipairs(r.bosses) do
      local k = b.id and ("i" .. b.id) or ("n" .. b.name:lower())
      if seenB[k] then fail(tag .. " boss twice in one run: " .. b.name .. " in " .. r.label) end
      seenB[k] = true
    end
    if r.wing and FLOOR[r.wing] and not r.label:find(FLOOR[r.wing], 1, true) then fail(tag .. " wing/label mismatch " .. r.wing .. " " .. r.label) end
    if r.wing and not FLOOR[r.wing] then fail(tag .. " bogus wing " .. tostring(r.wing) .. " " .. r.label) end
    for _, d in ipairs(r.drops) do if type(d.n) ~= "number" or d.n <= 0 then fail(tag .. " drop n " .. tostring(d.n)) end end
    for _, p in pairs(r.partners) do
      for _, k in ipairs({ "elapsed", "coin", "loot", "lootAH", "xp" }) do
        if (p[k] or 0) < 0 then fail(tag .. " partner negative") end
      end
    end
  end
  -- cache consistent with a fresh recompute
  local keys = {}
  for _, list in ipairs({ db.history, db.old }) do for _, r in ipairs(list) do keys[ns.RunKey(r)] = true end end
  local cached = {}
  for k in pairs(keys) do
    local i = ns.DungeonInfo(k)
    cached[k] = { i.max, i.total, i.final and (i.final.id or i.final.name), i.bestT, i.clears, #i.runs }
  end
  ns.ClearCache()
  for k in pairs(keys) do
    local i = ns.DungeonInfo(k)
    local f = { i.max, i.total, i.final and (i.final.id or i.final.name), i.bestT, i.clears, #i.runs }
    for j = 1, #f do
      if f[j] ~= cached[k][j] then fail(tag .. " stale cache for " .. k .. " field " .. j .. ": " .. tostring(cached[k][j]) .. " vs " .. tostring(f[j])) end
    end
  end
  -- render paths don't throw
  ns.LiveLines()
  ns.DungeonLines()
  for _, r in ipairs(allRuns(ns)) do ns.RunDetailLines(r) ns.CSVRow(r) end
  ns.HistoryContent()
  ns.ExportLines("")
  ns.ReportLines()
  errs = c.errors()
  if #errs > errorsSeen then fail(tag .. " lua error: " .. errs[#errs]) end
end

local prevRun = {}
local function monotonic(tag)
  local ns = c.ns
  local r = ns.run
  if r and prevRun.uid == ns.RunUID(r) then
    for _, k in ipairs({ "elapsed", "coin", "loot", "lootAH", "xp" }) do
      if r[k] + 1e-6 < prevRun[k] then fail(tag .. " in-progress total went down: " .. k .. " " .. prevRun[k] .. " -> " .. r[k]) end
    end
    if r.id and prevRun.id and r.id ~= prevRun.id then fail(tag .. " run id changed") end
  end
  prevRun = {}
  if r then
    prevRun.uid = ns.RunUID(r)
    for _, k in ipairs({ "elapsed", "coin", "loot", "lootAH", "xp" }) do prevRun[k] = r[k] end
    prevRun.id = r.id
  end
  if r and r.id and r.id >= _G.VulcanRunBookDB.nextId then fail(tag .. " run id >= nextId") end
end
WHERE = {}
local function uidSet()
  local s = {}
  local ns = c.ns
  for i, r in ipairs(_G.VulcanRunBookDB.history) do s[ns.RunUID(r)] = r WHERE[ns.RunUID(r)] = "history#" .. i .. "/" .. #_G.VulcanRunBookDB.history end
  for i, r in ipairs(_G.VulcanRunBookDB.old) do s[ns.RunUID(r)] = r WHERE[ns.RunUID(r)] = "old#" .. i .. "/" .. #_G.VulcanRunBookDB.old end
  if ns.run then s[ns.RunUID(ns.run)] = ns.run WHERE[ns.RunUID(ns.run)] = "run" end
  return s
end

local currentDungeon
local function bossFor()
  local list = BOSSES[c.instance and c.instance.map or 36] or BOSSES[36]
  return list[R(#list)]
end

local charName = "Tavlius"
local charDBs = {}      -- [name] = saved char table of characters not logged in
local function applyCaps(n)
  if os.getenv("SMALLCAP") then n.ns.HISTORY_MAX = 4 n.ns.OLD_MAX = 6 end
end
local function storedRunUIDs(s)
  for name, ch in pairs(charDBs) do
    if type(ch) == "table" and type(ch.run) == "table" then s[c.ns.RunUID(ch.run)] = ch.run end
    if type(ch) == "table" and type(ch.mirror) == "table" then
      for _, k in ipairs({ "history", "old" }) do
        for _, r in ipairs(ch.mirror[k] or {}) do
          local u = c.ns.RunUID(r)
          if not s[u] and not goneUIDs[u] and not (_G.VulcanRunBookDB.deleted[u]) and (r.keepAfterClear or (r.serverEnd or r.serverStart or 0) >= (_G.VulcanRunBookDB.clearedAt or 0)) then s[u] = r WHERE[u] = WHERE[u] or ("mirror of " .. name) end
        end
      end
    end
  end
end
local function relog(gap, dropAccount, newChar)
  local before = uidSet()
  storedRunUIDs(before)
  local inst, dead, group, raid = c.instance, c.dead, c.group, c.raid
  local money, xp, xpMax, bag = c.money, c.xp, c.xpMax, c.bagSlots
  local saved = c.savedCopy(dropAccount)
  if dropAccount then saved.db = nil end
  local name = charName
  if newChar and newChar ~= charName then
    charDBs[charName] = saved.char
    saved.char = charDBs[newChar] or {}
    charDBs[newChar] = nil
    name = newChar
    inst = nil
  end
  charName = name
  local n = H.boot({ name = name, saved = saved, gap = gap })
  applyCaps(n)
  setupItems(n)
  n.instance = inst and copy(inst)
  n.dead, n.group, n.raid, n.money, n.xp, n.xpMax, n.bagSlots = dead, group, raid, money, xp, xpMax, bag
  if newChar then n.dead = false end
  n.login()
  c = n
  errorsSeen = 0
  local after = uidSet()
  storedRunUIDs(after)
  for u, r in pairs(before) do
    if not after[u] then
      -- allowed: an in-progress run that ended at login and wasn't worth keeping
      -- (or one you never went into, made for your partner's new copy)
      if not (r.elapsed < 60 and #r.bosses == 0) and not r.entryOnEntry and not goneUIDs[u] and not (KNOWN and (r.serverEnd or 0) < (_G.VulcanRunBookDB.clearedAt or 0)) then
        -- trimmed past OLD_MAX is allowed too
        if #_G.VulcanRunBookDB.old < c.ns.OLD_MAX then fail("run lost across relog: " .. u .. " was " .. tostring(WHERE[u]) .. " elapsed " .. r.elapsed .. " bosses " .. #r.bosses .. " now hist " .. #_G.VulcanRunBookDB.history .. " old " .. #_G.VulcanRunBookDB.old .. " cleared " .. tostring(_G.VulcanRunBookDB.clearedAt) .. " end " .. tostring(r.serverEnd) .. " keep " .. tostring(r.keepAfterClear)) end
      end
    end
  end
end

local function partnerStart()
  return c.ns.run and c.ns.run.serverStart or (_G.VulcanRunBookDB.history[1] and _G.VulcanRunBookDB.history[1].serverStart) or 0
end

local function from(kind, start, fields, map, name)
  local r = c.ns.run or _G.VulcanRunBookDB.history[1]
  map = map or (r and r.mapID) or 36
  name = name or (r and r.name) or "Deadmines"
  c.addonMsg("Mirel-Realm", string.format("%s3|beef01|%s|%s||%d|%s", kind, tostring(map), name, start, fields))
end

local partnerElapsed = 0
local ops = {
  { 3, "markkey", function()
    _G.VulcanRunBook_MarkBoss()
    if R() < 0.5 then c.tick(R(1, 15)) local b = bossFor() c.fire("BOSS_KILL", b[1], b[2]) return "markkey+BOSS_KILL " .. b[2] end
    return "markkey"
  end },
  { 4, "killpair", function()
    local b = bossFor()
    c.fire("ENCOUNTER_START", c.SECRET, c.SECRET, 1, 5) c.tick(R(5,30))
    c.fire("BOSS_KILL", c.SECRET, c.SECRET)
    c.fire("ENCOUNTER_END", b[1], b[2], 1, 5, 1)
    return "killpair " .. b[2]
  end },
  { 2, "syncBanon", function() from("B", partnerStart() + 3, "0|") return "sync B anon" end },
  { 2, "syncX", function() from("X", c.ns.ServerTime() + R(-120, 120), "") return "sync X" end },
  { 1, "merchant", function()
    c.fire("MERCHANT_SHOW") c.gainMoney(R(1, 999)) c.toBags(101, 2) c.tick(2) c.fire("MERCHANT_CLOSED") c.fire("MERCHANT_CLOSED")
    return "merchant"
  end },
  { 1, "group5", function() c.party("Mirel", "Pug", "Pugtwo", "Pugthree") return "party of 5" end },
  { 1, "raidflag", function() c.raid = not c.raid return "raid flag " .. tostring(c.raid) end },
  { 2, "floor", function()
    if c.instance and c.instance.map == 189 then c.instance.uiMap = 301 + R(4) c.fire("ZONE_CHANGED_NEW_AREA") return "floor change" end
    return "floor noop"
  end },
  { 6, "enter", function()
    local d = DUNGEONS[R(#DUNGEONS)]
    if R() < 0.6 and currentDungeon then d = currentDungeon end
    currentDungeon = d
    local opts = {}
    if d[2] == 189 then opts.uiMap = 301 + R(4) end
    if d[2] == 409 then opts.kind = "raid" end
    if R() < 0.1 then opts.diff = 2 end
    c.enter(d[1], d[2], opts)
    return "enter " .. d[1]
  end },
  { 5, "leave", function() c.leave() return "leave" end },
  { 12, "tick", function() local n = R(1, 120) c.tick(n) return "tick " .. n end },
  { 2, "bigtick", function() local n = R(600, 2400) c.tick(math.floor(n / 10), 10) return "tick10x" .. math.floor(n / 10) end },
  { 4, "encounter", function()
    local b = bossFor()
    local ok = R() < 0.8
    c.encounter(b[1], b[2], ok, R(5, 60))
    return "encounter " .. b[2] .. (ok and " kill" or " fail")
  end },
  { 2, "bosskill", function() local b = bossFor() c.fire("BOSS_KILL", b[1], b[2]) return "BOSS_KILL " .. b[2] end },
  { 3, "die", function() c.die() return "die" end },
  { 2, "revive", function() c.dead = false c.fire("PLAYER_UNGHOST") return "revive" end },
  { 2, "partnerdie", function()
    local m = c.group[1]
    if m then m.dead = not m.dead end
    return "partner dead toggle"
  end },
  { 4, "loot", function()
    local ids = { 100, 101, 103, 104, 105 }
    local id = ids[R(#ids)]
    local q = R(1, 3)
    c.lootReal(id, q, R() < 0.3)
    return "loot " .. id .. "x" .. q
  end },
  { 2, "lootother", function()
    local ids = { 100, 104 }
    c.lootMsg(R() < 0.5 and "Mirel" or "Pug", ids[R(2)])
    return "loot other"
  end },
  { 3, "money", function() c.gainMoney(R(1, 5000)) c.gainXP(R(1, 3000)) return "money/xp" end },
  { 1, "itemload", function() c.cached[105] = true c.fire("ITEM_DATA_LOAD_RESULT", 105, true) return "itemload" end },
  { 2, "reset", function() c.system((currentDungeon and currentDungeon[1] or "Deadmines") .. " has been reset.") return "reset msg" end },
  { 1, "party", function()
    if #c.group > 0 and R() < 0.3 then c.party() return "party off" end
    c.party("Mirel") return "party Mirel"
  end },
  { 3, "syncS", function()
    partnerElapsed = partnerElapsed + R(0, 200)
    from("S", partnerStart() + R(-30, 30), string.format("%d|%d|%d|%d|%d|%d", partnerElapsed, R(0, 9999), 100, 200, R(0, 999), R() < 0.1 and 1 or 0))
    return "sync S"
  end },
  { 2, "syncD", function() from("D", partnerStart() + 3, string.format("%d|%d|%d", ({ 100, 104, 103 })[R(3)], 1, 3)) return "sync D" end },
  { 2, "syncB", function() local b = bossFor() from("B", partnerStart() + 3, b[1] .. "|" .. b[2]) return "sync B " .. b[2] end },
  { 1, "syncN", function() from("N", partnerStart() + 3, "note " .. R(5)) return "sync N" end },
  { 1, "syncR", function() c.addonMsg("Mirel-Realm", "R3|beef01|" .. (currentDungeon and currentDungeon[1] or "Deadmines")) return "sync R" end },
  { 6, "slash", function()
    local cmds = { "end", "start", "new", "new yes", NOANON and "boss Gilnid" or "boss", "boss Sneed", "boss Rhahk'Zor", "unboss", "note hello", "note #1 hi",
      "delete 1", "delete 2", "final", "final auto", "final sneed", "report", "report party", "export", "history", "stats",
      "quality 3", "quality 2", "price ah", "price vendor", "check", "clear yes", "cap", "partner mirel", "partner off", "quiet" }
    local cmd = cmds[R(#cmds)]
    if cmd == "clear yes" and R() < 0.7 then cmd = "stats" end
    if cmd:match("^delete") then
      local h = _G.VulcanRunBookDB.history
      if #h > 0 then cmd = "delete " .. h[R(#h)].id end
    end
    local pre = {}
    for _, r in ipairs(_G.VulcanRunBookDB.history) do pre[c.ns.RunUID(r)] = true end
    if cmd == "clear yes" then for _, r in ipairs(_G.VulcanRunBookDB.old) do pre[c.ns.RunUID(r)] = true end end
    c.slash(cmd)
    if cmd:match("^delete") or cmd == "clear yes" then
      local post = {}
      for _, r in ipairs(_G.VulcanRunBookDB.history) do post[c.ns.RunUID(r)] = true end
      for u in pairs(pre) do if not post[u] then goneUIDs[u] = cmd end end
    end
    return "/runbook " .. cmd
  end },
  { 2, "reload", function() relog(1) return "reload" end },
  { 1, "relog", function() local g = R(60, 7200) relog(g) return "relog gap " .. g end },
  { 1, "relogNoAcct", function() relog(5, true) return "relog, account data lost" end },
  { 2, "alt", function()
    local names = { "Tavlius", "Altone", "Alttwo" }
    local nm = names[R(3)]
    relog(R(5, 4000), false, nm)
    return "switch to " .. nm
  end },
}
local total = 0
for _, o in ipairs(ops) do total = total + o[1] end
local function pick()
  local x = R() * total
  for _, o in ipairs(ops) do
    x = x - o[1]
    if x <= 0 then return o end
  end
  return ops[#ops]
end

for step = 1, STEPS do
  local o = pick()
  local desc = o[3]()
  L(step .. ":" .. desc)
  if os.getenv("WATCH") and step >= tonumber(os.getenv("FROM") or 410) then
    local U = os.getenv("WATCH")
    local inHist = false
    for _, r in ipairs(_G.VulcanRunBookDB.history) do if c.ns.RunUID(r) == U then inHist = true end end
    local m = _G.VulcanRunBookCharDB.mirror
    local inMirror = false
    local inOld = false
    for _, r in ipairs(_G.VulcanRunBookDB.old) do if c.ns.RunUID(r) == U then inOld = true end end
    local inRun = c.ns.run and c.ns.RunUID(c.ns.run) == U
    local kk
    for _, r in ipairs(allRuns(c.ns)) do if c.ns.RunUID(r) == U then kk = r end end
    for _, r in ipairs(_G.VulcanRunBookDB.old) do if c.ns.RunUID(r) == U then kk = r end end
    io.write(string.format("  old=%s run=%s clearedAt=%s keep=%s end=%s\n", tostring(inOld), tostring(inRun), tostring(_G.VulcanRunBookDB.clearedAt), tostring(kk and kk.keepAfterClear), tostring(kk and kk.serverEnd)))
    if m and m.history then for _, r in ipairs(m.history) do if c.ns.RunUID(r) == U then inMirror = true end end end
    P(string.format("  [%s] deleted=%s hist=%s mirrorDeleted=%s inOwnMirror=%s char=%s", desc, tostring(_G.VulcanRunBookDB.deleted[U]), tostring(inHist), tostring(m and m.deleted and m.deleted[U]), tostring(inMirror), charName))
  end
  checkInvariants("step " .. step .. " (" .. desc .. ")")
  monotonic("step " .. step .. " (" .. desc .. ")")
end
P("seed " .. SEED .. " ok, history " .. #_G.VulcanRunBookDB.history)
