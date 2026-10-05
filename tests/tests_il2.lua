-- RunBook tests for improvement loop 2.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check, eq = H.check, H.eq

local function fresh(opts) local c = H.boot(opts) c.login() return c end
local function noErrors(...)
  local all = {}
  for _, c in ipairs({ ... }) do for _, e in ipairs(c.errors()) do all[#all + 1] = e end end
  check("no errors", #all == 0, table.concat(all, "; "))
end
local function anyPrinted(c, text)
  for _, p in ipairs(c.printed) do if c.strip(p):find(text, 1, true) then return true end end
  return false
end
local function names(run)
  local t = {}
  for _, b in ipairs(run.bosses) do t[#t + 1] = b.name end
  return table.concat(t, ",")
end
local function duoSolo(c) c.party("Mirel") c.slash("partner Mirel") end
local DM = { "Rhahk'Zor", "Sneed", "Gilnid", "Mr. Smite", "Captain Greenskin", "Edwin VanCleef" }

---------------------------------------------------------------------------
-- Best times
---------------------------------------------------------------------------
H.group("a clear that began after a break isn't a best time")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(5)
  for i, b in ipairs(DM) do c.tick(240) c.encounter(i, b) end
  c.leave() c.system("Deadmines has been reset.") c.tick(2)
  local _, firstT = c.ns.BestRun(c.ns.RunKey(c.history()[1]))
  -- 3 bosses, /runbook end, out for 5 minutes, back in the same copy for the last 3 (fast)
  c.enter("Deadmines", 36) c.tick(5)
  for i = 1, 3 do c.tick(200) c.encounter(i, DM[i]) end
  c.slash("end") c.leave() c.tick(300)
  c.clearPrinted()
  c.enter("Deadmines", 36) c.tick(5)
  for i = 4, 6 do c.tick(60) c.encounter(i, DM[i]) end
  c.leave() c.system("Deadmines has been reset.") c.tick(2)
  check("no new best said", not anyPrinted(c, "New best clear"))
  local _, bestT = c.ns.BestRun(c.ns.RunKey(c.history()[1]))
  eq("best is still the full clear", bestT, firstT)
  local leftover = c.history()[1]
  check("a clear, though", c.ns.ClearTime(leftover) ~= nil)
  local detail = table.concat(c.ns.RunDetailLines(leftover), "\n")
  check("details say it's not a best time", c.strip(detail):find("not a best time", 1, true) ~= nil)
  -- still not after it's kept only in short form
  check("short form keeps it", c.ns.LateRun(c.ns.Lite(leftover)))
  noErrors(c)
end

H.group("a route that skips bosses is a clear like any other")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(5)
  for i, b in ipairs(DM) do c.tick(240) c.encounter(i, b) end
  c.leave() c.system("Deadmines has been reset.") c.tick(2)
  -- a run that kills only the last two (a new copy)
  c.enter("Deadmines", 36) c.tick(5)
  c.tick(60) c.encounter(5, DM[5]) c.tick(60) c.encounter(6, DM[6])
  c.leave() c.system("Deadmines has been reset.") c.tick(2)
  local run = c.history()[1]
  local best, bestT = c.ns.BestRun(c.ns.RunKey(run))
  check("it's the best", best == run and bestT == c.ns.ClearTime(run))
  check("no 'not a best time'", not c.strip(table.concat(c.ns.RunDetailLines(run), "\n")):find("not a best time", 1,
    true))
  noErrors(c)
end

H.group("a report doesn't call a clear that began after a break a new best")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(5)
  for i, b in ipairs(DM) do c.tick(240) c.encounter(i, b) end
  c.leave() c.system("Deadmines has been reset.") c.tick(2)
  c.enter("Deadmines", 36) c.tick(5)
  for i = 1, 3 do c.tick(200) c.encounter(i, DM[i]) end
  c.slash("end") c.leave() c.tick(300)
  c.enter("Deadmines", 36) c.tick(5)
  for i = 4, 6 do c.tick(60) c.encounter(i, DM[i]) end
  local lines = c.ns.ReportLines(c.run())
  check("no new best", not lines[1]:find("new best", 1, true), lines[1])
  check("best shown", lines[1]:find("(best ", 1, true) ~= nil, lines[1])
  noErrors(c)
end

---------------------------------------------------------------------------
-- Sync
---------------------------------------------------------------------------
H.group("send results 5 and 9 are retried for a while, then dropped")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(3)
  c.addonResult = 5
  c.slash("note one")
  c.tick(1)
  eq("kept", c.ns.SyncQueueSize(), 1)
  c.tick(700)
  c.addonResult = 0
  local n = #c.addonSent
  c.tick(2)
  local note = false
  for i = n + 1, #c.addonSent do if c.addonSent[i].msg:find("^N3|") then note = true end end
  check("dropped after 10 minutes", not note)
  noErrors(c)
end

H.group("a kill or drop from before your run began isn't put in it")
do
  local c = fresh()
  duoSolo(c)
  c.item(5000, "Cruel Barb", 3, 5000)
  c.enter("Deadmines", 36) c.tick(100)
  local old = c.run()
  c.slash("new yes") c.tick(3)
  local new = c.run()
  check("started over", new ~= old and old.ended)
  local at = old.serverStart + 50
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|beef01.1|3|%d|%d|Gilnid", old.serverStart, at,
    old.serverStart))
  c.addonMsg("Mirel", string.format("D3|beef01|36|Deadmines||%d|5000|1|3|%d", old.serverStart, at))
  c.tick(2)
  eq("no kill in the new run", #new.bosses, 0)
  eq("no drop in the new run", #new.drops, 0)
  eq("the drop is in the old run", #old.drops, 1)
  -- one at the moment it began, or after, still goes in
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|beef01.3|5|%d|%d|Captain Greenskin", old.serverStart,
    new.serverStart, old.serverStart))
  c.tick(2)
  eq("a kill as it began goes in", names(new), "Captain Greenskin")
  local now = c.ns.ServerTime()
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|beef01.2|4|%d|%d|Mr. Smite", old.serverStart, now,
    old.serverStart))
  c.tick(2)
  eq("a later kill goes in", names(new), "Captain Greenskin,Mr. Smite")
  c.addonMsg("Mirel", string.format("D3|beef01|36|Deadmines||%d|5000|1|3|%d", old.serverStart, new.serverStart))
  c.tick(2)
  eq("a drop as it began goes in", #new.drops, 1)
  -- with no run of yours going then: dropped, as it would have been at once
  local d = fresh()
  duoSolo(d)
  d.item(5000, "Cruel Barb", 3, 5000)
  d.enter("Deadmines", 36) d.tick(10)
  local r = d.run()
  d.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|beef01.1|3|%d|%d|Gilnid", r.serverStart - 300,
    r.serverStart - 5, r.serverStart - 300))
  d.addonMsg("Mirel", string.format("D3|beef01|36|Deadmines||%d|5000|1|3|%d", r.serverStart - 300, r.serverStart - 5))
  d.tick(2)
  eq("no kill from before you came", #r.bosses, 0)
  eq("no drop from before you came", #r.drops, 0)
  noErrors(c, d)
end

H.group("a reset that doesn't move the kill can't loop")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(60)
  c.encounter(644, "Rhahk'Zor") c.tick(30)
  c.leave() c.tick(300)
  local real = c.ns.PartnerFoundReset
  c.ns.PartnerFoundReset = function() return c.ns.run end  -- (as if it moved nothing)
  local entry, now = c.ns.ServerTime() - 200, c.ns.ServerTime()
  local ok = pcall(c.addonMsg, "Mirel", string.format("B3|beef01|36|Deadmines||%d|beef01.1|644|%d|%d|Rhahk'Zor",
    entry, now, entry))
  c.ns.PartnerFoundReset = real
  check("no endless retry", ok)
end

H.group("a message for a run that ended before theirs began isn't put on it")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(100)
  c.slash("end") c.leave() c.tick(5)
  local saved = c.history()[1]
  c.tick(200)
  local theirs = saved.serverEnd + 100
  c.addonMsg("Mirel", string.format("N3|beef01|36|Deadmines||%d|1|pull left", theirs))
  c.tick(2)
  eq("no note on your ended run", #saved.notes, 0)
  noErrors(c)
end

---------------------------------------------------------------------------
-- Data and resources
---------------------------------------------------------------------------
H.group("the backup keeps every short-form run")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100) c.leave() c.tick(2)
  for i = 1, 550 do
    _G.VulcanRunBookDB.old[i] = { lite = true, name = "Deadmines", mapID = 36, diff = 1, serverStart = 1000 + i,
      startedAt = 1000 + i, elapsed = 100, bosses = {} }
  end
  c.ns.SaveBackup()
  eq("backup short-form runs", #_G.VulcanRunBookCharDB.mirror.old, 550)
  noErrors(c)
end

H.group("no bag scans outside a run")
do
  local c = fresh()
  local scans = 0
  local real = _G.C_Container.GetContainerNumSlots
  _G.C_Container.GetContainerNumSlots = function(...) scans = scans + 1 return real(...) end
  c.toBags(2589, 5) c.tick(3)
  eq("none in town", scans, 0)
  c.enter("Deadmines", 36) c.tick(3)
  local before = scans
  c.toBags(2589, 5) c.tick(3)
  check("scanned in a run", scans > before)
  _G.C_Container.GetContainerNumSlots = real
  noErrors(c)
end

---------------------------------------------------------------------------
-- The player's view
---------------------------------------------------------------------------
H.group("the live window's gold adds up")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(400)
  c.gainMoney(296)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|400|328|0|0|0|0|0", c.run().serverStart))
  c.tick(2)
  local t = c.strip(c.liveText())
  check("you", t:find("You: 3 silver", 1, true) ~= nil, t)
  check("Mirel", t:find("Mirel: 3 silver", 1, true) ~= nil, t)
  check("together", t:find("Together: 6 silver", 1, true) ~= nil, t)
  check("rates to the silver", not t:find("%d+c/hr"), t)
  -- a share under a silver: the total keeps its copper
  local d = fresh()
  duoSolo(d)
  d.enter("Deadmines", 36) d.tick(400)
  d.gainMoney(50)
  d.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|400|349|0|0|0|0|0", d.run().serverStart))
  d.tick(2)
  local u = d.strip(table.concat(d.ns.LiveLines(), "\n"))
  check("under a silver", u:find("Together: 3s 50c", 1, true) ~= nil, u)
  d.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|420|10000|0|0|0|0|0", d.run().serverStart))
  d.tick(2)
  u = d.strip(table.concat(d.ns.LiveLines(), "\n"))
  check("over a gold", u:find("Together: 1g 50c", 1, true) ~= nil, u)
  noErrors(c, d)
end

H.group("a partner's rate doesn't drift while you're both outside")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(600)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|600|20000|0|0|0|0|0", c.run().serverStart))
  c.leave() c.tick(2)
  local a = c.strip(table.concat(c.ns.LiveLines(), "\n"))
  c.tick(25)
  local b = c.strip(table.concat(c.ns.LiveLines(), "\n"))
  check("his rate as sent (2g in 10 min)", a:find("Mirel: 2g\n    12g/hr", 1, true) ~= nil, a)
  check("still, later", b:find("Mirel: 2g\n    12g/hr", 1, true) ~= nil, b)
  noErrors(c)
end

H.group("raid details don't list you as with yourself")
do
  local c = fresh()
  c.raid = true
  local g = { "Mirel" }
  for i = 1, 38 do g[#g + 1] = "Raider" .. i end
  c.party(unpack(g))
  c.slash("partner Mirel")
  c.enter("Molten Core", 409, { kind = "raid" }) c.tick(100)
  c.leave() c.tick(2)
  local run = c.run() or c.history()[1]
  local d = c.strip(table.concat(c.ns.RunDetailLines(run), "\n"))
  check("partner named", d:find("players, with Mirel", 1, true) ~= nil, d)
  check("not you", not d:find("with Tavlius", 1, true), d)
  noErrors(c)
end

H.group("report to party or raid checks you're in one")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100) c.encounter(644, "Rhahk'Zor")
  local sent = 0
  local real = c.ns.SendChat
  c.ns.SendChat = function() sent = sent + 1 end
  c.slash("report party")
  check("not in a party", anyPrinted(c, "You're not in a party."))
  c.slash("report raid")
  check("not in a raid", anyPrinted(c, "You're not in a raid."))
  eq("nothing sent", sent, 0)
  c.ns.SendChat = real
  noErrors(c)
end

H.group("a boss name typed in lowercase is capitalised")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100)
  c.slash("boss   captain greenskin  ")
  eq("capitalised", c.run().bosses[1].name, "Captain Greenskin")
  c.tick(30)
  c.slash("boss VanCleef")
  eq("other spellings kept", c.run().bosses[2].name, "VanCleef")
  noErrors(c)
end

H.group("delete asks first")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100) c.slash("end") c.leave() c.tick(2)
  local id = c.history()[1].id
  c.slash("delete " .. id)
  eq("kept after one", #c.history(), 1)
  check("says how", anyPrinted(c, "Type /runbook delete " .. id .. " again within 15 seconds"))
  c.tick(20)
  c.slash("delete " .. id)
  eq("asked again after 15 s", #c.history(), 1)
  c.slash("delete " .. id)
  eq("deleted on the second", #c.history(), 0)
  noErrors(c)
end

H.group("CSV cells that look like formulas stay text")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100)
  c.slash("boss =HYPERLINK(1)")
  c.slash("end") c.leave() c.tick(2)
  local lines = c.ns.ExportLines()
  check("prefixed", lines[2]:find(",'=HYPERLINK", 1, true) ~= nil, lines[2])
  noErrors(c)
end

H.group("no zero noise in details and stats")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100) c.encounter(644, "Rhahk'Zor") c.slash("end") c.leave() c.tick(2)
  local d = c.strip(table.concat(c.ns.RunDetailLines(c.history()[1]), "\n"))
  check("you: nothing", d:find("You: nothing", 1, true) ~= nil, d)
  local s = c.strip(table.concat(c.ns.DungeonLines(), "\n"))
  check("no deaths", s:find("no deaths", 1, true) ~= nil and not s:find("0.0 deaths", 1, true), s)
  noErrors(c)
end

---------------------------------------------------------------------------
-- Guards no test had seen fail (audit 1's mutations)
---------------------------------------------------------------------------
H.group("a partner's reset message long after you came back in doesn't split")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(60) c.encounter(644, "Rhahk'Zor") c.tick(30)
  c.leave() c.tick(60) c.enter("Deadmines", 36) c.tick(300)
  c.addonMsg("Mirel", "R3|beef01|Deadmines")
  c.tick(2)
  eq("no split", #c.history(), 0)
  -- (within 2 minutes of coming back in, it does: the message was late)
  local d = fresh()
  duoSolo(d)
  d.enter("Deadmines", 36) d.tick(60) d.encounter(644, "Rhahk'Zor") d.tick(30)
  d.leave() d.tick(60) d.enter("Deadmines", 36) d.tick(30)
  d.addonMsg("Mirel", "R3|beef01|Deadmines")
  d.tick(2)
  eq("split", #d.history(), 1)
  noErrors(c, d)
end

H.group("his split message doesn't pull items from an older split run")
do
  local c = fresh()
  duoSolo(c)
  c.item(500, "Blue Sword", 3, 100)
  c.enter("Deadmines", 36) c.tick(60) c.encounter(644, "Rhahk'Zor") c.tick(30)
  c.lootReal(500, 1) c.tick(5)
  local st0 = c.run().serverStart
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|beef01.1|645|%d|%d|Sneed", st0, c.ns.ServerTime(),
    st0))  -- (his kill: things of his can move by time)
  c.tick(5)
  c.leave() c.tick(60) c.enter("Deadmines", 36) c.tick(20)
  c.addonMsg("Mirel", "R3|beef01|Deadmines")  -- (late reset message: split at your return)
  c.tick(2)
  local split = c.history()[1]
  check("split", split and split.endReason == "split" and #split.drops == 1 and #split.bosses == 2)
  -- the new run is left empty and short; later a run of its own
  c.leave() c.system("Deadmines has been reset.") c.tick(600)
  c.enter("Deadmines", 36) c.tick(30)
  check("the split run is your last", c.ns.LastOwnRun() == split)
  local first = split.serverStart
  local before = #split.drops + #split.bosses
  c.addonMsg("Mirel", string.format("P3|beef01|36|Deadmines||%d|%d|", first + 1, c.ns.ServerTime()))
  c.tick(2)
  eq("the older run keeps its things", #split.drops + #split.bosses, before)
  noErrors(c)
end

H.group("his split message after a kill you saw this visit doesn't split")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(60)
  c.leave() c.tick(30) c.enter("Deadmines", 36) c.tick(60)
  c.encounter(644, "Rhahk'Zor") c.tick(5)
  local after = c.run().bosses[1].st
  c.tick(120)
  c.addonMsg("Mirel", string.format("P3|beef01|36|Deadmines||%d|%d|%d", c.ns.ServerTime() - 10, c.ns.ServerTime(),
    after))
  c.tick(2)
  eq("no split", #c.history(), 0)
  noErrors(c)
end

H.group("his fuller name for a kill you have takes over")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Blackrock Depths", 230) c.tick(60)
  local st, now = c.run().serverStart, c.ns.ServerTime()
  c.addonMsg("Mirel", string.format("B3|beef01|230|Blackrock Depths||%d|beef01.1|0|%d|%d|Roccor", st, now, st))
  c.tick(5)
  c.addonMsg("Mirel", string.format("B3|beef01|230|Blackrock Depths||%d|beef01.1|0|%d|%d|Lord Roccor", st, now, st))
  c.tick(2)
  eq("one kill, fuller name", names(c.run()), "Lord Roccor")
  noErrors(c)
end

H.group("his log split his earlier run: only what he made since you began counts")
do
  local c = fresh()
  duoSolo(c)
  c.tick(5)
  local F = c.ns.ServerTime() - 600
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|500|1000|0|0|0|0|0", F))
  c.tick(2)
  c.enter("Deadmines", 36) c.tick(2)
  local S = c.run().serverStart
  c.tick(60)
  -- his log split his run at N, half a minute before you came in: final word on F, then N
  local N = S - 30
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|530|600|0|0|0|1|0", F))
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|90|500|0|0|0|0|0", N))
  c.tick(2)
  eq("his gold in your run", c.ns.PartnerGold(c.run().partners.Mirel), 100)
  noErrors(c)
end

H.group("a drop for your ended run is taken only a few seconds after it ended")
do
  local c = fresh()
  duoSolo(c)
  c.item(5000, "Cruel Barb", 3, 5000)
  c.enter("Deadmines", 36) c.tick(100)
  local start = c.run().serverStart
  c.slash("end") c.leave() c.tick(10)
  local run = c.history()[1]
  c.addonMsg("Mirel", string.format("D3|beef01|36|Deadmines||%d|5000|1|3|%d", start, c.ns.ServerTime()))
  c.tick(1)
  eq("too late", #run.drops, 0)
  noErrors(c)
end

H.group("bare sync and auto show the setting")
do
  local c = fresh()
  c.slash("auto")
  check("auto unchanged", c.ns.DB.autoShow == true)
  check("auto shown", anyPrinted(c, "shows itself in dungeons: on. /runbook auto off"))
  c.slash("sync off")
  c.slash("sync")
  check("sync unchanged", c.ns.DB.sync == false)
  noErrors(c)
end

---------------------------------------------------------------------------
-- Audit cycle 2
---------------------------------------------------------------------------
H.group("details and the end line show gold as the live window does")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(300)
  c.gainMoney(25760)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|300|11060|0|0|0|0|0", c.run().serverStart))
  c.tick(2)
  local live = c.strip(table.concat(c.ns.LiveLines(), "\n"))
  check("live", live:find("You: 2g 58s", 1, true) and live:find("Together: 3g 69s", 1, true), live)
  c.clearPrinted()
  c.slash("end")
  check("end line", anyPrinted(c, "2g 58s, together 3g 69s"))
  local d = c.strip(table.concat(c.ns.RunDetailLines(c.history()[1]), "\n"))
  check("details", d:find("You: 2g 58s", 1, true) and d:find("Mirel: 1g 11s", 1, true)
    and d:find("Together: 3g 69s", 1, true), d)
  noErrors(c)
end

H.group("check doesn't compare with a partner's ended or old run")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(60) c.encounter(644, "Rhahk'Zor")
  local st = c.run().serverStart
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|60|0|0|0|0|1|6", st))
  c.clearPrinted() c.slash("check")
  check("his run ended", anyPrinted(c, "Mirel has no run here going"))
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|70|0|0|0|0|0|3", st))
  c.tick(120)
  c.clearPrinted() c.slash("check")
  check("old numbers", anyPrinted(c, "so they can differ") and not anyPrinted(c, "they differ: a kill"))
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|200|0|0|0|0|0|3", st))
  c.clearPrinted() c.slash("check")
  check("fresh numbers compared", anyPrinted(c, "they differ: a kill"))
  noErrors(c)
end

H.group("a damaged list of copies doesn't stop /runbook start")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100)
  c.slash("end")
  local s = c.savedCopy()
  s.char.copies = 5 s.char.manualEnded = nil
  local x = H.boot({ saved = s, gap = 30 })
  x.instance = { name = "Deadmines", map = 36, diff = 1, kind = "party", uiMap = 10036 }
  x.login() x.tick(3)
  x.slash("start")
  check("a run", x.run() ~= nil)
  noErrors(x)
end

---------------------------------------------------------------------------
-- Audit cycle 3
---------------------------------------------------------------------------
H.group("his kill from before you came in, after an inside split, has no time")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(70) c.encounter(1, "Rhahk'Zor", true, 30)
  c.tick(20) c.leave() c.tick(300)
  local srv = function() return c.ns.ServerTime() end
  local Te, Tk = srv() - 5, srv() + 60
  c.tick(65)
  c.enter("Deadmines", 36)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|beef01.1|1|%d|%d|Rhahk'Zor", Te, Tk, Te))
  c.tick(1)
  local b = c.run().bosses[1]
  check("split, his kill in", #c.history() == 1 and b and b.name == "Rhahk'Zor")
  check("no time of yours", b and b.untimed == true)
  noErrors(c)
end

H.group("rows and the Last line round gold as the details do")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(300)
  c.gainMoney(25760)
  c.slash("end") c.leave() c.tick(2)
  local row = c.strip(c.ns.RunRowText(c.history()[1]))
  check("row", row:find("2g 58s", 1, true) ~= nil, row)
  local live = c.strip(table.concat(c.ns.LiveLines(), "\n"))
  check("last line", live:find("2g 58s", 1, true) ~= nil, live)
  noErrors(c)
end

H.group("the coin and loot split adds up to the total")
do
  local c = fresh()
  c.item(2589, "Linen Cloth", 1, 50)
  c.enter("Deadmines", 36) c.tick(300)
  c.gainMoney(51)
  c.lootReal(2589, 4) c.tick(3)
  c.slash("end") c.leave() c.tick(2)
  local d = c.strip(table.concat(c.ns.RunDetailLines(c.history()[1]), "\n"))
  check("in silver", d:find("You: 3 silver (coin 1 silver, loot 2 silver)", 1, true) ~= nil, d)
  noErrors(c)
end

H.group("a note you write outside stays on your run when his kill shows a reset")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(70) c.encounter(1, "Rhahk'Zor", true, 30)
  c.tick(200) c.leave() c.tick(60)
  local Te = c.ns.ServerTime()
  c.tick(120)
  c.slash("note repairing - 2 greens sold")
  c.tick(60)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|beef01.1|1|%d|%d|Rhahk'Zor", Te,
    c.ns.ServerTime() - 2, Te))
  c.tick(1)
  local old = c.history()[1]
  check("note on the old run", old and #old.notes == 1)
  eq("not on the new one", #c.run().notes, 0)
  noErrors(c)
end

---------------------------------------------------------------------------
-- Audit cycle 4
---------------------------------------------------------------------------
H.group("his kill while you were out has no time, even if it arrives after you're back")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(5)
  for i = 1, 5 do c.tick(200) c.encounter(i, DM[i]) end
  local run = c.run()
  c.leave() c.tick(600)
  local Tk = c.ns.ServerTime()
  c.tick(5)
  c.enter("Deadmines", 36)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|beef01.9|6|%d|%d|Edwin VanCleef", run.serverStart, Tk,
    run.serverStart))
  c.tick(1)
  local b = run.bosses[#run.bosses]
  check("untimed", b.name == "Edwin VanCleef" and b.untimed == true)
  -- (one that died after you came back in is timed)
  c.tick(60)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|beef01.10|7|%d|%d|Mr. Smite Jr", run.serverStart,
    c.ns.ServerTime() - 2, run.serverStart))
  c.tick(1)
  check("timed after you're back", not run.bosses[#run.bosses].untimed)
  noErrors(c)
end

H.group("a note or report after his start-over while you're outside is for your last run")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(300) c.encounter(1, "Rhahk'Zor") c.tick(30) c.leave() c.tick(60)
  c.addonMsg("Mirel", string.format("X3|beef01|36|Deadmines||%d|1", c.ns.ServerTime() - 5))
  c.tick(1)
  check("a run you haven't gone into", c.run() and c.run().entryOnEntry)
  c.slash("note heading home")
  local last = c.history()[1]
  check("note on the last run", last and #last.notes == 1)
  local lines = c.ns.ReportLines()
  check("report on the last run", lines and lines[1]:find("Deadmines 6:00, 1 boss", 1, true) ~= nil, lines and lines[1])
  noErrors(c)
end

H.group("greens go to your partner even above your own quality setting")
do
  local c = H.boot({ name = "Mirel" }) c.login()
  c.party("Tavlius") c.slash("partner Tavlius")
  c.slash("quality 3")
  c.item(6000, "Green Thing", 2, 500)
  c.item(6001, "White Thing", 1, 5)
  c.enter("Deadmines", 36) c.tick(5)
  local n = #c.addonSent
  c.lootReal(6000, 1) c.tick(3)
  c.lootReal(6001, 1) c.tick(3)
  local d = 0
  for i = n + 1, #c.addonSent do if c.addonSent[i].msg:find("^D3") then d = d + 1 end end
  eq("the green is sent, not the white", d, 1)
  eq("not in his own log", #c.run().drops, 0)
  noErrors(c)
end

H.group("a damaged copy of the run you ended doesn't break the login")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100)
  c.slash("end")
  local s = c.savedCopy()
  s.char.manualEnded.savedServer = "x"
  s.char.manualEnded.bosses = 5
  local x = H.boot({ saved = s, gap = 30 })
  x.instance = { name = "Deadmines", map = 36, diff = 1, kind = "party", uiMap = 10036 }
  x.login() x.tick(3)
  check("live", pcall(x.ns.LiveLines))
  x.slash("start")
  check("reopened", x.run() ~= nil)
  noErrors(x)
end

---------------------------------------------------------------------------
-- Audit cycle 5
---------------------------------------------------------------------------
local function DiedOut(resOutside, minutes)
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(5)
  for i = 1, 2 do c.tick(200) c.encounter(i, DM[i]) end
  c.leave() c.tick(120) c.enter("Deadmines", 36) c.tick(5)  -- (a repair trip)
  for i = 3, 5 do c.tick(200) c.encounter(i, DM[i]) end
  local run = c.run()
  c.die() c.leave()
  if resOutside then c.dead = false end
  c.tick(minutes * 60)
  local Tk = c.ns.ServerTime()
  c.tick(5)
  c.enter("Deadmines", 36)
  c.dead = false
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|beef01.9|6|%d|%d|Edwin VanCleef", run.serverStart, Tk,
    run.serverStart))
  c.tick(1)
  return c, run.bosses[#run.bosses]
end

H.group("revived at the graveyard, or a long ghost run: his kill meanwhile has no time")
do
  local c, b = DiedOut(true, 8)
  check("revived outside", b.name == "Edwin VanCleef" and b.untimed == true)
  local d, e = DiedOut(false, 15)
  check("ghost past 10 minutes", e.untimed == true)
  local f, g = DiedOut(false, 5)
  check("a run back that counts is timed", not g.untimed)
  noErrors(c, d, f)
end

H.group("a reset after a graveyard revive is still found")
do
  local c = fresh()
  c.party("Mirel", "Pugleader")
  c.enter("Deadmines", 36) c.tick(5)
  c.tick(100) c.leave() c.tick(60) c.enter("Deadmines", 36) c.tick(5)
  for i = 1, 3 do c.tick(200) c.encounter(i, DM[i]) end
  c.die() c.leave()
  c.dead = false
  c.tick(300)
  c.enter("Deadmines", 36) c.tick(5)
  c.tick(200) c.encounter(1, DM[1])
  check("split", #c.history() == 1 and names(c.history()[1]) == "Rhahk'Zor,Sneed,Gilnid")
  eq("the new run has it", names(c.run()), "Rhahk'Zor")
  noErrors(c)
end

H.group("/runbook end on a run you never went into says why it isn't saved")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(300) c.encounter(1, "Rhahk'Zor") c.tick(30) c.leave() c.tick(60)
  c.addonMsg("Mirel", string.format("X3|beef01|36|Deadmines||%d|1", c.ns.ServerTime() - 5))
  c.tick(1)
  c.clearPrinted()
  c.slash("end")
  check("says so", anyPrinted(c, "you never went in, so it isn't saved"))
  noErrors(c)
end

---------------------------------------------------------------------------
-- Audit cycle 6
---------------------------------------------------------------------------
H.group("a ghost into another wing splits there, not at the last return")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Scarlet Monastery", 189, { uiMap = 303 }) c.tick(10)
  c.tick(200) c.encounter(31, "Houndmaster Loksey")
  c.leave() c.tick(120)
  c.enter("Scarlet Monastery", 189, { uiMap = 303 }) c.tick(10)
  c.tick(200) c.encounter(32, "Arcanist Doan")
  c.tick(30) c.die() c.tick(5)
  c.leave() c.tick(90)
  c.enter("Scarlet Monastery", 189, { uiMap = 304 }) c.dead = false
  c.tick(15)
  local lib = c.history()[1]
  eq("the Library run keeps both", lib and names(lib), "Houndmaster Loksey,Arcanist Doan")
  eq("the Armory run has none", #c.run().bosses, 0)
  check("short Armory clock", c.run().elapsed < 30, c.run().elapsed)
  noErrors(c)
end

H.group("unboss on a run you haven't gone into takes back from your last run")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(100) c.encounter(1, "Rhahk'Zor") c.tick(20)
  c.slash("boss Sneed") c.tick(20) c.leave() c.tick(60)
  c.addonMsg("Mirel", string.format("X3|beef01|36|Deadmines||%d|1", c.ns.ServerTime() - 5))
  c.tick(1)
  local now = c.ns.ServerTime()
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|beef01.1|1|%d|%d|Rhahk'Zor", now - 6, now, now - 6))
  c.tick(1)
  c.slash("unboss")
  eq("your last run", names(c.history()[1]), "Rhahk'Zor")
  eq("his kill kept", names(c.run()), "Rhahk'Zor")
  noErrors(c)
end

---------------------------------------------------------------------------
-- Audit cycle 7
---------------------------------------------------------------------------
H.group("a damaged kill in the saved copies doesn't break the next kills")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100) c.encounter(1, "Rhahk'Zor") c.tick(10)
  c.slash("end") c.leave() c.tick(60)
  local s = c.savedCopy()
  local k = s.char.copies[1].kills[1]
  k.anonymous, k.name, k.id = true, 5, nil
  local x = H.boot({ saved = s }) x.login()
  x.enter("Deadmines", 36) x.tick(100) x.encounter(2, "Sneed") x.tick(5)
  eq("the kill", x.run() and #x.run().bosses, 1)
  noErrors(x)
end

H.summary("tests_il2.lua")
