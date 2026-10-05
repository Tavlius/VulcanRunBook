-- RunBook tests for the audit round 11 fixes.
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

local function S(c, start, el, coin, final)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|%d|%d|0|0|0|%d", start, el, coin, final and 1 or 0))
end

---------------------------------------------------------------------------
H.group("your partner starts over: his old run's numbers stay in yours")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  local p1 = run.serverStart
  c.tick(200)
  S(c, p1, 200, 5000)
  S(c, p1, 200, 5000, true)                       -- his old run's final word
  S(c, p1 + 200, 0, 0)                            -- his new run
  c.addonMsg("Mirel", string.format("X3|beef01|36|Deadmines||%d|1", p1 + 200))
  eq("your old run keeps his 5000", run.partners.Mirel.coin, 5000)
  local new = c.run()
  check("you started over", new ~= run)
  c.tick(60)
  S(c, p1 + 200, 60, 700)
  eq("your new run: his new run", new.partners.Mirel.coin, 700)
  eq("old run unchanged", run.partners.Mirel.coin, 5000)
  noErrors(c)
end

H.group("/runbook new soon after your partner came in")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local first = c.run()
  local p = first.serverStart + 20                 -- he came in 20s after you
  c.tick(50)
  S(c, p, 30, 0)
  c.slash("new yes")                                    -- he ignores it (his run is too new)
  local new = c.run()
  c.tick(30)
  S(c, p, 60, 4000)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.1|644|Rhahk'Zor", p))
  eq("his numbers in your new run", new.partners.Mirel.coin, 4000)
  eq("his kill too", names(new), "Rhahk'Zor")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("your partner's kill in a new copy while you're outside")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local old = c.run()
  c.tick(60)
  c.encounter(644, "Rhahk'Zor")
  c.tick(60)
  c.leave()
  c.tick(120)
  -- (Reset nobody saw.) He goes in first and kills it again.
  local hisStart = c.ns.ServerTime()
  c.tick(60)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.9|644|Rhahk'Zor", hisStart))
  check("your old run ended", old.ended and old.endReason == "reset")
  local new = c.run()
  check("a new run holds his kill", new and new ~= old and names(new) == "Rhahk'Zor")
  local n = #_G.VulcanRunBookDB.entries
  c.enter("Deadmines", 36)
  check("same run when you go in", c.run() == new)
  eq("counted when you go in", #_G.VulcanRunBookDB.entries, n + 1)
  noErrors(c)
end

H.group("a run that ends at login ends when you left it")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(300)
  c.leave()
  local leftAt = c.run().leftAt
  local s = c.savedCopy(false)
  local r = H.boot({ saved = s, gap = 3000 })
  r.login()
  local h = _G.VulcanRunBookDB.history[1]
  eq("ended at leaving", h and h.endedAt, leftAt)
  noErrors(r)
end

---------------------------------------------------------------------------
H.group("a named mark that reveals a reset, after your partner's press")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(60)
  c.slash("boss Rhahk'Zor")
  c.tick(60)
  c.leave()
  c.tick(60)
  c.enter("Deadmines", 36)
  c.tick(60)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.2|0|", run.serverStart))
  c.tick(15)
  c.slash("boss Rhahk'Zor")
  check("split", c.run() ~= run)
  eq("one kill, named", names(c.run()), "Rhahk'Zor")
  noErrors(c)
end

H.group("unnamed kills are numbered within their run after a split")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(60)
  c.slash("boss Sneed")
  c.tick(60)
  c.leave()
  c.tick(60)
  c.enter("Deadmines", 36)
  c.tick(30)
  _G.VulcanRunBook_MarkBoss()
  c.tick(30)
  c.slash("boss Sneed")                              -- the reset shows here
  check("split", c.run() ~= run)
  eq("renumbered", names(c.run()), "Boss 1,Sneed")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("the naming tip and its window")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(60)
  c.slash("boss")
  c.tick(6)
  c.slash("boss")
  check("tip", anyPrinted(c, "To name it, type /runbook boss <name> within 10 seconds."))
  c.tick(8)                                          -- 14s after the kill, 8s after the tip
  c.slash("boss Rhahk'Zor")
  eq("named", names(c.run()), "Rhahk'Zor")
  c.tick(60)
  c.slash("boss Sneed")
  c.tick(2)
  c.clearPrinted()
  c.slash("boss")
  check("no tip for a named kill", not anyPrinted(c, "To name it"))
  -- A press, then another boss named 30s later: two bosses.
  c.tick(60)
  _G.VulcanRunBook_MarkBoss()
  c.tick(30)
  c.slash("boss Gilnid")
  eq("two more", names(c.run()), "Rhahk'Zor,Sneed,Boss 3,Gilnid")
  noErrors(c)
end

H.group("cap message below the cap, and the Last line")
do
  local c = fresh()
  c.enter("Ragefire Chasm", 389)
  c.tick(100)
  c.gainMoney(500)
  c.leave()
  c.system("Ragefire Chasm has been reset.")
  c.system("You have entered too many instances recently.")
  check("can't tell when", anyPrinted(c, "so it can't tell when a slot frees up"))
  local text = c.strip(table.concat(c.ns.LiveLines(), "\n"))
  check("5 silver", text:find("5 silver", 1, true) ~= nil, text)
  noErrors(c)
end

H.group("a stale map on the way back into a wing you left")
do
  local c = fresh()
  c.mapGroups = { [302] = 50, [303] = 50, [304] = 50, [305] = 50 }
  c.mapNames = { [1420] = "Tirisfal Glades" }
  c.enter("Scarlet Monastery", 189, { uiMap = 302 })
  c.tick(200)
  c.slash("end")
  c.leave()
  c.tick(60)
  c.enter("Scarlet Monastery", 189, { uiMap = 1420 })
  c.tick(1)
  c.instance.uiMap = 302
  c.tick(6)
  eq("the same copy: one entry", #_G.VulcanRunBookDB.entries, 1)
  eq("graveyard", c.run().label, "Scarlet Monastery - Graveyard")
  noErrors(c)
end

H.summary("tests_round11.lua")
