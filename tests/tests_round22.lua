-- RunBook tests for the audit round 22 fixes.
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

---------------------------------------------------------------------------
H.group("his note on the run he started over (/runbook new a second before yours)")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local first = c.run()
  c.tick(120)
  local his = c.ns.ServerTime()
  c.tick(1)
  c.addonMsg("Mirel", string.format("X3|beef01|36|Deadmines||%d|1", his))
  local second = c.run()
  check("started over", second ~= first and first.endReason == "new")
  c.tick(300)
  c.slash("end")
  c.addonMsg("Mirel", string.format("N3|beef01|36|Deadmines||%d|0|great second run", his))
  eq("on the second run", #second.notes, 1)
  eq("not the first", #first.notes, 0)
  noErrors(c)
end

H.group("his note when your run started over and the next one wasn't kept")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local first = c.run()
  local his = first.serverStart + 30
  c.tick(300)
  c.slash("new yes")
  c.tick(5)
  c.slash("end")                                -- (too short to keep)
  c.addonMsg("Mirel", string.format("N3|beef01|36|Deadmines||%d|0|first run note", his))
  eq("on the first run", #first.notes, 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a death on the entrance map outside isn't a run death")
do
  local c = fresh()
  duo(c)
  c.enter("Scarlet Monastery", 189, { uiMap = 303 })
  c.tick(300)
  c.away = { Mirel = 19 }
  c.mapTypes = { [19] = 5 }
  c.member("Mirel").dead = true
  c.tick(3)
  eq("not counted", #c.run().deaths, 0)
  noErrors(c)
end

H.group("a dungeon whose map is a zone: deaths on your map still count")
do
  local c = fresh()
  duo(c)
  c.enter("Molten Core", 409, { kind = "raid" })
  c.mapTypes = { [10409] = 3 }
  c.tick(300)
  c.member("Mirel").dead = true
  c.tick(3)
  eq("counted", #c.run().deaths, 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a named mark right after the game's kill is that kill")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(230)
  c.encounter(639, "Edwin VanCleef")
  c.tick(3)
  c.clearPrinted()
  c.slash("boss VanCleef")
  eq("one kill", names(run), "Edwin VanCleef")
  check("just recorded", anyPrinted(c, "Edwin VanCleef was just recorded."))
  c.clearPrinted()
  c.slash("boss Edwin VanCleef")
  eq("still one", #run.bosses, 1)
  check("no reset advice", not anyPrinted(c, "/runbook new"))
  c.tick(60)
  c.clearPrinted()
  c.slash("boss Edwin VanCleef")
  check("later this visit: no reset advice", anyPrinted(c, "is already in this run.") and not anyPrinted(c, "/runbook new"))
  noErrors(c)
end

H.group("a fuller name a moment after the game's short one")
do
  local c = fresh()
  c.enter("Stratholme", 329)
  local run = c.run()
  c.tick(200)
  c.encounter(1, "Malor")
  c.tick(4)
  c.slash("boss Malor the Zealous")
  eq("renamed", names(run), "Malor the Zealous")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("raid deaths line keeps both your names")
do
  local c = fresh()
  c.party("Mirel", "A", "B", "C", "D", "E", "F", "G")
  c.raid = true
  c.slash("partner Mirel")
  c.enter("Molten Core", 409, { kind = "raid" })
  local run = c.run()
  c.tick(300)
  local t = run.elapsed
  for _ = 1, 2 do
    run.deaths[#run.deaths + 1] = { who = "Tavlius", t = t }
    run.deaths[#run.deaths + 1] = { who = "Mirel", t = t }
  end
  for i = 1, 106 do run.deaths[#run.deaths + 1] = { who = "Raider" .. (i % 38), t = t } end
  run.wipes = { { t = t, boss = "Lucifron" }, { t = t, boss = "Magmadar" } }
  local line
  for _, l in ipairs(c.ns.LiveLines()) do if c.strip(l):find("deaths", 1, true) then line = c.strip(l) end end
  check("both names", line and line:find("Tavlius x2", 1, true) and line:find("Mirel x2", 1, true), line)
  check("wipes kept", line and line:find("2 wipes", 1, true), line)
  check("fits", line and c.ns.Len(line) <= 49, line)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a note that starts with #1st")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.slash("note #1st pull went bad")
  eq("on this run", c.run().notes[1] and c.run().notes[1].text, "#1st pull went bad")
  noErrors(c)
end

H.group("report: stack counts")
do
  local c = fresh()
  c.enter("Molten Core", 409, { kind = "raid" })
  c.item(17010, "Fiery Core", 3, 0)
  c.tick(70)
  c.lootMsg(nil, 17010, 3)
  local text = c.strip(table.concat(c.ns.ReportLines(c.run()), "\n"))
  check("x3", text:find("Fiery Core%]? ?x3") ~= nil or text:find("x3", 1, true) ~= nil, text)
  noErrors(c)
end

H.group("/runbook check reads in words")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.clearPrinted()
  c.slash("check")
  check("no wings", anyPrinted(c, "no wings"))
  check("no 'nil'", not anyPrinted(c, "nil"))
  check("difficulty in words", anyPrinted(c, "difficulty: "))
  noErrors(c)
end

H.summary("tests_round22.lua")
