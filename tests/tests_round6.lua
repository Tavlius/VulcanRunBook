-- RunBook tests for the audit round 6 fixes.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check, eq = H.check, H.eq

local function fresh(opts)
  local c = H.boot(opts)
  c.login()
  return c
end

local function noErrors(...)
  local all = {}
  for _, c in ipairs({ ... }) do for _, e in ipairs(c.errors()) do all[#all + 1] = e end end
  check("no errors", #all == 0, table.concat(all, "; "))
end

local function anyPrinted(c, text)
  for _, p in ipairs(c.printed) do
    if c.strip(p):find(text, 1, true) then return true end
  end
  return false
end

local function countPrinted(c, text)
  local n = 0
  for _, p in ipairs(c.printed) do if c.strip(p):find(text, 1, true) then n = n + 1 end end
  return n
end

-- One run of Deadmines killing the named bosses, then a reset.
local function dmRun(c, bosses)
  c.enter("Deadmines", 36)
  for i, b in ipairs(bosses) do c.encounter(i, b) c.tick(60) end
  c.leave()
  c.system("Deadmines has been reset.")
  c.tick(2)
end

local function sm(c)
  c.mapGroups = { [302] = 50, [303] = 50, [304] = 50, [305] = 50 }
  c.mapNames = { [302] = "Scarlet Monastery", [303] = "Scarlet Monastery" }
  c.groupFloors = { [50] = { { mapID = 302, name = "Graveyard" }, { mapID = 303, name = "Library" },
    { mapID = 304, name = "Armory" }, { mapID = 305, name = "Cathedral" } } }
end

local function sentKinds(c, kind)
  local out = {}
  for _, m in ipairs(c.addonSent) do
    if m.msg:sub(1, 1) == kind then out[#out + 1] = m.msg end
  end
  return out
end

---------------------------------------------------------------------------
H.group("final boss: farm runs that stop early don't vote")
do
  local c = fresh()
  dmRun(c, { "A", "B", "C", "D", "E" })
  for _ = 1, 3 do dmRun(c, { "A", "B", "C" }) end
  local key = c.ns.RunKey(c.history()[1])
  eq("final is the full clear's last boss", c.ns.FinalBoss(key).name, "E")
  eq("denominator is the full clear", c.ns.BossTotal(key), 5)
  -- An extra (optional) boss killed once after the last doesn't take over
  -- once a second full run ends on the usual boss.
  dmRun(c, { "A", "B", "C", "D", "E", "Extra" })
  dmRun(c, { "A", "B", "C", "D", "E" })
  eq("usual last boss still final", c.ns.FinalBoss(key).name, "E")
  -- Skipping one boss on the way still votes.
  dmRun(c, { "A", "C", "D", "E" })
  eq("a skip still votes for the final", c.ns.FinalBoss(key).name, "E")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a boss kill event with everything hidden still counts")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(60)
  c.fire("BOSS_KILL", c.SECRET, c.SECRET)
  c.fire("ENCOUNTER_END", c.SECRET, c.SECRET, 1, 5, 1)
  eq("one kill", #c.run().bosses, 1)
  eq("unnamed", c.run().bosses[1].name, "Boss 1")
  check("boss events seen", c.ns.DB.bossEventsSeen == true)
  noErrors(c)
end

H.group("a fight start alone isn't a boss event")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.fire("ENCOUNTER_START", 1, "Rhahk'Zor", 1, 5)
  check("not yet", not c.ns.DB.bossEventsSeen)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("the game's kill right after your key press names the mark")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100)
  _G.VulcanRunBook_MarkBoss()
  c.tick(3)
  c.fire("BOSS_KILL", 644, "Rhahk'Zor")
  local run = c.run()
  eq("one kill", #run.bosses, 1)
  eq("named by the game", run.bosses[1].name, "Rhahk'Zor")
  check("now the game's kill", not run.bosses[1].manual and run.bosses[1].id == 644)
  -- A named mark gets the game's id (the event only had the id).
  c.tick(100)
  c.slash("boss Sneed")
  c.tick(2)
  c.fire("BOSS_KILL", 643, c.SECRET)
  eq("still two kills", #run.bosses, 2)
  eq("id added to the mark", run.bosses[2].id, 643)
  eq("keeps your name", run.bosses[2].name, "Sneed")
  noErrors(c)
end

H.group("unnamed marks never repeat a number")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  local run = c.run()
  run.bosses[1] = { name = "Boss 3", anonymous = true, manual = true, t = 1, v = 1 }
  c.tick(30)
  _G.VulcanRunBook_MarkBoss()
  eq("next is Boss 4", run.bosses[2].name, "Boss 4")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("unnamed marks sync, and a press after your partner's is the same kill")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(100)
  _G.VulcanRunBook_MarkBoss()
  c.tick(31)
  local bs = sentKinds(c, "B")
  check("your unnamed mark was sent", #bs >= 1 and bs[#bs]:find("|0|%d+|%d+|$") ~= nil, bs[#bs])
  -- His unnamed mark of the next boss; your press 15s later is the same kill.
  c.tick(100)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|0|", run.serverStart))
  eq("his mark added", #run.bosses, 2)
  check("said it came from him", anyPrinted(c, "(from your partner)"))
  c.tick(15)
  _G.VulcanRunBook_MarkBoss()
  eq("your press is the same kill", #run.bosses, 2)
  check("no second line for his mark", not anyPrinted(c, "was just recorded"))
  -- Named: /runbook boss after his named kill (a minute later, so it isn't
  -- taken as the name of his unnamed mark).
  c.tick(70)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|0|Smite", run.serverStart))
  c.tick(5)
  c.slash("boss Smite")
  eq("no duplicate", #run.bosses, 3)
  check("no /runbook new advice", not anyPrinted(c, "type /runbook new"))
  check("told he marked it", countPrinted(c, "Smite was already marked by your partner") == 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("/runbook new starts your partner's run over too")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local old = c.run()
  c.tick(300)
  c.slash("new yes")
  c.tick(31)
  eq("X sent", #sentKinds(c, "X"), 1)
  -- Receiving his: your run (older than his new one) starts over.
  c.tick(300)
  local mine = c.run()
  local start = c.ns.ServerTime()
  c.addonMsg("Mirel", string.format("X3|beef01|36|Deadmines||%d", start))
  check("started over", c.run() ~= mine and mine.endReason == "new")
  check("told why", anyPrinted(c, "Mirel started a new run here"))
  eq("no echo back", #sentKinds(c, "X"), 1)
  -- A second copy of it (or his, right after yours) changes nothing.
  local now = c.run()
  c.addonMsg("Mirel", string.format("X3|beef01|36|Deadmines||%d", start))
  check("same run", c.run() == now)
  -- Another dungeon's: ignored.
  c.tick(120)
  c.addonMsg("Mirel", string.format("X3|beef01|43|Wailing Caverns||%d", c.ns.ServerTime()))
  check("other dungeon ignored", c.run() == now)
  check("old run kept", old.endReason == "new")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("back into the copy you ended: new run, no new cap entry")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(200)
  c.slash("end")
  c.leave()
  c.tick(60)
  local entries = #_G.VulcanRunBookDB.entries
  c.enter("Deadmines", 36)
  check("a new run", c.run() ~= nil)
  eq("no new entry", #_G.VulcanRunBookDB.entries, entries)
  -- After a reset it's a new copy.
  c.slash("end")
  c.leave()
  c.system("Deadmines has been reset.")
  c.enter("Deadmines", 36)
  eq("reset copy counts", #_G.VulcanRunBookDB.entries, entries + 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a fight that began with no run: deaths at the end decide")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36)
  c.tick(100)
  c.slash("end")
  c.fire("ENCOUNTER_START", 1, "Rhahk'Zor", 1, 5)
  c.slash("start")
  c.tick(5)
  c.member("Mirel").dead = true
  c.dead = true
  c.fire("PLAYER_DEAD")
  c.tick(2)
  c.fire("ENCOUNTER_END", 1, "Rhahk'Zor", 1, 5, 0)
  c.tick(6)
  check("wipe recorded", #c.run().wipes >= 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("map data that throws doesn't break a run")
do
  local c = fresh()
  sm(c)
  _G.C_Map.GetBestMapForUnit = function() error("forbidden table") end
  c.enter("Scarlet Monastery", 189, { uiMap = 302 })
  check("run started", c.run() ~= nil)
  noErrors(c)
end

H.group("a run started without a loading screen takes its wing from the map")
do
  local c = H.boot()
  sm(c)
  c.instance = { name = "Scarlet Monastery", map = 189, diff = 1, kind = "party", uiMap = 302 }
  c.login()
  local run = c.run()
  c.tick(4)
  eq("wing read at login", run.label, "Scarlet Monastery - Graveyard")
  c.tick(100)
  c.leave()
  c.enter("Scarlet Monastery", 189, { uiMap = 303 })
  c.tick(4)
  check("another wing: a new run", c.run() ~= run and run.endReason == "wing")
  eq("new run's wing", c.run().label, "Scarlet Monastery - Library")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("display text")
do
  local c = fresh()
  eq("short label", c.ns.ShortLabel({ label = "Scarlet Monastery - Cathedral" }), "SM Cathedral")
  eq("plain label", c.ns.ShortLabel({ label = "Deadmines" }), "Deadmines")
  eq("dire maul", c.ns.ShortLabel({ label = "Dire Maul - Warpwood Quarter" }), "DM Warpwood Quarter")
  c.party("Mirelthelongnamed")
  c.enter("Deadmines", 36)
  c.tick(70)
  c.member("Mirelthelongnamed").dead = true
  c.tick(2)
  c.slash("show")
  local text = c.liveText()
  check("a long name that fits is shown whole", text:find("1 death (Mirelthelongnamed)", 1, true) ~= nil, text)
  c.gainMoney(123456)
  c.leave()
  c.system("Deadmines has been reset.")
  c.tick(2)
  text = c.strip(table.concat(c.ns.LiveLines(), "\n"))
  check("last line whole gold", text:find("12g", 1, true) ~= nil and not text:find("34s", 1, true), text)
  c.clearPrinted()
  c.slash("clear")
  check("one run: its stats", anyPrinted(c, "your 1 saved run and its stats."))
  c.slash("debug clear")
  check("plural entries", anyPrinted(c, "0 entries") or anyPrinted(c, "1 entry"))
  noErrors(c)
end

H.group("cap message wording")
do
  local c = fresh()
  c.slash("cap 1")
  c.enter("Deadmines", 36)
  c.tick(70)
  c.leave()
  c.system("Deadmines has been reset.")
  c.system("You have entered too many instances recently.")
  check("under the cap again", anyPrinted(c, "you're under the cap again in"))
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("drops with unknown quality ask the client to load the item")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.item(5000, "Mystery", 3, 100, false)
  c.enter("Deadmines", 36)
  local before = #c.loadRequests
  c.addonMsg("Mirel", string.format("D3|beef01|36|Deadmines||%d|5000|1|-1", c.run().serverStart))
  check("load requested", #c.loadRequests > before)
  noErrors(c)
end

H.group("who's with you is noted on coming back in")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(60)
  c.leave()
  c.group = { { name = "Mirel", dead = false, feign = false } }  -- joined while outside, no roster event
  c.enter("Deadmines", 36)
  local found = false
  for _, n in ipairs(c.run().members) do if n == "Mirel" then found = true end end
  check("Mirel in members", found)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("saved data: one copy per run")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(120)
  local s = c.savedCopy(false)
  -- A stale saved copy of the run in progress (e.g. one you reopened).
  local copy = {}
  for k, v in pairs(s.char.run) do copy[k] = v end
  copy.id = 99
  table.insert(s.db.history, 1, copy)
  local r = H.boot({ saved = s })
  r.login()
  eq("not in history twice", #r.history(), 0)
  r.leave()
  r.system("Deadmines has been reset.")
  r.tick(2)
  eq("saved once", #r.history(), 1)
  noErrors(r)
end

H.summary("tests_round6.lua")
