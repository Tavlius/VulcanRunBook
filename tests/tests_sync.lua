-- RunBook tests: duo sync, commands, windows, export, secrets, saved-data backup.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check, eq = H.check, H.eq

local function fresh(opts)
  local c = H.boot(opts)
  c.login()
  return c
end

local function items(c)
  c.item(100, "Cruel Barb", 3, 5000)
  c.item(103, "Lucky Charm", 2, 300)
  c.item(104, "Smite's Hammer", 4, 20000)
end

local function noErrors(...)
  local all = {}
  for _, c in ipairs({ ... }) do for _, e in ipairs(c.errors()) do all[#all + 1] = e end end
  check("no errors", #all == 0, table.concat(all, "; "))
end

local function lastSent(c, kind)
  for i = #c.addonSent, 1, -1 do
    if c.addonSent[i].msg:sub(1, 1) == kind then return c.addonSent[i] end
  end
  return nil
end

local function countSent(c, kind)
  local n = 0
  for _, m in ipairs(c.addonSent) do if m.msg:sub(1, 1) == kind then n = n + 1 end end
  return n
end

-- A message from Mirel's client about his run.
local function from(c, kind, start, fields, map, name, wing)
  c.addonMsg("Mirel-Realm", string.format("%s3|beef01|%s|%s|%s|%d|%s", kind, map or "36", name or "Deadmines",
    wing or "", start, fields))
end

---------------------------------------------------------------------------
H.group("sync: sending")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36)
  local run = c.run()
  local s = lastSent(c, "S")
  check("stats sent at run start", s ~= nil)
  eq("prefix", s and s.prefix, "VulcanRunBook")
  eq("party channel", s and s.ch, "PARTY")
  check("stats format", s and s.msg:match("^S3|%x+|36|Deadmines||%d+|0|0|0|0|0|0|0$") ~= nil, s and s.msg)
  c.gainMoney(250)
  c.tick(30)
  s = lastSent(c, "S")
  check("periodic stats with coin", s and s.msg:find("|%d+|250|0|0|0|0|0$") ~= nil, s and s.msg)
  -- Locked down during a boss fight: queued, then sent after.
  c.addonResult = 11
  local n = #c.addonSent
  c.slash("note pull the left pack first")
  c.tick(3)
  eq("nothing sent in lockdown", #c.addonSent, n)
  eq("still queued", c.ns.SyncQueueSize(), 1)
  c.addonResult = 0
  c.fire("ENCOUNTER_END", 1, "X", 1, 5, 1)
  local note = lastSent(c, "N")
  check("note sent after lockdown", note and note.msg:find("pull the left pack first", 1, true) ~= nil)
  c.tick(1)  -- (the boss's stats go out)
  -- Throttled: retried next tick.
  c.addonResult = 3
  c.slash("note second")
  c.tick(1)
  eq("throttled kept", c.ns.SyncQueueSize(), 1)
  c.addonResult = 0
  c.tick(1)
  eq("throttled sent next tick", c.ns.SyncQueueSize(), 0)
  -- A general error (or not in a group, mid-change) is retried for a while.
  c.addonResult = 9
  c.slash("note third")
  c.tick(1)
  eq("general error kept", c.ns.SyncQueueSize(), 1)
  c.addonResult = 0
  c.tick(1)
  eq("then sent", c.ns.SyncQueueSize(), 0)
  -- Other errors drop the message rather than retrying.
  c.addonResult = 2
  c.slash("note fourth")
  c.tick(1)
  eq("other error dropped", c.ns.SyncQueueSize(), 0)
  c.addonResult = 0
  -- Stats are replaced, not stacked, while waiting.
  c.addonResult = 11
  c.ns.SyncStats()
  c.ns.SyncStats()
  c.ns.SyncStats()
  eq("one stats message queued", c.ns.SyncQueueSize(), 1)
  c.addonResult = 0
  c.tick(1)
  -- Pipes and long notes are made safe; item links become [Name].
  c.slash("note a||b " .. string.rep("x", 400))
  c.tick(1)
  note = lastSent(c, "N")
  check("note under 255", note and #note.msg <= 255, note and #note.msg)
  check("note cut is reported", c.printedMatch("cut short to fit", true) ~= nil)
  check("local note truncated", #run.notes[#run.notes].text <= c.ns.NOTE_MAX_BYTES)
  c.slash("note got " .. c.link(104, "Smite's Hammer", 4) .. " finally")
  eq("link in note becomes a name", run.notes[#run.notes].text, "got [Smite's Hammer] finally")
  -- Drops of yours are sent to your partner.
  items(c)
  c.lootMsg(nil, 100)
  c.tick(1)
  local d = lastSent(c, "D")
  check("drop sent", d and d.msg:find("|100|1|3|%d+$") ~= nil, d and d.msg)
  -- Not in a group: nothing queued or sent.
  c.party()
  c.slash("note solo")
  eq("solo note not queued", c.ns.SyncQueueSize(), 0)
  -- Sync off.
  c.party("Mirel")
  c.slash("sync off")
  n = #c.addonSent
  c.tick(30)
  eq("sync off sends nothing", #c.addonSent, n)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("sync: receiving")
do
  local c = fresh()
  items(c)
  c.party("Mirel")
  c.enter("Deadmines", 36)
  local run = c.run()
  local start = run.serverStart
  c.tick(70)
  from(c, "S", start + 20, "600|50000|12000|20000|4100|0")
  local p = run.partners.Mirel
  check("partner stats stored", p ~= nil)
  eq("partner coin", p and p.coin, 50000)
  eq("partner xp", p and p.xp, 4100)
  check("partner seen", c.ns.partnersSeen.Mirel ~= nil)
  check("partner line in window", c.liveText():find("Mirel: 6g 20s", 1, true) ~= nil, c.liveText())
  check("together line in window", c.liveText():find("Together: 6g 20s", 1, true) ~= nil, c.liveText())
  -- An older stats message (less time) doesn't overwrite newer numbers.
  from(c, "S", start + 20, "300|1|1|1|1|0")
  eq("older stats ignored", run.partners.Mirel.coin, 50000)
  -- His note lands on this run.
  from(c, "N", start + 20, "skip the goblins")
  eq("partner note", run.notes[1] and run.notes[1].text, "skip the goblins")
  eq("partner note who", run.notes[1] and run.notes[1].who, "Mirel")
  from(c, "N", start + 20, "skip the goblins")
  eq("duplicate note ignored", #run.notes, 1)
  -- His drop: listed even if his loot line was hidden from you...
  from(c, "D", start + 20, "104|1|4")
  eq("partner drop via sync", #run.drops, 1)
  eq("partner drop who", run.drops[1] and run.drops[1].who, "Mirel")
  -- ...and not twice when his loot line does show up.
  c.lootMsg("Mirel", 104)
  eq("sync + loot line = one drop", #run.drops, 1)
  -- And the other way round.
  c.lootMsg("Mirel", 103)
  from(c, "D", start + 20, "103|1|2")
  eq("loot line + sync = one drop", #run.drops, 2)
  -- A message about another dungeon or a run far apart in time is ignored.
  from(c, "S", start, "9999|1|1|1|1|0", "43", "Wailing Caverns")
  from(c, "S", start - 4000, "9999|1|1|1|1|0")
  eq("mismatched stats ignored", run.partners.Mirel.coin, 50000)
  -- Garbage is ignored quietly.
  c.addonMsg("Mirel", "S3|beef01|36|Deadmines||x|1|2")
  c.addonMsg("Mirel", "S3|beef01|36|Deadmines||5|9999|-1|1|1|1|0")
  c.addonMsg("Mirel", "hello")
  c.addonMsg("Mirel", "S3|zz|36|Deadmines||5|1|1|1|1|1|0")
  c.addonMsg("Mirel", "X3|beef01|whatever")
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|9999|1|1|1|1|0", start), "OtherAddon")
  eq("garbage ignored", run.partners.Mirel.coin, 50000)
  -- Your own echo is ignored (by name, and by session tag even under another name).
  c.addonMsg("Tavlius", string.format("S3|%s|36|Deadmines||%d|9999|1|1|1|1|0", c.ns.token, start))
  c.addonMsg("Tavlius Surname", string.format("S3|%s|36|Deadmines||%d|9999|1|1|1|1|0", c.ns.token, start))
  check("own echo ignored", run.partners.Tavlius == nil and run.partners["Tavlius Surname"] == nil)
  -- Newer version: one notice, no data.
  c.addonMsg("Mirel", "S4|beef01|36|Deadmines||1|1|1|1|1|1|0")
  c.addonMsg("Mirel", "S4|beef01|36|Deadmines||1|1|1|1|1|1|0")
  local notices = 0
  for _, l in ipairs(c.printed) do if l:find("a newer RunBook", 1, true) then notices = notices + 1 end end
  eq("one version notice", notices, 1)
  -- After the run ends, his final numbers still reach the archived run.
  c.leave()
  c.system("Deadmines has been reset.")
  check("ended", c.run() == nil)
  from(c, "S", start + 20, "900|60000|2000|3000|5000|0")
  eq("late stats reach the archived run", c.history()[1].partners.Mirel.coin, 60000)
  -- Back-to-back: his NEW run's first message (zeros) can't overwrite the old one.
  local ended = c.history()[1].serverEnd
  from(c, "S", ended + 30, "0|0|0|0|0|0")
  eq("next run's stats don't touch the last run", c.history()[1].partners.Mirel.coin, 60000)
  -- Reset relayed by partner ends your run too (you didn't see the message).
  c.enter("Deadmines", 36)
  local r2 = c.run()
  c.tick(100)
  c.leave()
  c.addonMsg("Mirel", "R3|beef01|Deadmines")
  check("partner reset ends run", c.run() == nil and r2.endReason == "reset")
  eq("reset seen by us was relayed once", countSent(c, "R"), 1)
  -- A reset of a dungeon you've never run is ignored.
  c.addonMsg("Mirel", "R3|beef01|Nowhere Keep")
  check("unknown dungeon reset ignored", _G.VulcanRunBookCharDB.resets["Nowhere Keep"] == nil)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("sync: reset message arriving after you went back in")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36)
  local run1 = c.run()
  c.tick(300)
  c.encounter(1144, "Rhahk'Zor", true, 30)
  c.leave()
  c.tick(30)
  c.enter("Deadmines", 36)        -- in before the reset relay arrives
  check("resumed", c.run() == run1)
  c.tick(5)
  c.addonMsg("Mirel", "R3|beef01|Deadmines")
  check("split into a new run", c.run() ~= run1 and run1.ended)
  check("explained", c.printedMatch("was reset just before you went back in", true) ~= nil)
  -- A stale reset (from before) doesn't end a run later.
  local r2 = c.run()
  c.tick(10)
  c.leave()
  c.tick(10)
  c.enter("Deadmines", 36)
  check("no false reset on the next trip", c.run() == r2)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("sync: partner joins late, clock differences, channel")
do
  local c = fresh({ serverOffset = 0 })
  c.party("Mirel")
  c.wall = c.wall + 180            -- your PC clock is 3 minutes off; server time isn't
  c.enter("Deadmines", 36)
  local run = c.run()
  from(c, "S", run.serverStart + 900, "60|1|1|1|1|0")
  check("late joiner (15 min) still matched", run.partners.Mirel ~= nil)
  local d = fresh({ noServerTime = true })
  d.party("Mirel")
  d.enter("Deadmines", 36)
  check("start time without server time", type(d.run().serverStart) == "number")
  -- Dungeon-finder group: instance channel.
  local f = fresh()
  _G.LE_PARTY_CATEGORY_HOME, _G.LE_PARTY_CATEGORY_INSTANCE = 1, 2
  local realIsInGroup = _G.IsInGroup
  _G.IsInGroup = function(cat) if cat == 1 then return false end return true end
  eq("instance channel", f.ns.GroupChannel(), "INSTANCE_CHAT")
  _G.IsInGroup = realIsInGroup
  _G.LE_PARTY_CATEGORY_HOME, _G.LE_PARTY_CATEGORY_INSTANCE = nil, nil
  noErrors(c, d, f)
end

---------------------------------------------------------------------------
H.group("commands")
do
  local c = fresh()
  items(c)
  c.party("Mirel")
  c.slash("note too early")
  check("note without a run", c.printedMatch("No run to add a note to yet.", true) ~= nil)
  c.enter("Deadmines", 36)
  c.tick(70)
  c.encounter(1144, "Rhahk'Zor", true, 30)
  c.lootMsg(nil, 100)
  c.lootMsg("Mirel", 104)
  c.slash("note first run")
  eq("note on current run", c.run().notes[1].text, "first run")
  c.slash("note")
  check("note usage", c.printedMatch("Usage: /runbook note", true) ~= nil)
  -- Report to party: summary + drops with links.
  c.slash("report party")
  check("report sent", #c.sent >= 2)
  check("report summary", c.sent[1] and c.sent[1].msg:find("^RunBook: Deadmines 1:40") ~= nil,
    c.sent[1] and c.sent[1].msg)
  check("report has no color codes in summary", c.sent[1] and not c.sent[1].msg:find("|c", 1, true))
  check("report drops keep links", c.sent[2] and c.sent[2].msg:find("|Hitem:104", 1, true) ~= nil)
  eq("report channel", c.sent[1] and c.sent[1].ch, "PARTY")
  c.slash("report GROUP")
  eq("report group picks party", c.sent[#c.sent].ch, "PARTY")
  c.slash("report w")
  check("whisper needs a name", c.printedMatch("Who to whisper?", true) ~= nil)
  c.slash("report w Mirel-Realm")
  eq("whisper target keeps realm", c.sent[#c.sent].target, "Mirel-Realm")
  c.slash("report officer")
  check("unknown channel explained", c.printedMatch("Unknown channel", true) ~= nil)
  -- Chat locked in a boss fight: told so, nothing silently lost.
  c.chatLockdown = true
  local sentBefore = #c.sent
  c.slash("report party")
  check("lockdown explained", c.printedMatch("Chat is locked right now", true) ~= nil)
  eq("nothing sent in lockdown", #c.sent, sentBefore)
  eq("nothing blocked", c.blockedChat or 0, 0)
  c.chatLockdown = false
  c.clearPrinted()
  c.slash("report")
  check("report to yourself, no doubled prefix", c.printed[1] and c.printed[1]:find("^RunBook: Deadmines") ~= nil
    and not c.printed[1]:find("RunBook: RunBook", 1, true), c.printed[1])
  -- End, then note #id and delete by id.
  c.leave()
  c.system("Deadmines has been reset.")
  local id = c.history()[1].id
  c.slash("note #" .. id .. " good run")
  eq("note on run #id", c.history()[1].notes[2].text, "good run")
  c.slash("note #" .. id)
  check("note #id without text", c.printedMatch("Usage: /runbook note", true) ~= nil)
  c.slash("note #99 nope")
  check("missing run number", c.printedMatch("No run #99.", true) ~= nil)
  c.slash("note 2 pulls at a time")
  eq("number without # is note text", c.history()[1].notes[3].text, "2 pulls at a time")
  -- Export CSV.
  c.slash("export")
  check("copy frame built", _G.VulcanRunBookCopyFrame ~= nil)
  local lines = c.ns.ExportLines()
  eq("csv rows", #lines, 2)
  eq("csv header", lines[1], c.ns.CSV_HEADER)
  local cols, inQuote = 1, false
  for ch in lines[2]:gmatch(".") do
    if ch == '"' then inQuote = not inQuote elseif ch == "," and not inQuote then cols = cols + 1 end
  end
  eq("csv columns match header", cols, select(2, c.ns.CSV_HEADER:gsub(",", "")) + 1)
  check("csv drops named", lines[2]:find("Smite's Hammer (Mirel)", 1, true) ~= nil, lines[2])
  check("csv notes", lines[2]:find("first run", 1, true) ~= nil)
  check("csv status", lines[2]:find(",reset,", 1, true) ~= nil, lines[2])
  check("csv has no color codes", not lines[2]:find("|c", 1, true))
  c.slash("note #" .. id .. ' said "go, go"')
  lines = c.ns.ExportLines()
  check("csv quotes escaped", lines[2]:find('said ""go, go""', 1, true) ~= nil, lines[2])
  -- Delete and clear.
  c.slash("delete 5")
  check("delete bad number", c.printedMatch("No saved run #5", true) ~= nil)
  c.slash("delete")
  check("delete usage", c.printedMatch("Usage: /runbook delete", true) ~= nil)
  c.slash("delete #" .. id)
  eq("asks first", #c.history(), 1)
  c.slash("delete #" .. id)
  eq("deleted", #c.history(), 0)
  c.slash("clear")
  check("clear with nothing saved", c.printedMatch("No saved runs.", true) ~= nil)
  c.slash("clear YES")
  -- Settings.
  c.slash("price AH")
  eq("price ah", _G.VulcanRunBookDB.priceSource, "auction")
  c.slash("price vendor")
  eq("price vendor", _G.VulcanRunBookDB.priceSource, "vendor")
  c.slash("auto off")
  eq("auto off", _G.VulcanRunBookDB.autoShow, false)
  c.slash("lock")
  eq("locked", _G.VulcanRunBookDB.locked, true)
  c.slash("scale 1.5")
  eq("scale", _G.VulcanRunBookDB.scale, 1.5)
  check("scale feedback", c.printedMatch("scale 1.5", true) ~= nil)
  c.slash("scale 9")
  check("scale bounds", c.printedMatch("Usage: /runbook scale", true) ~= nil)
  c.slash("resetpos")
  check("resetpos feedback", c.printedMatch("starting spot", true) ~= nil)
  c.slash("debug ON")
  eq("debug on", _G.VulcanRunBookDB.debug, true)
  c.slash("debug nonsense")
  check("debug usage", c.printedMatch("Usage: /runbook debug", true) ~= nil)
  c.enter("Deadmines", 36)
  check("debug log written", #_G.VulcanRunBookDB.debugLog > 0)
  c.slash("export DEBUG")
  c.slash("check")
  check("check runs", c.printedMatch("check (version dev)", true) ~= nil)  -- (running from source: the TOC token shows as dev)
  check("check boss events", c.printedMatch("Boss events this session", true) ~= nil)
  check("check chat lockdown", c.printedMatch("Chat lockdown right now", true) ~= nil)
  c.clearPrinted()
  c.slash("help")
  check("help", c.printedMatch("history", true) ~= nil)
  -- No bare "|" escapes in help: every | starts |c, |r or ||.
  local bad
  for _, l in ipairs(c.printed) do
    local stripped = l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("||", "")
    if stripped:find("|", 1, true) then bad = l end
  end
  check("help has no stray pipe escapes", bad == nil, bad)
  c.slash("nonsense")
  check("unknown command explained", c.printedMatch("Unknown command", true) ~= nil)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("history window")
do
  local c = fresh()
  items(c)
  for i = 1, 3 do
    c.enter("Deadmines", 36)
    c.tick(100 * i)
    c.encounter(1144, "Rhahk'Zor", true, 30)
    c.lootMsg(nil, 100)
    c.leave()
    c.system("Deadmines has been reset.")
  end
  c.slash("history")
  local f = _G.VulcanRunBookHistoryFrame
  check("history open", f and f:IsShown())
  local lines = c.ns.HistoryContent()
  eq("three rows", #lines, 3)
  check("row text", c.strip(lines[1][1]):find("#3", 1, true) and c.strip(lines[1][1]):find("Deadmines", 1, true),
    c.strip(lines[1][1]))
  check("rows clickable", lines[1][2] == c.history()[1])
  local rowButtons = {}
  for _, fr in ipairs(c.frames) do
    if fr.kind == "Button" and rawget(fr, "run") then rowButtons[#rowButtons + 1] = fr end
  end
  check("row buttons", #rowButtons >= 3)
  rowButtons[2]:Click()
  local detail, heading = c.ns.HistoryContent()
  eq("detail heading by run number", heading, "Run #2")
  local all = {}
  for _, l in ipairs(detail) do all[#all + 1] = c.strip(l[1]) end
  local txt = table.concat(all, "\n")
  check("detail shows bosses", txt:find("Rhahk'Zor", 1, true) ~= nil, txt)
  check("detail shows drops", txt:find("[Cruel Barb]", 1, true) ~= nil, txt)
  check("detail names the run number", txt:find("/runbook delete 2", 1, true) ~= nil, txt)
  check("detail rows not clickable", detail[1][2] == nil)
  -- A new run ending while the details are open: still the same run shown.
  c.enter("Wailing Caverns", 43)
  c.tick(100)
  c.leave()
  c.system("Wailing Caverns has been reset.")
  local _, heading2 = c.ns.HistoryContent()
  eq("detail stays on its run", heading2, "Run #2")
  -- Deleting the open run goes back to the list.
  c.slash("delete 2 yes")
  local _, heading3 = c.ns.HistoryContent()
  check("deleted run closes its details", heading3:find("^Runs") ~= nil, heading3)
  -- The run in progress is listed first.
  c.enter("Deadmines", 36)
  local now = c.ns.HistoryContent()
  check("current run listed", c.strip(now[1][1]):find("Now:", 1, true) ~= nil, c.strip(now[1][1]))
  c.ns.ShowHistory("dungeons")
  local d = c.ns.HistoryContent()
  check("dungeon stats", c.strip(d[1][1]):find("Deadmines  2 runs", 1, true) ~= nil, c.strip(d[1][1]))
  check("clears line", c.strip(d[2][1]):find("2 clears (to Rhahk'Zor)", 1, true) ~= nil, c.strip(d[2][1]))
  local e = fresh()
  e.slash("history")
  eq("empty message", #e.ns.HistoryContent(), 1)
  e.slash("stats")
  check("empty stats", e.strip(e.ns.HistoryContent()[1][1]):find("No runs yet", 1, true) ~= nil)
  noErrors(c, e)
end

---------------------------------------------------------------------------
H.group("report limits")
do
  local c = fresh()
  c.party("Mirel", "A", "B", "C", "D", "E", "F", "G", "H", "I")
  c.raid = true
  c.slash("partner Mirel")
  c.enter("Molten Core", 409, { kind = "raid" })
  for i = 1, 30 do
    c.item(2000 + i, "Epic Thing Number " .. i, 4, 1000)
    c.lootMsg(i % 2 == 0 and "A" or "B", 2000 + i)
  end
  c.lootMsg("Mirel", 2001)
  c.slash("report raid")
  local raidLines = 0
  for _, m in ipairs(c.sent) do if m.ch == "RAID" then raidLines = raidLines + 1 end end
  eq("raid report: summary + your two's drops only", raidLines, 2)
  local raidOnly = c.ns.ReportLines(c.run(), false)
  eq("a raid run's report lists only your two's drops anywhere", #raidOnly, 2)
  c.leave()
  c.raid = false
  c.party("Mirel", "A", "B", "C")
  c.enter("Deadmines", 36)
  for i = 1, 30 do c.lootMsg(i % 2 == 0 and "A" or "B", 2000 + i) end
  local lines = c.ns.ReportLines(c.run(), false)
  check("at most 3 lines", #lines <= 3, #lines)
  check("+N more", lines[#lines]:find("more$") ~= nil, lines[#lines])
  for _, l in ipairs(lines) do check("line under 255", #l <= 255, #l) end
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("secret values")
do
  local c = fresh()
  items(c)
  c.party("Mirel")
  c.enter("Deadmines", 36)
  local run = c.run()
  c.fire("CHAT_MSG_LOOT", H.SECRET, H.SECRET)
  eq("secret loot counted", c.ns.stats.lootSecret, 1)
  c.tick(2)
  c.member("Mirel").secretDead = true
  c.member("Mirel").dead = true
  c.tick(3)
  eq("no death while secret", #run.deaths, 0)
  c.member("Mirel").secretDead = false
  c.tick(1)
  eq("death once readable", #run.deaths, 1)
  c.fire("ENCOUNTER_START", H.SECRET, H.SECRET, 1, 5)
  c.fire("ENCOUNTER_END", H.SECRET, H.SECRET, 1, 5, 1)
  eq("secret boss counted", #run.bosses, 1)
  eq("secret boss named", run.bosses[1].name, "Boss 1")
  c.secret.money, c.secret.xp = true, true
  c.gainMoney(10)
  c.gainXP(10)
  c.secret.money, c.secret.xp = false, false
  c.fire("CHAT_MSG_ADDON", H.SECRET, H.SECRET, "PARTY", H.SECRET)
  c.fire("CHAT_MSG_SYSTEM", H.SECRET)
  c.fire("UI_ERROR_MESSAGE", 1, H.SECRET)
  c.fire("PLAYER_XP_UPDATE", H.SECRET)
  c.member("Mirel").secretName = true
  c.tick(2)
  c.fire("GROUP_ROSTER_UPDATE")
  c.member("Mirel").secretName = false
  c.secret.dead = true
  c.tick(2)
  c.secret.dead = false
  local d = fresh()
  d.secret.map = true
  d.enter("Deadmines", 36)
  eq("map falls back to name", d.run() and d.run().map, "Deadmines")
  d.leave()
  d.enter("Deadmines", 36)
  eq("resume works with name key", #_G.VulcanRunBookDB.entries, 1)
  local s = fresh()
  s.secret.server = true
  s.enter("Deadmines", 36)
  check("server time fallback", type(s.run().serverStart) == "number")
  local u = H.boot({ unknownEvents = { BOSS_KILL = true, ITEM_DATA_LOAD_RESULT = true, BAG_UPDATE_DELAYED = true } })
  u.login()
  u.enter("Deadmines", 36)
  check("unknown events tolerated", u.run() ~= nil)
  local o = fresh({ secretAware = false })
  o.enter("Deadmines", 36)
  check("works without issecretvalue", o.run() ~= nil)
  noErrors(c, d, s, u, o)
end

---------------------------------------------------------------------------
H.group("saved data backup and damaged data")
do
  local c = fresh()
  for _ = 1, 2 do
    c.enter("Deadmines", 36)
    c.tick(100)
    c.leave()
    c.system("Deadmines has been reset.")
  end
  eq("two runs", #c.history(), 2)
  -- Take both copies before booting another client (boots share the globals).
  local s = c.savedCopy(true)
  local s2 = c.savedCopy(false)
  local r = H.boot({ saved = s })
  r.login()
  eq("restored runs", #r.history(), 2)
  check("restore message", r.printedMatch("this character's backup was used", true) ~= nil)
  eq("cap entries restored", #_G.VulcanRunBookDB.entries, 2)
  r.enter("Deadmines", 36)
  r.tick(70)
  r.leave()
  r.system("Deadmines has been reset.")
  eq("run numbers continue after restore", r.history()[1].id, 3)
  local ok = H.boot({ saved = s2 })
  ok.login()
  check("no restore message when fine", ok.printedMatch("backup", true) == nil)
  eq("runs intact", #ok.history(), 2)
  local s3 = ok.savedCopy(false)
  s3.char.mirror.savedAt = s3.db.savedAt - 1000
  s3.char.mirror.history = {}
  local alt = H.boot({ saved = s3 })
  alt.login()
  eq("newer account data wins", #alt.history(), 2)
  -- Damaged saved data doesn't break loading, the windows, stats or export.
  local damaged = {
    db = { history = { 5, { name = "Deadmines", elapsed = "x" }, { bosses = "no", drops = { 7, { id = 1 } } } },
      resets = { Deadmines = "soon", [5] = 1 }, entries = { "a", 1 }, savedAt = "x", nextId = "y" },
    char = { run = { name = "Deadmines", bosses = 5 }, mirror = "x" },
    wall = c.wall, now = c.now,
  }
  local bad = H.boot({ saved = damaged })
  bad.login()
  eq("bad rows dropped", #bad.history(), 2)
  bad.ns.DungeonStats()
  bad.ns.ExportLines()
  bad.slash("history")
  bad.slash("stats")
  bad.slash("show")
  bad.ns.LiveLines()
  bad.enter("Deadmines", 36)
  bad.tick(5)
  local corrupt = H.boot({ saved = { db = "oops", char = { run = 5, mirror = "x" }, wall = c.wall, now = c.now } })
  corrupt.login()
  check("corrupt data tolerated", corrupt.run() == nil)
  noErrors(r, ok, alt, bad, corrupt)
end

---------------------------------------------------------------------------
H.group("auctionator prices")
do
  local c = fresh({ auctionator = { [100] = 9000 } })
  items(c)
  c.enter("Deadmines", 36)
  c.lootMsg(nil, 100)
  c.lootMsg(nil, 103)
  eq("vendor value", c.run().loot, 5300)
  eq("ah value (95%, at least vendor)", c.run().lootAH, math.floor(9000 * 0.95) + 300)
  c.slash("price ah")
  eq("gold uses ah", c.ns.RunGold(c.run()), math.floor(9000 * 0.95) + 300)
  local t = fresh({ auctionator = {}, auctionatorThrows = true })
  items(t)
  t.enter("Deadmines", 36)
  t.lootMsg(nil, 100)
  eq("throwing auctionator falls back to vendor", t.run().lootAH, 5000)
  noErrors(c, t)
end

---------------------------------------------------------------------------
H.group("formatting")
do
  local c = fresh()
  local ns = c.ns
  eq("money gold only", ns.Money(100000), "10g")
  eq("money gold silver", ns.Money(102000), "10g 20s")
  eq("money silver only", ns.Money(500), "5s")
  eq("money copper", ns.Money(7), "7c")
  eq("clock", ns.Clock(3725), "1:02:05")
  eq("delta ahead", ns.Delta(-42), "-0:42")
  eq("delta even", ns.Delta(0.4), "±0:00")
  eq("plural", ns.Plural(1, "boss", "bosses") .. "," .. ns.Plural(2, "boss", "bosses"), "1 boss,2 bosses")
  eq("ellipsis", ns.Ellipsis("abcdefghij", 8), "abcde...")
  eq("clean link", ns.CleanText("a |cnIQ4:|Hitem:1::|h[Robe]|h|r b"), "a [Robe] b")
  eq("clean hex link", ns.CleanText("|cffa335ee|Hitem:1::|h[Robe]|h|r"), "[Robe]")
  eq("clean pipes", ns.CleanText("x||y|z"), "x/y/z")
  local who = ns.ParseLoot("Beute: Mirel erhält |cnIQ3:|Hitem:55::|h[X]|h|rx2.")
  check("unknown format returns nil", who == nil)
end

os.exit(H.summary("tests_sync.lua") and 0 or 1)
