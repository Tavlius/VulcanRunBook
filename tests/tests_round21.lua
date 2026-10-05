-- RunBook tests for the audit round 21 fixes.
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

local function sm(c)
  c.mapGroups = { [302] = 50, [303] = 50 }
  c.groupFloors = { [50] = { { mapID = 302, name = "Graveyard" }, { mapID = 303, name = "Library" } } }
end

---------------------------------------------------------------------------
H.group("a Scarlet Monastery reset while you're back in a wing: no split")
do
  local c = fresh()
  duo(c)
  sm(c)
  c.enter("Scarlet Monastery", 189, { uiMap = 303 })
  c.tick(400) c.encounter(1, "Houndmaster Loksey") c.tick(200)
  local run = c.run()
  c.leave() c.tick(240)
  c.enter("Scarlet Monastery", 189, { uiMap = 303 })
  c.tick(60)
  c.addonMsg("Mirel", "R3|beef01|Scarlet Monastery")
  c.tick(5)
  check("same run", c.run() == run)
  eq("one entry", #_G.VulcanRunBookDB.entries, 1)
  noErrors(c)
end

H.group("a late reset message still splits a one-copy dungeon")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(200) c.encounter(644, "Rhahk'Zor") c.tick(60)
  local run = c.run()
  c.leave() c.tick(60)
  c.enter("Deadmines", 36)
  c.tick(30)
  c.system("Deadmines has been reset.")
  check("split", c.run() ~= run and run.endReason == "split")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("his note on the run after an unseen reset (he came back in first)")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local first = c.run()
  c.tick(200) c.encounter(644, "Rhahk'Zor") c.tick(300)
  c.leave() c.tick(120)
  local hisStart = c.ns.ServerTime()
  c.tick(20)
  c.enter("Deadmines", 36)
  c.tick(100)
  c.encounter(644, "Rhahk'Zor")
  local new = c.run()
  check("split", new ~= first)
  c.tick(60) c.leave() c.tick(5) c.slash("end") c.tick(2)
  c.addonMsg("Mirel", string.format("N3|beef01|36|Deadmines||%d|0|on his second run", hisStart))
  eq("on the second run", #new.notes, 1)
  eq("not the first", #first.notes, 0)
  noErrors(c)
end

H.group("a note from a partner who joined just before you left goes on that run")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local first = c.run()
  c.tick(600)
  local his = c.ns.ServerTime()
  c.tick(20)
  c.leave()
  c.system("Deadmines has been reset.")
  c.tick(5)
  c.enter("Deadmines", 36)
  local second = c.run()
  c.tick(100)
  c.addonMsg("Mirel", string.format("N3|beef01|36|Deadmines||%d|0|joined late", his))
  eq("on the run he joined", #first.notes, 1)
  eq("not the next", #second.notes, 0)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("your partner dies outside: not a death in your run")
do
  local c = fresh()
  duo(c)
  c.enter("Blackrock Depths", 230)
  c.tick(600)
  c.away = { Mirel = 1415 }                    -- (out on the mountain)
  c.mapTypes = { [1415] = 3 }
  c.member("Mirel").dead = true
  c.tick(3)
  eq("no death", #c.run().deaths, 0)
  c.member("Mirel").dead = false
  c.away = nil
  c.tick(3)
  c.member("Mirel").dead = true
  c.tick(3)
  eq("inside, it counts", #c.run().deaths, 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("the Scarlet Monastery entrance map isn't a wing")
do
  local c = fresh()
  sm(c)
  c.mapNames = { [19] = "Scarlet Monastery Entrance" }
  c.mapTypes = { [19] = 5 }
  c.enter("Scarlet Monastery", 189, { uiMap = 19 })    -- (the map still shows the doors)
  c.tick(1)
  check("not a wing", not (c.run() and c.run().wing == "m19"))
  check("no 'map 19' label", not anyPrinted(c, "map 19"))
  c.instance.uiMap = 303
  c.tick(15)
  eq("the wing once read", c.run() and c.run().wing, "m303")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("'Malor' 15 seconds after 'Malor the Zealous' is the same kill")
do
  local c = fresh()
  duo(c)
  c.enter("Stratholme", 329)
  local run = c.run()
  c.tick(120)
  c.slash("boss Malor the Zealous")
  c.tick(15)
  c.addonMsg("Mirel", string.format("B3|beef01|329|Stratholme||%d|k.1!m|0|Malor", run.serverStart))
  eq("one kill", names(run), "Malor the Zealous")
  -- Two different names 15 seconds apart are two kills.
  c.tick(120)
  c.slash("boss Ramstein")
  c.tick(15)
  c.addonMsg("Mirel", string.format("B3|beef01|329|Stratholme||%d|k.2!m|0|Baron Rivendare", run.serverStart))
  eq("two more", names(run), "Malor the Zealous,Ramstein,Baron Rivendare")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("debug off turns echo off too")
do
  local c = fresh()
  c.slash("debug echo")
  check("echo on", c.ns.DB.debugEcho)
  c.slash("debug off")
  c.slash("debug on")
  check("echo off", not c.ns.DB.debugEcho)
  noErrors(c)
end

H.summary("tests_round21.lua")
