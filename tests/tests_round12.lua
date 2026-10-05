-- RunBook tests for the audit round 12 fixes.
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

local function names(run)
  local t = {}
  for _, b in ipairs(run.bosses) do t[#t + 1] = b.name end
  return table.concat(t, ",")
end

local function duo(c)
  c.party("Mirel")
  c.slash("partner Mirel")
end

local function S(c, start, el, coin, final, map, dungeon)
  c.addonMsg("Mirel", string.format("S3|beef01|%s|%s||%d|%d|%d|0|0|0|%d", map or 36, dungeon or "Deadmines", start,
    el, coin, final and 1 or 0))
end

---------------------------------------------------------------------------
H.group("a partner who joins hours into your raid still syncs")
do
  local c = fresh()
  duo(c)
  c.enter("Molten Core", 409, { kind = "raid" })
  local run = c.run()
  c.tick(2 * 3600 + 300, 10)
  local his = c.ns.ServerTime()
  S(c, his, 0, 0, false, 409, "Molten Core")
  c.tick(60)
  S(c, his, 60, 5000, false, 409, "Molten Core")
  c.addonMsg("Mirel", string.format("B3|beef01|409|Molten Core||%d|k.1|0|Magmadar", his))
  eq("his gold", run.partners.Mirel and run.partners.Mirel.coin, 5000)
  eq("his kill", names(run), "Magmadar")
  c.addonMsg("Mirel", string.format("N3|beef01|409|Molten Core||%d|1|tank swap at 50%%", his))
  eq("his note", #run.notes, 1)
  noErrors(c)
end

H.group("a partner's note on an earlier run goes there")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local first = c.run()
  c.tick(200)
  c.leave()
  c.system("Deadmines has been reset.")
  c.tick(5)
  c.enter("Deadmines", 36)
  local second = c.run()
  c.addonMsg("Mirel", string.format("N3|beef01|36|Deadmines||%d|0|that pull was rough", first.serverStart + 10))
  eq("on the earlier run", #first.notes, 1)
  eq("not this one", #second.notes, 0)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("end, start, then a repeat kill still shows the reset")
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
  c.tick(30)
  c.slash("end")
  c.slash("start")
  check("reopened", c.run() == run)
  c.tick(30)
  c.encounter(644, "Rhahk'Zor")
  check("split", c.run() ~= run and names(c.run()) == "Rhahk'Zor")
  noErrors(c)
end

H.group("a reopened run doesn't take what your partner made while it was ended")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  local p = run.serverStart
  c.tick(100)
  S(c, p, 100, 1000)
  c.slash("end")
  c.tick(30)
  S(c, p, 130, 6000)
  c.tick(30)
  c.slash("start")
  c.tick(10)
  S(c, p, 170, 6100)
  eq("1000 before, 100 after", run.partners.Mirel.coin, 1100)
  noErrors(c)
end

H.group("after a reload, a new run still knows where his run stood")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local p = c.run().serverStart
  c.tick(100)
  S(c, p, 100, 1000)
  c.slash("end")
  S(c, p, 120, 6000)                               -- he loots while you have no run
  c.leave()
  local r = H.boot({ saved = c.savedCopy(false) })
  r.party("Mirel")
  r.login()
  r.enter("Deadmines", 36)
  r.tick(10)
  r.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|200|6010|0|0|0|0", p))
  eq("only since your new run", r.run().partners.Mirel.coin, 10)
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("your partner's kills while you're outside don't make a best time")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  c.tick(300) c.encounter(1, "A") c.tick(600) c.encounter(2, "B")
  c.leave()
  c.system("Deadmines has been reset.")
  c.tick(5)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(100)
  c.encounter(1, "A")
  c.leave()                                         -- repair trip
  c.tick(600)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.5|2|B", run.serverStart))
  check("no 'vs best' for it", not anyPrinted(c, "B down at 1:40 ("))
  c.enter("Deadmines", 36)
  c.tick(10)
  c.leave()
  c.system("Deadmines has been reset.")
  c.tick(5)
  check("no new best", not anyPrinted(c, "New best clear"))
  local key = c.ns.RunKey(run)
  local _, bestT = c.ns.BestRun(key)
  eq("best is the real clear", bestT, 960)
  noErrors(c)
end

H.group("a new copy found by your partner: his gold goes with it, and the entry says so")
do
  local c = fresh()
  duo(c)
  c.slash("cap 2")
  c.enter("Deadmines", 36)
  local old = c.run()
  local p1 = old.serverStart
  c.tick(60)
  c.encounter(644, "Rhahk'Zor")
  c.tick(30)
  c.leave()
  c.tick(120)
  local p2 = c.ns.ServerTime()
  S(c, p2, 0, 0)
  c.tick(10)
  S(c, p2, 10, 300)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.9|644|Rhahk'Zor", p2))
  local new = c.run()
  check("new run", new ~= old)
  eq("his new-copy gold in the new run", new.partners.Mirel and new.partners.Mirel.coin, 300)
  check("old run keeps none of it", not (old.partners.Mirel and old.partners.Mirel.coin > 0))
  local _ = p1
  c.enter("Deadmines", 36)
  check("start line with the cap", anyPrinted(c, "Deadmines started. That's 2/2"))
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("money under 1g reads as silver everywhere")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(70)
  c.gainMoney(6500)
  c.leave()
  c.system("Deadmines has been reset.")
  c.tick(2)
  check("chat summary", anyPrinted(c, "65 silver"))
  local row = c.strip(c.ns.RunRowText(c.history()[1]))
  check("history row", row:find("65 silver", 1, true) ~= nil, row)
  noErrors(c)
end

H.group("saved runs don't keep the partner snapshot")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  c.tick(100)
  c.leave()
  c.system("Deadmines has been reset.")
  c.tick(2)
  eq("cleared at the end", c.history()[1].startTotals, nil)
  noErrors(c)
end

H.summary("tests_round12.lua")
