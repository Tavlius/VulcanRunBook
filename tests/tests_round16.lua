-- RunBook tests for the audit round 16 fixes.
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

---------------------------------------------------------------------------
H.group("a hidden loot, then a readable loot of the same item 30s later: two")
do
  local c = fresh()
  c.item(100, "Cruel Barb", 3, 5000)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(10)
  c.lootReal(100, 1, true)
  c.tick(31)
  c.lootReal(100, 1, false)
  c.tick(3)
  eq("valued twice", run.loot, 10000)
  eq("two drops", #run.drops, 2)
  noErrors(c)
end

H.group("time dead outside doesn't count toward the 30 minutes")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(60)
  c.die()
  c.leave()
  c.tick(1200, 1)                                -- 20 minutes dead outside
  c.dead = false
  c.tick(660, 1)                                 -- 11 minutes alive
  check("still going", c.run() ~= nil and not c.run().ended)
  c.tick(1200, 1)
  check("ends after 30 alive", c.run() == nil)
  noErrors(c)
end

H.group("text: check over the cap, the Last line keeps a name that fits")
do
  local c = fresh()
  c.slash("cap 2")
  for i = 1, 3 do
    c.enter("Deadmines", 36)
    c.tick(70)
    c.leave()
    c.system("Deadmines has been reset.")
    c.tick(5)
    local _ = i
  end
  c.slash("check")
  check("under the cap again", anyPrinted(c, "under the cap again in"))
  local d = fresh()
  d.enter("Lower Blackrock Spire", 229)
  d.tick(1835)
  d.gainMoney(450000)
  d.leave()
  d.system("Lower Blackrock Spire has been reset.")
  d.tick(2)
  local text = d.strip(table.concat(d.ns.LiveLines(), "\n"))
  check("full name", text:find("Last: Lower Blackrock Spire", 1, true) ~= nil, text)
  noErrors(c, d)
end

H.group("your own raid slot, when unit comparison is hidden")
do
  local c = fresh()
  c.party("Mirel", "A", "B", "C", "D", "E", "F", "G", "H", "I")
  c.raid = true
  local orig = _G.UnitIsUnit
  _G.UnitIsUnit = function(a, b)
    if a ~= "player" and b == "player" then return c.SECRET end
    return orig(a, b)
  end
  _G.UnitInRaid = function(u) if u == "player" then return 1 end return nil end
  -- Some builds return something other than the realm second: not used to tell you apart.
  local origName = _G.UnitName
  _G.UnitName = function(u)
    local n = origName(u)
    if u == "player" or u == "raid1" then return n, "Surname" end
    return n
  end
  c.enter("Molten Core", 409, { kind = "raid" })
  c.tick(100)
  c.die()
  c.tick(3)
  eq("one death", #c.run().deaths, 1)
  _G.UnitInRaid = nil
  check("by name too", c.ns.IsPlayerUnit("raid1"))
  _G.UnitName = origName
  noErrors(c)
end

H.summary("tests_round16.lua")
