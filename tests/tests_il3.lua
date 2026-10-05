-- RunBook tests for improvement loop 3: the data's long life, sync over
-- reloads and realms, and behaviour no test had pinned down (found by a
-- mutation sweep).
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
local function duoSolo(c) c.party("Mirel") c.slash("partner Mirel") end
local function sent(c, kind)
  local t = {}
  for _, m in ipairs(c.addonSent) do if m.msg:sub(1, 1) == kind then t[#t + 1] = m.msg end end
  return t
end
-- n quick saved runs of Deadmines (one boss each), oldest first.
local function manyRuns(c, n)
  for _ = 1, n do
    c.enter("Deadmines", 36) c.tick(20) c.encounter(644, "Rhahk'Zor") c.tick(5)
    c.slash("end") c.leave() c.system("Deadmines has been reset.") c.tick(2)
  end
end

---------------------------------------------------------------------------
-- History over a long life
---------------------------------------------------------------------------
H.group("a short-form run can be deleted, and note or unboss on one says why not")
do
  local c = fresh()
  manyRuns(c, 3)
  local old = c.history()[3]
  local id = old.id
  -- (two more runs push it out of the full list)
  c.ns.HISTORY_MAX = 2
  manyRuns(c, 1)
  local inOld = false
  for _, r in ipairs(_G.VulcanRunBookDB.old) do if r.id == id then inOld = true end end
  check("now short form", inOld)
  local nOld = #_G.VulcanRunBookDB.old
  c.clearPrinted()
  c.slash("note #" .. id .. " hi")
  check("note explains", anyPrinted(c, "kept in short form"))
  c.slash("unboss #" .. id)
  check("unboss explains", anyPrinted(c, "can be deleted (/runbook delete " .. id .. ")"))
  c.slash("delete " .. id .. " yes")
  eq("deleted", #_G.VulcanRunBookDB.old, nOld - 1)
  noErrors(c)
end

H.group("the Dungeons tab shows the best run's number")
do
  local c = fresh()
  manyRuns(c, 2)
  local best = c.ns.BestRun(c.ns.RunKey(c.history()[1]))
  local s = c.strip(table.concat(c.ns.DungeonLines(), "\n"))
  check("number", s:find("(#" .. best.id .. ")", 1, true) ~= nil, s)
  noErrors(c)
end

H.group("a failed account load says what the backup brought back, each time")
do
  local c = fresh()
  manyRuns(c, 3)
  for i = 1, 4 do
    _G.VulcanRunBookDB.old[i] = { lite = true, name = "Deadmines", mapID = 36, diff = 1, serverStart = 1000 + i,
      startedAt = 1000 + i, elapsed = 100, bosses = {}, id = 100 + i, char = "Tavlius-Realm" }
  end
  c.ns.SaveBackup()
  local s1 = c.savedCopy(true)    -- (the account file didn't load)
  local x = H.boot({ saved = s1 }) x.login()
  check("both kinds counted", anyPrinted(x, "3 runs restored (and 4 older ones in short form)"))
  eq("all short-form runs back", #_G.VulcanRunBookDB.old, 4)
  local s2 = x.savedCopy(false)   -- (a good load)
  local y = H.boot({ saved = s2 }) y.login()
  check("no notice on a good load", not anyPrinted(y, "backup was used"))
  local s3 = y.savedCopy(true)    -- (it fails again)
  local z = H.boot({ saved = s3 }) z.login()
  check("told again", anyPrinted(z, "backup was used"))
  noErrors(x, y, z)
end

H.group("an old run ending at login goes into short form in order, and says so")
do
  local c = fresh()
  c.ns.HISTORY_MAX = 1
  manyRuns(c, 3)                   -- (one in full, two in short form)
  c.enter("Deadmines", 36) c.tick(70)
  c.run().startedAt = _G.VulcanRunBookDB.old[1].startedAt - 1   -- (older than one of them: an alt's run from long ago)
  c.clearPrinted()
  c.slash("end")
  check("says so", anyPrinted(c, "kept in short form"))
  local old = _G.VulcanRunBookDB.old
  local sorted = true
  for i = 2, #old do if (old[i - 1].startedAt or 0) < (old[i].startedAt or 0) then sorted = false end end
  check("short form newest first", sorted and #old == 3)
  noErrors(c)
end

H.group("the same name on two realms is two characters, shown with the realm")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(70) c.slash("end") c.leave() c.tick(2)
  local s = c.savedCopy()
  local d = H.boot({ saved = s }) d.realm = "Dreamforge" d.login()
  d.enter("Deadmines", 36) d.tick(70) d.slash("end") d.leave() d.tick(2)
  eq("two characters", d.ns.CharacterCount(), 2)
  local row = d.strip(d.ns.RunRowText(d.history()[1]))
  check("row shows the realm", row:find("Tavlius-Dream", 1, true) ~= nil, row)
  noErrors(d)
end

H.group("short-form partner gold follows the price setting")
do
  local c = fresh()
  local run = { coin = 0, loot = 0, lootAH = 0, partners = { Mirel = { coin = 100, loot = 50, lootAH = 5000 } },
    bosses = {}, drops = {}, deaths = {}, wipes = {}, notes = {}, elapsed = 100 }
  local lite = c.ns.Lite(run)
  c.slash("price vendor")
  eq("vendor", c.ns.PartnersGold(lite), 150)
  c.slash("price ah")
  eq("auction", c.ns.PartnersGold(lite), 5100)
  noErrors(c)
end

H.group("deletions are kept, however old the run; past the cap the oldest deletions go")
do
  local c = fresh()
  manyRuns(c, 2)
  local db = _G.VulcanRunBookDB
  db.deleted["10:Tavlius-Realm:Deadmines"] = 5   -- (an old run, deleted a while ago)
  for i = 1, c.ns.OLD_MAX do
    db.old[i] = { lite = true, name = "Deadmines", serverStart = 100000 - i, startedAt = 100000 - i, bosses = {} }
  end
  c.ns.DeleteRun(1)
  check("an old run's deletion stays with the list full", db.deleted["10:Tavlius-Realm:Deadmines"] ~= nil)
  for i = 1, c.ns.DELETED_MAX do db.deleted["x" .. i] = 50 end
  db.deleted["new"] = c.ns.ServerTime() - 10
  local uid = c.ns.RunUID(c.history()[1])
  c.ns.DeleteRun(1)
  check("the oldest deletion goes past the cap", db.deleted["10:Tavlius-Realm:Deadmines"] == nil)
  check("recent ones stay", db.deleted["new"] ~= nil and db.deleted[uid] ~= nil)
  noErrors(c)
end

---------------------------------------------------------------------------
-- Sync
---------------------------------------------------------------------------
H.group("messages that couldn't go out are sent after a /reload")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(5)
  c.addonResult = 3                 -- (throttled)
  c.slash("note one") c.slash("note two")
  c.fire("PLAYER_LOGOUT")
  local s = c.savedCopy()
  check("saved", type(s.char.syncQueue) == "table" and #s.char.syncQueue >= 2)
  local x = H.boot({ saved = s, gap = 5 })
  x.instance = { name = "Deadmines", map = 36, diff = 1, kind = "party", uiMap = 10036 }
  x.party("Mirel")
  x.login() x.tick(3)
  local notes = sent(x, "N")
  check("sent after", #notes >= 2 and notes[1]:find("one", 1, true) and notes[2]:find("two", 1, true))
  -- (too old by the next login: dropped)
  x.addonResult = 3
  x.slash("note three")
  x.fire("PLAYER_LOGOUT")
  local s2 = x.savedCopy()
  local y = H.boot({ saved = s2, gap = 900 })
  y.party("Mirel")
  y.login() y.tick(3)
  check("not after 10 minutes", #sent(y, "N") == 0)
  noErrors(x, y)
end

H.group("messages wait out a short break in the group")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(5)
  c.addonResult = 3
  c.slash("note one")
  c.party() c.tick(5)
  eq("kept", c.ns.SyncQueueSize() > 0, true)
  c.addonResult = 0
  c.party("Mirel") c.tick(2)
  check("sent once back", #sent(c, "N") == 1)
  noErrors(c)
end

H.group("a drop looted before your run ended counts, even arriving late")
do
  local c = fresh()
  duoSolo(c)
  c.item(5000, "Cruel Barb", 3, 5000)
  c.enter("Deadmines", 36) c.tick(100)
  local st = c.run().serverStart
  local looted = c.ns.ServerTime() - 1
  c.slash("end") c.leave() c.tick(20)
  local run = c.history()[1]
  c.addonMsg("Mirel", string.format("D3|beef01|36|Deadmines||%d|5000|1|3|%d", st, looted))
  eq("counted", #run.drops, 1)
  c.addonMsg("Mirel", string.format("D3|beef01|36|Deadmines||%d|5000|1|3|%d", st, c.ns.ServerTime()))
  eq("one looted after: not", #run.drops, 1)
  noErrors(c)
end

H.group("a same-name player on another realm isn't your partner")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel-Realm")
  c.enter("Deadmines", 36) c.tick(5)
  local st = c.run().serverStart
  c.party("Mirel", "Mirel-Other")
  c.addonMsg("Mirel-Other", string.format("S3|cafe01|36|Deadmines||%d|10|70000|0|0|0|0|0", st - 10))
  c.addonMsg("Mirel-Realm", string.format("S3|beef01|36|Deadmines||%d|10|5000|0|0|0|0|0", st))
  c.tick(1)
  eq("only his gold", c.ns.PartnerGold(c.run().partners.Mirel), 5000)
  eq("and only his in Together", c.ns.PartnersGold(c.run()), 5000)
  noErrors(c)
end

H.group("check finds your partner whatever the case of the name")
do
  local c = fresh()
  c.slash("partner élan")           -- (set before grouping: kept as typed)
  c.party("Élan")
  c.enter("Deadmines", 36) c.tick(5)
  c.addonMsg("Élan", string.format("S3|beef01|36|Deadmines||%d|10|0|0|0|0|0|0", c.run().serverStart))
  c.clearPrinted() c.slash("check")
  check("heard", not anyPrinted(c, "none this session"))
  check("kills line", anyPrinted(c, "Kills this run"))
  noErrors(c)
end

H.group("a partner's kill is timed when it died, not when the message came")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(100)
  local st = c.run().serverStart
  local died = c.ns.ServerTime()
  c.tick(30)                         -- (held up 30 s)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|beef01.1|644|%d|%d|Rhahk'Zor", st, died, st))
  local b = c.run().bosses[1]
  check("its time", b and math.abs(b.t - 100) <= 2, b and b.t)
  noErrors(c)
end

---------------------------------------------------------------------------
-- Behaviour the mutation sweep found untested
---------------------------------------------------------------------------
H.group("your repeat kill that shows a reset tells your partner to split")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(60) c.encounter(644, "Rhahk'Zor") c.tick(30)
  c.leave() c.tick(60) c.enter("Deadmines", 36) c.tick(30)
  local n = #sent(c, "P")
  c.encounter(644, "Rhahk'Zor")
  c.tick(2)
  check("split message", #sent(c, "P") == n + 1)
  -- (and one that died before this run began: back in after /runbook end)
  local d = fresh()
  duoSolo(d)
  d.enter("Deadmines", 36) d.tick(60) d.encounter(644, "Rhahk'Zor") d.tick(30)
  d.slash("end") d.leave() d.tick(60) d.enter("Deadmines", 36) d.tick(30)
  local m = #sent(d, "P")
  d.encounter(644, "Rhahk'Zor") d.tick(2)
  check("split message, copy kill", #sent(d, "P") == m + 1)
  noErrors(c, d)
end

H.group("what died here before is kept over a second /runbook end")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(60) c.encounter(644, "Rhahk'Zor") c.tick(30)
  c.slash("end") c.leave() c.tick(60)
  c.enter("Deadmines", 36) c.tick(30)
  c.slash("end") c.leave() c.tick(60)
  c.enter("Deadmines", 36) c.tick(30)
  check("still known", c.run().copyKills and #c.run().copyKills == 1)
  noErrors(c)
end

H.group("your notes aren't cut short")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(5)
  local text = string.rep("word ", 30)
  c.slash("note " .. text)
  eq("whole", c.run().notes[1].text, (text:gsub("%s+$", "")))
  noErrors(c)
end

H.group("your partner's kill keeps its boss id")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(5)
  local st = c.run().serverStart
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|beef01.1|644|%d|%d|Rhahk'Zor", st, c.ns.ServerTime(),
    st))
  eq("id", c.run().bosses[1] and c.run().bosses[1].id, 644)
  noErrors(c)
end

H.group("the short form has no notes or drop list")
do
  local c = fresh()
  c.item(5000, "Cruel Barb", 3, 5000)
  c.enter("Deadmines", 36) c.tick(60) c.lootReal(5000, 1) c.tick(3) c.slash("note hi")
  local lite = c.ns.Lite(c.run())
  check("short", lite.lite and lite.notes == nil and lite.drops == nil and lite.blues == 1)
  noErrors(c)
end

H.group("deleting another run doesn't stop /runbook start")
do
  local c = fresh()
  manyRuns(c, 2)
  c.enter("Deadmines", 36) c.tick(70)
  c.slash("end")
  c.slash("delete " .. c.history()[2].id .. " yes")
  c.slash("start")
  check("reopened", c.run() ~= nil and #c.history() == 1)
  noErrors(c)
end

H.group("/runbook end then /runbook new starts cleanly")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(70)
  c.slash("end") c.slash("new yes")
  check("a run", c.run() ~= nil)
  check("nothing held", _G.VulcanRunBookCharDB.suppress == nil and _G.VulcanRunBookCharDB.manualEnded == nil)
  noErrors(c)
end

H.group("long notes in the details keep every word")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(70)
  local words = {}
  for i = 1, 40 do words[i] = "w" .. i end
  c.slash("note " .. table.concat(words, " "))
  c.slash("end") c.leave() c.tick(2)
  local d = c.strip(table.concat(c.ns.RunDetailLines(c.history()[1]), " "))
  local all = true
  for i = 1, 40 do if not d:find("w" .. i .. "%f[%W]") then all = false end end
  check("all 40", all, d)
  noErrors(c)
end

H.group("details say how a run ended")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(70) c.slash("end") c.leave() c.tick(2)
  local d = c.strip(table.concat(c.ns.RunDetailLines(c.history()[1]), "\n"))
  check("by hand", d:find("ended by hand", 1, true) and not d:find("away", 1, true), d)
  c.enter("Deadmines", 36) c.tick(70)
  local e = c.strip(table.concat(c.ns.RunDetailLines(c.run()), "\n"))
  check("in progress", e:find("in progress", 1, true) ~= nil, e)
  noErrors(c)
end

H.group("the CSV has your partner's gold and the minutes")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(600)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|600|12345|0|0|0|0|0", c.run().serverStart))
  c.slash("end") c.leave() c.tick(2)
  local line = c.ns.ExportLines()[2]
  check("minutes", line:find(",10.0,", 1, true) ~= nil, line)
  local col
  local i = 0
  for name in c.ns.CSV_HEADER:gmatch("[^,]+") do i = i + 1 if name == "partner_gold_copper" then col = i end end
  local fields = {}
  for v in (line .. ","):gmatch("([^,]*),") do fields[#fields + 1] = v end
  eq("partner gold", fields[col], "12345")
  noErrors(c)
end

H.group("rates only after 5 minutes; XP per hour shown")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(200)
  c.gainMoney(5000) c.gainXP(300) c.tick(1)
  local t = c.strip(table.concat(c.ns.LiveLines(), "\n"))
  check("no rate yet", not t:find("/hr", 1, true), t)
  c.tick(200)
  t = c.strip(table.concat(c.ns.LiveLines(), "\n"))
  check("gold rate", t:find("/hr", 1, true) ~= nil, t)
  check("XP rate", t:find("XP/hr", 1, true) ~= nil, t)
  noErrors(c)
end

H.group("a short run with only a note, or only a copper, is kept")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(20) c.slash("note quick one") c.slash("end") c.leave() c.tick(2)
  eq("note run kept", #c.history(), 1)
  c.enter("Deadmines", 36) c.tick(20) c.gainMoney(1) c.slash("end") c.leave() c.tick(2)
  eq("copper run kept", #c.history(), 2)
  c.enter("Deadmines", 36) c.tick(20) c.encounter(644, "Rhahk'Zor") c.slash("end") c.leave() c.tick(2)
  eq("boss run kept", #c.history(), 3)
  noErrors(c)
end

H.group("dying outside isn't a death in the run")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(20) c.leave() c.tick(5)
  c.die() c.tick(2)
  eq("no death", #c.run().deaths, 0)
  local d = fresh()
  d.die() d.tick(2)
  noErrors(c, d)
end

H.group("someone who joins mid-run is in the group list")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36) c.tick(20)
  c.party("Mirel", "Healbot")
  c.tick(2)
  local has = false
  for _, m in ipairs(c.run().members) do if m == "Healbot" then has = true end end
  check("listed", has)
  noErrors(c)
end

H.group("report takes the channel in any case")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36) c.tick(60) c.encounter(644, "Rhahk'Zor")
  local n = 0
  local real = c.ns.SendChat
  c.ns.SendChat = function() n = n + 1 end
  c.slash("report PARTY")
  c.ns.SendChat = real
  check("sent", n > 0)
  noErrors(c)
end

H.group("/runbook end says the run ended, nothing else")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(70)
  c.clearPrinted()
  c.slash("end")
  check("no 'no run'", not anyPrinted(c, "No run in progress"))
  noErrors(c)
end

H.group("no zero counts on rows or in stats")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(70) c.encounter(644, "Rhahk'Zor") c.slash("end") c.leave() c.tick(2)
  local row = c.strip(c.ns.RunRowText(c.history()[1]))
  check("no 0 blues", not row:find("0 blue", 1, true), row)
  local s = c.strip(table.concat(c.ns.DungeonLines(), "\n"))
  check("no 0 wipes", not s:find("0 wipe", 1, true), s)
  noErrors(c)
end

H.group("a newer stats update replaces the waiting one")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(5)
  c.addonResult = 11
  c.gainMoney(10) c.tick(1)
  c.gainMoney(10) c.tick(1)
  local n = 0
  c.addonResult = 0
  local before = #c.addonSent
  c.tick(1)
  for i = before + 1, #c.addonSent do if c.addonSent[i].msg:find("^S3") then n = n + 1 end end
  eq("one stats message", n, 1)
  check("the latest", c.addonSent[#c.addonSent].msg:find("|%d+|20|0|0|0|0|%d+$") ~= nil, c.addonSent[#c.addonSent].msg)
  noErrors(c)
end

---------------------------------------------------------------------------
-- Audit cycle 1
---------------------------------------------------------------------------
H.group("short-form runs are numbered apart from full ones at load")
do
  local c = fresh()
  manyRuns(c, 2)
  local s = c.savedCopy()
  s.db.old[1] = { lite = true, name = "Deadmines", mapID = 36, diff = 1, serverStart = 5, startedAt = 5, elapsed = 100,
    bosses = {}, id = s.db.history[1].id, char = "Tavlius-Realm" }
  local x = H.boot({ saved = s }) x.login()
  local seen, clash = {}, false
  for _, list in ipairs({ _G.VulcanRunBookDB.history, _G.VulcanRunBookDB.old }) do
    for _, r in ipairs(list) do
      if seen[r.id] then clash = true end
      seen[r.id] = true
    end
  end
  check("no two runs share a number", not clash)
  noErrors(x)
end

H.group("a run too old to keep says it isn't saved")
do
  local c = fresh()
  c.ns.HISTORY_MAX, c.ns.OLD_MAX = 1, 1
  manyRuns(c, 3)
  c.enter("Deadmines", 36) c.tick(5) c.encounter(644, "Rhahk'Zor", true, 3)   -- (a fast clear...)
  c.run().startedAt = 1                                                      -- (...from long ago)
  c.clearPrinted()
  c.slash("end")
  check("says so", anyPrinted(c, "Older than every run kept, so it isn't saved."))
  check("not a new best", not anyPrinted(c, "New best clear"))
  noErrors(c)
end

H.group("a partner drop looted after your run ended isn't put on it")
do
  local c = fresh()
  duoSolo(c)
  c.item(5000, "Cruel Barb", 3, 5000)
  c.enter("Deadmines", 36) c.tick(70)
  local st = c.run().serverStart
  c.slash("end") c.leave() c.tick(1)
  local run = c.history()[1]
  c.addonMsg("Mirel", string.format("D3|beef01|36|Deadmines||%d|5000|1|3|%d", st, run.serverEnd + 3))
  eq("not on it", #run.drops, 0)
  noErrors(c)
end

H.group("a damaged deleted list doesn't stop the load")
do
  local c = fresh()
  manyRuns(c, 1)
  local s = c.savedCopy()
  for i = 1, 5010 do s.db.deleted[i .. ":x:y"] = true end
  s.db.deleted[7] = true
  local x = H.boot({ saved = s }) x.login()
  check("loaded", x.ns.DB and _G.VulcanRunBookDB.nextId > 1)
  noErrors(x)
end

---------------------------------------------------------------------------
-- Audit cycle 4
---------------------------------------------------------------------------
H.group("clear yes asks again when it would clear more than one character")
do
  local c = fresh()
  manyRuns(c, 1)
  local s = c.savedCopy()
  local a = H.boot({ saved = s, name = "Alt" }) a.login()
  manyRuns(a, 1)
  a.clearPrinted()
  a.slash("clear yes")
  eq("not yet", #_G.VulcanRunBookDB.history, 2)
  check("asks", anyPrinted(a, "for all 2 of your characters. Type /runbook clear yes again"))
  a.slash("clear yes")
  eq("cleared", #_G.VulcanRunBookDB.history, 0)
  check("says so", anyPrinted(a, "for all 2 characters"))
  noErrors(a)
end

H.group("history rates round as the live window does")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(568)
  c.gainMoney(5000)
  local live = c.strip(table.concat(c.ns.LiveLines(), "\n")):match("(%d[%dgsc ]*)/hr")
  c.slash("end") c.leave() c.tick(2)
  local d = c.strip(table.concat(c.ns.RunDetailLines(c.history()[1]), "\n"))
  check("same rate", live and d:find(live .. "/hr", 1, true) ~= nil, tostring(live) .. " | " .. d)
  noErrors(c)
end

---------------------------------------------------------------------------
-- Audit cycle 5
---------------------------------------------------------------------------
H.group("your gold rate is the same live, in the details and in the Dungeons tab")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(1800)
  c.gainMoney(12345)
  local live = c.strip(table.concat(c.ns.LiveLines(), "\n")):match("(%d[%dgsc ]*)/hr")
  local d = c.strip(table.concat(c.ns.RunDetailLines(c.run()), "\n"))
  check("details", live and d:find(live .. "/hr", 1, true) ~= nil, tostring(live) .. " | " .. d)
  c.slash("end") c.leave() c.tick(2)
  local s = c.strip(table.concat(c.ns.DungeonLines(), "\n"))
  check("Dungeons tab", live and s:find(live .. "/hr", 1, true) ~= nil, tostring(live) .. " | " .. s)
  noErrors(c)
end

H.group("with two characters, clear then clear yes does it")
do
  local c = fresh()
  manyRuns(c, 1)
  local sv = c.savedCopy()
  local a = H.boot({ saved = sv, name = "Alt" }) a.login()
  manyRuns(a, 1)
  a.clearPrinted()
  a.slash("clear")
  check("says within 15 seconds", anyPrinted(a, "Type /runbook clear yes within 15 seconds to confirm."))
  a.slash("clear yes")
  eq("cleared", #_G.VulcanRunBookDB.history, 0)
  noErrors(a)
end

H.group("your partner's kill while you ran back keeps its time, on your first visit too")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(300)
  local run = c.run()
  c.die() c.tick(3) c.leave() c.tick(30)
  local Tk = c.ns.ServerTime()
  c.tick(5)
  c.enter("Deadmines", 36) c.dead = false
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|beef01.9|6|%d|%d|Edwin VanCleef", run.serverStart, Tk,
    run.serverStart))
  c.tick(1)
  local b = run.bosses[#run.bosses]
  check("timed", b and not b.untimed, b and tostring(b.untimed))
  noErrors(c)
end

---------------------------------------------------------------------------
-- Audit cycle 6
---------------------------------------------------------------------------
H.group("a reset while you were dead outside is found after a ghost return")
do
  for _, second in ipairs({ false, true }) do
    local c = fresh()
    c.enter("Deadmines", 36) c.tick(60)
    if second then c.leave() c.tick(60) c.enter("Deadmines", 36) c.tick(30) end
    c.encounter(644, "Rhahk'Zor", true, 20) c.tick(60)
    c.die() c.tick(5) c.leave() c.tick(60)       -- (released; the copy is reset meanwhile)
    c.enter("Deadmines", 36) c.dead = false c.tick(60)
    c.encounter(644, "Rhahk'Zor", true, 20) c.tick(30)
    local tag = second and "after an earlier trip: " or "first visit: "
    eq(tag .. "split", #c.history(), 1)
    check(tag .. "the new run has the kill", c.run() and #c.run().bosses == 1)
    noErrors(c)
  end
  -- (a ghost return into the same copy: a boss killed after it is a new kill, nothing splits)
  local d = fresh()
  d.enter("Deadmines", 36) d.tick(60)
  d.encounter(644, "Rhahk'Zor", true, 20) d.tick(30)
  d.die() d.tick(5) d.leave() d.tick(60)
  d.enter("Deadmines", 36) d.dead = false d.tick(30)
  d.encounter(645, "Sneed", true, 20) d.tick(5)
  d.encounter(645, "Sneed", true, 1) d.tick(5)   -- (the same kill reported twice)
  eq("no split", #d.history(), 0)
  eq("two kills", #d.run().bosses, 2)
  noErrors(d)
end

H.group("his late reset message after your ghost return splits there")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(60)
  c.encounter(644, "Rhahk'Zor", true, 20) c.tick(60)
  c.die() c.tick(5) c.leave() c.tick(60)
  c.enter("Deadmines", 36)
  c.addonMsg("Mirel", "R3|beef01|Deadmines")
  c.dead = false c.tick(5)
  eq("split on the message alone", #c.history(), 1)
  check("said why", anyPrinted(c, "reset just before you went back in"))
  c.tick(55)
  c.encounter(645, "Sneed", true, 20) c.tick(30)
  check("next kill in the new run", c.run() and #c.run().bosses == 1 and #c.history() == 1)
  noErrors(c)
end

H.group("his repeat kill or split after your ghost return splits there")
do
  for _, kind in ipairs({ "B", "P" }) do
    local c = fresh()
    duoSolo(c)
    c.enter("Deadmines", 36) c.tick(60)
    c.encounter(644, "Rhahk'Zor", true, 20) c.tick(5)
    local first = c.ns.ServerTime() - 5
    c.tick(55)
    c.die() c.tick(5) c.leave() c.tick(60)
    c.enter("Deadmines", 36) c.dead = false c.tick(90)
    local now = c.ns.ServerTime()
    if kind == "B" then
      c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|beef01.1|644|%d|%d|Rhahk'Zor",
        c.run().serverStart, now - 20, now))
    else
      c.addonMsg("Mirel", string.format("P3|beef01|36|Deadmines||%d|%d|%d", now - 85, now, first))
    end
    c.tick(5)
    eq(kind .. ": split", #c.history(), 1)
    check(kind .. ": the old run keeps the first kill", #c.history()[1].bosses == 1)
    noErrors(c)
  end
end

---------------------------------------------------------------------------
-- Audit cycle 7
---------------------------------------------------------------------------
local MC = { { 663, "Lucifron" }, { 664, "Magmadar" }, { 665, "Gehennas" }, { 666, "Garr" }, { 672, "Ragnaros" } }
local function entriesSince(t)
  local n = 0
  for _, e in ipairs(_G.VulcanRunBookDB.entries) do if e >= t then n = n + 1 end end
  return n
end
local function raidNight(c, from, to, gap)
  c.enter("Molten Core", 409, { kind = "raid" })
  for i = from, to do c.tick(gap) c.encounter(MC[i][1], MC[i][2], true, 60) end
  c.tick(60) c.leave() c.tick(80, 100)  -- (times out after 2 hours outside)
end

H.group("a raid week over two nights: the second night carries on in the saved raid")
do
  for _, weekly in ipairs({ true, false }) do
    local c = fresh({ noWeekly = not weekly })
    c.weeklyAt = c.wall + c.serverOffset - 3600  -- (the weekly reset was an hour ago)
    raidNight(c, 1, 5, 1500)
    c.tick(1, 7 * 86400)
    raidNight(c, 1, 5, 1500)
    local key = c.ns.RunKey(c.history()[1])
    local _, before = c.ns.BestRun(key)
    c.tick(1, 7 * 86400)
    raidNight(c, 1, 3, 1500)
    c.tick(1, 86400)                     -- (the next night: no weekly reset in between)
    local e0 = c.ns.ServerTime()
    raidNight(c, 4, 5, 900)
    local _, after = c.ns.BestRun(key)
    local night2 = c.history()[1]
    if weekly then
      eq("no new cap entry", entriesSince(e0), 0)
      check("night 2 is late", c.ns.LateRun(night2))
      eq("the best clear stays", after, before)
      check("no 'new best'", not anyPrinted(c, "New best clear"))
    else
      -- (Without the game's weekly reset time it can't tell: the documented limit.)
      check("without it: a fresh-looking run", not c.ns.LateRun(night2))
    end
    noErrors(c)
  end
  -- After the weekly reset the raid is fresh again.
  local c = fresh()
  c.weeklyAt = c.wall + c.serverOffset - 3600
  raidNight(c, 1, 3, 1500)
  c.tick(1, 7 * 86400)
  local e0 = c.ns.ServerTime()
  raidNight(c, 1, 2, 900)
  eq("after the weekly reset: a new instance", entriesSince(e0), 1)
  check("and not late", not c.ns.LateRun(c.history()[1]))
  noErrors(c)
end

H.group("unboss of a mark that split the run takes back its cap entry")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(60)
  c.slash("boss Sneed") c.tick(60)
  c.leave() c.tick(120) c.enter("Deadmines", 36) c.tick(60)
  local e0 = #_G.VulcanRunBookDB.entries
  c.slash("boss Sneed")                 -- (meant Gilnid)
  c.tick(5)
  eq("the split counted a new instance", #_G.VulcanRunBookDB.entries - e0, 1)
  c.slash("unboss")
  eq("taken back", #_G.VulcanRunBookDB.entries - e0, 0)
  check("said so", anyPrinted(c, "counted this run as a new instance"))
  noErrors(c)
end

H.group("CSV: a cell starting with '-' stays text unless it's a plain number")
do
  local c = fresh()
  local function cell(v)
    return c.ns.CSVRow({ partners = {}, bosses = { { name = v, untimed = true } }, notes = {}, drops = {}, elapsed = 0,
      coin = 0, loot = 0, lootAH = 0, xp = 0, wipes = {}, deaths = {} })
  end
  check("formula quoted", cell('-1+WEBSERVICE("x")'):find("'%-1%+WEBSERVICE") ~= nil, cell('-1+WEBSERVICE("x")'))
  check("-cmd quoted", cell("-cmd|x"):find("'%-cmd") ~= nil)
  check("a negative number stays a number", cell("-12"):find(",%-12,") ~= nil, cell("-12"))
  noErrors(c)
end

H.group("a repair trip, then a ghost return into a reset copy: the run splits again there")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(120)
  c.encounter(644, "Rhahk'Zor", true, 20) c.tick(60)
  c.leave() c.tick(300) c.enter("Deadmines", 36) c.tick(120)  -- (repairs)
  c.encounter(645, "Sneed", true, 20) c.tick(120)
  c.die() c.tick(5) c.leave() c.tick(90)                      -- (wipe; reset)
  c.enter("Deadmines", 36) c.dead = false c.tick(60)
  c.slash("note new copy") c.tick(60)
  c.encounter(644, "Rhahk'Zor", true, 20) c.tick(120)
  eq("split at the trip alive", #c.history(), 1)
  c.encounter(645, "Sneed", true, 20) c.tick(30)
  eq("Sneed killed again splits at the ghost return", #c.history(), 2)
  local r = c.run()
  eq("the new copy's run has both", #r.bosses, 2)
  eq("Rhahk'Zor's time in it", r.bosses[1] and r.bosses[1].name, "Rhahk'Zor")
  check("its time from the ghost return", r.bosses[1] and r.bosses[1].t <= 145, r.bosses[1] and r.bosses[1].t)
  eq("the note from after the ghost return moved with it", #r.notes, 1)
  eq("the stretch in between keeps none", #c.history()[1].notes, 0)
  noErrors(c)
end

H.summary("tests_il3.lua")
