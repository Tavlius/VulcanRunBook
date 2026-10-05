-- RunBook tests for the audit round 7 fixes.
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

local function reset(c, name)
  c.leave()
  c.system((name or "Deadmines") .. " has been reset.")
  c.tick(2)
end

---------------------------------------------------------------------------
H.group("final boss: reported and hand-marked kills of one boss vote together")
do
  local c = fresh()
  local function run(last)
    c.enter("Deadmines", 36)
    for i = 1, 4 do c.encounter(i, "B" .. i) c.tick(30) end
    if last == "game" then
      c.encounter(9, "VanCleef")
    elseif last == "mark" then
      c.tick(15)
      c.slash("boss VanCleef")
    else
      c.encounter(8, "Gilnid")
    end
    c.tick(30)
    reset(c)
  end
  run("game") run("game") run("mark") run("mark") run("gilnid") run("gilnid") run("gilnid")
  local key = c.ns.RunKey(c.history()[1])
  eq("VanCleef is final", c.ns.FinalBoss(key).name, "VanCleef")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a kill your partner's sync recorded first still catches a reset")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(100)
  B(c, run, 644, "Rhahk'Zor")
  c.encounter(644, "Rhahk'Zor", true, 1)
  eq("one kill", #run.bosses, 1)
  c.tick(60)
  c.leave()
  c.tick(60)
  c.enter("Deadmines", 36)
  c.tick(100)
  c.encounter(644, "Rhahk'Zor")
  check("split", c.run() ~= run and #c.run().bosses == 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("two bosses close together, marked by both of you")
do
  local c = fresh()
  duo(c)
  c.enter("Scarlet Monastery", 189)
  local run = c.run()
  local function KB(id, name)
    c.addonMsg("Mirel", string.format("B3|beef01|189|Scarlet Monastery||%d|%d|%s", run.serverStart, id or 0,
      name or ""))
  end
  c.tick(100)
  KB() c.tick(3) _G.VulcanRunBook_MarkBoss()           -- Mograine: his, then yours
  c.tick(27)
  _G.VulcanRunBook_MarkBoss() c.tick(2) KB()          -- Whitemane: yours, then his
  eq("two bosses", #run.bosses, 2)
  -- Each of you marks one boss, half a minute apart: two.
  c.tick(100)
  _G.VulcanRunBook_MarkBoss()
  c.tick(30)
  KB(nil, "Fairbanks")
  eq("four bosses", #run.bosses, 4)
  eq("your mark keeps its number", run.bosses[3].name, "Boss 3")
  -- His two marks 25s apart, you pressed for neither: two.
  c.tick(100)
  KB() c.tick(25) KB()
  eq("six bosses", #run.bosses, 6)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("the copy you ended: other wing, long logout, ended outside")
do
  local c = fresh()
  sm(c)
  c.enter("Scarlet Monastery", 189, { uiMap = 303 })
  c.tick(200)
  c.slash("end")
  c.leave()
  local n = #_G.VulcanRunBookDB.entries
  c.enter("Scarlet Monastery", 189, { uiMap = 304 })
  eq("another wing is another instance", #_G.VulcanRunBookDB.entries, n + 1)
  -- Ended inside, logged out inside, back 3 hours later outside.
  local d = fresh()
  d.enter("Deadmines", 36)
  d.tick(200)
  d.slash("end")
  local s = d.savedCopy(false)
  local r = H.boot({ saved = s, gap = 3 * 3600 })
  r.instance = nil
  r.login()
  r.tick(5)
  local m = #_G.VulcanRunBookDB.entries
  r.enter("Deadmines", 36)
  eq("hours later: a new instance", #_G.VulcanRunBookDB.entries, m + 1)
  -- Ended outside (repair trip), back into the same copy.
  local e = fresh()
  e.enter("Deadmines", 36)
  e.tick(200)
  e.leave()
  e.slash("end")
  local k = #_G.VulcanRunBookDB.entries
  e.tick(60)
  e.enter("Deadmines", 36)
  check("a new run", e.run() ~= nil)
  eq("same copy: no new entry", #_G.VulcanRunBookDB.entries, k)
  noErrors(c, r, e)
end

---------------------------------------------------------------------------
H.group("your partner's /runbook new: wing, difficulty, and you outside")
do
  local c = fresh()
  sm(c)
  duo(c)
  c.enter("Scarlet Monastery", 189, { uiMap = 305 })
  c.tick(4)
  local cath = c.run()
  c.tick(300)
  local now = c.ns.ServerTime()
  c.addonMsg("Mirel", string.format("X3|beef01|189|Scarlet Monastery|m303|%d|1", now))
  check("another wing's: ignored", c.run() == cath)
  c.addonMsg("Mirel", string.format("X3|beef01|189|Scarlet Monastery|m305|%d|2", now))
  check("another difficulty's: ignored", c.run() == cath)
  c.leave()
  c.addonMsg("Mirel", string.format("X3|beef01|189|Scarlet Monastery|m305|%d|1", now + 20))
  check("outside: run ended", cath.endReason == "new" and c.run() ~= cath and not c.ns.inside)
  c.enter("Scarlet Monastery", 189, { uiMap = 305 })
  check("back in: a new run", c.run() ~= nil and c.run() ~= cath)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("/runbook new right after coming into another wing")
do
  local c = fresh()
  sm(c)
  c.enter("Scarlet Monastery", 189, { uiMap = 303 })
  c.tick(200)
  c.leave()
  c.enter("Scarlet Monastery", 189, { uiMap = 305 })
  c.tick(1)
  c.slash("new yes")
  c.tick(4)
  eq("new run is the Cathedral", c.run().label, "Scarlet Monastery - Cathedral")
  check("no false wing hint", not anyPrinted(c, "can't be told apart"))
  -- And /runbook new deep inside keeps the wing, with no hint either.
  c.tick(100)
  c.slash("new yes")
  eq("keeps the wing", c.run().label, "Scarlet Monastery - Cathedral")
  check("start line names the wing", anyPrinted(c, "Scarlet Monastery - Cathedral started"))
  check("still no false hint", not anyPrinted(c, "can't be told apart"))
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a key press just before a repeat kill isn't a second boss")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(100)
  c.encounter(644, "Rhahk'Zor")
  c.tick(60)
  c.leave()
  c.tick(60)
  c.enter("Deadmines", 36)
  c.tick(100)
  _G.VulcanRunBook_MarkBoss()
  c.tick(2)
  c.fire("BOSS_KILL", 644, "Rhahk'Zor")
  check("split", c.run() ~= run)
  eq("one kill in the new run", #c.run().bosses, 1)
  eq("it's the game's", c.run().bosses[1].name, "Rhahk'Zor")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("your own death in a raid when unit comparison is hidden")
do
  local c = fresh()
  c.party("Mirel", "A", "B", "C", "D", "E", "F", "G", "H", "I")
  c.raid = true
  local orig = _G.UnitIsUnit
  _G.UnitIsUnit = function(a, b)
    if a ~= "player" and b == "player" then return c.SECRET end
    return orig(a, b)
  end
  c.enter("Molten Core", 409, { kind = "raid" })
  c.tick(100)
  c.die()
  c.tick(3)
  eq("one death", #c.run().deaths, 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("raid rows before the final boss is known")
do
  local c = fresh()
  c.party("Mirel", "A", "B", "C", "D", "E", "F", "G", "H", "I")
  c.raid = true
  c.enter("Molten Core", 409, { kind = "raid" })
  for i = 1, 7 do c.encounter(i, "Boss" .. i) c.tick(60) end
  reset(c, "Molten Core")
  local row = c.strip(c.ns.RunRowText(c.history()[1]))
  check("7 bosses, not 7/7", row:find("7 bosses", 1, true) ~= nil and not row:find("7/7", 1, true), row)
  for _, l in ipairs(c.ns.DungeonLines()) do
    local t = c.strip(type(l) == "table" and l[1] or l)
    check("dungeon line fits", #t <= 96, t)
  end
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("unboss says your partner's log keeps it")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  c.tick(100)
  _G.VulcanRunBook_MarkBoss()
  c.slash("unboss")
  check("mentions partner", anyPrinted(c, "Your partner's log keeps it"))
  noErrors(c)
end

H.summary("tests_round7.lua")
