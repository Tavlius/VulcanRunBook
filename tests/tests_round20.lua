-- RunBook tests for the audit round 20 fixes.
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

-- The difficulty reads as a secret while hide() is true.
local function hideDiff(c)
  local orig = _G.GetInstanceInfo
  local on = true
  _G.GetInstanceInfo = function()
    local a, b, d, e, f, g, h, i = orig()
    if on then d = c.SECRET end
    return a, b, d, e, f, g, h, i
  end
  return function() on = false end
end

---------------------------------------------------------------------------
H.group("after /runbook end inside, an unreadable difficulty doesn't restart it")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(120)
  c.slash("end")
  local show = hideDiff(c)
  c.tick(10)
  show()
  c.tick(10)
  check("no new run", c.run() == nil)
  eq("one entry", #_G.VulcanRunBookDB.entries, 1)
  noErrors(c)
end

H.group("going back into a copy while the difficulty is unreadable: no new entry")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(120)
  c.enter("Wailing Caverns", 43)
  c.tick(120)
  local show = hideDiff(c)
  c.enter("Deadmines", 36)
  show()
  c.tick(20)
  eq("two entries", #_G.VulcanRunBookDB.entries, 2)
  noErrors(c)
end

H.group("a split keeps 'difficulty unknown'")
do
  local c = fresh()
  local show = hideDiff(c)
  c.enter("Deadmines", 36)
  c.tick(200)
  c.encounter(1, "Rhahk'Zor")
  c.tick(60)
  c.leave() c.tick(60)
  c.enter("Deadmines", 36)
  c.tick(30)
  c.system("Deadmines has been reset.")
  local new = c.run()
  check("split", new and #c.history() == 1)
  show()
  c.tick(20)
  check("same run once readable", c.run() == new)
  eq("still one saved", #c.history(), 1)
  eq("entries", #_G.VulcanRunBookDB.entries, 2)
  noErrors(c)
end

H.group("a partner's /runbook new with an unknown difficulty")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local r = c.run()
  c.tick(300)
  c.addonMsg("Mirel", string.format("X3|beef01|36|Deadmines||%d|", c.ns.ServerTime()))
  check("started over", c.run() ~= r)
  noErrors(c)
end

H.group("yours sent without a difficulty when it's unknown")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  local show = hideDiff(c)
  c.enter("Deadmines", 36)
  c.tick(300)
  c.slash("new yes")
  c.tick(2)
  local x
  for _, m in ipairs(c.addonSent) do if m.msg:find("^X") then x = m.msg end end
  check("ends with an empty difficulty", x and x:find("|$") ~= nil, x)
  show()
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a map ID unreadable at the start is filled in")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100) c.encounter(1, "Rhahk'Zor") c.tick(100) c.encounter(4, "Van Cleef") c.tick(10)
  c.leave() c.system("Deadmines has been reset.") c.tick(5)
  c.secret.map = true
  c.enter("Deadmines", 36) c.tick(3) c.secret.map = nil
  c.tick(60) c.encounter(1, "Rhahk'Zor") c.tick(50) c.encounter(4, "Van Cleef") c.tick(10)
  eq("map ID", c.run().mapID, 36)
  c.leave() c.system("Deadmines has been reset.") c.tick(5)
  eq("one Dungeons row", #c.ns.DungeonStats(), 1)
  check("new best", anyPrinted(c, "New best clear"))
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("no false 'slot is free' while a wing is read")
do
  local c = fresh()
  c.mapGroups = { [302] = 50, [303] = 50 }
  c.groupFloors = { [50] = { { mapID = 302, name = "Graveyard" }, { mapID = 303, name = "Library" } } }
  for _, d in ipairs({ { "Deadmines", 36 }, { "Wailing Caverns", 43 } }) do
    c.enter(d[1], d[2]) c.tick(70) c.leave() c.tick(5)
  end
  c.enter("Scarlet Monastery", 189, { uiMap = 303 }) c.tick(300)
  c.enter("Shadowfang Keep", 33) c.tick(100)
  c.leave() c.tick(2)
  c.clearPrinted()
  c.secret.uimap = true
  c.enter("Scarlet Monastery", 189, { uiMap = 303 })
  c.tick(4) c.secret.uimap = nil c.tick(10)
  eq("entries", #_G.VulcanRunBookDB.entries, 4)
  check("no 'slot is free'", not anyPrinted(c, "slot is free again"))
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a zone change before the loading screen ends doesn't backdate leaving")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(120)
  c.slash("end")
  c.tick(5)
  -- Out of the dungeon: the zone change comes first, then the loading screen ends.
  c.ns.lastSaved = c.ns.ServerTime() - 7200   -- (logged out two hours before this session)
  c.instance = nil
  c.fire("ZONE_CHANGED_NEW_AREA")
  c.leave()
  c.tick(60)
  c.enter("Deadmines", 36)
  c.tick(5)
  eq("same copy: still one entry", #_G.VulcanRunBookDB.entries, 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("hand-mark flag on the tag; the tag is stored without it")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(60)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.3!m|0|", run.serverStart))
  eq("one kill", #run.bosses, 1)
  eq("tag", run.bosses[1].key or run.bosses[1].peer, "k.3")
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.3!m|644|Rhahk'Zor", run.serverStart))
  eq("named, same kill", #run.bosses, 1)
  eq("name", run.bosses[1].name, "Rhahk'Zor")
  noErrors(c)
end

H.summary("tests_round20.lua")
