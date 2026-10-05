-- RunBook tests for the audit round 14 fixes.
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

local function partnerTotal(c)
  local n = 0
  local runs = {}
  if c.run() then runs[1] = c.run() end
  for _, r in ipairs(c.history()) do runs[#runs + 1] = r end
  for _, r in ipairs(runs) do for _, p in pairs(r.partners) do n = n + (p.coin or 0) end end
  return n
end

---------------------------------------------------------------------------
H.group("your partner's log splits a run: his gold moves to his new run, not lost")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local p1 = c.run().serverStart
  c.tick(60)
  c.encounter(644, "Rhahk'Zor")
  c.tick(30)
  S(c, p1, 90, 100)
  c.leave()
  c.tick(60)
  -- (Reset nobody saw.) He goes back in and loots; you come in 90s later.
  local hisBack = c.ns.ServerTime()
  c.tick(10)
  S(c, p1, 100, 941)
  c.tick(80)
  c.enter("Deadmines", 36)
  c.tick(30)
  eq("before: all of it in your run", partnerTotal(c), 941)
  -- Both logs see the repeat kill: his split comes as a lower final word for
  -- his old run, then his new run's numbers.
  c.encounter(644, "Rhahk'Zor")
  S(c, p1, 100, 100, true)
  S(c, hisBack, 130, 841)
  eq("after: still all of it", partnerTotal(c), 941)
  eq("the 841 in your new run", c.run().partners.Mirel.coin, 841)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a late-joining partner's kill in a new copy while you're out")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(60)
  c.leave()                                   -- repair trip
  c.tick(60)
  c.enter("Deadmines", 36)
  c.tick(30)
  c.encounter(644, "Rhahk'Zor")
  c.tick(60)
  local hisJoin = c.ns.ServerTime()           -- he joins this copy now
  c.tick(60)
  c.leave()
  c.tick(120)
  -- (Reset nobody saw.) He kills Rhahk'Zor in the new copy.
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.4|644|Rhahk'Zor", hisJoin + 200))
  check("your run ends whole (reset)", run.ended and run.endReason == "reset" and #run.bosses == 1)
  eq("his kill in a new run", c.run() and c.run().bosses[1] and c.run().bosses[1].name, "Rhahk'Zor")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("an alt's raid drops count for that alt's runs")
do
  local c = fresh({ name = "Paladin" })
  c.party("A", "B", "C", "D", "E", "F", "G", "H", "I", "J")
  c.raid = true
  c.enter("Molten Core", 409, { kind = "raid" })
  c.item(3001, "Paladin Epic", 4, 1000)
  c.tick(70)
  c.lootMsg(nil, 3001)
  c.leave()
  c.system("Molten Core has been reset.")
  c.tick(5)
  local s = c.savedCopy(false)
  s.char = nil
  local r = H.boot({ saved = s, name = "Tavlius" })
  r.login()
  local run = r.history()[1]
  local _, epics = r.ns.DropCounts(run)
  eq("epic counted on Tavlius", epics, 1)
  noErrors(c, r)
end

H.group("names: Cyrillic case, typed partner capital")
do
  local c = fresh()
  check("Келан = келан", c.ns.SameName("Келан", "келан"))
  check("Ёж = ёж", c.ns.SameName("Ёж", "ёж"))
  c.slash("partner mirel")
  eq("capitalized", c.ns.DB.partner, "Mirel")
  check("warned not in group", anyPrinted(c, "Not in your group right now"))
  noErrors(c)
end

H.group("raid: one hint when no partner is set")
do
  local c = fresh()
  c.party("Mirel", "A", "B", "C", "D", "E", "F", "G")
  c.raid = true
  c.enter("Molten Core", 409, { kind = "raid" })
  c.addonMsg("Mirel", string.format("S3|beef01|409|Molten Core||%d|1|0|0|0|0|0", c.run().serverStart))
  c.addonMsg("A", string.format("S3|beef02|409|Molten Core||%d|1|0|0|0|0|0", c.run().serverStart))
  local n = 0
  for _, p in ipairs(c.printed) do if c.strip(p):find("/runbook partner <name>", 1, true) then n = n + 1 end end
  eq("one hint", n, 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("live window: your show/hide holds through end/start/new")
do
  local c = fresh()
  c.slash("auto off")
  c.enter("Deadmines", 36)
  c.slash("show")
  check("shown", c.ns.LiveShown())
  c.tick(100)
  c.slash("new yes")
  check("still shown after new", c.ns.LiveShown())
  c.slash("end")
  check("still shown after end", c.ns.LiveShown())
  local text = c.strip(table.concat(c.ns.LiveLines(), "\n"))
  check("says it ended", text:find("run ended", 1, true) ~= nil, text)
  c.leave()
  check("hidden after leaving (auto off)", not c.ns.LiveShown())
  noErrors(c)
end

H.group("ended then deleted: the window doesn't offer a reopen")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(200)
  c.slash("end")
  c.slash("delete " .. c.history()[1].id .. " yes")
  local text = c.strip(table.concat(c.ns.LiveLines(), "\n"))
  check("starts a new one", text:find("/runbook start: new run", 1, true) ~= nil, text)
  c.slash("quiet on")
  c.clearPrinted()
  c.slash("start")
  check("confirmed in quiet mode", anyPrinted(c, "The Deadmines started.") or anyPrinted(c, "Deadmines started."))
  noErrors(c)
end

H.group("the Last line fits")
do
  local c = fresh()
  c.enter("Blackrock Depths", 230)
  c.tick(4368, 10)
  c.gainMoney(1234500)
  c.gainXP(4000)
  c.leave()
  c.system("Blackrock Depths has been reset.")
  c.tick(2)
  for _, l in ipairs(c.ns.LiveLines()) do
    local t = c.strip(l)
    check("fits", #t <= 49, t)
  end
  noErrors(c)
end

H.summary("tests_round14.lua")
