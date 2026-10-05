-- RunBook tests for the audit round 5 fixes.
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
H.group("a mistaken zone-in with your partner isn't saved")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Wailing Caverns", 43)
  c.addonMsg("Mirel", string.format("S3|beef01|43|Wailing Caverns||%d|0|0|0|0|0|0", c.run().serverStart))
  c.tick(10)
  c.leave()
  c.system("Wailing Caverns has been reset.")
  eq("not saved", #c.history(), 0)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("your partner's kill while you're outside, then your own mark")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(100)
  c.die()
  c.tick(1)
  c.leave()
  c.tick(20)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|0|Sneed", run.serverStart))
  c.dead = false
  c.enter("Deadmines", 36)
  c.tick(20)
  c.slash("boss Sneed")
  check("no split", c.run() == run and #c.history() == 0)
  eq("one Sneed", #run.bosses, 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a repeat mark after a reload or a reopen isn't a reset")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.slash("boss Rhahk'Zor")
  local r = H.boot({ saved = c.saved() })
  r.instance = { name = "Deadmines", map = 36, diff = 1, kind = "party", uiMap = 10036 }
  r.login()
  r.tick(10)
  r.slash("boss Rhahk'Zor")
  check("reload: already in this run", r.printedMatch("already in this run", true) ~= nil and #r.history() == 0)
  r.slash("end")
  r.slash("start")
  r.tick(10)
  r.slash("boss Rhahk'Zor")
  check("reopen: already in this run", #r.history() == 0 and #r.run().bosses == 1)
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("an unnamed mark isn't renamed to a boss already in the run")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(100)
  c.slash("boss Rhahk'Zor")
  c.tick(40)
  _G.VulcanRunBook_MarkBoss()
  c.tick(10)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|0|Rhahk'Zor", run.serverStart))
  eq("two bosses", #run.bosses, 2)
  eq("the mark stays unnamed", run.bosses[2].name, "Boss 2")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a cleared run stays cleared after a second clear")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(70)
  local alt = c.savedCopy(false)   -- an older backup somewhere (taken before)
  c.slash("clear yes")             -- mid-run: this run is kept
  c.leave()
  c.system("Deadmines has been reset.")
  eq("kept through the first clear", #c.history(), 1)
  c.tick(5)
  c.slash("clear yes")             -- cleared now
  local s = c.savedCopy(false)
  s.char.mirror.history = { c.ns.FixRun({ name = "Deadmines", serverStart = 1, char = "Tavlius" }) }
  local r = H.boot({ saved = s })
  r.login()
  eq("stays cleared", #r.history(), 0)
  local _ = alt
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("the window hides after /runbook end and leaving")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.slash("end")
  check("shown while ended inside", _G.VulcanRunBookFrame:IsShown())
  c.leave()
  c.tick(2)
  check("hidden outside", not _G.VulcanRunBookFrame:IsShown())
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("Dire Maul: floors never split a run; one hint per run")
do
  local c = fresh()
  c.mapNames = { [235] = "Warpwood Quarter", [236] = "Capital Gardens", [237] = "Court of the Highborne" }
  c.enter("Dire Maul", 429, { uiMap = 236 })   -- West entrance
  c.tick(4)
  local first = c.run()
  eq("no wing from a floor", first.label, "Dire Maul")
  c.instance.uiMap = 237                         -- deeper floor
  c.tick(100)
  c.leave()
  c.enter("Dire Maul", 429, { uiMap = 235 })    -- back in somewhere else (a summon)
  c.tick(5)
  check("same run", c.run() == first)
  local hints = 0
  for _, p in ipairs(c.printed) do if p:find("wings can't be told apart", 1, true) then hints = hints + 1 end end
  eq("hint once per run", hints, 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("boss count with a skip run in history")
do
  local c = fresh()
  local function run(ids)
    c.enter("Shadowfang Keep", 33)
    for _, id in ipairs(ids) do
      c.tick(60)
      c.encounter(id, "B" .. id, true, 10)
    end
    c.leave()
    c.system("Shadowfang Keep has been reset.")
  end
  run({ 1, 2, 3, 4, 5, 6, 7, 8 })
  run({ 1, 2, 3, 4, 5, 6, 7, 8 })
  run({ 1, 4, 7, 8 })                -- fast skip run: the best clear
  local row = c.strip(c.ns.RunRowText(c.history()[2]))
  check("full runs read 8/8", row:find("  8/8", 1, true) ~= nil, row)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("raid drop counts are yours two's")
do
  local c = fresh()
  c.slash("partner Mirel")
  c.party("Mirel", "A", "B", "C", "D", "E")
  c.raid = true
  c.enter("Molten Core", 409, { kind = "raid" })
  c.item(600, "Raider Epic", 4, 1000)
  for _ = 1, 10 do c.lootMsg("A", 600) end
  c.lootMsg("Mirel", 600)
  c.tick(100)
  local b, e = c.ns.DropCounts(c.run())
  eq("one epic (Mirel's)", e, 1)
  eq("no blues", b, 0)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("text: final wording, deaths line, last line")
do
  local c = fresh()
  c.enter("Wailing Caverns", 43)
  c.slash("final")
  check("dungeon wording", anyPrinted(c, "set from your first finished run"))
  c.leave()
  -- A raid night with wipes: the deaths line fits.
  c.slash("partner Mirel")
  local names = { "Mirel" }
  for i = 1, 20 do names[#names + 1] = "Raider" .. i end
  c.party(unpack(names))
  c.raid = true
  c.enter("Molten Core", 409, { kind = "raid" })
  c.tick(5)
  for round = 1, 3 do
    for _, m in ipairs(c.group) do m.dead = true end
    c.die()
    c.tick(1)
    for _, m in ipairs(c.group) do m.dead = false end
    c.dead = false
    c.tick(120)
    local _ = round
  end
  local line
  for _, l in ipairs(c.ns.LiveLines()) do if c.strip(l):find("deaths", 1, true) then line = c.strip(l) end end
  check("deaths line fits (<= 49 chars)", line and #line <= 49, line)
  c.raid = false
  c.party()
  c.leave()
  c.tick(7300)
  -- Last line shows gold and XP.
  c.enter("Deadmines", 36)
  c.gainMoney(270000)
  c.gainXP(1200)
  c.tick(100)
  c.leave()
  c.system("Deadmines has been reset.")
  c.slash("show")
  local last
  for _, l in ipairs(c.ns.LiveLines()) do if c.strip(l):find("Last:", 1, true) then last = c.strip(l) end end
  check("last line has gold and XP", last and last:find("27g", 1, true) and last:find("XP", 1, true), last)
  noErrors(c)
end

os.exit(H.summary("tests_round5.lua") and 0 or 1)
