-- RunBook tests for improvement loop 1.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check, eq = H.check, H.eq
dofile("duo_common.lua")

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
local function B(c, start, key, id, name, at, entry)
  if at then
    c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|%s|%d|%d|%d|%s", start, key, id, at, entry, name))
  else
    c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|%s|%d|%s", start, key, id, name))
  end
end

---------------------------------------------------------------------------
-- Reconciliation
---------------------------------------------------------------------------
H.group("a partner's split message while you're outside doesn't split your run")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(60) c.leave() c.tick(60) c.enter("Deadmines", 36) c.tick(120)
  c.leave() c.tick(30)
  c.addonMsg("Mirel", string.format("P3|beef01|36|Deadmines||%d|%d|", c.ns.ServerTime() - 10, c.ns.ServerTime()))
  check("same run", c.run() == run and not run.ended)
  noErrors(c)
end

H.group("his late message for the same kill isn't a reset")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(100)
  c.encounter(644, "Rhahk'Zor")
  local killed = c.ns.ServerTime()
  c.tick(60) c.leave() c.tick(60) c.enter("Deadmines", 36) c.tick(200)
  -- His message for that same kill, held up until now: it died when yours did.
  B(c, run.serverStart, "k.1", 644, "Rhahk'Zor", killed, run.serverStart)
  check("same run", c.run() == run)
  eq("one kill", names(run), "Rhahk'Zor")
  noErrors(c)
end

H.group("his kill minutes after yours, after you both came back in: a reset")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(100)
  c.encounter(644, "Rhahk'Zor")
  c.tick(60) c.leave() c.tick(60) c.enter("Deadmines", 36)
  local back = c.ns.ServerTime()
  c.tick(100)
  B(c, run.serverStart, "k.2", 644, "Rhahk'Zor", c.ns.ServerTime(), back)
  check("split", c.run() ~= run and run.endReason == "split")
  eq("new run", names(c.run()), "Rhahk'Zor")
  noErrors(c)
end

H.group("his /runbook end and back into the same copy isn't a new copy (his entry is)")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(100)
  c.encounter(644, "Rhahk'Zor")
  local hisRestart = c.ns.ServerTime() + 30     -- (his /runbook end and new run in the same copy)
  c.tick(200)
  c.encounter(646, "Sneed")
  c.item(500, "Blue Sword", 3, 100)
  c.addonMsg("Mirel", string.format("D3|beef01|36|Deadmines||%d|500|1|3|%d", hisRestart, c.ns.ServerTime()))
  c.tick(60) c.leave() c.tick(120)              -- (a reset nobody saw)
  local hisEntry = c.ns.ServerTime()
  c.tick(30)
  -- He kills Rhahk'Zor in the new copy; his run began at hisRestart, his entry is hisEntry.
  B(c, hisRestart, "k.5", 644, "Rhahk'Zor", c.ns.ServerTime(), hisEntry)
  check("your run ended (reset)", run.ended and run.endReason == "reset")
  eq("your old run keeps both", names(run), "Rhahk'Zor,Sneed")
  eq("and his drop from the old copy", #run.drops, 1)
  eq("the new run: his kill", c.run() and names(c.run()), "Rhahk'Zor")
  noErrors(c)
end

H.group("a ghost run back doesn't move where a split goes")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(100)
  c.encounter(644, "Rhahk'Zor")
  c.tick(60) c.leave() c.tick(60)               -- (reset nobody saw)
  c.enter("Deadmines", 36)
  c.tick(30)
  c.gainMoney(3000)
  c.die() c.tick(3) c.leave() c.tick(60)
  c.enter("Deadmines", 36) c.dead = false
  c.tick(30)
  c.encounter(644, "Rhahk'Zor")
  check("split", c.run() ~= run)
  eq("the new copy's coin moved", c.run().coin, 3000)
  eq("and the death", #c.run().deaths, 1)
  noErrors(c)
end

H.group("a boss that died in this copy in an earlier run dies again: new copy")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.encounter(644, "Rhahk'Zor")
  c.tick(30)
  c.slash("end")
  c.leave() c.tick(60)                          -- (a reset nobody saw)
  c.enter("Deadmines", 36)
  local run = c.run()
  eq("not counted yet", #_G.VulcanRunBookDB.entries, 1)
  c.tick(60)
  c.encounter(644, "Rhahk'Zor")
  check("same run", c.run() == run)
  eq("now a new instance", #_G.VulcanRunBookDB.entries, 2)
  check("said so", anyPrinted(c, "this run is in a new copy"))
  noErrors(c)
end

H.group("two clients: a kill only one log can place still reaches the other")
do
  local A, Bc = duo()
  local function kill(id, name, who)
    for _, x in ipairs(who) do D.use(x) x.fire("ENCOUNTER_START", id, name, 1, 5) end
    D.tick(A, Bc, 10)
    for _, x in ipairs(who) do D.use(x) x.fire("BOSS_KILL", id, name) x.fire("ENCOUNTER_END", id, name, 1, 5, 1) end
    D.tick(A, Bc, 3)
  end
  D.use(Bc) Bc.enter("Deadmines", 36) D.tick(A, Bc, 30)
  kill(1, "Rhahk'Zor", { Bc })
  D.tick(A, Bc, 60)
  D.use(A) A.enter("Deadmines", 36) D.tick(A, Bc, 30)
  kill(2, "Sneed", { A, Bc })
  D.tick(A, Bc, 60)
  D.use(A) A.leave() D.use(Bc) Bc.leave() D.tick(A, Bc, 60)
  D.use(A) A.enter("Deadmines", 36) D.use(Bc) Bc.enter("Deadmines", 36) D.tick(A, Bc, 60)
  kill(1, "Rhahk'Zor", { A, Bc })
  D.tick(A, Bc, 5)
  D.use(A)
  eq("Tavlius's new run", names(A.run()), "Rhahk'Zor")
  noErrors(A, Bc)
end

H.group("two clients: his kill shows your log a reset his log can't see; his run splits too")
do
  local A, Bc = duo()
  local function kill(id, name, who)
    for _, x in ipairs(who) do D.use(x) x.fire("ENCOUNTER_START", id, name, 1, 5) end
    D.tick(A, Bc, 10)
    for _, x in ipairs(who) do D.use(x) x.fire("BOSS_KILL", id, name) x.fire("ENCOUNTER_END", id, name, 1, 5, 1) end
    D.tick(A, Bc, 3)
  end
  D.use(A) A.enter("Deadmines", 36) D.tick(A, Bc, 30)
  kill(1, "Rhahk'Zor", { A })                    -- Tavlius alone
  D.tick(A, Bc, 60)
  D.use(Bc) Bc.enter("Deadmines", 36) D.tick(A, Bc, 30)
  kill(2, "Sneed", { A, Bc })
  D.tick(A, Bc, 60)
  D.use(A) A.leave() D.use(Bc) Bc.leave() D.tick(A, Bc, 60)   -- (a reset nobody saw)
  D.use(Bc) Bc.enter("Deadmines", 36) D.tick(A, Bc, 60)
  kill(1, "Rhahk'Zor", { Bc })                   -- Mirel, in the new copy; Tavlius still outside
  D.tick(A, Bc, 5)
  D.use(Bc)
  eq("Mirel's run now", names(Bc.run()), "Rhahk'Zor")
  eq("Mirel's earlier run", Bc.history()[1] and names(Bc.history()[1]), "Sneed")
  noErrors(A, Bc)
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
H.group("partner numbers: only finite whole numbers")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  local s = c.run().serverStart
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|10|1e308|0|0|0|0", s))
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|10|inf|0|0|0|0", s))
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|10|3.5|0|0|0|0", s))
  c.addonMsg("Mirel", string.format("D3|beef01|36|Deadmines||%d|nan|1|3|%d", s, s))
  c.addonMsg("Mirel", string.format("D3|beef01|36|Deadmines||%d|100|inf|3|%d", s, s))
  local p = c.run().partners.Mirel
  check("no infinite gold", not p or (p.coin or 0) < 1e12)
  eq("no drops", #c.run().drops, 0)
  noErrors(c)
end

H.group("only from your group, on your group's channel")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(300)
  local x = string.format("X3|beef01|36|Deadmines||%d|1", c.ns.ServerTime())
  c.fire("CHAT_MSG_ADDON", "VulcanRunBook", x, "WHISPER", "Mirel")
  check("a whisper can't start your run over", c.run() == run)
  c.fire("CHAT_MSG_ADDON", "VulcanRunBook", x, "PARTY", "Stranger")
  check("nor someone outside your group", c.run() == run)
  c.fire("CHAT_MSG_ADDON", "VulcanRunBook", string.format("S3|cafe01|36|Deadmines||%d|10|500|0|0|0|0|0",
    c.run().serverStart), "PARTY", "Stranger")
  check("not even in the group view", c.run().group == nil or c.run().group.Stranger == nil)
  c.fire("CHAT_MSG_ADDON", "VulcanRunBook", x, "PARTY", "Mirel-OtherRealm")
  check("nor a Mirel from another realm", c.run() == run)
  c.fire("CHAT_MSG_ADDON", "VulcanRunBook", x, "PARTY", "Mirel-Realm")
  check("your partner can", c.run() ~= run)
  noErrors(c)
end

H.group("a partner's boss name is cleaned and capped")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  B(c, c.run().serverStart, "k.1", 0, "|Hurl:x|h[Click]|h" .. string.rep("y", 100))
  local n = c.run().bosses[1] and c.run().bosses[1].name or ""
  check("no link code", not n:find("|H", 1, true), n)
  check("100 bytes at most", #n <= 100, #n)
  noErrors(c)
end

H.group("your note fits one message, so both logs keep the same text")
do
  local c = fresh()
  duoSolo(c)
  local long = "Скарлетский монастырь и его очень длинное название"
  c.enter(long, 9999)
  c.slash("note " .. string.rep("ж", 120))
  local note = c.run().notes[1]
  check("cut", note and #note.text < 240)
  local sent
  for _, m in ipairs(c.addonSent) do if m.msg:find("^N") then sent = m.msg end end
  c.tick(2)
  for _, m in ipairs(c.addonSent) do if m.msg:find("^N") then sent = m.msg end end
  check("whole in the message", sent and sent:find(note.text, 1, true) ~= nil)
  noErrors(c)
end

H.group("an older client's 'not now' is retried")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  local real = c.ns.SendAddon
  local busy = true
  c.ns.SendAddon = function(...) if busy then return false end return real(...) end
  c.slash("note later")
  c.tick(3)
  busy = false
  c.tick(3)
  local sent = false
  for _, m in ipairs(c.addonSent) do if m.msg:find("later", 1, true) then sent = true end end
  check("sent once it could", sent)
  c.ns.SendAddon = real
  noErrors(c)
end

H.group("a different version: both get the notice")
do
  local c = fresh()
  duoSolo(c)
  c.addonMsg("Mirel", "S2|beef01|36|Deadmines||1|1|1|1|1|1|0")
  check("told", anyPrinted(c, "older RunBook"))
  noErrors(c)
end

---------------------------------------------------------------------------
-- Saved data, patterns, bags
---------------------------------------------------------------------------
H.group("a damaged saved run doesn't stop the history")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100) c.encounter(1, "A") c.leave()
  c.system("Deadmines has been reset.") c.tick(5)
  local s = c.savedCopy(false)
  local r = s.db.history[1]
  r.startedAt, r.serverEnd, r.savedServer = "x", {}, "y"
  r.members = { 5, "Tavlius" }
  r.drops = { { id = 1, q = "blue", who = 7, name = {} } }
  r.deaths = { { who = {} } }
  r.coin = 0 / 0
  s.char.mirror = nil
  local x = H.boot({ saved = s })
  x.login()
  x.slash("history")
  local ok = pcall(x.ns.HistoryContent)
  check("history renders", ok)
  check("details render", pcall(x.ns.RunDetailLines, x.history()[1]))
  check("export works", pcall(x.ns.ExportLines))
  check("stats work", pcall(x.ns.DungeonLines))
  noErrors(x)
end

H.group("the dungeon finder's 'too many instances' isn't the cap")
do
  local c = fresh()
  check("queue error", not c.ns.IsTooManyInstances("You are queued for too many instances."))
  check("the cap", c.ns.IsTooManyInstances("You have entered too many instances recently."))
  -- (A client without the strings: the English text itself, not the queue's.)
  local a, b = _G.TRANSFER_ABORT_TOO_MANY_INSTANCES, _G.ERR_TOO_MANY_INSTANCES
  _G.TRANSFER_ABORT_TOO_MANY_INSTANCES, _G.ERR_TOO_MANY_INSTANCES = nil, nil
  check("queue error, no strings", not c.ns.IsTooManyInstances("You are queued for too many instances."))
  check("the cap, no strings", c.ns.IsTooManyInstances("You have entered too many instances recently."))
  _G.TRANSFER_ABORT_TOO_MANY_INSTANCES, _G.ERR_TOO_MANY_INSTANCES = a, b
  noErrors(c)
end

H.group("Korean reset messages")
do
  local c = fresh()
  local restore = c.ns.ResetPattern("%s|1이;가; 초기화되었습니다.")
  eq("name", c.ns.ParseReset("데드마인이 초기화되었습니다."), "데드마인")
  restore()
  eq("English again", c.ns.ParseReset("Deadmines has been reset."), "Deadmines")
  noErrors(c)
end

H.group("a reset message naming 'The Deadmines' ends a 'Deadmines' run")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(100) c.leave()
  c.system("The Deadmines has been reset.")
  check("ended", run.ended and run.endReason == "reset")
  noErrors(c)
end

H.group("a stack that dips and comes back isn't loot")
do
  local c = fresh()
  c.item(1251, "Linen Bandage", 1, 10)
  c.bagSlots = { { id = 1251, n = 10 } }
  c.enter("Deadmines", 36)
  c.tick(70)
  c.ns.lastHiddenLootAt = GetTime()
  c.bagSlots[1].n = 5 c.fire("BAG_UPDATE_DELAYED") c.tick(2)
  c.ns.lastHiddenLootAt = GetTime()
  c.bagSlots[1].n = 10 c.fire("BAG_UPDATE_DELAYED") c.tick(2)
  eq("no loot", c.run().loot, 0)
  noErrors(c)
end

---------------------------------------------------------------------------
-- Cap
---------------------------------------------------------------------------
H.group("the daily cap")
do
  local c = fresh()
  local now = c.ns.ServerTime()
  for i = 1, 29 do table.insert(_G.VulcanRunBookDB.entries, now - 7200 - i * 60) end
  c.enter("Deadmines", 36)
  local line = c.strip(c.ns.DayCapLine())
  eq("line", line:match("Instances %d+/%d+ today"), "Instances 30/30 today")
  check("the hour's line too", c.strip(c.ns.CapLine()):find("this hour", 1, true) ~= nil)
  check("start line says so", anyPrinted(c, "30/30 instances today"))
  noErrors(c)
end

H.group("the game let you in past the cap: said once")
do
  local c = fresh()
  local now = c.ns.ServerTime()
  for i = 1, 5 do table.insert(_G.VulcanRunBookDB.entries, now - i * 60) end
  c.enter("Deadmines", 36)
  check("hint", anyPrinted(c, "Forever's limit may be higher"))
  noErrors(c)
end

---------------------------------------------------------------------------
-- Player-facing
---------------------------------------------------------------------------
H.group("a typed boss name matches how you wrote it before")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100) c.slash("boss Edwin VanCleef") c.tick(30) c.leave()
  c.system("Deadmines has been reset.") c.tick(5)
  c.enter("Deadmines", 36) c.tick(100) c.slash("boss VanCleef")
  eq("canonical", names(c.run()), "Edwin VanCleef")
  c.tick(20)
  c.slash("final nobody")
  check("final lists bosses", anyPrinted(c, "Bosses there: Edwin VanCleef"))
  noErrors(c)
end

H.group("old spellings still count as the same boss")
do
  local c = fresh()
  for _, n in ipairs({ "VanCleef", "Edwin VanCleef" }) do
    c.enter("Deadmines", 36) c.tick(100) c.ns.AddBoss(nil, n, "manual") c.tick(30) c.leave()
    c.system("Deadmines has been reset.") c.tick(5)
  end
  local s = c.ns.DungeonStats()[1]
  eq("both clears", s.clears, 2)
  noErrors(c)
end

H.group("an ambiguous name stays as typed")
do
  local c = fresh()
  c.enter("Scholomance", 289) c.tick(100)
  c.slash("boss Lord Alexei Barov") c.tick(30) c.slash("boss Lady Illucia Barov") c.tick(30)
  eq("as typed", c.ns.KnownBossName(c.ns.RunKey(c.run()), "Barov", c.run()), "Barov")
  noErrors(c)
end

H.group("/runbook new on a run with kills asks first")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(150) c.encounter(644, "Rhahk'Zor")
  c.slash("new")
  check("asked", c.run() == run and anyPrinted(c, "again within 15 seconds"))
  c.slash("new")
  check("done", c.run() ~= run)
  noErrors(c)
end

H.group("alts: whose run, and clear says all characters")
do
  local c = fresh({ name = "Altchar" })
  c.enter("Deadmines", 36) c.tick(100) c.leave() c.system("Deadmines has been reset.") c.tick(5)
  local s = c.savedCopy(false)
  s.char = nil
  local x = H.boot({ saved = s, name = "Tavlius" })
  x.login()
  x.enter("Deadmines", 36) x.tick(100) x.leave() x.system("Deadmines has been reset.") x.tick(5)
  local row = x.strip(x.ns.RunRowText(x.history()[2]))
  check("row shows the alt", row:find("Altchar", 1, true) ~= nil, row)
  x.clearPrinted()
  x.slash("clear")
  check("all characters", anyPrinted(x, "for all your characters"))
  noErrors(c, x)
end

H.group("raid deaths: you two's")
do
  local c = fresh()
  c.party("Mirel", "A", "B", "C", "D", "E", "F", "G", "H", "I")
  c.raid = true
  c.slash("partner Mirel")
  c.enter("Molten Core", 409, { kind = "raid" })
  c.tick(100)
  for _, n in ipairs({ "A", "B", "Mirel" }) do c.member(n).dead = true c.tick(2) c.member(n).dead = false c.tick(2) end
  eq("count", c.ns.DeathCount(c.run()), 1)
  local text = c.strip(table.concat(c.ns.LiveLines(), "\n"))
  check("live", text:find("1 death (Mirel)", 1, true) ~= nil, text)
  local detail = c.strip(table.concat(c.ns.RunDetailLines(c.run()), "\n"))
  check("group as a count", detail:find("Group: 11 players, with", 1, true) ~= nil, detail)
  noErrors(c)
end

H.group("hand marks from either of you are labelled")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  c.tick(60)
  B(c, c.run().serverStart, "k.1!m", 0, "Sneed")
  local detail = c.strip(table.concat(c.ns.RunDetailLines(c.run()), "\n"))
  check("labelled", detail:find("(marked by hand)", 1, true) ~= nil, detail)
  noErrors(c)
end

H.group("together gold on the run's end line and in the stats")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  local s = c.run().serverStart
  c.tick(400)
  c.gainMoney(10000)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|400|20000|0|0|0|0", s))
  c.leave() c.system("Deadmines has been reset.") c.tick(5)
  check("end line", anyPrinted(c, "together 3g"))
  local stats = c.strip(table.concat(c.ns.DungeonLines(), "\n"))
  check("stats", stats:find("together", 1, true) ~= nil, stats)
  noErrors(c)
end

H.group("/runbook check: resets, group, last message")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|1|0|0|0|0|0", c.run().serverStart))
  c.leave()
  c.system("Deadmines has been reset.")
  c.clearPrinted()
  c.slash("check")
  check("resets", anyPrinted(c, "1 reset messages seen this session, 1 matched"))
  check("group", anyPrinted(c, "Group: 2 members, names readable for 2"))
  check("last message", anyPrinted(c, "Last message from Mirel:"))
  noErrors(c)
end

H.group("your group changed while you were outside: a reminder")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  c.tick(100) c.leave()
  c.group = {} c.fire("GROUP_ROSTER_UPDATE")
  c.party("Mirel")
  c.enter("Deadmines", 36)
  check("reminded", anyPrinted(c, "Your group changed while you were outside"))
  noErrors(c)
end

---------------------------------------------------------------------------
-- Audit cycle 1
---------------------------------------------------------------------------
H.group("Sneed and Sneed's Shredder are two bosses")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100) c.slash("boss Sneed's Shredder") c.tick(40) c.slash("boss Sneed")
  eq("both", names(c.run()), "Sneed's Shredder,Sneed")
  c.slash("unboss")
  c.tick(30) c.leave() c.tick(30) c.enter("Deadmines", 36) c.tick(30)
  c.slash("boss Sneed")                                -- (after a repair trip)
  check("no false reset", #c.history() == 0)
  eq("Sneed added", names(c.run()), "Sneed's Shredder,Sneed")
  c.tick(30) c.leave() c.system("Deadmines has been reset.") c.tick(5)
  c.enter("Deadmines", 36) c.tick(100) c.slash("boss Sneed")
  eq("typed name kept", c.run().bosses[1].name, "Sneed")
  noErrors(c)
end

H.group("two brothers, two bosses seconds apart")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  c.tick(100)
  c.slash("boss Sneed's Shredder")
  c.tick(5)
  B(c, c.run().serverStart, "k.1!m", 0, "Sneed")
  eq("two kills", #c.run().bosses, 2)
  noErrors(c)
end

H.group("back into a Scarlet Monastery wing after a reset nobody saw")
do
  local c = fresh()
  c.mapGroups = { [302] = 50, [305] = 50 }
  c.groupFloors = { [50] = { { mapID = 302, name = "Graveyard" }, { mapID = 305, name = "Cathedral" } } }
  c.enter("Scarlet Monastery", 189, { uiMap = 305 }) c.tick(100)
  c.encounter(1, "High Inquisitor Whitemane") c.tick(30)
  c.leave() c.tick(20)
  c.enter("Scarlet Monastery", 189, { uiMap = 302 }) c.tick(10) c.tick(100)
  c.leave() c.tick(60)                                     -- (a reset nobody saw)
  c.enter("Scarlet Monastery", 189, { uiMap = 305 }) c.tick(10) c.tick(60)
  local before = #_G.VulcanRunBookDB.entries
  c.encounter(1, "High Inquisitor Whitemane")
  check("found the reset", #_G.VulcanRunBookDB.entries == before + 1 or anyPrinted(c, "dungeon was reset"))
  noErrors(c)
end

H.group("a partner's messages are trusted when party names can't be read")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  c.member("Mirel").secretName = true
  c.addonMsg("Mirel", string.format("N3|beef01|36|Deadmines||%d|1|hello", c.run().serverStart))
  eq("note arrived", #c.run().notes, 1)
  noErrors(c)
end

H.group("damaged settings are put right at load")
do
  local c = fresh()
  local s = c.savedCopy(false)
  s.db.point = { {}, "CENTER", "x", 1 }
  s.db.scale = 0
  s.db.quality = 3.5
  s.db.priceSource = 7
  s.db.finals = { bad = 5, ["36::1"] = { name = {} } }
  s.db.debugLog = { "ok", {} }
  s.char.mirror = nil
  local x = H.boot({ saved = s })
  x.login()
  eq("point", x.ns.DB.point[1], "CENTER")
  eq("scale", x.ns.DB.scale, 1)
  eq("quality", x.ns.DB.quality, 2)
  eq("price", x.ns.DB.priceSource, "vendor")
  check("finals", next(x.ns.DB.finals) == nil)
  x.slash("quality") x.slash("final") x.slash("price") x.slash("debug")
  check("export debug", pcall(x.ns.ExportLines, "debug"))
  noErrors(x)
end

---------------------------------------------------------------------------
-- Audit cycle 2
---------------------------------------------------------------------------
H.group("his kill right after his entry: no endless loop")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  c.tick(200)
  c.encounter(1763, "Gilnid")
  local K = c.ns.ServerTime()
  local E = K + 3
  c.tick(60)
  c.die() c.tick(5) c.leave() c.tick(60)
  local D = c.ns.ServerTime()
  local start = os.clock()
  local stuck = false
  debug.sethook(function() if os.clock() - start > 3 then stuck = true error("stuck") end end, "", 100000)
  pcall(c.addonMsg, "Mirel-Realm", string.format("B3|beef01|36|Deadmines||%d|beef01.7|1763|%d|%d|Gilnid", E - 100,
    D, E))
  debug.sethook()
  check("returned", not stuck)
  local n = 0
  for _, p in ipairs(c.printed) do if p:find("killed again", 1, true) then n = n + 1 end end
  check("said once", n <= 1, n)
  eq("his kill in the new run", c.run() and names(c.run()), "Gilnid")
  eq("yours stays in the old one", c.history()[1] and names(c.history()[1]), "Gilnid")
  noErrors(c)
end

H.group("a slot frees up by the hour but the day is full: not 'free'")
do
  local c = fresh()
  c.slash("cap day 5")
  local now = c.ns.ServerTime()
  for i = 1, 5 do table.insert(_G.VulcanRunBookDB.entries, now - 3500 + i) end
  c.tick(10)
  c.clearPrinted()
  c.tick(200, 5)
  check("not free", not anyPrinted(c, "slot is free again"))
  noErrors(c)
end

H.group("'Edwin Van Cleef' is 'Edwin VanCleef'")
do
  local c = fresh()
  for _, n in ipairs({ "Edwin VanCleef", "Edwin VanCleef" }) do
    c.enter("Deadmines", 36) c.tick(100) c.ns.AddBoss(nil, n, "manual") c.tick(30) c.leave()
    c.system("Deadmines has been reset.") c.tick(5)
  end
  c.enter("Deadmines", 36) c.tick(100) c.slash("boss Edwin Van Cleef")
  eq("typed name canonical", names(c.run()), "Edwin VanCleef")
  c.run().bosses[1].name = "Edwin Van Cleef"             -- (as an older version would have kept it)
  c.tick(30) c.leave() c.system("Deadmines has been reset.") c.tick(5)
  eq("three clears", c.ns.DungeonStats()[1].clears, 3)
  noErrors(c)
end

H.group("/runbook unboss takes back the instance a mistaken mark counted")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(200) c.slash("boss Rhahk'Zor") c.tick(200) c.slash("boss Sneed's Shredder") c.tick(30)
  c.slash("end") c.leave() c.tick(60) c.enter("Deadmines", 36) c.tick(100)
  local before = #_G.VulcanRunBookDB.entries
  c.slash("boss Sneed's Shredder")
  eq("counted", #_G.VulcanRunBookDB.entries, before + 1)
  c.clearPrinted()
  c.slash("unboss")
  eq("taken back", #_G.VulcanRunBookDB.entries, before)
  check("said so", anyPrinted(c, "taken back too"))
  c.tick(100)
  c.slash("boss Sneed's Shredder")
  eq("and it's still known to have died here", #_G.VulcanRunBookDB.entries, before + 1)
  noErrors(c)
end

H.group("NaN in saved entries and junk in waiting prices don't stop loading")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100)
  local s = c.savedCopy(false)
  s.db.entries = { 0 / 0, 1 / 0, s.db.entries[1] }
  s.char.run.pending = { a = { id = 5, n = 1, tries = "x", v = {} } }
  s.char.mirror = nil
  local x = H.boot({ saved = s })
  x.login()
  x.tick(5)
  check("run restored", x.run() ~= nil)
  noErrors(x)
end

---------------------------------------------------------------------------
-- Audit cycle 3
---------------------------------------------------------------------------
H.group("the instance a kill counted goes with that kill only")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(100)
  c.encounter(644, "Rhahk'Zor") c.tick(30)
  c.slash("end") c.leave() c.tick(60)
  c.enter("Deadmines", 36) c.tick(60)
  local before = #_G.VulcanRunBookDB.entries
  c.fire("BOSS_KILL", c.SECRET, c.SECRET)
  c.tick(3)
  local now = c.ns.ServerTime()
  c.addonMsg("Mirel-Realm", string.format("B3|beef01|36|Deadmines||%d|beef01.1|644|%d|%d|Rhahk'Zor", now - 50, now,
    now - 50))
  c.tick(2)
  eq("counted", #_G.VulcanRunBookDB.entries, before + 1)
  c.tick(100)
  c.encounter(645, "Sneed") c.tick(5)
  c.slash("unboss")                                   -- (Sneed: not the kill that counted it)
  eq("still counted", #_G.VulcanRunBookDB.entries, before + 1)
  c.slash("unboss")                                   -- (Rhahk'Zor)
  eq("taken back with it", #_G.VulcanRunBookDB.entries, before)
  noErrors(c)
end

H.group("a different boss typed right after a reported kill is added")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100)
  c.fire("BOSS_KILL", 0, "Sneed's Shredder")
  c.tick(4)
  c.slash("boss Sneed")
  eq("both", names(c.run()), "Sneed's Shredder,Sneed")
  noErrors(c)
end

H.group("damaged partner parts in a saved run don't break the live window")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(100)
  c.addonMsg("Mirel-Realm", string.format("S3|beef01|36|Deadmines||%d|100|50|60|70|80|0", c.ns.run.serverStart))
  c.tick(2)
  local s = c.savedCopy(false)
  for _, e in pairs(s.char.run.partners) do for _, p in pairs(e.parts) do p.at = "12" p.rawv = { "x" } end end
  s.char.partnerTotals = { bad = { 1, 2, "3", 4, 5, at = 1, d = "Deadmines" } }
  local x = H.boot({ saved = s })
  x.instance = { name = "Deadmines", map = 36, diff = 1, kind = "party", uiMap = 10036 }
  x.login() x.tick(20)
  check("live renders", pcall(x.ns.LiveLines))
  x.slash("end") x.slash("start")
  noErrors(x)
end

H.group("logged out inside for 40 minutes, back in the same place: the same run")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(300)
  c.encounter(644, "Rhahk'Zor") c.tick(30)
  local s = c.savedCopy(false)
  local s2 = c.savedCopy(false)                        -- (before another client takes the globals)
  local x = H.boot({ saved = s, gap = 2400 })
  x.instance = { name = "Deadmines", map = 36, diff = 1, kind = "party", uiMap = 10036 }
  x.login() x.tick(10)
  eq("one kill, same run", x.run() and #x.run().bosses, 1)
  eq("nothing saved", #x.history(), 0)
  eq("one entry", #_G.VulcanRunBookDB.entries, 1)
  local y = H.boot({ saved = s2, gap = 2400 })
  y.login() y.tick(10)                                 -- (outside this time)
  check("ended at logout", y.run() == nil and y.history()[1] and y.history()[1].endReason == "login")
  noErrors(c, x, y)
end

---------------------------------------------------------------------------
-- Audit cycle 4
---------------------------------------------------------------------------
H.group("the key, then the name: a boss that died here before still shows the reset")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100) c.slash("boss Rhahk'Zor") c.tick(30)
  c.slash("end") c.leave() c.tick(60)                  -- (a reset nobody saw)
  c.enter("Deadmines", 36) c.tick(100)
  local before = #_G.VulcanRunBookDB.entries
  _G.VulcanRunBook_MarkBoss()
  c.tick(3)
  c.slash("boss Rhahk'Zor")
  eq("new instance", #_G.VulcanRunBookDB.entries, before + 1)
  check("said so", anyPrinted(c, "died here before"))
  noErrors(c)
end

H.group("damaged partner keys, short-form boss ids and resume points")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(100)
  c.encounter(644, "Rhahk'Zor") c.tick(60) c.leave() c.tick(60) c.enter("Deadmines", 36) c.tick(60)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|100|50|60|70|80|0", c.run().serverStart))
  local s = c.savedCopy(false)
  s.char.run.partners[7] = { coin = 1 }
  s.char.run.resumeSnap.coin = nil
  s.char.run.reopenSnap = 5
  s.db.old = { { lite = true, name = "Deadmines", mapID = 36, diff = 1, serverStart = 5, startedAt = 5,
    elapsed = 100, bosses = { { id = {}, name = "X", t = 10 } } } }
  s.char.mirror = nil
  local x = H.boot({ saved = s })
  x.instance = { name = "Deadmines", map = 36, diff = 1, kind = "party", uiMap = 10036 }
  x.login() x.tick(10)
  check("live", pcall(x.ns.LiveLines))
  check("details", pcall(x.ns.RunDetailLines, x.run()))
  check("stats", pcall(x.ns.DungeonLines))
  local el = x.run().elapsed
  x.encounter(644, "Rhahk'Zor")
  check("clock kept", x.run().elapsed >= el or #x.history() > 0)
  x.slash("end") x.slash("start") x.tick(5) x.encounter(645, "Sneed")
  noErrors(x)
end

---------------------------------------------------------------------------
-- Audit cycle 5
---------------------------------------------------------------------------
local function bossNames(r) local t = {} for _, b in ipairs(r.bosses) do t[#t + 1] = b.name end return table.concat(t, ",") end

H.group("a kill named only by its end event gets the usual checks")
do
  -- (a) a reset nobody saw: the kill splits the run, as a named kill does
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100)
  c.encounter(644, "Rhahk'Zor") c.tick(60)
  c.leave() c.tick(60) c.enter("Deadmines", 36) c.tick(100)
  c.fire("ENCOUNTER_START", c.SECRET, c.SECRET, 1, 5) c.tick(20)
  c.fire("BOSS_KILL", c.SECRET, c.SECRET) c.tick(1)
  c.fire("ENCOUNTER_END", 644, "Rhahk'Zor", 1, 5, 1) c.tick(3)
  eq("split off", #c.history(), 1)
  eq("new run has the kill", bossNames(c.run()), "Rhahk'Zor")
  -- (b) after /runbook end and back in: "died here before" counts the instance
  local d = fresh()
  d.enter("Deadmines", 36) d.tick(100)
  d.encounter(644, "Rhahk'Zor") d.tick(30)
  d.slash("end") d.leave() d.tick(60) d.enter("Deadmines", 36) d.tick(100)
  local before = #_G.VulcanRunBookDB.entries
  d.fire("ENCOUNTER_START", d.SECRET, d.SECRET, 1, 5) d.tick(20)
  d.fire("BOSS_KILL", d.SECRET, d.SECRET) d.tick(1)
  local kt = d.run().bosses[1].t
  d.tick(1)
  d.fire("ENCOUNTER_END", 644, "Rhahk'Zor", 1, 5, 1) d.tick(3)
  eq("new instance", #_G.VulcanRunBookDB.entries, before + 1)
  eq("recorded again, same time", d.run().bosses[1].t, kt)
  eq("one kill", bossNames(d.run()), "Rhahk'Zor")
  -- (c) the plain case still just names it, keeping its time
  local e = fresh()
  e.enter("Deadmines", 36) e.tick(100)
  e.fire("ENCOUNTER_START", e.SECRET, e.SECRET, 1, 5) e.tick(20)
  e.fire("BOSS_KILL", e.SECRET, e.SECRET) e.tick(1)
  local t = e.run().bosses[1].t
  e.fire("ENCOUNTER_END", 644, "Rhahk'Zor", 1, 5, 1) e.tick(3)
  eq("named", bossNames(e.run()), "Rhahk'Zor")
  eq("time kept", e.run().bosses[1].t, t)
  noErrors(c, d, e)
end

H.group("a partner's kill named in a second message gets the usual checks")
do
  -- (a) his hand mark, then its name, of a boss you marked: one kill
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(100)
  c.slash("boss Rhahk'Zor") c.tick(300)
  local now = c.ns.ServerTime()
  c.addonMsg("Mirel-Realm", string.format("B3|beef01|36|Deadmines||%d|beef01.1!m|0|%d|%d|", now - 30, now, now - 30))
  c.tick(25)
  eq("his press is a second kill for now", #c.run().bosses, 2)
  c.addonMsg("Mirel-Realm", string.format("B3|beef01|36|Deadmines||%d|beef01.1!m|0|%d|%d|Rhahk'Zor", now - 30, now, now - 30))
  c.tick(3)
  eq("one kill once named", bossNames(c.run()), "Rhahk'Zor")
  -- (b) his game kill while you're outside, unnamed then named: your run ends
  local d = fresh()
  duoSolo(d)
  d.enter("Deadmines", 36) d.tick(100)
  d.encounter(644, "Rhahk'Zor") d.tick(60)
  local run = d.run()
  d.leave() d.tick(300)
  local entry, at = d.ns.ServerTime() - 200, d.ns.ServerTime()
  d.addonMsg("Mirel-Realm", string.format("B3|beef01|36|Deadmines||%d|beef01.1|0|%d|%d|", entry, at, entry))
  d.tick(2)
  d.addonMsg("Mirel-Realm", string.format("B3|beef01|36|Deadmines||%d|beef01.1|644|%d|%d|Rhahk'Zor", entry, at, entry))
  d.tick(3)
  check("old run ended", run.ended == true)
  eq("old run keeps its kill only", bossNames(run), "Rhahk'Zor")
  eq("his kill in the new run", d.run() and bossNames(d.run()), "Rhahk'Zor")
  -- (c) his unnamed kill, then a name nobody has: named in place, keeps its place
  local e = fresh()
  duoSolo(e)
  e.enter("Deadmines", 36) e.tick(100)
  local n2 = e.ns.ServerTime()
  e.addonMsg("Mirel-Realm", string.format("B3|beef01|36|Deadmines||%d|beef01.1|0|%d|%d|", n2 - 100, n2, n2 - 100))
  e.tick(30)
  e.encounter(645, "Sneed") e.tick(5)
  e.addonMsg("Mirel-Realm", string.format("B3|beef01|36|Deadmines||%d|beef01.1|644|%d|%d|Rhahk'Zor", n2 - 100, n2, n2 - 100))
  e.tick(3)
  eq("named in place", bossNames(e.run()), "Rhahk'Zor,Sneed")
  noErrors(c, d, e)
end

H.group("a kill recorded again under its name doesn't pair with another kill")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(100)
  c.encounter(644, "Rhahk'Zor") c.tick(30)
  c.slash("end") c.leave() c.tick(60)
  c.enter("Deadmines", 36) c.tick(100)
  local st, now = c.run().serverStart, c.ns.ServerTime()
  c.addonMsg("Mirel-Realm", string.format("B3|beef01|36|Deadmines||%d|beef01.1!m|0|%d|%d|", st - 300, now, st - 300))
  c.tick(25)
  c.fire("BOSS_KILL", c.SECRET, c.SECRET) c.tick(5)
  c.addonMsg("Mirel-Realm", string.format("B3|beef01|36|Deadmines||%d|beef01.1!m|0|%d|%d|Rhahk'Zor", st - 300, now, st - 300))
  c.tick(3)
  eq("two kills, his named", bossNames(c.run()), "Rhahk'Zor,Boss 2")
  noErrors(c)
end

H.group("key, then name: his hand mark of a boss that died before your run says nothing")
do
  for _, mode in ipairs({ "direct", "key" }) do
    local c = fresh()
    duoSolo(c)
    c.enter("Deadmines", 36) c.tick(100)
    c.encounter(644, "Rhahk'Zor") c.tick(30)
    c.slash("end") c.leave() c.tick(60)
    c.enter("Deadmines", 36) c.tick(100)
    local before = #_G.VulcanRunBookDB.entries
    local st, now = c.run().serverStart, c.ns.ServerTime()
    if mode == "key" then
      c.addonMsg("Mirel-Realm", string.format("B3|beef01|36|Deadmines||%d|beef01.1!m|0|%d|%d|", st - 300, now, st - 300))
      c.tick(3)
    end
    c.addonMsg("Mirel-Realm", string.format("B3|beef01|36|Deadmines||%d|beef01.1!m|0|%d|%d|Rhahk'Zor", st - 300, now, st - 300))
    c.tick(3)
    eq(mode .. ": no new instance", #_G.VulcanRunBookDB.entries, before)
    check(mode .. ": no reset said", not anyPrinted(c, "died here before"))
    noErrors(c)
  end
end

H.group("a named mark then the game's other boss within 10 s: two kills")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100)
  c.slash("boss Sneed") c.tick(5)
  c.fire("BOSS_KILL", 643, "Sneed's Shredder") c.tick(2)
  eq("both kept", bossNames(c.run()), "Sneed,Sneed's Shredder")
  -- (an unnamed mark is still the game's kill)
  local d = fresh()
  d.enter("Deadmines", 36) d.tick(100)
  _G.VulcanRunBook_MarkBoss() d.tick(5)
  d.fire("BOSS_KILL", 643, "Sneed's Shredder") d.tick(2)
  eq("one kill", bossNames(d.run()), "Sneed's Shredder")
  noErrors(c, d)
end

H.group("a damaged backup clear time or run number doesn't empty the history")
do
  local c = fresh()
  for _ = 1, 3 do
    c.enter("Deadmines", 36) c.tick(100) c.encounter(644, "Rhahk'Zor") c.tick(10)
    c.slash("end") c.leave() c.tick(40) c.system("Deadmines has been reset.")
  end
  local s = c.savedCopy(false)
  local s2 = c.savedCopy(false)
  s.char.mirror.clearedAt = 1e13
  s.db.clearedAt = 1e14
  local x = H.boot({ saved = s }) x.login() x.tick(5)
  eq("history kept", #_G.VulcanRunBookDB.history, 3)
  s2.char.mirror.nextId = 1 / 0
  local y = H.boot({ saved = s2 }) y.login() y.tick(5)
  check("run numbers finite", _G.VulcanRunBookDB.nextId < 1e15)
  noErrors(x, y)
end

---------------------------------------------------------------------------
-- Audit cycle 6
---------------------------------------------------------------------------
local function sentB(c)
  local t = {}
  for _, m in ipairs(c.addonSent) do
    if m.msg:sub(1, 1) == "B" then
      local f = {}
      for x in (m.msg .. "|"):gmatch("([^|]*)|") do f[#f + 1] = x end
      t[#t + 1] = { key = f[7], name = f[11], msg = m.msg }
    end
  end
  return t
end

H.group("a kill recorded again keeps its tag, so your partner's copy gets the name")
do
  -- (a) a reset nobody saw, named only when the fight ends: sent again under the same tag
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(100)
  c.encounter(644, "Rhahk'Zor") c.tick(30)
  c.slash("end") c.leave() c.tick(60) c.enter("Deadmines", 36) c.tick(100)
  c.fire("ENCOUNTER_START", c.SECRET, c.SECRET, 1, 5) c.tick(20)
  c.fire("BOSS_KILL", c.SECRET, c.SECRET) c.tick(1)
  c.fire("ENCOUNTER_END", 644, "Rhahk'Zor", 1, 5, 1) c.tick(3)
  local b = sentB(c)
  local n = #b
  check("sent unnamed, then named", n >= 2 and b[n - 1].name == "" and b[n].name == "Rhahk'Zor")
  eq("same tag", n >= 2 and b[n].key, n >= 2 and b[n - 1].key)
  eq("the kill keeps it", c.run().bosses[1].key, b[n].key)
  -- (b) merged into a kill you have: the name still goes out under its tag
  local d = fresh()
  duoSolo(d)
  d.enter("Deadmines", 36) d.tick(100)
  d.slash("boss Rhahk'Zor") d.tick(60)
  d.fire("ENCOUNTER_START", d.SECRET, d.SECRET, 1, 5) d.tick(20)
  d.fire("BOSS_KILL", d.SECRET, d.SECRET) d.tick(1)
  local unnamed = d.run().bosses[2] and d.run().bosses[2].key
  d.fire("ENCOUNTER_END", 644, "Rhahk'Zor", 1, 5, 1) d.tick(3)
  eq("one kill", bossNames(d.run()), "Rhahk'Zor")
  local e = sentB(d)
  check("its name sent under its tag", unnamed and e[#e].key == unnamed and e[#e].name == "Rhahk'Zor")
  noErrors(c, d)
end

H.group("a mark the fight's end names is the game's kill")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(100)
  c.fire("ENCOUNTER_START", c.SECRET, c.SECRET, 1, 5) c.tick(20)
  _G.VulcanRunBook_MarkBoss() c.tick(2)
  c.fire("BOSS_KILL", c.SECRET, c.SECRET) c.tick(1)
  c.fire("ENCOUNTER_END", 644, "Rhahk'Zor", 1, 5, 1) c.tick(3)
  local b = c.run().bosses[1]
  check("not by hand", b and b.name == "Rhahk'Zor" and not b.manual and not b.byHand and not b.src)
  local m = sentB(c)
  check("sent without the hand flag", not m[#m].key:find("!m", 1, true) and m[#m].name == "Rhahk'Zor")
  noErrors(c)
end

H.group("your own kill named by your partner stays yours")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(100)
  c.encounter(644, "Rhahk'Zor") c.tick(30)
  c.slash("end") c.leave() c.tick(60) c.enter("Deadmines", 36) c.tick(100)
  _G.VulcanRunBook_MarkBoss() c.tick(2)
  local b = c.run().bosses[1]
  local key, t = b.key, b.t
  local st = c.run().serverStart
  c.clearPrinted()
  c.addonMsg("Mirel-Realm", string.format("B3|beef01|36|Deadmines||%d|%s|0|%d|%d|Rhahk'Zor", st, key, b.st, st))
  c.tick(2)
  local x = c.run().bosses[1]
  check("yours, by hand", x and x.name == "Rhahk'Zor" and x.src == "manual" and x.byHand)
  eq("its time", x and x.t, t)
  eq("its tag", x and x.key, key)
  check("not from your partner", not anyPrinted(c, "from your partner"))
  noErrors(c)
end

---------------------------------------------------------------------------
-- Audit cycle 7
---------------------------------------------------------------------------
H.group("two hidden kills seconds apart, named at each fight's end: two kills")
do
  local c = fresh()
  c.enter("Deadmines", 36) c.tick(100)
  c.fire("ENCOUNTER_START", c.SECRET, c.SECRET, 1, 5) c.tick(20)
  c.fire("BOSS_KILL", c.SECRET, c.SECRET) c.tick(1)
  c.fire("ENCOUNTER_END", 643, "Sneed's Shredder", 1, 5, 1) c.tick(1)
  c.fire("ENCOUNTER_START", c.SECRET, c.SECRET, 1, 5) c.tick(4)
  c.fire("BOSS_KILL", c.SECRET, c.SECRET) c.tick(1)
  c.fire("ENCOUNTER_END", 645, "Sneed", 1, 5, 1) c.tick(3)
  eq("both", bossNames(c.run()), "Sneed's Shredder,Sneed")
  -- (nothing readable at all in the second fight: still a second kill)
  local f = fresh()
  f.enter("Deadmines", 36) f.tick(100)
  f.encounter(643, "Sneed's Shredder") f.tick(1)
  f.fire("ENCOUNTER_START", f.SECRET, f.SECRET, 1, 5) f.tick(4)
  f.fire("BOSS_KILL", f.SECRET, f.SECRET) f.tick(1)
  f.fire("ENCOUNTER_END", f.SECRET, f.SECRET, 1, 5, 1) f.tick(3)
  eq("a second, unnamed", bossNames(f.run()), "Sneed's Shredder,Boss 2")
  noErrors(f)
  -- your mark of one boss, then the fight's end names another
  local d = fresh()
  d.enter("Deadmines", 36) d.tick(100)
  d.fire("ENCOUNTER_START", d.SECRET, d.SECRET, 1, 5) d.tick(20)
  d.slash("boss Sneed") d.tick(5)
  d.fire("BOSS_KILL", d.SECRET, d.SECRET)
  d.fire("ENCOUNTER_END", 643, "Sneed's Shredder", 1, 5, 1) d.tick(3)
  eq("mark and the game's kill", bossNames(d.run()), "Sneed,Sneed's Shredder")
  -- (the same name at the end is still one kill)
  local e = fresh()
  e.enter("Deadmines", 36) e.tick(100)
  e.fire("ENCOUNTER_START", e.SECRET, e.SECRET, 1, 5) e.tick(20)
  e.slash("boss Sneed") e.tick(5)
  e.fire("BOSS_KILL", e.SECRET, e.SECRET)
  e.fire("ENCOUNTER_END", 645, "Sneed", 1, 5, 1) e.tick(3)
  eq("one kill", bossNames(e.run()), "Sneed")
  noErrors(c, d, e)
end

H.group("his mark the game named later isn't shown as by hand")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36) c.tick(100)
  local st, now = c.run().serverStart, c.ns.ServerTime()
  c.addonMsg("Mirel-Realm", string.format("B3|beef01|36|Deadmines||%d|beef01.1!m|0|%d|%d|", st, now, st))
  c.tick(3)
  check("by hand at first", c.run().bosses[1] and c.run().bosses[1].byHand)
  c.addonMsg("Mirel-Realm", string.format("B3|beef01|36|Deadmines||%d|beef01.1|644|%d|%d|Rhahk'Zor", st, now, st))
  c.tick(3)
  local b = c.run().bosses[1]
  check("the game's kill now", b and b.name == "Rhahk'Zor" and not b.byHand)
  noErrors(c)
end

H.summary("tests_il1.lua")
