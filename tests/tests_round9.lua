-- RunBook tests for the audit round 9 fixes.
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

local function sm(c, plainNames)
  c.mapGroups = { [302] = 50, [303] = 50, [304] = 50, [305] = 50 }
  c.mapNames = { [302] = "Scarlet Monastery", [303] = "Scarlet Monastery", [304] = "Scarlet Monastery",
    [305] = "Scarlet Monastery" }
  if not plainNames then
    c.groupFloors = { [50] = { { mapID = 302, name = "Graveyard" }, { mapID = 303, name = "Library" },
      { mapID = 304, name = "Armory" }, { mapID = 305, name = "Cathedral" } } }
  end
end

local function names(run)
  local t = {}
  for _, b in ipairs(run.bosses) do t[#t + 1] = b.name end
  return table.concat(t, ",")
end

---------------------------------------------------------------------------
H.group("you end your run, your partner's goes on: his numbers go to your new run")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local r1 = c.run()
  local p = r1.serverStart
  c.tick(300)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|300|20000|0|0|100|0", p))
  c.slash("end")
  c.leave()
  c.tick(60)
  c.enter("Deadmines", 36)
  local r2 = c.run()
  check("a new run", r2 ~= r1)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|375|20000|0|0|100|0", p))
  c.tick(300)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|675|90000|0|0|400|0", p))
  eq("old run not inflated", r1.partners.Mirel.coin, 20000)
  eq("new run: his coin since then", r2.partners.Mirel.coin, 70000)
  eq("new run: his XP since then", r2.partners.Mirel.xp, 300)
  c.addonMsg("Mirel", string.format("D3|beef01|36|Deadmines||%d|2001|1|3", p))
  check("his drop lands in the new run", #r2.drops == 1 and #r1.drops == 0)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a nameless kill event, then the fight's end with its name later")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(60)
  c.fire("ENCOUNTER_START", 643, "Sneed", 1, 5)
  c.tick(30)
  c.fire("BOSS_KILL", c.SECRET, c.SECRET)
  c.tick(15)
  c.fire("ENCOUNTER_END", 643, "Sneed", 1, 5, 1)
  eq("one kill, named", names(c.run()), "Sneed")
  -- Hidden at the start too: named at the end.
  c.tick(60)
  c.fire("ENCOUNTER_START", c.SECRET, c.SECRET, 1, 5)
  c.tick(30)
  c.fire("BOSS_KILL", c.SECRET, c.SECRET)
  c.tick(15)
  c.fire("ENCOUNTER_END", 644, "Gilnid", 1, 5, 1)
  eq("two kills", names(c.run()), "Sneed,Gilnid")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("cap entries: /runbook new after re-entering an ended copy; wings revisited")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(200)
  c.slash("end")
  c.leave()
  c.tick(30)
  c.enter("Deadmines", 36)
  eq("same copy", #_G.VulcanRunBookDB.entries, 1)
  c.tick(20)
  c.slash("new yes")
  eq("/runbook new: a new copy", #_G.VulcanRunBookDB.entries, 2)
  -- Graveyard, Library, back to the same Graveyard: two instances.
  local d = fresh()
  sm(d)
  d.enter("Scarlet Monastery", 189, { uiMap = 302 })
  d.tick(300)
  d.leave()
  d.enter("Scarlet Monastery", 189, { uiMap = 303 })
  d.tick(300)
  d.leave()
  d.enter("Scarlet Monastery", 189, { uiMap = 302 })
  d.tick(4)
  eq("back to the graveyard: not a new instance", #_G.VulcanRunBookDB.entries, 2)
  eq("but a new run", d.run().label, "Scarlet Monastery - Graveyard")
  noErrors(c, d)
end

---------------------------------------------------------------------------
H.group("wing unreadable for a moment when coming into another wing")
do
  local c = fresh()
  sm(c)
  c.enter("Scarlet Monastery", 189, { uiMap = 302 })
  local gy = c.run()
  c.tick(300)
  c.leave()
  c.secret.uimap = true
  c.enter("Scarlet Monastery", 189, { uiMap = 303 })
  c.tick(4)
  c.secret.uimap = nil
  c.tick(4)
  check("split", c.run() ~= gy and gy.endReason == "wing")
  eq("library", c.run().label, "Scarlet Monastery - Library")
  noErrors(c)
end

H.group("a reset message right after entering another wing")
do
  local c = fresh()
  sm(c)
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Scarlet Monastery", 189, { uiMap = 302 })
  local gy = c.run()
  c.tick(300)
  c.leave()
  c.tick(20)
  c.enter("Scarlet Monastery", 189, { uiMap = 303 })
  c.addonMsg("Mirel", "R3|beef01|Scarlet Monastery")
  c.tick(6)
  check("new run", c.run() ~= gy)
  eq("its wing is the library", c.run().label, "Scarlet Monastery - Library")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("your partner's reset of a copy you ended (too short to save)")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  c.tick(20)
  c.slash("end")
  c.leave()
  c.addonMsg("Mirel", "R3|beef01|Deadmines")
  c.tick(5)
  c.enter("Deadmines", 36)
  eq("reset copy counts", #_G.VulcanRunBookDB.entries, 2)
  noErrors(c)
end

H.group("/runbook end while the instance can't be read")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(200)
  local saved = _G.GetInstanceInfo
  _G.GetInstanceInfo = function() return c.SECRET end
  c.slash("end")
  _G.GetInstanceInfo = saved
  c.tick(10)
  check("no restart", c.run() == nil)
  eq("one entry", #_G.VulcanRunBookDB.entries, 1)
  noErrors(c)
end

H.group("end, delete, start: still the same copy")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(200)
  c.slash("end")
  local id = c.history()[1].id
  c.slash("delete " .. id .. " yes")
  c.slash("start")
  check("a run", c.run() ~= nil)
  eq("one entry", #_G.VulcanRunBookDB.entries, 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("live text: wipes alone, raid deaths, last run's gold")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36)
  c.tick(70)
  c.ns.AddWipe("Sneed")
  local text = c.strip(table.concat(c.ns.LiveLines(), "\n"))
  check("no dangling separator", text:find("1 wipe\n", 1, true) ~= nil or text:match("1 wipe$") ~= nil, text)
  c.gainMoney(19500)
  c.leave()
  c.system("Deadmines has been reset.")
  c.tick(2)
  text = c.strip(table.concat(c.ns.LiveLines(), "\n"))
  check("under 10g keeps silver", text:find("1g 95s", 1, true) ~= nil, text)
  local r = fresh()
  r.party("Mirel", "A", "B", "C", "D", "E", "F", "G", "H", "I")
  r.raid = true
  r.slash("partner Mirel")
  r.enter("Molten Core", 409, { kind = "raid" })
  r.tick(70)
  for _, n in ipairs({ "A", "B", "C" }) do
    r.member(n).dead = true
    r.tick(2)
    r.member(n).dead = false
    r.tick(2)
  end
  text = r.strip(table.concat(r.ns.LiveLines(), "\n"))
  check("no line for others' deaths", not text:find("deaths", 1, true), text)
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("wing names, short labels, Dire Maul check and hint")
do
  local c = fresh()
  sm(c, true)
  c.enter("Scarlet Monastery", 189, { uiMap = 305 })
  c.tick(4)
  eq("fallback wing name", c.run().label, "Scarlet Monastery - Cathedral")
  eq("utf-8 initials", c.ns.ShortLabel({ label = "Monastère Écarlate - Cimetière" }), "MÉ Cimetière")
  local d = fresh()
  d.enter("Dire Maul", 429, { uiMap = 236 })
  d.slash("check")
  check("dire maul check text", anyPrinted(d, "Dire Maul: wings aren't told apart (by design)"))
  d.tick(100)
  d.leave()
  d.system("Dire Maul has been reset.")
  d.enter("Dire Maul", 429, { uiMap = 236 })
  d.tick(5)
  eq("hint once per session", countPrinted(d, "wings can't be told apart"), 1)
  noErrors(c, d)
end

H.group("a wing switch at the cap says so")
do
  local c = fresh()
  sm(c)
  c.slash("cap 2")
  c.slash("quiet on")
  c.enter("Scarlet Monastery", 189, { uiMap = 302 })
  c.tick(300)
  c.leave()
  c.enter("Scarlet Monastery", 189, { uiMap = 303 })
  c.tick(4)
  check("cap line in quiet mode", anyPrinted(c, "Scarlet Monastery - Library started. That's 2/2"))
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("key press, then its name")
do
  local c = fresh()
  c.enter("Scarlet Monastery", 189)
  c.tick(100)
  _G.VulcanRunBook_MarkBoss()
  c.tick(4)
  c.slash("boss Odo the Blindwatcher")
  eq("one boss, named", names(c.run()), "Odo the Blindwatcher")
  check("told", anyPrinted(c, "Boss 1 is now Odo the Blindwatcher."))
  noErrors(c)
end

H.group("unboss #id")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(60)
  c.encounter(1, "A")
  c.tick(30)
  _G.VulcanRunBook_MarkBoss()
  c.leave()
  c.system("Deadmines has been reset.")
  c.tick(2)
  local id = c.history()[1].id
  c.enter("Deadmines", 36)
  c.tick(30)
  c.slash("unboss #" .. id)
  eq("taken from that run", names(c.history()[1]), "A")
  check("told", anyPrinted(c, "from run #" .. id))
  c.slash("unboss xyz")
  check("usage", anyPrinted(c, "Usage: /runbook unboss"))
  noErrors(c)
end

H.summary("tests_round9.lua")
