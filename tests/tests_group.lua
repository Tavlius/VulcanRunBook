-- RunBook tests: auto-pairing with friends (and your partner's other
-- characters), and the read-only group view.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check, eq = H.check, H.eq

local function fresh(opts) local c = H.boot(opts) c.login() return c end
local function noErrors(c) check("no errors", #c.errors() == 0, table.concat(c.errors(), "; ")) end
local function anyPrinted(c, text)
  for _, p in ipairs(c.printed) do if c.strip(p):find(text, 1, true) then return true end end
  return false
end
-- Their stats message: S3|token|map|dungeon|wing|start|elapsed|coin|loot|lootAH|xp|ended|kills
local function S(c, sender, start, elapsed, coin, xp, opts)
  opts = opts or {}
  c.addonMsg(sender, string.format("S%d|%s|%s|%s||%d|%d|%d|%d|%d|%d|%d|%d", opts.ver or 3, opts.token or "beef01",
    opts.map or "36", opts.dungeon or "Deadmines", start, elapsed, coin, opts.loot or 0, opts.loot or 0, xp,
    opts.ended and 1 or 0, opts.kills or 0))
end
local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
local function names(rows) local t = {} for _, r in ipairs(rows) do t[#t + 1] = r.name end return table.concat(t, ",") end

---------------------------------------------------------------------------
-- A: auto-pairing
---------------------------------------------------------------------------
H.group("a friend (friends list) in a 5-player group becomes your partner")
do
  local c = fresh()
  c.party("Mirel", "Pug1", "Pug2", "Pug3")
  c.friends.Mirel = true
  c.enter("Deadmines", 36) c.tick(30)
  S(c, "Mirel-Realm", c.run().serverStart, 30, 0, 0)
  c.tick(10)
  check("not before everyone's had time to be heard", c.ns.DB.partner == nil)
  c.tick(30)
  eq("partner", c.ns.DB.partner, "Mirel")
  check("said so", anyPrinted(c, "Mirel (a friend of yours) also runs RunBook"))
  S(c, "Mirel-Realm", c.run().serverStart, 60, 500, 0)
  eq("his gold is a partner's", c.run().partners.Mirel and c.run().partners.Mirel.coin, 500)
  check("not in the group view", not c.ns.HasGroupStats(c.run()))
  noErrors(c)
end

H.group("a Battle.net friend in a raid becomes your partner, with their BattleTag")
do
  local c = fresh()
  c.party("Mirel", "A", "B", "C", "D", "E") c.raid = true
  c.bnet.Mirel = "Mirel#1111"
  c.enter("Molten Core", 409, { kind = "raid" }) c.tick(30)
  S(c, "Mirel-Realm", c.run().serverStart, 30, 0, 0, { map = "409", dungeon = "Molten Core" })
  c.tick(40)
  eq("partner", c.ns.DB.partner, "Mirel")
  eq("tag kept", c.ns.DB.partnerTag, "Mirel#1111")
  noErrors(c)
end

H.group("a stranger in a 5-player group is not picked; their stats go to the group view")
do
  local c = fresh()
  c.party("Pug1", "Pug2", "Pug3", "Pug4")
  c.enter("Deadmines", 36) c.tick(30)
  S(c, "Pug1-Realm", c.run().serverStart, 30, 0, 0)
  check("no partner", c.ns.DB.partner == nil)
  check("the note", anyPrinted(c, "Pug1 runs RunBook too"))
  S(c, "Pug1-Realm", c.run().serverStart, 90, 700, 1200)
  local g = c.run().group and c.run().group.Pug1
  eq("their gold shown", g and g.coin, 700)
  eq("their XP shown", g and g.xp, 1200)
  eq("your gold untouched", c.run().coin, 0)
  check("no partner entry", next(c.run().partners) == nil)
  noErrors(c)
end

H.group("two players: the old rule, no friends list needed")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36) c.tick(30)
  S(c, "Mirel-Realm", c.run().serverStart, 30, 0, 0)
  eq("partner", c.ns.DB.partner, "Mirel")
  check("plain message", anyPrinted(c, "Mirel also runs RunBook"))
  noErrors(c)
end

H.group("your partner on another character (same Battle.net account) is followed")
do
  local c = fresh()
  c.party("Mirel")
  c.bnet.Mirel = "Mirel#1111"
  c.enter("Deadmines", 36) c.tick(30)
  S(c, "Mirel-Realm", c.run().serverStart, 30, 0, 0)
  eq("tag", c.ns.DB.partnerTag, "Mirel#1111")
  c.slash("end") c.leave() c.tick(60)
  -- Mirel logs his alt; a new group with a pug.
  c.party("Kelalt", "Pug1", "Pug2")
  c.bnet.Kelalt = "Mirel#1111"
  c.enter("Deadmines", 36) c.tick(30)
  c.clearPrinted()
  S(c, "Kelalt-Realm", c.run().serverStart, 30, 0, 0)
  eq("follows the alt", c.ns.DB.partner, "Kelalt")
  check("says why", anyPrinted(c, "Mirel is on Kelalt now (the same Battle.net account)"))
  eq("tag kept", c.ns.DB.partnerTag, "Mirel#1111")
  S(c, "Kelalt-Realm", c.run().serverStart, 60, 300, 0)
  eq("his numbers are a partner's", c.run().partners.Kelalt and c.run().partners.Kelalt.coin, 300)
  noErrors(c)
end

H.group("a friend with another BattleTag doesn't take your partner's place")
do
  local c = fresh()
  c.party("Mirel", "Bob", "Pug1")
  c.slash("partner Mirel")
  c.bnet.Mirel, c.bnet.Bob = "Mirel#1111", "Bob#2222"
  c.enter("Deadmines", 36) c.tick(30)
  S(c, "Mirel-Realm", c.run().serverStart, 30, 0, 0)
  eq("tag learned from his first message", c.ns.DB.partnerTag, "Mirel#1111")
  S(c, "Bob-Realm", c.run().serverStart, 30, 400, 0)
  S(c, "Bob-Realm", c.run().serverStart, 60, 900, 0)
  eq("still Mirel", c.ns.DB.partner, "Mirel")
  -- (His run began with yours: all of it is from this run.)
  eq("Bob in the group view", c.run().group and c.run().group.Bob and c.run().group.Bob.coin, 900)
  noErrors(c)
end

H.group("without the friends APIs, or with hidden GUIDs: no friends, no errors")
do
  local c = fresh({ noFriendAPI = true })
  c.party("Mirel", "Pug1", "Pug2")
  c.enter("Deadmines", 36) c.tick(30)
  S(c, "Mirel-Realm", c.run().serverStart, 30, 0, 0)
  c.tick(40)
  check("no partner", c.ns.DB.partner == nil)
  noErrors(c)
  local d = fresh()
  d.party("Mirel", "Pug1", "Pug2")
  d.friends.Mirel = true
  d.group[1].secretGUID = true
  d.enter("Deadmines", 36) d.tick(30)
  S(d, "Mirel-Realm", d.run().serverStart, 30, 0, 0)
  d.tick(40)
  -- (The friends list by name still works.)
  eq("by name", d.ns.DB.partner, "Mirel")
  noErrors(d)
end

H.group("partner off clears the BattleTag; a damaged saved tag is dropped")
do
  local c = fresh()
  c.party("Mirel")
  c.bnet.Mirel = "Mirel#1111"
  c.enter("Deadmines", 36) c.tick(30)
  S(c, "Mirel-Realm", c.run().serverStart, 30, 0, 0)
  c.slash("partner off")
  check("tag gone", c.ns.DB.partnerTag == nil)
  check("says friends count", anyPrinted(c, "or a friend of yours in any group"))
  local saved = c.saved()
  saved.db.partnerTag = 42
  saved.db.partner = "Mirel"
  local d = H.boot({ saved = saved }) d.login()
  check("number tag dropped", d.ns.DB.partnerTag == nil)
  noErrors(c) noErrors(d)
end

---------------------------------------------------------------------------
-- D: the group view
---------------------------------------------------------------------------
local function raid10()
  local c = fresh()
  c.party("Mirel", "Bob", "Cid", "Dee", "Eve", "Fay", "Gus", "Hal", "Ivy") c.raid = true
  c.slash("partner Mirel")
  c.enter("Molten Core", 409, { kind = "raid" }) c.tick(30)
  return c
end
local MC = { map = "409", dungeon = "Molten Core" }

H.group("raid: others' numbers are shown, never added to yours")
do
  local c = raid10()
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 0, 0, MC)
  for _, n in ipairs({ "Bob", "Cid", "Dee" }) do S(c, n .. "-Realm", st, 30, 0, 0, MC) end
  c.tick(60)
  S(c, "Mirel-Realm", st, 90, 2000, 100, MC)
  S(c, "Bob-Realm", st, 90, 9000, 0, MC)
  S(c, "Cid-Realm", st, 90, 3000, 500, MC)
  c.gainMoney(5000)
  c.tick(2)
  eq("three in the group view", count(c.run().group), 3)
  eq("your gold is yours", c.run().coin, 5000)
  eq("partner", c.run().partners.Mirel.coin, 2000)
  local gold, xp, n = c.ns.GroupTotals(c.run())
  eq("players with numbers", n, 5)
  eq("all their gold", gold, 5000 + 2000 + 9000 + 3000)
  eq("all their XP", xp, 600)
  local rows = c.ns.GroupRows(c.run())
  eq("everyone listed", #rows, 10)
  eq("most gold first", rows[1].name, "Bob")
  check("players without RunBook last", not rows[#rows].log and not rows[6].log and rows[5].log)
  local live = c.liveText()
  check("live line", live:find("Group (5 with RunBook): 1g 90s", 1, true) ~= nil, live)
  check("the duo line is the duo's", live:find("Together: 70 silver", 1, true) ~= nil, live)
  local tab = table.concat(c.ns.GroupTabLines(), "\n")
  check("tab: count", c.strip(tab):find("10 players · 5 with RunBook", 1, true) ~= nil, c.strip(tab))
  check("tab: no RunBook", c.strip(tab):find("Hal: no RunBook", 1, true) ~= nil)
  check("tab: you", c.strip(tab):find("(you): 50 silver", 1, true) ~= nil, c.strip(tab))
  check("tab: partner", c.strip(tab):find("Mirel (partner): 20 silver  ·  100 XP", 1, true) ~= nil)
  noErrors(c)
end

H.group("deaths and drops count for everyone in the group view")
do
  local c = raid10()
  c.member("Bob").dead = true c.fire("UNIT_HEALTH", "raid3") c.tick(2)
  c.item(900, "Robe of Volatile Power", 4, 50000)
  c.lootMsg("Bob", 900)
  c.tick(2)
  local bob
  for _, r in ipairs(c.ns.GroupRows(c.run())) do if r.name == "Bob" then bob = r end end
  eq("his death", bob and bob.deaths, 1)
  eq("his drop", bob and bob.drops, 1)
  check("shown", c.strip(table.concat(c.ns.GroupLines(c.run()), "\n")):find("Bob: no RunBook  ·  1 death, 1 drop", 1,
    true) ~= nil, c.strip(table.concat(c.ns.GroupLines(c.run()), "\n")))
  noErrors(c)
end

H.group("a run of theirs that began well before yours counts from the first message")
do
  local c = raid10()
  local st = c.run().serverStart
  S(c, "Bob-Realm", st - 600, 600, 40000, 9000, MC)
  eq("nothing yet", c.run().group.Bob.coin, 0)
  S(c, "Bob-Realm", st - 600, 660, 41500, 9500, MC)
  eq("what he made since", c.run().group.Bob.coin, 1500)
  eq("XP since", c.run().group.Bob.xp, 500)
  noErrors(c)
end

H.group("the group view has limits: 40 players, 4 runs each, 200 saved totals")
do
  local c = fresh()
  local many = {}
  for i = 1, 45 do many[i] = "P" .. i end
  c.party(unpack(many)) c.raid = true
  c.enter("Molten Core", 409, { kind = "raid" }) c.tick(30)
  local st = c.run().serverStart
  for i = 1, 45 do S(c, "P" .. i .. "-Realm", st, 30, i, 0, MC) end
  eq("40 players", count(c.run().group), 40)
  check("the 41st isn't", c.run().group.P45 == nil)
  local d = raid10()
  local dst = d.run().serverStart
  for i = 1, 8 do S(d, "Bob-Realm", dst + i * 2, 30, 100, 0, MC) end
  eq("4 runs of his", count(d.run().group.Bob.parts), 4)
  for i = 1, 260 do S(d, "Bob-Realm", dst + 100 + i, 30, 1, 0, MC) end
  local bobs = 0
  for k in pairs(_G.VulcanRunBookCharDB.partnerTotals) do if k:find("^Bob@") then bobs = bobs + 1 end end
  check("4 runs of one player's totals kept", bobs <= 4, bobs)
  -- Many players (raids over an evening), a few runs each: 200 at most in all.
  local e = fresh()
  many = {}
  for i = 1, 60 do many[i] = "R" .. i end
  e.party(unpack(many)) e.raid = true
  e.enter("Molten Core", 409, { kind = "raid" }) e.tick(30)
  for k = 1, 4 do for i = 1, 60 do S(e, "R" .. i .. "-Realm", e.run().serverStart + k, 30, 1, 0, MC) end end
  check("200 at most", count(_G.VulcanRunBookCharDB.partnerTotals) <= 200, count(_G.VulcanRunBookCharDB.partnerTotals))
  noErrors(e)
  noErrors(c) noErrors(d)
end

H.group("bad group messages are ignored")
do
  local c = raid10()
  local st = c.run().serverStart
  c.addonMsg("Bob-Realm", string.format("S3|beef01|409|Molten Core||%d|30|-5|0|0|0|0|0", st))
  c.addonMsg("Bob-Realm", string.format("S3|beef01|409|Molten Core||%d|30|nan|0|0|0|0|0", st))
  c.addonMsg("Bob-Realm", string.format("S3|beef01|409|Molten Core||%d|30|5|0|0|0|0|0|9|9", st))
  c.addonMsg("Bob-Realm", "S3|beef01|garbage")
  S(c, "Bob-Realm", st, 30, 500, 0, { ver = 2, map = "409", dungeon = "Molten Core" })
  S(c, "Bob-Realm", st, 30, 500, 0, { ver = 9, map = "409", dungeon = "Molten Core" })
  c.addonMsg("Bob-Realm", string.format("S3|beef01|409|Molten Core||%d|30|500|0|0|0|0|0", st), nil, "WHISPER")
  check("nothing kept", c.run().group == nil or c.run().group.Bob == nil)
  -- Someone who isn't in your group.
  S(c, "Zed-Realm", st, 30, 500, 0, MC)
  check("not in your group: ignored", c.run().group == nil or c.run().group.Zed == nil)
  -- Another dungeon's numbers don't make a group entry here.
  S(c, "Cid-Realm", st, 30, 500, 0)
  check("other dungeon", c.run().group == nil or c.run().group.Cid == nil)
  noErrors(c)
end

H.group("someone from another realm keeps their realm in the group view")
do
  local c = raid10()
  c.group[2].name = "Bob-Other"
  local st = c.run().serverStart
  S(c, "Bob-Other", st, 30, 0, 0, MC)
  S(c, "Bob-Other", st, 60, 800, 0, MC)
  eq("keyed with the realm", c.run().group["Bob-Other"] and c.run().group["Bob-Other"].coin, 800)
  noErrors(c)
end

H.group("setting someone as partner moves their numbers out of the group view")
do
  local c = raid10()
  c.slash("partner off")
  local st = c.run().serverStart
  S(c, "Bob-Realm", st, 30, 0, 0, MC)
  S(c, "Bob-Realm", st, 60, 600, 0, MC)
  eq("in the group view", c.run().group.Bob.coin, 600)
  c.slash("partner Bob")
  check("moved", c.run().group.Bob == nil)
  eq("now a partner's", c.run().partners.Bob and c.run().partners.Bob.coin, 600)
  S(c, "Bob-Realm", st, 90, 900, 0, MC)
  eq("and grows there", c.run().partners.Bob.coin, 900)
  noErrors(c)
end

H.group("an ended run takes no more of the group's numbers; details and CSV show them")
do
  local c = raid10()
  local st = c.run().serverStart
  S(c, "Bob-Realm", st, 30, 0, 0, MC)
  S(c, "Bob-Realm", st, 60, 600, 50, MC)
  c.gainMoney(100)
  c.slash("end") c.tick(10)
  S(c, "Bob-Realm", st, 120, 5000, 50, MC)
  local run = c.history()[1]
  eq("kept at the end", run.group.Bob.coin, 600)
  local details = c.strip(table.concat(c.ns.RunDetailLines(run), "\n"))
  check("details: group section", details:find("Group  (shown only: not in your totals)", 1, true) ~= nil, details)
  check("details: Bob", details:find("Bob: 6 silver  ·  50 XP", 1, true) ~= nil, details)
  local header = c.ns.CSV_HEADER
  local row = c.ns.CSVRow(run)
  local function fields(s) local n = 1 for _ in s:gmatch(",") do n = n + 1 end return n end
  eq("CSV fields line up", fields(row), fields(header))
  check("CSV group columns", row:find(",2,700,50$") ~= nil, row)
  noErrors(c)
end

H.group("a split moves the group's runs that began in the new copy")
do
  local c = raid10()
  c.enter("Deadmines", 36) c.tick(60)
  local st = c.run().serverStart
  c.encounter(644, "Rhahk'Zor", true, 20) c.tick(30)
  local h0 = #c.history()
  S(c, "Bob-Realm", st, 30, 0, 0)
  S(c, "Bob-Realm", st, 60, 300, 0)
  c.leave() c.tick(120) c.enter("Deadmines", 36) c.tick(30)
  S(c, "Bob-Realm", c.ns.ServerTime() - 20, 20, 0, 0)
  S(c, "Bob-Realm", c.ns.ServerTime() - 20, 40, 200, 0)
  c.encounter(644, "Rhahk'Zor", true, 20) c.tick(5)
  eq("split", #c.history(), h0 + 1)
  eq("old run keeps his first", c.history()[1].group.Bob.coin, 300)
  eq("new run has his new one", c.run().group and c.run().group.Bob and c.run().group.Bob.coin, 200)
  noErrors(c)
end

H.group("damaged saved group data is cleaned on load")
do
  local c = raid10()
  local st = c.run().serverStart
  S(c, "Bob-Realm", st, 30, 0, 0, MC)
  c.gainMoney(100)
  c.slash("end") c.tick(5)
  local saved = c.saved()
  local r = saved.db.history[1]
  r.group.Bob.coin = "lots"
  r.group[7] = { coin = 5 }
  r.group.Junk = "x"
  for i = 1, 50 do r.group["Z" .. i] = { coin = i, parts = {} } end
  local d = H.boot({ saved = saved }) d.login()
  local g = d.history()[1].group
  eq("bad number fixed", g.Bob and g.Bob.coin, 0)
  check("non-string key gone", g[7] == nil)
  check("non-table gone", g.Junk == nil)
  check("40 at most", count(g) <= 40, count(g))
  local lines = d.ns.GroupLines(d.history()[1])
  check("still shows", #lines > 0)
  d.slash("group")
  noErrors(d)
end

H.group("Group tab and command with no runs; a short-form run")
do
  local c = fresh()
  local lines = c.ns.GroupTabLines()
  check("no runs", c.strip(lines[1]):find("No runs yet", 1, true) ~= nil)
  c.slash("group")
  local l = c.ns.GroupLines({ lite = true })
  check("short form", c.strip(l[1]):find("short form", 1, true) ~= nil)
  eq("no rows for short form", #c.ns.GroupRows({ lite = true }), 0)
  noErrors(c)
end

H.group("friends list by GUID only; a known account that isn't a friend")
do
  local c = fresh()
  c.party("Mirel", "Pug1", "Pug2")
  c.friends.Mirel = true
  c.friendInfoOff = true
  c.enter("Deadmines", 36) c.tick(30)
  S(c, "Mirel-Realm", c.run().serverStart, 30, 0, 0)
  c.tick(40)
  eq("by GUID", c.ns.DB.partner, "Mirel")
  local d = fresh()
  d.party("Pug1", "Pug2", "Pug3")
  d.bnet.Pug1 = { "Pug#9999", false }
  d.enter("Deadmines", 36) d.tick(30)
  S(d, "Pug1-Realm", d.run().serverStart, 30, 0, 0)
  d.tick(40)
  check("not a friend: not paired", d.ns.DB.partner == nil)
  noErrors(c) noErrors(d)
end

H.group("group numbers never start a part in an older run")
do
  local c = raid10()
  c.leave() c.tick(5)
  c.enter("Deadmines", 36) c.tick(60) c.gainMoney(100)
  c.slash("end") c.leave() c.tick(5)
  c.enter("Molten Core", 409, { kind = "raid" }) c.tick(30)
  local dm
  for _, r in ipairs(c.history()) do if r.name == "Deadmines" then dm = r end end
  check("a Deadmines run in history", dm ~= nil)
  S(c, "Cid-Realm", dm.serverStart, 0, 0, 0)
  check("not added there", dm.group == nil or dm.group.Cid == nil)
  noErrors(c)
end

H.group("a reopened run counts the group's numbers from then on")
do
  local c = raid10()
  local st = c.run().serverStart
  S(c, "Bob-Realm", st, 30, 0, 0, MC)
  S(c, "Bob-Realm", st, 60, 600, 0, MC)
  c.gainMoney(100)
  c.slash("end") c.tick(10)
  S(c, "Bob-Realm", st, 120, 5000, 0, MC)
  c.slash("start") c.tick(5)
  S(c, "Bob-Realm", st, 130, 5200, 0, MC)
  eq("600, then 200 since", c.run().group.Bob.coin, 800)
  noErrors(c)
end

H.group("players with numbers come before those without, even with nothing yet")
do
  local c = fresh()
  local run = { char = "Tavlius-Realm", members = { "Abe", "Tavlius", "Zed" }, partners = {}, deaths = {}, drops = {},
    group = { Zed = { coin = 0, loot = 0, lootAH = 0, xp = 0, elapsed = 10, parts = {} } },
    coin = 0, loot = 0, lootAH = 0, xp = 0, elapsed = 10 }
  local rows = c.ns.GroupRows(run)
  eq("order", names(rows), "Tavlius,Zed,Abe")
  noErrors(c)
end

H.group("/runbook check says whether friends can be read")
do
  local c = fresh()
  c.slash("check")
  check("readable", anyPrinted(c, "Friends: Battle.net readable, friends list readable"))
  local d = fresh({ noFriendAPI = true })
  d.slash("check")
  check("not available", anyPrinted(d, "Friends: Battle.net not available, friends list not available"))
  noErrors(c) noErrors(d)
end

---------------------------------------------------------------------------
-- Audit cycle 1
---------------------------------------------------------------------------
H.group("someone from another realm with a friend's name is not your friend")
do
  local c = fresh()
  c.party("Mirel-Other", "Pug1", "Pug2")
  c.friends.Mirel = true
  c.enter("Deadmines", 36) c.tick(30)
  S(c, "Mirel-Other", c.run().serverStart, 30, 0, 0)
  c.tick(40)
  check("not paired", c.ns.DB.partner == nil)
  -- Your friend from that realm (on your friends list with it) is.
  local d = fresh()
  d.party("Mirel-Other", "Pug1", "Pug2")
  d.friends["Mirel-Other"] = true
  d.friendInfoOff = false
  d.group[1].secretGUID = true
  d.enter("Deadmines", 36) d.tick(30)
  S(d, "Mirel-Other", d.run().serverStart, 30, 0, 0)
  d.tick(40)
  eq("paired by the full name", d.ns.DB.partner, "Mirel")
  noErrors(c) noErrors(d)
end

H.group("a namesake of your partner from your realm stays apart from your partner")
do
  -- Your partner is Mirel from another realm; a Mirel from your realm is in the raid too.
  local c = fresh()
  c.party("Mirel-Other", "Mirel", "Bob", "Cid", "Dee", "Eve") c.raid = true
  c.enter("Molten Core", 409, { kind = "raid" }) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 0, 0, MC)
  S(c, "Mirel-Realm", st, 60, 40000, 0, MC)
  eq("the stranger in the group view", c.run().group.Mirel and c.run().group.Mirel.coin, 40000)
  c.slash("partner Mirel-Other")
  check("the stranger stays in the group view", c.run().group.Mirel ~= nil)
  check("nothing of his in your partner's", c.run().partners.Mirel == nil)
  S(c, "Mirel-Other", st, 90, 1000, 0, MC)
  eq("your partner's own", c.run().partners["Mirel-Other"] and c.run().partners["Mirel-Other"].coin, 1000)
  -- The stranger's final word (lower) parks nothing your partner's next run gets.
  S(c, "Mirel-Realm", st, 100, 1000, 0, { ended = true, map = "409", dungeon = "Molten Core" })
  local rows = c.ns.GroupRows(c.run())
  local both = 0
  for _, r in ipairs(rows) do if c.ns.ShortName(r.name) == "Mirel" then both = both + 1 end end
  eq("two rows, one each", both, 2)
  c.slash("end") c.leave() c.tick(5)
  c.enter("Molten Core", 409, { kind = "raid" }) c.tick(30)
  local st2 = c.run().serverStart
  S(c, "Mirel-Other", st2, 30, 500, 0, MC)
  eq("his new run: his own numbers only", c.run().partners["Mirel-Other"] and c.run().partners["Mirel-Other"].coin, 500)
  noErrors(c)
end

H.group("several friends who run RunBook: none is picked, you're told")
do
  local c = fresh()
  c.party("Mirel", "Bob", "Cid", "Dee", "Eve", "Fay") c.raid = true
  c.friends.Mirel, c.friends.Bob = true, true
  c.enter("Molten Core", 409, { kind = "raid" }) c.tick(30)
  local st = c.run().serverStart
  S(c, "Bob-Realm", st, 30, 0, 0, MC)
  c.tick(5)
  S(c, "Mirel-Realm", st, 30, 0, 0, MC)
  c.tick(40)
  check("no partner", c.ns.DB.partner == nil)
  check("told", anyPrinted(c, "Friends of yours here run RunBook (Bob, Mirel)"))
  -- (And it doesn't pick one later on its own.)
  c.clearPrinted()
  S(c, "Mirel-Realm", st, 90, 0, 0, MC)
  c.tick(40)
  check("still none", c.ns.DB.partner == nil)
  -- partner off: friends are picked again.
  c.slash("partner off")
  S(c, "Mirel-Realm", st, 120, 0, 0, MC)
  c.tick(40)
  eq("picked again (only Mirel was heard this time)", c.ns.DB.partner, "Mirel")
  noErrors(c)
  -- A friend who left before it was decided doesn't count.
  local d = fresh()
  d.party("Mirel", "Bob", "Cid", "Dee", "Eve", "Fay") d.raid = true
  d.friends.Mirel, d.friends.Bob = true, true
  d.enter("Molten Core", 409, { kind = "raid" }) d.tick(30)
  S(d, "Bob-Realm", d.run().serverStart, 30, 0, 0, MC)
  S(d, "Mirel-Realm", d.run().serverStart, 30, 0, 0, MC)
  table.remove(d.group, 2)  -- (Bob leaves)
  d.tick(40)
  eq("the one still here", d.ns.DB.partner, "Mirel")
  noErrors(d)
end

H.group("two characters of one Battle.net account side by side: no flip-flop")
do
  local c = fresh()
  c.party("Mirel", "Kelbox", "Pug1")
  c.slash("partner Mirel")
  c.bnet.Mirel, c.bnet.Kelbox = "Mirel#1111", "Mirel#1111"
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  for i = 1, 3 do
    S(c, "Mirel-Realm", st, 30 * i, 0, 0)
    S(c, "Kelbox-Realm", st, 30 * i, 0, 0)
  end
  eq("still Mirel", c.ns.DB.partner, "Mirel")
  check("no switch lines", not anyPrinted(c, "is on Kelbox now"))
  noErrors(c)
end

H.group("check: hidden players' GUIDs; CSV gold to the copper")
do
  local c = fresh()
  c.party("Mirel", "Pug1")
  c.group[1].secretGUID = true
  c.slash("check")
  check("says so", anyPrinted(c, "Battle.net not readable here (hidden players), friends list by name only"))
  local d = raid10()
  local st = d.run().serverStart
  S(d, "Bob-Realm", st, 30, 149, 0, MC)
  S(d, "Cid-Realm", st, 30, 149, 0, MC)
  d.gainMoney(149)
  d.tick(2)
  local row = d.ns.CSVRow(d.run())
  check("exact", row:find(",3,447,0$") ~= nil, row)
  noErrors(c) noErrors(d)
end

H.group("a namesake's final word never reaches your partner's numbers")
do
  local c = fresh()
  c.party("Mirel", "Mirel-Other", "Pug1", "Pug2")
  c.slash("partner Mirel-Other")
  c.enter("Deadmines", 36) c.tick(120)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 0, 0)
  S(c, "Mirel-Realm", st, 60, 900000, 0)
  S(c, "Mirel-Realm", st, 61, 0, 0, { ended = true })   -- (lower: his log split his run)
  local theirs = st - 300                                -- (your partner's run began well before yours)
  S(c, "Mirel-Other", theirs, 400, 950000, 0)
  S(c, "Mirel-Other", theirs, 430, 950000, 0)
  eq("your partner: nothing since your run began", c.run().partners["Mirel-Other"]
    and c.run().partners["Mirel-Other"].coin, 0)
  check("no Together from the stranger", not c.liveText():find("Together", 1, true), c.liveText())
  noErrors(c)
end

H.group("a group member's numbers from before your run began aren't counted")
do
  local c = fresh()
  c.party("Mirel", "Bob", "Cid", "Dee", "Eve", "Fay") c.raid = true
  c.slash("partner Mirel")
  local T = c.ns.ServerTime()
  -- Bob is inside already; you're still outside.
  S(c, "Bob-Realm", T, 20, 1000, 300, MC)
  c.tick(20)
  c.enter("Molten Core", 409, { kind = "raid" }) c.tick(10)
  S(c, "Bob-Realm", T, 50, 1500, 400, MC)
  eq("only what he made since", c.run().group.Bob and c.run().group.Bob.coin, 500)
  eq("XP since", c.run().group.Bob and c.run().group.Bob.xp, 100)
  noErrors(c)
end

---------------------------------------------------------------------------
-- Audit cycle 2
---------------------------------------------------------------------------
H.group("a friend on another RunBook version is never picked")
do
  local c = fresh()
  c.party("Guildie", "Mirel", "A", "B", "C", "D") c.raid = true
  c.friends.Guildie, c.friends.Mirel = true, true
  c.enter("Molten Core", 409, { kind = "raid" }) c.tick(30)
  local st = c.run().serverStart
  S(c, "Guildie-Realm", st, 30, 0, 0, { ver = 2, map = "409", dungeon = "Molten Core" })
  check("not at once", c.ns.DB.partner == nil)
  check("told about the version", anyPrinted(c, "Guildie runs an older RunBook"))
  S(c, "Mirel-Realm", st, 30, 0, 0, MC)
  c.tick(40)
  eq("the friend on this version", c.ns.DB.partner, "Mirel")
  noErrors(c)
end

H.group("a friend heard just before you left the group isn't picked")
do
  local c = fresh()
  c.party("Guildie", "Pug1", "Pug2")
  c.friends.Guildie = true
  c.enter("Deadmines", 36) c.tick(30)
  S(c, "Guildie-Realm", c.run().serverStart, 30, 0, 0)
  c.tick(10)
  c.party()
  c.tick(40)
  check("not picked", c.ns.DB.partner == nil)
  noErrors(c)
end

H.group("raid: a friend heard after one was picked gets a note")
do
  local c = fresh()
  c.party("Guildie", "Mirel", "A", "B", "C", "D") c.raid = true
  c.friends.Guildie, c.friends.Mirel = true, true
  c.enter("Molten Core", 409, { kind = "raid" }) c.tick(30)
  local st = c.run().serverStart
  S(c, "Guildie-Realm", st, 30, 0, 0, MC)
  c.tick(40)
  eq("picked", c.ns.DB.partner, "Guildie")
  S(c, "Mirel-Realm", st, 80, 0, 0, MC)
  check("told", anyPrinted(c, "Mirel also runs RunBook; your sync partner is Guildie. (/runbook partner Mirel"))
  -- (Not for a stranger in a raid: one note at most for them.)
  c.clearPrinted()
  S(c, "A-Realm", st, 80, 0, 0, MC)
  check("no note for a stranger", not anyPrinted(c, "A also runs RunBook"))
  noErrors(c)
end

H.group("changing partner mid-run moves the old one's numbers to the group view")
do
  local c = fresh()
  c.party("Guildie", "Mirel", "A", "B", "C", "D") c.raid = true
  c.friends.Guildie = true
  c.enter("Molten Core", 409, { kind = "raid" }) c.tick(30)
  local st = c.run().serverStart
  S(c, "Guildie-Realm", st, 30, 0, 0, MC)
  c.tick(40)
  S(c, "Guildie-Realm", st, 80, 7000, 0, MC)
  eq("picked", c.ns.DB.partner, "Guildie")
  c.slash("partner Mirel")
  S(c, "Mirel-Realm", st, 90, 900, 0, MC)
  check("Guildie isn't a partner any more", c.run().partners.Guildie == nil)
  eq("in the group view", c.run().group.Guildie and c.run().group.Guildie.coin, 7000)
  S(c, "Guildie-Realm", st, 100, 7500, 0, MC)
  eq("and grows there", c.run().group.Guildie.coin, 7500)
  eq("Together: Mirel only", c.ns.PartnersGold(c.run()), 900)
  local rows = c.ns.GroupRows(c.run())
  local g = 0
  for _, r in ipairs(rows) do if r.name == "Guildie" then g = g + 1 end end
  eq("one Guildie row", g, 1)
  noErrors(c)
end

H.group("partner off mid-run: no player counted twice")
do
  local c = fresh()
  c.party("Mirel", "Pug1")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 1000, 0)
  c.slash("partner off")
  S(c, "Mirel-Realm", st, 60, 1500, 0)
  local gold, _, n = c.ns.GroupTotals(c.run(), true)
  eq("gold", gold, 1500)
  eq("players with numbers", n, 2)
  check("no partner entry", next(c.run().partners) == nil)
  noErrors(c)
end

H.group("your partner on another character keeps the first one's numbers in your run")
do
  local c = fresh()
  c.party("Mirel", "Pug1")
  c.bnet.Mirel = "Mirel#1111"
  c.slash("partner Mirel")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 1000, 0)
  -- (He relogs onto his alt mid-run.)
  c.group[1].name = "Kelalt"
  c.bnet.Kelalt = "Mirel#1111"
  c.tick(5)
  S(c, "Kelalt-Realm", st + 100, 10, 300, 0)
  eq("now Kelalt", c.ns.DB.partner, "Kelalt")
  eq("Mirel's still a partner's", c.run().partners.Mirel and c.run().partners.Mirel.coin, 1000)
  eq("together", c.ns.PartnersGold(c.run()), 1300)
  noErrors(c)
end

H.group("several friends: settled while you're in that group, over a reload")
do
  local c = fresh()
  c.party("Guildie", "Mirel", "A", "B", "C", "D") c.raid = true
  c.friends.Guildie, c.friends.Mirel = true, true
  c.enter("Molten Core", 409, { kind = "raid" }) c.tick(30)
  local st = c.run().serverStart
  S(c, "Guildie-Realm", st, 30, 0, 0, MC)
  S(c, "Mirel-Realm", st, 30, 0, 0, MC)
  c.tick(40)
  check("none", c.ns.DB.partner == nil)
  local saved = c.savedCopy()
  local d = H.boot({ saved = saved, gap = 5 })
  d.group, d.raid = c.group, true
  d.friends.Guildie, d.friends.Mirel = true, true
  d.instance = c.instance d.lastInstance = c.instance
  d.login()
  d.tick(5)
  S(d, "Guildie-Realm", st, 80, 0, 0, MC)
  d.tick(40)
  check("still none after a reload", d.ns.DB.partner == nil)
  -- Leaving the group settles it: the next group can pick again.
  d.party() d.tick(2)
  d.party("Mirel", "Pug1", "Pug2")
  d.tick(2)
  S(d, "Mirel-Realm", st, 200, 0, 0, MC)
  d.tick(40)
  eq("picked in the next group", d.ns.DB.partner, "Mirel")
  noErrors(d)
end

H.group("what a friend sends during the wait is taken once they're picked")
do
  local c = fresh()
  c.party("Mirel", "Pug1")
  c.friends.Mirel = true
  c.item(500, "Blue Sword", 3, 1000)
  c.enter("Deadmines", 36) c.tick(5)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 5, 0, 0)
  c.tick(15)
  c.addonMsg("Mirel-Realm", string.format("D3|beef01|36|Deadmines||%d|500|1|3|%d", st, c.ns.ServerTime()))
  c.addonMsg("Mirel-Realm", string.format("N3|beef01|36|Deadmines||%d|1|pulled the patrol", st))
  check("not yet", #c.run().notes == 0)
  c.tick(30)
  eq("picked", c.ns.DB.partner, "Mirel")
  eq("his drop", #c.run().drops, 1)
  eq("his note", c.run().notes[1] and c.run().notes[1].text, "pulled the patrol")
  -- (At most 50 held per friend.)
  local e = fresh()
  e.party("Mirel", "Pug1")
  e.friends.Mirel = true
  e.enter("Deadmines", 36) e.tick(5)
  local est = e.run().serverStart
  S(e, "Mirel-Realm", est, 5, 0, 0)
  for i = 1, 60 do e.addonMsg("Mirel-Realm", string.format("N3|beef01|36|Deadmines||%d|1|note %d", est, i)) end
  local w = _G.VulcanRunBookCharDB.friendWait
  eq("50 kept while waiting", w and w.list.Mirel and #w.list.Mirel.held, 50)
  e.tick(40)
  eq("50 held", #e.run().notes, 50)
  noErrors(e)
  -- Not picked (several): nothing held is used.
  local d = fresh()
  d.party("Mirel", "Bob", "Pug1")
  d.friends.Mirel, d.friends.Bob = true, true
  d.enter("Deadmines", 36) d.tick(5)
  local dst = d.run().serverStart
  S(d, "Mirel-Realm", dst, 5, 0, 0)
  S(d, "Bob-Realm", dst, 5, 0, 0)
  d.addonMsg("Mirel-Realm", string.format("N3|beef01|36|Deadmines||%d|1|a note", dst))
  d.tick(40)
  eq("no note", #d.run().notes, 0)
  noErrors(c) noErrors(d)
end

---------------------------------------------------------------------------
-- Audit cycle 3
---------------------------------------------------------------------------
H.group("end, a new partner, then start: the old partner's numbers aren't your partner's")
do
  local c = fresh()
  c.party("Guildie", "Mirel", "Pug1")
  c.slash("partner Guildie")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Guildie-Realm", st, 30, 5000, 0)
  c.gainMoney(100)
  c.slash("end") c.tick(5)
  c.slash("partner Mirel")
  c.slash("start") c.tick(5)
  check("Guildie isn't a partner here", c.run().partners.Guildie == nil)
  eq("in the group view", c.run().group and c.run().group.Guildie and c.run().group.Guildie.coin, 5000)
  S(c, "Mirel-Realm", st, 40, 900, 0)
  eq("Together: Mirel's", c.ns.PartnersGold(c.run()), 900)
  local gold = c.ns.GroupTotals(c.run(), true)
  eq("Guildie once", gold, 100 + 5000 + 900)
  -- partner off in between: no Together at all.
  c.slash("end") c.tick(5)
  c.slash("partner off")
  c.slash("start") c.tick(5)
  eq("no partner numbers", c.ns.PartnersGold(c.run()), 0)
  noErrors(c)
end

H.group("followed onto an alt while the main is still in the group, offline")
do
  local c = fresh()
  c.party("Mirel", "Pug1")
  c.bnet.Mirel = "Mirel#1111"
  c.slash("partner Mirel")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 1000, 0)
  c.member("Mirel").offline = true
  c.party("Mirel", "Pug1", "Kelalt")
  c.member("Mirel").offline = true
  c.bnet.Kelalt = "Mirel#1111"
  c.tick(5)
  S(c, "Kelalt-Realm", st + 100, 10, 800, 0)
  eq("followed", c.ns.DB.partner, "Kelalt")
  eq("both in Together", c.ns.PartnersGold(c.run()), 1800)
  check("the main still counts as you two's", c.ns.IsDuo("Mirel"))
  -- The hint to switch back keeps both.
  c.slash("partner Mirel")
  eq("still both", c.ns.PartnersGold(c.run()), 1800)
  -- Someone else, or off: both go to the group view.
  c.slash("partner Pug1")
  check("neither in partners", c.run().partners.Mirel == nil and c.run().partners.Kelalt == nil)
  eq("both in the group view", (c.run().group.Mirel and c.run().group.Mirel.coin or 0)
    + (c.run().group.Kelalt and c.run().group.Kelalt.coin or 0), 1800)
  check("not you two's any more", not c.ns.IsDuo("Mirel") and not c.ns.IsDuo("Kelalt"))
  noErrors(c)
end

H.group("partner off: their deaths and drops aren't 'you two's' any more")
do
  local c = fresh()
  c.party("Mirel", "Pug1")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36) c.tick(30)
  S(c, "Mirel-Realm", c.run().serverStart, 30, 0, 0)
  check("duo", c.ns.IsDuo("Mirel"))
  c.slash("partner off")
  check("not duo", not c.ns.IsDuo("Mirel"))
  noErrors(c)
end

H.group("what a waited-on friend sent is taken however they become your partner")
do
  -- The group shrinks to two during the wait.
  local c = fresh()
  c.party("Mirel", "Pug1", "Pug2")
  c.friends.Mirel = true
  c.enter("Deadmines", 36) c.tick(5)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 5, 0, 0)
  c.addonMsg("Mirel-Realm", string.format("N3|beef01|36|Deadmines||%d|1|note one", st))
  c.party("Mirel")
  S(c, "Mirel-Realm", st, 15, 0, 0)
  eq("paired", c.ns.DB.partner, "Mirel")
  eq("note taken", #c.run().notes, 1)
  noErrors(c)
  -- Set by hand during the wait.
  local d = fresh()
  d.party("Mirel", "Pug1", "Pug2")
  d.friends.Mirel = true
  d.enter("Deadmines", 36) d.tick(5)
  local dst = d.run().serverStart
  S(d, "Mirel-Realm", dst, 5, 0, 0)
  d.addonMsg("Mirel-Realm", string.format("N3|beef01|36|Deadmines||%d|1|note one", dst))
  d.slash("partner Mirel")
  eq("note taken", #d.run().notes, 1)
  d.tick(40)
  eq("only once", #d.run().notes, 1)
  noErrors(d)
  -- A /reload during the wait.
  local e = fresh()
  e.party("Mirel", "Pug1", "Pug2")
  e.friends.Mirel = true
  e.enter("Deadmines", 36) e.tick(5)
  local est = e.run().serverStart
  S(e, "Mirel-Realm", est, 5, 0, 0)
  e.addonMsg("Mirel-Realm", string.format("N3|beef01|36|Deadmines||%d|1|note one", est))
  e.tick(10)
  local saved = e.savedCopy()
  local f = H.boot({ saved = saved, gap = 5 })
  f.group = e.group f.friends.Mirel = true
  f.instance = e.instance f.lastInstance = e.instance
  f.login() f.tick(5)
  S(f, "Mirel-Realm", est, 40, 0, 0)
  f.tick(40)
  eq("paired after the reload", f.ns.DB.partner, "Mirel")
  eq("note kept over it", #f.run().notes, 1)
  noErrors(f)
  -- A damaged saved wait is dropped.
  local saved2 = f.savedCopy()
  saved2.char.friendWait = { first = "x", list = 5 }
  local g = H.boot({ saved = saved2, gap = 5 }) g.login() g.tick(40)
  check("dropped", g.ns.DB.partner == "Mirel" and _G.VulcanRunBookCharDB.friendWait == nil)
  saved2 = g.savedCopy()
  saved2.char.friendWait = { first = 1, list = { Mirel = { name = "Mirel", sender = 5, held = {} },
    Bob = { name = "Bob", sender = "Bob-Realm", held = { { kind = 1 }, "x" } } } }
  local h = H.boot({ saved = saved2, gap = 5 }) h.login() h.tick(40)
  -- A saved wait holding too much: 50 taken at most.
  saved2 = h.savedCopy()
  saved2.db.partner, saved2.db.partnerChars = nil, nil
  local many = {}
  for i = 1, 60 do many[i] = { kind = "N", body = string.format("36|Deadmines||%d|1|n%d", est, i) } end
  saved2.char.friendWait = { first = 1, list = { Mirel = { name = "Mirel", sender = "Mirel-Realm", held = many } } }
  local k = H.boot({ saved = saved2, gap = 5 })
  k.group = e.group k.friends.Mirel = true
  k.instance = e.instance k.lastInstance = e.instance
  k.login() k.tick(40)
  eq("picked", k.ns.DB.partner, "Mirel")
  local n = 0
  for _, x in ipairs(k.run() and k.run().notes or {}) do if x.text:match("^n%d+$") then n = n + 1 end end
  eq("50 at most", n, 50)
  noErrors(g) noErrors(h) noErrors(k)
end

H.group("a friend on another version isn't picked in a two-person group either")
do
  local c = fresh()
  c.party("Guildie")
  c.friends.Guildie = true
  c.enter("Deadmines", 36) c.tick(5)
  S(c, "Guildie-Realm", c.run().serverStart, 5, 0, 0, { ver = 2 })
  check("not paired", c.ns.DB.partner == nil)
  check("told", anyPrinted(c, "Guildie runs an older RunBook"))
  noErrors(c)
end

H.group("two friends with one name on different realms are two friends")
do
  local c = fresh()
  c.party("Mirel", "Mirel-Other", "A", "B", "C", "D") c.raid = true
  c.friends.Mirel, c.friends["Mirel-Other"] = true, true
  c.enter("Molten Core", 409, { kind = "raid" }) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 0, 0, MC)
  S(c, "Mirel-Other", st, 30, 0, 0, MC)
  c.tick(40)
  check("none picked", c.ns.DB.partner == nil)
  check("both named", anyPrinted(c, "(Mirel, Mirel-Other)"))
  noErrors(c)
end

H.group("names hidden: two characters of one account side by side don't flip-flop")
do
  local c = fresh()
  c.party("Mirel", "Kelbox", "A", "B", "C", "D") c.raid = true
  c.bnet.Mirel, c.bnet.Kelbox = "Mirel#1111", "Mirel#1111"
  c.slash("partner Mirel")
  c.enter("Molten Core", 409, { kind = "raid" }) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 0, 0, MC)
  S(c, "Kelbox-Realm", st, 30, 0, 0, MC)
  for _, m in ipairs(c.group) do m.secretName = true end
  local seq = {}
  for i = 1, 3 do
    S(c, "Kelbox-Realm", st, 40 + i, 0, 0, MC) seq[#seq + 1] = c.ns.DB.partner
    S(c, "Mirel-Realm", st, 40 + i, 0, 0, MC) seq[#seq + 1] = c.ns.DB.partner
  end
  eq("Mirel throughout", table.concat(seq, ","), "Mirel,Mirel,Mirel,Mirel,Mirel,Mirel")
  noErrors(c)
end

H.group("a dungeon-finder group down to two: the stranger isn't picked")
do
  local c = fresh()
  c.party("Pug1", "Pug2", "Pug3", "Pug4")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Pug1-Realm", st, 30, 40000, 0)
  c.party("Pug1")
  S(c, "Pug1-Realm", st, 60, 41000, 0)
  check("not picked", c.ns.DB.partner == nil)
  eq("no Together", c.ns.PartnersGold(c.run()), 0)
  -- (Someone first heard in a two-person group is, as before.)
  local d = fresh()
  d.party("Mirel")
  d.enter("Deadmines", 36) d.tick(30)
  S(d, "Mirel-Realm", d.run().serverStart, 30, 0, 0)
  eq("picked", d.ns.DB.partner, "Mirel")
  noErrors(c) noErrors(d)
end

H.group("damaged saved partner characters are dropped")
do
  local c = fresh()
  c.slash("partner Mirel")
  local saved = c.savedCopy()
  saved.db.partnerChars = { Mirel = 5 }
  local d = H.boot({ saved = saved, gap = 5 }) d.login()
  check("dropped", _G.VulcanRunBookDB.partnerChars == nil or _G.VulcanRunBookDB.partnerChars.Mirel ~= 5)
  saved = d.savedCopy()
  saved.db.partnerChars = "x"
  local e = H.boot({ saved = saved, gap = 5 }) e.login()
  check("not a table: dropped", type(_G.VulcanRunBookDB.partnerChars) ~= "string")
  check("still works", e.ns.IsPartnerChar("Mirel"))
  noErrors(d) noErrors(e)
end

---------------------------------------------------------------------------
-- Audit cycle 4
---------------------------------------------------------------------------
H.group("reopening counts nothing made while the run was ended, for a new partner too")
do
  local c = fresh()
  c.party("Guildie", "Mirel", "Pug1")
  c.slash("partner Guildie")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Guildie-Realm", st, 30, 2000, 0)
  S(c, "Mirel-Realm", st, 30, 900, 0)
  c.slash("end") c.tick(10)
  S(c, "Mirel-Realm", st, 300, 50000, 0)
  c.slash("partner Mirel")
  c.slash("start") c.tick(2)
  S(c, "Mirel-Realm", st, 330, 50100, 0)
  eq("900 before, 100 since", c.ns.PartnersGold(c.run()), 1000)
  noErrors(c)
end

H.group("a partner from another realm moved to the group view keeps their realm")
do
  local c = fresh()
  c.party("Mirel-Other", "Guildie", "Pug1")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Other", st, 30, 5000, 0)
  c.slash("partner Guildie")
  S(c, "Mirel-Other", st, 60, 6000, 0)
  local gold, _, n = c.ns.GroupTotals(c.run(), true)
  eq("counted once", gold, 6000)
  eq("two players with numbers", n, 2)
  noErrors(c)
  -- Changed while the run was ended.
  local d = fresh()
  d.party("Mirel-Other", "Guildie", "Pug1")
  d.slash("partner Mirel")
  d.enter("Deadmines", 36) d.tick(30)
  local dst = d.run().serverStart
  S(d, "Mirel-Other", dst, 30, 5000, 0)
  d.gainMoney(100)
  d.slash("end") d.tick(5)
  d.slash("partner Guildie")
  d.slash("start") d.tick(5)
  S(d, "Mirel-Other", dst, 60, 6000, 0)
  local dg, _, dn = d.ns.GroupTotals(d.run(), true)
  eq("counted once (reopened)", dg, 6100)
  eq("two with numbers (you and Mirel)", dn, 2)
  -- Moved in from the group view and straight out again (no message between).
  local e = fresh()
  e.party("Mirel-Other", "Guildie", "Pug1")
  e.enter("Deadmines", 36) e.tick(30)
  local est = e.run().serverStart
  S(e, "Mirel-Other", est, 30, 0, 0)
  S(e, "Mirel-Other", est, 40, 5000, 0)
  e.slash("partner Mirel-Other")
  e.slash("partner Guildie")
  S(e, "Mirel-Other", est, 60, 6000, 0)
  local eg = e.ns.GroupTotals(e.run(), true)
  eq("counted once (moved twice)", eg, 6000)
  noErrors(d) noErrors(e)
end

H.group("a friend first heard in a bigger group is still picked in a two-person group")
do
  local c = fresh()
  c.party("Mirel", "Pug1", "Pug2", "Pug3")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 0, 0)    -- (not a friend yet)
  c.friends.Mirel = true                -- (added as a friend)
  c.party("Mirel")
  S(c, "Mirel-Realm", st, 60, 0, 0)
  eq("picked", c.ns.DB.partner, "Mirel")
  noErrors(c)
end

H.group("a stranger first heard in a bigger group gets a note when it's down to two")
do
  local c = fresh()
  c.party("Pug1", "Pug2", "Pug3")
  c.enter("Deadmines", 36) c.tick(30)
  S(c, "Pug1-Realm", c.run().serverStart, 30, 0, 0)
  c.party("Pug1")
  c.clearPrinted()
  S(c, "Pug1-Realm", c.run().serverStart, 60, 0, 0)
  check("told how", anyPrinted(c, "Pug1 runs RunBook too. If that's your duo partner"))
  noErrors(c)
end

H.group("a saved friend wait from the future doesn't block pairing")
do
  local c = fresh()
  c.party("Mirel", "Pug1", "Pug2")
  c.friends.Mirel = true
  local saved = c.savedCopy()
  saved.char.friendWait = { first = saved.wall + 10 * 86400, list = {} }
  local d = H.boot({ saved = saved, gap = 5 })
  d.group = c.group d.friends.Mirel = true
  d.login()
  d.enter("Deadmines", 36) d.tick(5)
  S(d, "Mirel-Realm", d.run().serverStart, 5, 0, 0)
  d.tick(40)
  eq("picked", d.ns.DB.partner, "Mirel")
  noErrors(d)
end

H.group("many characters of your partner's: at most 20 kept, never all dropped")
do
  local c = fresh()
  c.slash("partner Mirel")
  for i = 1, 25 do c.ns.DB.partnerChars["K" .. i] = true end
  local saved = c.savedCopy()
  local d = H.boot({ saved = saved, gap = 5 }) d.login()
  local n = 0
  for _ in pairs(_G.VulcanRunBookDB.partnerChars or {}) do n = n + 1 end
  check("20 at most, some kept", n > 0 and n <= 20, n)
  check("your partner kept", d.ns.IsPartnerChar("Mirel"))
  -- Following onto one more keeps 20.
  d.ns.SetPartner("Knew", nil, nil, true)
  n = 0
  for _ in pairs(_G.VulcanRunBookDB.partnerChars) do n = n + 1 end
  check("still 20 at most", n <= 20, n)
  check("the new one in", d.ns.IsPartnerChar("Knew"))
  noErrors(d)
end

H.group("two characters of your partner's online together: both your partner's")
do
  local c = fresh()
  c.bnet.Mirel, c.bnet.Kelbox = "Mirel#1111", "Mirel#1111"
  c.party("Mirel", "Pug1")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 1000, 0)
  c.member("Mirel").offline = true
  c.party("Mirel", "Pug1", "Kelbox") c.member("Mirel").offline = true
  c.tick(2)
  S(c, "Kelbox-Realm", st + 60, 10, 300, 0)
  eq("followed", c.ns.DB.partner, "Kelbox")
  c.member("Mirel").offline = false
  S(c, "Mirel-Realm", st, 120, 1600, 0)
  eq("still Kelbox", c.ns.DB.partner, "Kelbox")
  eq("Together: both, all of it", c.ns.PartnersGold(c.run()), 1900)
  local gold, _, n = c.ns.GroupTotals(c.run(), true)
  eq("counted once", gold, 1900)
  eq("three players", n, 3)
  noErrors(c)
end

H.group("partner Mirel with two Mirels in the group: the one from your realm")
do
  local c = fresh()
  c.party("Mirel", "Mirel-Other", "Pug1")
  c.slash("partner Mirel")
  eq("your realm's", c.ns.DB.partnerRealm, "Realm")
  c.enter("Deadmines", 36) c.tick(30)
  S(c, "Mirel-Other", c.run().serverStart, 30, 500, 0)
  check("the other Mirel's numbers aren't your partner's", next(c.run().partners) == nil)
  c.slash("partner Mirel")
  check("not even after a partner change", next(c.run().partners) == nil)
  c.slash("partner Mirel-Other")
  eq("by realm", c.ns.DB.partnerRealm, "Other")
  noErrors(c)
end

H.group("switching to a namesake on another realm is someone else")
do
  local c = fresh()
  c.party("Mirel", "Mirel-Other", "Pug1")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 4000, 0)
  c.slash("partner Mirel-Other")
  S(c, "Mirel-Other", st, 60, 900, 0)
  eq("Together: the new partner's only", c.ns.PartnersGold(c.run()), 900)
  noErrors(c)
end

H.group("partner <name> alt: your partner on a character the addon can't link")
do
  local c = fresh()
  c.bnet.Mirel, c.bnet.Kelalt = "Mirel#1111", "Mirel#1111"
  c.party("Mirel", "Pug1")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 1000, 0)
  c.party("Pug1", "Kelalt")
  for _, m in ipairs(c.group) do m.secretGUID = true end
  c.tick(60)
  c.ns.ForgetFriends()
  S(c, "Kelalt-Realm", st + 100, 10, 300, 0)
  check("not followed (no BattleTag readable)", c.ns.DB.partner == "Mirel")
  check("the hint says alt", anyPrinted(c, "/runbook partner Kelalt alt if that's Mirel on another character"))
  c.slash("partner Kelalt alt")
  S(c, "Kelalt-Realm", st + 100, 40, 400, 0)
  eq("both in Together", c.ns.PartnersGold(c.run()), 1400)
  check("Mirel still you two's", c.ns.IsDuo("Mirel"))
  -- Without "alt": someone else.
  c.slash("partner Pug1")
  eq("neither", c.ns.PartnersGold(c.run()), 0)
  noErrors(c)
  -- Side by side, switched by hand to the other character: the same person by BattleTag.
  local d = fresh()
  d.bnet.Mirel, d.bnet.Kelbox = "Mirel#1111", "Mirel#1111"
  d.party("Mirel", "Kelbox", "Pug1")
  d.slash("partner Mirel")
  d.enter("Deadmines", 36) d.tick(30)
  local dst = d.run().serverStart
  S(d, "Mirel-Realm", dst, 30, 1000, 0)
  d.slash("partner Kelbox")
  S(d, "Kelbox-Realm", dst, 40, 200, 0)
  eq("both in Together", d.ns.PartnersGold(d.run()), 1200)
  noErrors(d)
end

---------------------------------------------------------------------------
-- Audit cycle 5
---------------------------------------------------------------------------
H.group("a new partner who plays on while your run is ended: none of the gap counts")
do
  local c = fresh()
  c.party("Guildie", "Mirel", "Pug1")
  c.slash("partner Guildie")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Guildie-Realm", st, 30, 2000, 0)
  S(c, "Mirel-Realm", st, 30, 900, 0)
  c.slash("end") c.tick(5)
  c.slash("partner Mirel")
  for i = 1, 20 do c.tick(30) S(c, "Mirel-Realm", st, 30 + 30 * i, 900 + 2500 * i, 0) end
  c.slash("start") c.tick(2)
  S(c, "Mirel-Realm", st, 700, 50900 + 100, 0)
  eq("900 before, 100 since", c.ns.PartnersGold(c.run()), 1000)
  noErrors(c)
  -- Your partner from another realm plays on while it's ended; you change to someone else.
  local d = fresh()
  d.party("Mirel-Other", "Guildie", "Pug1")
  d.slash("partner Mirel-Other")
  d.enter("Deadmines", 36) d.tick(30)
  local dst = d.run().serverStart
  S(d, "Mirel-Other", dst, 30, 900, 0)
  d.slash("end") d.tick(5)
  for i = 1, 5 do d.tick(30) S(d, "Mirel-Other", dst, 30 + 30 * i, 900 + 2500 * i, 0) end
  d.slash("start") d.tick(2)
  S(d, "Mirel-Other", dst, 400, 900 + 12500 + 100, 0)
  eq("his: 900 before, 100 since", d.ns.PartnersGold(d.run()), 1000)
  check("the group key for someone on your realm, in any case",
    d.ns.GroupKey("Bob", "realm") == "Bob" and d.ns.GroupKey("Bob", "Other") == "Bob-Other")
  noErrors(d)
end

H.group("your partner back on a known character, alone: followed, everything taken")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 0, 0)          -- (two-person rule: no BattleTag)
  c.slash("end") c.leave() c.tick(5)
  c.party("Kelalt")
  c.enter("Deadmines", 36) c.tick(30)
  S(c, "Kelalt-Realm", c.run().serverStart, 30, 0, 0)
  c.slash("partner Kelalt alt")
  c.slash("end") c.leave() c.tick(5)
  c.party("Mirel")
  c.item(500, "Blue Sword", 3, 1000)
  c.enter("Deadmines", 36) c.tick(30)
  local st2 = c.run().serverStart
  S(c, "Mirel-Realm", st2, 30, 700, 0)
  eq("followed back", c.ns.DB.partner, "Mirel")
  c.addonMsg("Mirel-Realm", string.format("D3|beef01|36|Deadmines||%d|500|1|3|%d", st2, c.ns.ServerTime()))
  c.addonMsg("Mirel-Realm", string.format("N3|beef01|36|Deadmines||%d|1|hello", st2))
  eq("his drop", #c.run().drops, 1)
  eq("his note", #c.run().notes, 1)
  noErrors(c)
end

H.group("a /reload in a dungeon-finder group: the stranger still isn't picked at two")
do
  local c = fresh()
  c.party("Strange", "Pug2", "Pug3", "Pug4")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Strange-Realm", st, 30, 30000, 0)
  local saved = c.savedCopy()
  local d = H.boot({ saved = saved, gap = 5 })
  d.group = c.group
  d.instance = c.instance d.lastInstance = c.lastInstance
  d.login() d.tick(5)
  d.party("Strange")
  S(d, "Strange-Realm", st, 90, 40000, 0)
  check("not picked", d.ns.DB.partner == nil)
  -- Leaving the group forgets it.
  d.party() d.tick(2)
  check("forgotten", _G.VulcanRunBookCharDB.bigGroup == nil or next(_G.VulcanRunBookCharDB.bigGroup) == nil)
  noErrors(d)
end

H.group("a partner character saved without a realm is on yours")
do
  local c = fresh()
  c.slash("partner Mirel")
  c.party("Kelalt")
  c.enter("Deadmines", 36) c.tick(30)
  S(c, "Kelalt-Realm", c.run().serverStart, 30, 0, 0)
  c.slash("partner Kelalt alt")
  c.slash("end") c.leave() c.tick(600)
  c.party("Kelalt", "Mirel-Other", "Pug3", "Pug4")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Kelalt-Realm", st, 30, 1000, 0)
  S(c, "Mirel-Other", st, 30, 25000, 0)
  eq("Together: Kelalt's only", c.ns.PartnersGold(c.run()), 1000)
  check("Mirel-Other in the group view", c.run().group and c.run().group["Mirel-Other"] ~= nil)
  noErrors(c)
end

H.group("a realm typed in lower case is the game's realm")
do
  local c = fresh()
  c.party("Mirel-Other", "Guildie", "Pug1")
  c.slash("partner mirel-other")
  eq("as the game spells it", c.ns.DB.partnerRealm, "Other")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Other", st, 30, 5000, 0)
  c.slash("partner Guildie")
  S(c, "Mirel-Other", st, 60, 6000, 0)
  local gold, _, n = c.ns.GroupTotals(c.run(), true)
  eq("once", gold, 6000)
  eq("two with numbers", n, 2)
  noErrors(c)
end

---------------------------------------------------------------------------
-- Audit cycle 6
---------------------------------------------------------------------------
H.group("your partner on a character with the same name on another realm is followed")
do
  local c = fresh()
  c.bnet.Mirel = "Mirel#1111"
  c.party("Mirel")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 1000, 0)
  c.member("Mirel").offline = true
  c.group[2] = { name = "Mirel-Other", dead = false, feign = false }
  c.bnet["Mirel-Other"] = "Mirel#1111"
  c.fire("GROUP_ROSTER_UPDATE")
  c.tick(5)
  S(c, "Mirel-Other", st + 100, 30, 3000, 0)
  eq("followed", c.ns.DB.partnerRealm, "Other")
  check("both his characters known", c.ns.IsPartnerChar("Mirel", "Realm") and c.ns.IsPartnerChar("Mirel", "Other"))
  noErrors(c)
end

H.group("a namesake who becomes your partner never touches the old one's entry")
do
  local c = fresh()
  c.party("Mirel", "Mirel-Other", "Pug1")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 4000, 0)
  S(c, "Mirel-Other", st + 3, 27, 100, 0)
  c.slash("end") c.tick(5)
  c.slash("partner Mirel-Other")
  S(c, "Mirel-Other", st + 3, 60, 300, 0)
  eq("the ended run's entry is his alone", c.history()[1].partners.Mirel and c.history()[1].partners.Mirel.coin, 4000)
  c.slash("start") c.tick(2)
  S(c, "Mirel-Other", st + 3, 90, 400, 0)
  S(c, "Mirel-Realm", st, 90, 4500, 0)
  check("the old partner's 40s isn't in Together", c.ns.PartnersGold(c.run()) < 4000, c.ns.PartnersGold(c.run()))
  noErrors(c)
end

H.group("a bare name set before grouping is on your realm")
do
  local c = fresh()
  c.slash("partner Mirel")
  eq("your realm", c.ns.DB.partnerRealm, "Realm")
  c.party("Mirel-Other", "Pug1", "Pug2")
  c.enter("Deadmines", 36) c.tick(30)
  S(c, "Mirel-Other", c.run().serverStart, 30, 25000, 0)
  eq("not your partner", c.ns.PartnersGold(c.run()), 0)
  -- Retyping your partner's bare name keeps a realm already known.
  c.slash("partner Mirel-Other")
  c.party("Pug1")
  c.slash("partner Mirel")
  eq("kept", c.ns.DB.partnerRealm, "Other")
  noErrors(c)
end

H.group("your partner's realm learned from their first message: their group entry moves over")
do
  local c = fresh({ noRealm = true })
  c.party("Mirel", "Pug1", "Pug2")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 2000, 0)
  c.slash("partner Mirel")
  S(c, "Mirel-Realm", st, 60, 3000, 0)
  local gold, _, n = c.ns.GroupTotals(c.run(), true)
  eq("once", gold, 3000)
  eq("two with numbers", n, 2)
  noErrors(c)
end

H.group("damaged saved partner characters can't move your partner out")
do
  local c = fresh()
  c.party("Mirel", "Pug1")
  c.slash("partner Mirel")
  local saved = c.savedCopy()
  saved.db.partnerChars = { Mirel = "Other", [""] = true, X = "" }
  local d = H.boot({ saved = saved, gap = 5 })
  d.group = c.group
  d.login()
  d.enter("Deadmines", 36) d.tick(30)
  local st = d.run().serverStart
  S(d, "Mirel-Realm", st, 30, 2000, 0)
  d.gainMoney(100)
  d.slash("end") d.tick(5)
  d.slash("start") d.tick(2)
  eq("still your partner's", d.ns.PartnersGold(d.run()), 2000)
  check("bad entries gone", _G.VulcanRunBookDB.partnerChars[""] == nil and _G.VulcanRunBookDB.partnerChars.X == nil)
  noErrors(d)
end

H.group("a split keeps your partner's realm")
do
  local c = fresh()
  c.party("Mirel-Other", "Guildie", "Pug1")
  c.slash("partner Mirel-Other")
  c.enter("Deadmines", 36) c.tick(60)
  local st = c.run().serverStart
  c.encounter(644, "Rhahk'Zor", true, 20) c.tick(30)
  S(c, "Mirel-Other", st, 60, 300, 0)
  c.leave() c.tick(120) c.enter("Deadmines", 36) c.tick(30)
  local nst = c.ns.ServerTime() - 20
  S(c, "Mirel-Other", nst, 20, 0, 0)
  S(c, "Mirel-Other", nst, 40, 200, 0)
  c.encounter(644, "Rhahk'Zor", true, 20) c.tick(5)
  check("still under his realm's name", c.run().partners["Mirel-Other"] ~= nil)
  c.slash("partner off")
  S(c, "Mirel-Other", nst, 70, 900, 0)
  local _, _, n = c.ns.GroupTotals(c.run(), true)
  eq("counted once", n, 2)
  noErrors(c)
end

H.group("names hidden, a long boss fight: no flip to your partner's other character")
do
  local c = fresh()
  c.party("Mirel", "Kelbox", "Pug1")
  c.slash("partner Mirel")
  c.slash("partner Kelbox alt")
  c.item(500, "Blue Sword", 3, 1000)
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Kelbox-Realm", st, 10, 0, 0)            -- (heard as your partner)
  c.slash("partner Mirel")
  for _, m in ipairs(c.group) do m.secretName = true end
  S(c, "Mirel-Realm", st, 30, 1000, 0)
  S(c, "Kelbox-Realm", st, 30, 500, 0)
  c.tick(20)
  c.encounter(644, "Rhahk'Zor", true, 180)
  S(c, "Kelbox-Realm", st, 230, 700, 0)
  S(c, "Mirel-Realm", st, 230, 1500, 0)
  c.addonMsg("Mirel-Realm", string.format("D3|beef01|36|Deadmines||%d|500|1|3|%d", st, c.ns.ServerTime()))
  eq("still Mirel", c.ns.DB.partner, "Mirel")
  eq("his drop", #c.run().drops, 1)
  noErrors(c)
end

---------------------------------------------------------------------------
-- Audit cycle 7
---------------------------------------------------------------------------
H.group("your partner's same-named characters on two realms keep their own numbers")
do
  local c = fresh()
  c.bnet.Mirel, c.bnet["Mirel-Other"] = "Mirel#1111", "Mirel#1111"
  c.party("Mirel", "Mirel-Other", "Pug1")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Realm", st, 30, 1000, 0)
  S(c, "Mirel-Other", st, 30, 3000, 0)        -- (same run start: zoned in together)
  c.member("Mirel").offline = true
  c.fire("GROUP_ROSTER_UPDATE")
  c.tick(5)
  S(c, "Mirel-Other", st, 60, 3500, 0)
  eq("followed", c.ns.DB.partnerRealm, "Other")
  eq("Together: both characters", c.ns.PartnersGold(c.run()), 4500)
  eq("all of you", c.ns.GroupTotals(c.run(), true), 4500)
  noErrors(c)
end

H.group("the follow line's switch-back command keeps a partner from another realm")
do
  local c = fresh()
  c.bnet["Mirel-Other"], c.bnet["Kelbox-Other"] = "Mirel#1111", "Mirel#1111"
  c.party("Mirel-Other", "Pug1")
  c.slash("partner Mirel-Other")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Other", st, 30, 1000, 0)
  c.group[1] = { name = "Kelbox-Other", dead = false, feign = false }
  c.fire("GROUP_ROSTER_UPDATE") c.tick(5)
  S(c, "Kelbox-Other", st + 60, 30, 3000, 0)
  check("the line names the realm", anyPrinted(c, "(/runbook partner Mirel-Other to switch back.)"))
  c.slash("partner Mirel")
  eq("back on his realm", c.ns.DB.partnerRealm, "Other")
  eq("Together kept", c.ns.PartnersGold(c.run()), 4000)
  noErrors(c)
end

H.group("a character of your partner's never heard from isn't followed without a BattleTag")
do
  local c = fresh()
  c.slash("partner Mirel")
  c.party("Mirel-Other", "Pug1", "Pug2")
  c.enter("Deadmines", 36) c.tick(30)
  local st = c.run().serverStart
  S(c, "Mirel-Other", st, 30, 1000, 0)
  c.slash("partner Mirel-Other alt")
  S(c, "Mirel-Other", st, 60, 1500, 0)
  c.slash("end") c.leave() c.tick(5)
  c.party("Mirel", "Pug3", "Pug4")
  c.enter("Shadowfang Keep", 33) c.tick(30)
  S(c, "Mirel-Realm", c.run().serverStart, 30, 25000, 0, { map = "33", dungeon = "Shadowfang Keep" })
  eq("not your partner", c.ns.PartnersGold(c.run()), 0)
  eq("still the one on Other", c.ns.DB.partnerRealm, "Other")
  noErrors(c)
end

H.group("IsRunDuo: a saved run's partner from another realm")
do
  local c = fresh()
  local run = { char = "Tavlius-Realm", partners = { ["Mirel-Other"] = { coin = 0, parts = {} } } }
  check("their deaths are you two's", c.ns.IsRunDuo(run, "Mirel"))
  check("someone else's aren't", not c.ns.IsRunDuo(run, "Bob"))
  noErrors(c)
end

H.summary("tests_group.lua")
