-- RunBook tests for the audit round 17 fixes.
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

local function duo(c)
  c.party("Mirel")
  c.slash("partner Mirel")
end

---------------------------------------------------------------------------
H.group("a partner's note on a run 7 back finds that run, or none")
do
  local c = fresh()
  duo(c)
  local starts = {}
  for i = 1, 7 do
    c.enter("Deadmines", 36)
    starts[i] = c.run().serverStart
    c.tick(70)
    c.leave()
    c.system("Deadmines has been reset.")
    c.tick(30)
  end
  c.addonMsg("Mirel", string.format("N3|beef01|36|Deadmines||%d|0|first one", starts[1] + 20))
  local first
  for _, r in ipairs(c.history()) do if r.serverStart == starts[1] then first = r end end
  eq("on the first run", first and #first.notes, 1)
  c.addonMsg("Mirel", string.format("N3|beef01|36|Deadmines||%d|0|no such run", starts[1] - 3 * 3600))
  local total = 0
  for _, r in ipairs(c.history()) do total = total + #r.notes end
  eq("no match: dropped", total, 1)
  noErrors(c)
end

H.group("dead or running back: not time away")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(60)
  c.die()
  c.leave()
  c.tick(540, 1)                                 -- 9 minutes running back
  c.dead = false
  c.tick(1320, 1)                                -- 22 minutes alive outside
  check("still going", c.run() ~= nil)
  -- And a reload after time dead outside.
  local d = fresh()
  d.enter("Deadmines", 36)
  d.tick(60)
  d.leave()
  d.dead = true
  d.tick(1200, 1)
  d.dead = false
  d.tick(660, 1)
  local r = H.boot({ saved = d.savedCopy(false) })
  r.login()
  check("a reload keeps it", r.run() ~= nil)
  noErrors(c, d, r)
end

H.group("a kill you took back stays gone when your partner names it")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(60)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.1|0|", run.serverStart))
  c.slash("unboss")
  c.tick(5)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.1|0|Sneed", run.serverStart))
  eq("still none", #run.bosses, 0)
  noErrors(c)
end

H.group("history stays newest first when an older run ends late")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  local old = c.run()
  c.tick(100)
  c.leave()
  c.enter("Wailing Caverns", 43)                 -- ends the Deadmines run (new dungeon)
  c.tick(70)
  c.leave()
  c.system("Wailing Caverns has been reset.")
  c.tick(5)
  check("newest first", c.history()[1].startedAt >= c.history()[2].startedAt)
  local _ = old
  noErrors(c)
end

H.group("a partner's drop synced late still matches its loot line")
do
  local c = fresh()
  duo(c)
  c.item(100, "Cruel Barb", 3, 5000)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(70)
  local lootedAt = c.ns.ServerTime()
  c.lootMsg("Mirel", 100)
  c.tick(90)                                     -- his message waited out a boss fight
  c.addonMsg("Mirel", string.format("D3|beef01|36|Deadmines||%d|100|1|3|%d", run.serverStart, lootedAt))
  local n = 0
  for _, d in ipairs(run.drops) do if d.who == "Mirel" then n = n + 1 end end
  eq("one barb", n, 1)
  noErrors(c)
end

H.group("a partner's kill while you're outside shows no time")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(300)
  c.leave()
  c.tick(400)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.3|645|Gilnid", run.serverStart))
  check("chat says so", anyPrinted(c, "Gilnid down (from your partner, while you were outside)."))
  local detail = c.strip(table.concat(c.ns.RunDetailLines(run), "\n"))
  check("details say so", detail:find("while you were outside", 1, true) ~= nil, detail)
  noErrors(c)
end

H.group("line fitting counts characters")
do
  local c = fresh()
  eq("dot is one", c.ns.Len("a · b"), 5)
  c.enter("Blackrock Depths", 230)
  c.tick(2455)
  c.gainMoney(1230000)
  c.xp = 0 c.xpMax = 200000 c.gainXP(118500)
  c.leave()
  c.system("Blackrock Depths has been reset.")
  c.tick(2)
  local text = c.strip(table.concat(c.ns.LiveLines(), "\n"))
  check("full name kept", text:find("Last: Blackrock Depths", 1, true) ~= nil, text)
  noErrors(c)
end

H.summary("tests_round17.lua")
