-- RunBook tests for the audit round 4 fixes.
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

local function clear(c, name, map, kills)
  c.enter(name, map)
  local last = 0
  for _, k in ipairs(kills) do
    c.tick(k[3] - last - 30)
    c.encounter(k[1], k[2], true, 30)
    last = k[3]
  end
  c.leave()
  c.system(name .. " has been reset.")
end

---------------------------------------------------------------------------
H.group("your key press and your partner's named mark are one kill")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(200)
  _G.VulcanRunBook_MarkBoss()                    -- unnamed "Boss 1"
  c.tick(5)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|0|Rhahk'Zor", run.serverStart))
  eq("one boss", #run.bosses, 1)
  eq("named by your partner", run.bosses[1].name, "Rhahk'Zor")
  -- The other way round: his named kill first, your press 20s later.
  c.tick(200)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|0|Sneed", run.serverStart))
  c.tick(20)
  _G.VulcanRunBook_MarkBoss()
  eq("still two bosses", #run.bosses, 2)
  check("no second line for it", not anyPrinted(c, "Sneed was just recorded"))
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("clear yes mid-run, then a split: both parts survive a relog")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.encounter(1144, "Rhahk'Zor", true, 30)
  c.leave()
  c.enter("Deadmines", 36)
  c.slash("clear yes")
  c.tick(30)
  c.encounter(1144, "Rhahk'Zor", true, 30)   -- a split
  c.tick(70)
  c.leave()
  c.system("Deadmines has been reset.")
  eq("two runs", #c.history(), 2)
  local r = H.boot({ saved = c.savedCopy(false) })
  r.login()
  eq("both after relog", #r.history(), 2)
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("best comparisons use the dungeon's final boss")
do
  local c = fresh()
  clear(c, "Deadmines", 36, { { 1, "A", 300 }, { 2, "B", 600 }, { 3, "C", 900 } })
  clear(c, "Deadmines", 36, { { 1, "A", 280 }, { 2, "B", 560 }, { 3, "C", 800 } })
  local lines = c.ns.ReportLines(c.history()[1])
  check("report: new best, was 15:00", lines[1]:find("Cleared at 13:20 (new best, was 15:00).", 1, true) ~= nil, lines[1])
  local detail = {}
  for _, l in ipairs(c.ns.RunDetailLines(c.history()[1])) do detail[#detail + 1] = c.strip(l) end
  local txt = table.concat(detail, "\n")
  check("detail compares with the other clear", txt:find("fastest other clear, 15:00", 1, true) ~= nil, txt)
  -- Partial runs ending on B can't make a false "new best".
  for _ = 1, 3 do clear(c, "Deadmines", 36, { { 1, "A", 300 }, { 2, "B", 640 } }) end
  check("no false new best", not anyPrinted(c, "New best clear for Deadmines: 10:40"))
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("splits from your second run")
do
  local c = fresh()
  clear(c, "Wailing Caverns", 43, { { 1, "Kresh", 300 }, { 2, "Mutanus", 900 } })
  c.enter("Wailing Caverns", 43)
  c.tick(250)
  c.encounter(1, "Kresh", true, 30)
  local live = c.liveText()
  check("best and split on run 2", live:find("best 15:00", 1, true) ~= nil and live:find("Kresh  4:40  -0:20", 1, true)
    ~= nil, live)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a reopened run keeps its number")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.slash("end")
  local id = c.history()[1].id
  c.slash("start")
  local r = H.boot({ saved = c.saved() })
  r.instance = { name = "Deadmines", map = 36, diff = 1, kind = "party", uiMap = 10036 }
  r.login()
  r.slash("end")
  eq("same number", r.history()[1].id, id)
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("/runbook end: hints and window")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.slash("end")
  check("window stays up after end inside", _G.VulcanRunBookFrame:IsShown())
  check("and says how to reopen", c.liveText():find("/runbook start reopens it", 1, true) ~= nil, c.liveText())
  c.slash("start")
  c.leave()
  c.clearPrinted()
  c.slash("end")
  check("no reopen hint when ended outside", not anyPrinted(c, "reopens it"))
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a short run with loot is saved")
do
  local c = fresh()
  c.item(101, "Linen Cloth", 1, 15)
  c.enter("Deadmines", 36)
  c.tick(20)
  c.lootMsg(nil, 101, 3)
  c.slash("new yes")
  eq("saved", #c.history(), 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("two runs started in the same second stay apart")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.gainMoney(10)
  c.slash("new yes")
  c.gainMoney(10)
  c.slash("new yes")
  c.gainMoney(10)
  c.slash("end")
  eq("three runs", #c.history(), 3)
  local r = H.boot({ saved = c.savedCopy(false) })
  r.login()
  eq("three after relog", #r.history(), 3)
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("Scarlet Monastery wings that share one map group")
do
  local c = fresh()
  c.mapGroups = { [302] = 50, [303] = 50, [304] = 50, [305] = 50 }
  c.mapNames = { [302] = "Scarlet Monastery", [303] = "Scarlet Monastery" }
  c.groupFloors = { [50] = { { mapID = 302, name = "Graveyard" }, { mapID = 303, name = "Library" },
    { mapID = 304, name = "Armory" }, { mapID = 305, name = "Cathedral" } } }
  c.enter("Scarlet Monastery", 189, { uiMap = 302 })
  local gy = c.run()
  eq("label from the floor name", gy.label, "Scarlet Monastery - Graveyard")
  c.tick(300)
  c.leave()
  c.enter("Scarlet Monastery", 189, { uiMap = 303 })
  c.tick(4)
  check("library is a new run", c.run() ~= gy and gy.endReason == "wing")
  eq("library label", c.run().label, "Scarlet Monastery - Library")
  check("no hint when wings can be read", not anyPrinted(c, "can't be told apart"))
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("partner names: any case")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner MIREL")
  eq("stored as the group shows it", _G.VulcanRunBookDB.partner, "Mirel")
  c.enter("Deadmines", 36)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|60|500|0|0|0|0", c.run().serverStart))
  check("synced", c.run().partners.Mirel ~= nil)
  _G.VulcanRunBookDB.partner = "mirel"
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|90|900|0|0|0|0", c.run().serverStart))
  eq("still synced with different case", c.run().partners.Mirel.coin, 900)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a hand-marked boss again after an unseen reset")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.slash("boss Rhahk'Zor")
  c.leave()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.slash("boss Rhahk'Zor")
  check("split into a new run", c.history()[1] ~= nil and #c.run().bosses == 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("first run with pugs: how to set the partner")
do
  local c = fresh()
  c.party("Mirel", "A", "B", "C")
  c.enter("Deadmines", 36)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|60|500|0|0|0|0", c.run().serverStart))
  check("hint shown", anyPrinted(c, "If that's your duo partner, type /runbook partner Mirel"))
  c.slash("check")
  check("check lists who was heard", anyPrinted(c, "heard from: Mirel"))
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a 5-player group with a replaced member isn't a raid")
do
  local c = fresh()
  c.item(100, "Cruel Barb", 3, 5000)
  c.party("Mirel", "A", "B", "C")
  c.enter("Deadmines", 36)
  c.party("Mirel", "A", "B", "D")
  c.fire("GROUP_ROSTER_UPDATE")
  c.lootMsg("D", 100)
  check("pug blue still listed", c.liveText():find("Cruel Barb", 1, true) ~= nil, c.liveText())
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("check text, cap countdown, notes, quiet, clear, report")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.slash("check")
  check("no wing warning in a normal dungeon", not anyPrinted(c, "Wing unreadable"))
  check("run in progress named", anyPrinted(c, "Run in progress: Deadmines"))
  -- Over the cap: the countdown is to being under it again.
  c.leave()
  c.slash("cap 2")
  for i = 1, 3 do
    c.enter("Dungeon" .. i, 100 + i)
    c.tick(70)
    c.leave()
    c.tick(600)
  end
  local count, wait = c.ns.CapStatus()
  eq("4 entries", count, 4)
  local sorted = {}
  for _, t in ipairs(_G.VulcanRunBookDB.entries) do sorted[#sorted + 1] = t end
  table.sort(sorted)
  eq("wait until enough have aged out to be under the cap", wait, sorted[3] + 3600 - _G.GetServerTime())
  noErrors(c)
end

do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(70)
  c.slash("note " .. string.rep("word ", 30))
  c.leave()
  c.system("Deadmines has been reset.")
  local lines = c.ns.RunDetailLines(c.history()[1])
  local first
  for _, l in ipairs(lines) do if c.strip(l):find(": word", 1, true) then first = l end end
  check("note keeps its indent", first and first:sub(1, 2) == "  ", first)
  -- Quiet mode still shows the wing hint and /runbook new.
  c.slash("quiet")
  c.secret.uimap = true
  c.clearPrinted()
  c.enter("Scarlet Monastery", 189)
  c.tick(15)
  check("wing hint in quiet mode", anyPrinted(c, "can't be told apart"))
  c.slash("new yes")
  check("new in quiet mode says so", anyPrinted(c, "started over"))
  -- A report during a run says it's in progress.
  local rl = c.ns.ReportLines(c.run())
  check("in progress", rl[1]:find("(in progress).", 1, true) ~= nil, rl[1])
  noErrors(c)
end

os.exit(H.summary("tests_round4.lua") and 0 or 1)
