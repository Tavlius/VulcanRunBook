-- RunBook tests for the audit round 15 fixes.
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

local function S(c, start, el, coin, final)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|%d|%d|0|0|0|%d", start, el, coin, final and 1 or 0))
end

---------------------------------------------------------------------------
H.group("your partner's split lowers a part of your running run: the gold moves")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local mine = c.run()
  local p1 = mine.serverStart - 300                  -- his run began well before yours
  S(c, p1, 300, 0)
  c.tick(60)
  S(c, p1, 360, 1000)
  eq("in your run", mine.partners.Mirel.coin, 1000)
  local p2 = mine.serverStart - 100                  -- his log split there (a reset it found)
  S(c, p1, 200, 0, true)
  S(c, p2, 160, 1000)
  eq("still 1000", mine.partners.Mirel.coin, 1000)
  noErrors(c)
end

H.group("a copy you never went into isn't remembered")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  c.tick(60)
  c.encounter(644, "Rhahk'Zor")
  c.tick(30)
  c.leave()
  c.tick(120)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.1|644|Rhahk'Zor", c.ns.ServerTime() - 30))
  check("waiting run from his copy", c.run() and c.run().entryOnEntry)
  local n = #_G.VulcanRunBookDB.entries
  c.enter("Wailing Caverns", 43)
  c.tick(70)
  c.leave()
  c.enter("Deadmines", 36)
  eq("his copy counts when you first go in", #_G.VulcanRunBookDB.entries, n + 2)
  noErrors(c)
end

H.group("saved copies: the one changed last wins")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(70)
  c.leave()
  c.system("Deadmines has been reset.")
  c.tick(5)
  local stale = c.savedCopy(false)                   -- before the note
  c.tick(5)
  c.slash("note #" .. c.history()[1].id .. " later note")
  local fresh2 = c.savedCopy(false)
  -- The account copy is the stale one, the backup has the note.
  fresh2.db.history = stale.db.history
  local r = H.boot({ saved = fresh2 })
  r.login()
  eq("note kept", #r.history()[1].notes, 1)
  noErrors(c, r)
end

H.group("a second drop of the same item later isn't taken for the first")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.item(100, "Cruel Barb", 3, 5000)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(70)
  c.lootMsg("Mirel", 100)
  c.tick(60)
  c.addonMsg("Mirel", string.format("D3|beef01|36|Deadmines||%d|100|1|3", run.serverStart))
  local n = 0
  for _, d in ipairs(run.drops) do if d.who == "Mirel" then n = n + 1 end end
  eq("two barbs", n, 2)
  noErrors(c)
end

H.group("boss names fold case beyond ASCII; quiet partner mark reply; realm")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(60)
  c.encounter(644, "Ван Клиф")
  c.tick(30)
  c.slash("boss ван клиф")
  eq("one boss", #c.run().bosses, 1)
  c.leave()
  c.system("Deadmines has been reset.")
  c.tick(2)
  c.slash("final ВАН КЛИФ")
  check("final found", anyPrinted(c, "is now Ван Клиф"))
  local q = fresh()
  q.party("Mirel")
  q.slash("partner Mirel")
  q.slash("quiet on")
  q.enter("Deadmines", 36)
  q.tick(60)
  q.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.2|0|", q.run().serverStart))
  q.tick(3)
  q.clearPrinted()
  _G.VulcanRunBook_MarkBoss()
  check("quiet reply", anyPrinted(q, "was already marked by your partner"))
  local r = H.boot() r.realm = "Emberfall" r.login()
  r.enter("Deadmines", 36)
  eq("run keeps the realm", r.run().char, "Tavlius-Emberfall")
  noErrors(c, q, r)
end

H.group("partner rates use the time since his last numbers")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(300)
  S(c, run.serverStart, 300, 100000)
  c.tick(30)
  c.slash("show")
  local text = c.strip(table.concat(c.ns.LiveLines(), "\n"))
  check("rate over 330s, not 300s", text:find("109g 9s/hr", 1, true) ~= nil and not text:find("120g/hr", 1, true), text)
  noErrors(c)
end

H.summary("tests_round15.lua")
