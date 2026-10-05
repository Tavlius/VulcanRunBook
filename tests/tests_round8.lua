-- RunBook tests for the audit round 8 fixes.
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

local function sm(c)
  c.mapGroups = { [302] = 50, [303] = 50, [304] = 50, [305] = 50 }
  c.mapNames = { [302] = "Scarlet Monastery", [303] = "Scarlet Monastery" }
  c.groupFloors = { [50] = { { mapID = 302, name = "Graveyard" }, { mapID = 303, name = "Library" },
    { mapID = 304, name = "Armory" }, { mapID = 305, name = "Cathedral" } } }
end

local function duo(c)
  c.party("Mirel")
  c.slash("partner Mirel")
end

local function B(c, run, id, name)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|%d|%s", run.serverStart, id or 0, name or ""))
end

local function names(run)
  local t = {}
  for _, b in ipairs(run.bosses) do t[#t + 1] = b.name end
  return table.concat(t, ",")
end

---------------------------------------------------------------------------
H.group("a boss your partner killed while you were outside, killed again after a reset")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(60)
  c.leave()                                   -- corpse run
  B(c, run, 644, "Rhahk'Zor")                 -- he kills it meanwhile
  c.tick(30)
  c.enter("Deadmines", 36)
  c.tick(30)
  c.encounter(643, "Sneed")
  c.tick(30)
  c.leave()
  c.tick(60)
  c.enter("Deadmines", 36)                    -- reset by someone without RunBook
  c.tick(60)
  c.encounter(644, "Rhahk'Zor")
  check("split at the re-kill", c.run() ~= run)
  eq("new run has it", names(c.run()), "Rhahk'Zor")
  noErrors(c)
end

H.group("a nameless report just before a repeat kill isn't a second boss")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(60)
  c.encounter(644, "Rhahk'Zor")
  c.tick(60)
  c.leave()
  c.tick(60)
  c.enter("Deadmines", 36)
  c.tick(60)
  c.fire("BOSS_KILL", c.SECRET, c.SECRET)
  c.fire("ENCOUNTER_END", 644, "Rhahk'Zor", 1, 5, 1)
  check("split", c.run() ~= run)
  eq("one kill", names(c.run()), "Rhahk'Zor")
  noErrors(c)
end

H.group("a hand mark from before your trip out, reported again by the game")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(60)
  c.slash("boss Rhahk'Zor")
  c.tick(60)
  c.leave()
  c.tick(60)
  c.enter("Deadmines", 36)
  c.tick(60)
  c.encounter(644, "Rhahk'Zor")
  check("reset found", c.run() ~= run)
  noErrors(c)
end

H.group("your mark of a boss your partner marked before the reset")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(60)
  B(c, run, 0, "Sneed")
  c.tick(60)
  c.leave()
  c.tick(60)
  c.enter("Deadmines", 36)
  c.tick(60)
  c.slash("boss Sneed")
  check("reset found", c.run() ~= run)
  eq("new run has it", names(c.run()), "Sneed")
  noErrors(c)
end

H.group("naming your partner's unnamed mark says so")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(60)
  B(c, run)
  c.tick(8)
  c.slash("boss Edwin VanCleef")
  eq("renamed", names(run), "Edwin VanCleef")
  check("told", anyPrinted(c, "Boss 1 is now Edwin VanCleef."))
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("your partner's numbers: his two runs during yours add up")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(1500)
  local s0 = run.serverStart
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|1450|90000|0|0|0|1", s0))
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|40|500|0|0|0|0", s0 + 1400))
  eq("both of his runs in yours", run.partners.Mirel.elapsed, 1490)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|1450|90000|0|0|0|1", s0))
  eq("a repeated message changes nothing", run.partners.Mirel.elapsed, 1490)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("logging in after an alt played: your own logout time")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(200)
  c.slash("end")
  local s = c.savedCopy(false)
  -- An alt plays for 40 minutes and logs out (account data saved later).
  s.db.savedAt = s.db.savedAt + 2400
  local r = H.boot({ saved = s, gap = 2520 })
  r.instance = nil
  r.login()
  r.tick(5)
  local n = #_G.VulcanRunBookDB.entries
  r.enter("Deadmines", 36)
  eq("42 minutes later: a new instance", #_G.VulcanRunBookDB.entries, n + 1)
  noErrors(r)
end

H.group("portal from another instance into a Scarlet Monastery wing")
do
  local c = fresh()
  sm(c)
  c.enter("Deadmines", 36)
  c.tick(100)
  c.instance = { name = "Scarlet Monastery", map = 189, diff = 1, kind = "party", uiMap = 303 }
  c.tick(6)
  eq("wing taken", c.run().label, "Scarlet Monastery - Library")
  noErrors(c)
end

H.group("Dire Maul: one hint, no wing")
do
  local c = fresh()
  c.enter("Dire Maul", 429, { uiMap = 236 })
  c.tick(4)
  eq("no wing", c.run().label, "Dire Maul")
  check("hint", anyPrinted(c, "wings can't be told apart"))
  noErrors(c)
end

H.group("vote buckets: two ids with one placeholder name stay apart")
do
  local c = fresh()
  local function run(lastId)
    c.enter("Deadmines", 36)
    for i = 1, 3 do c.fire("BOSS_KILL", i, c.SECRET) c.tick(30) end
    c.fire("BOSS_KILL", lastId, c.SECRET)
    c.tick(30)
    c.leave()
    c.system("Deadmines has been reset.")
    c.tick(2)
  end
  run(4) run(4) run(9)
  local key = c.ns.RunKey(c.history()[1])
  eq("final is id 4", c.ns.FinalBoss(key).id, 4)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("settings take on/off")
do
  local c = fresh()
  c.slash("sync on")
  check("sync stays on", c.ns.DB.sync == true)
  c.slash("quiet off")
  check("quiet stays off", not c.ns.DB.quiet)
  c.slash("auto on")
  check("auto stays on", c.ns.DB.autoShow == true)
  c.slash("sync")
  check("bare shows, doesn't flip", c.ns.DB.sync == true and anyPrinted(c, "Duo sync: on. /runbook sync off"))
  c.slash("sync maybe")
  check("usage shown", anyPrinted(c, "Usage: /runbook sync on or off"))
  noErrors(c)
end

H.group("/runbook new right after the run started counts once")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(5)
  c.slash("new yes")
  eq("one entry", #_G.VulcanRunBookDB.entries, 1)
  c.tick(300)
  c.encounter(1, "A")
  c.slash("new yes")
  eq("a real restart counts", #_G.VulcanRunBookDB.entries, 2)
  noErrors(c)
end

H.group("unboss partner note only with him in the group")
do
  local c = fresh()
  c.slash("partner Mirel")
  c.party("Pug")
  c.enter("Deadmines", 36)
  c.tick(60)
  _G.VulcanRunBook_MarkBoss()
  c.slash("unboss")
  check("no note without him", not anyPrinted(c, "partner's log keeps it"))
  noErrors(c)
end

H.group("deaths line and history rows fit")
do
  local c = fresh()
  c.party("Bigtankguy", "Healzforyou", "Shadowstepz", "Mirel")
  c.slash("partner Mirel")
  c.enter("Lower Blackrock Spire", 229)
  c.tick(70)
  for _ = 1, 3 do
    for _, n in ipairs({ "Bigtankguy", "Healzforyou", "Shadowstepz" }) do
      c.member(n).dead = true
      c.tick(2)
      c.member(n).dead = false
      c.tick(2)
    end
  end
  c.slash("show")
  for _, l in ipairs(c.ns.LiveLines()) do
    local t = c.strip(l)
    check("live line fits", #t <= 49, t)
  end
  c.gainMoney(476200)
  c.slash("note big pull at the start")
  c.leave()
  c.system("Lower Blackrock Spire has been reset.")
  c.tick(2)
  local row = c.strip(c.ns.RunRowText(c.history()[1]))
  check("row fits", #row <= 96, row)
  check("whole gold", row:find("48g", 1, true) ~= nil and not row:find("62s", 1, true), row)
  noErrors(c)
end

H.summary("tests_round8.lua")
