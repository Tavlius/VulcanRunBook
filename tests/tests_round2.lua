-- RunBook tests for the audit round 2 fixes: final boss rules, floors and wings,
-- reload + split, partner identity, bag loot rules, backups, old runs, quiet.
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

-- A full run: kills at the given run times (each fight 30s), then out + reset.
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
H.group("final boss: rare kills, stray marks, pins")
do
  local c = fresh()
  local A, B, C, R = { 1, "Aggem" }, { 2, "Blind Hunter" }, { 3, "Charlga" }, { 9, "Earthcaller" }
  local function k(b, t) return { b[1], b[2], t } end
  clear(c, "Razorfen Kraul", 47, { k(A, 100), k(B, 200), k(C, 440) })
  clear(c, "Razorfen Kraul", 47, { k(A, 90), k(B, 190), k(C, 400) })
  -- A third run also kills a rare after the last boss.
  clear(c, "Razorfen Kraul", 47, { k(A, 100), k(B, 200), k(C, 450), k(R, 640) })
  local key = c.ns.RunKey(c.history()[1])
  eq("final boss stays Charlga (2 of 3 runs end there... and the rare run killed him too)",
    c.ns.FinalBoss(key).name, "Charlga")
  local s = c.ns.DungeonStats()[1]
  eq("all three are clears", s.clears, 3)
  eq("best unchanged", s.best, 400)
  -- Pressing /runbook boss right after a reported kill is ignored (it's that kill).
  c.enter("Razorfen Kraul", 47)
  c.tick(100)
  c.encounter(1, "Aggem", true, 30)
  c.tick(100)
  c.encounter(3, "Charlga", true, 30)
  c.slash("boss")
  c.slash("boss")
  c.leave()
  c.system("Razorfen Kraul has been reset.")
  eq("a second press right after a kill isn't a new boss", c.ns.FinalBoss(key).name, "Charlga")
  -- Pin the final boss by name; undo with auto.
  c.slash("final earthcaller")
  eq("pinned", c.ns.FinalBoss(key).name, "Earthcaller")
  eq("only the rare run is a clear now", c.ns.DungeonStats()[1].clears, 1)
  check("pin shown in stats", c.strip(c.ns.DungeonLines()[2]):find("pinned", 1, true) ~= nil,
    c.strip(c.ns.DungeonLines()[2]))
  c.slash("final nobody")
  check("unknown boss refused", c.printedMatch("No kill of", true) ~= nil)
  c.slash("final auto")
  eq("back to automatic", c.ns.FinalBoss(key).name, "Charlga")
  c.slash("final")
  check("final shows current", c.printedMatch("Final boss for Razorfen Kraul: Charlga", true) ~= nil)
  -- /runbook unboss takes back a mistaken mark.
  c.enter("Razorfen Kraul", 47)
  c.tick(50)
  c.slash("boss Oops")
  eq("marked", #c.run().bosses, 1)
  c.slash("unboss")
  eq("taken back", #c.run().bosses, 0)
  c.slash("unboss")
  check("nothing to take back", c.printedMatch("No boss kill to take back", true) ~= nil)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a nameless kill then the named event")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.fire("ENCOUNTER_END", H.SECRET, H.SECRET, 1, 5, 1)
  c.fire("BOSS_KILL", 1144, "Rhahk'Zor")
  eq("one boss", #c.run().bosses, 1)
  eq("named by the second event", c.run().bosses[1].name, "Rhahk'Zor")
  eq("with its ID", c.run().bosses[1].id, 1144)
  -- The same kill reported again 12s later (same visit): still one.
  c.tick(12)
  c.fire("ENCOUNTER_END", 1144, "Rhahk'Zor", 1, 5, 1)
  eq("late duplicate in the same visit", #c.run().bosses, 1)
  check("no split", c.history()[1] == nil)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("floors and wings")
do
  local c = fresh()
  -- Floors with no shared map group: walking between them never ends a run.
  c.enter("Blackrock Depths", 230, { uiMap = 242 })
  local run = c.run()
  c.tick(100)
  c.instance.uiMap = 243
  c.tick(20)
  check("floor change inside: same run", c.run() == run)
  eq("one cap entry", #_G.VulcanRunBookDB.entries, 1)
  -- Re-entering with the map reading stale (the outdoor zone) for a moment.
  c.instance.uiMap = 242
  c.leave()
  c.instance = nil
  c.enter("Blackrock Depths", 230, { uiMap = 1428 })  -- stale outdoor map...
  c.instance.uiMap = 242                              -- ...settles before the re-read
  c.tick(5)
  check("stale map on entry: same run", c.run() == run)
  -- Scarlet Monastery with unreadable wings: a hint to use /runbook new.
  local s = fresh()
  s.secret.uimap = true
  s.enter("Scarlet Monastery", 189)
  check("no hint before it gives up", s.printedMatch("wings can't be told apart", true) == nil)
  s.tick(15)
  check("multi-wing hint", s.printedMatch("wings can't be told apart", true) ~= nil)
  check("started line after it", s.printedMatch("Scarlet Monastery started", true) ~= nil)
  noErrors(c, s)
end

---------------------------------------------------------------------------
H.group("reload inside, then an unseen reset is found")
do
  local c = fresh()
  c.item(100, "Cruel Barb", 3, 5000)
  c.enter("Deadmines", 36)
  c.tick(200)
  c.encounter(1144, "Rhahk'Zor", true, 30)
  c.leave()
  c.tick(60)
  c.enter("Deadmines", 36)   -- a new copy (reset unseen)
  c.tick(300)
  c.lootMsg(nil, 100)
  local s = c.saved()
  local r = H.boot({ saved = s })
  r.instance = { name = "Deadmines", map = 36, diff = 1, kind = "party", uiMap = 10036 }
  r.item(100, "Cruel Barb", 3, 5000)
  r.login()
  r.tick(30)
  r.encounter(1144, "Rhahk'Zor", true, 30)
  local old = r.history()[1]
  check("split after reload", old ~= nil and r.run() ~= nil)
  eq("old run ends where you left", math.floor(old.elapsed + 0.5), 230)
  eq("old run has no drop", #old.drops, 0)
  eq("new run has the drop", #r.run().drops, 1)
  eq("new run time from re-entry", math.floor(r.run().elapsed + 0.5), 360)
  eq("cap counts both", #_G.VulcanRunBookDB.entries, 2)
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("split: pending loot and partner numbers")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36)
  c.item(200, "Slow Item", 2, 10000, false)  -- never loads before the split
  c.tick(100)
  c.lootMsg(nil, 200)
  c.encounter(1144, "Rhahk'Zor", true, 30)
  local run1 = c.run()
  local start1 = run1.serverStart
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|130|1000|0|0|0|0", start1))
  c.leave()
  c.tick(30)
  c.enter("Deadmines", 36)
  c.tick(60)
  -- His numbers grow while you're in the new copy (his client hasn't split yet).
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|190|50000|0|0|0|0", start1))
  c.encounter(1144, "Rhahk'Zor", true, 30)   -- found: it was reset
  eq("pending item stays with the old run", run1.pending == nil and run1.unpriced, 1)
  eq("new run has no pending item", next(c.run().pending), nil)
  -- His corrected final numbers for the old run are lower, and accepted.
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|130|1000|0|0|0|1", start1))
  eq("partner's corrected numbers accepted", run1.partners.Mirel.coin, 1000)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("bag gains: only when loot lines are hidden")
do
  local c = fresh()
  c.item(300, "Heavy Bandage", 1, 50)
  c.item(301, "Quest Ring", 3, 900)
  c.item(100, "Cruel Barb", 3, 5000)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(5)
  c.lootMsg(nil, 100)  -- loot lines are readable here
  c.toBags(100, 1)
  c.tick(2)
  c.toBags(300, 5)     -- crafted bandages
  c.toBags(301, 1)     -- a quest reward
  c.tick(2)
  eq("crafted/quest items aren't loot", run.loot, 5000)
  eq("one drop", #run.drops, 1)
  -- The same item twice: one from bags (hidden line), one from a readable line later.
  c.item(302, "Wolf Pelt", 2, 300)
  c.lootReal(302, 1, true)
  c.tick(2)
  c.tick(120)
  c.lootReal(302, 1, false)
  c.tick(2)
  local pelts = 0
  for _, d in ipairs(run.drops) do if d.id == 302 then pelts = pelts + 1 end end
  eq("two pelts are two drops", pelts, 2)
  eq("valued twice", run.loot, 5000 + 600)
  local sentDrops = 0
  for _, m in ipairs(c.addonSent) do if m.msg:sub(1, 1) == "D" then sentDrops = sentDrops + 1 end end
  check("each drop synced once (if grouped)", sentDrops == 0)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("end then start in the first minute")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(20)
  c.slash("end")
  c.slash("start")
  check("reopened even though too short to save", c.run() == run)
  eq("no second cap entry", #_G.VulcanRunBookDB.entries, 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("notes: duplicates, times after reload")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36)
  c.tick(100)
  c.slash("note pull slower")
  c.addonMsg("Mirel", string.format("N3|beef01|36|Deadmines||%d|my bags are full", c.run().serverStart))
  local before = 0
  for _, m in ipairs(c.addonSent) do if m.msg:sub(1, 1) == "N" then before = before + 1 end end
  c.slash("note pull slower")
  check("duplicate explained", c.printedMatch("already there", true) ~= nil)
  local after = 0
  for _, m in ipairs(c.addonSent) do if m.msg:sub(1, 1) == "N" then after = after + 1 end end
  c.tick(2)
  local resent = false
  for _, m in ipairs(c.addonSent) do if m.msg:find("my bags are full", 1, true) then resent = true end end
  check("partner's note never resent as yours", not resent)
  eq("nothing new sent", after, before)
  c.leave()
  c.system("Deadmines has been reset.")
  c.slash("note after the run")
  local s = c.saved()
  local r = H.boot({ saved = s })
  r.login()
  local notes = r.history()[1].notes
  check("post-run note has no time after reload", notes[#notes].t == nil)
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("synced drop quality obeys your setting")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.slash("quality 3")
  c.enter("Deadmines", 36)
  c.item(400, "Green Thing", 2, 100, false)  -- not cached on your side
  c.addonMsg("Mirel", string.format("D3|beef01|36|Deadmines||%d|400|1|2", c.run().serverStart))
  eq("partner green dropped at quality 3", #c.run().drops, 0)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("reload in a boss fight, then a wipe")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36)
  c.tick(50)
  c.fire("ENCOUNTER_START", 1146, "Mr. Smite", 1, 5)
  c.member("Mirel").dead = true
  c.tick(1)
  local r = H.boot({ saved = c.saved() })
  r.instance = { name = "Deadmines", map = 36, diff = 1, kind = "party", uiMap = 10036 }
  r.party("Mirel")
  r.member("Mirel").dead = true
  r.login()
  r.tick(2)
  r.die()
  r.fire("ENCOUNTER_END", 1146, "Mr. Smite", 1, 5, 0)
  r.tick(1)
  eq("wipe counted after reload", #r.run().wipes, 1)
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("events before the addon loads")
do
  local c = H.boot()
  c.fire("CHAT_MSG_SYSTEM", "Deadmines has been reset.")
  c.fire("UI_ERROR_MESSAGE", 1, "You have entered too many instances recently.")
  c.fire("PLAYER_DEAD")
  c.fire("CHAT_MSG_LOOT", "You receive loot: x.")
  c.fire("ITEM_DATA_LOAD_RESULT", 1, true)
  c.fire("CHAT_MSG_ADDON", "VulcanRunBook", "S3|x|y", "PARTY", "Mirel")
  _G.VulcanRunBook_ToggleHistory()
  _G.VulcanRunBook_ToggleLive()
  _G.SlashCmdList.VULCANRUNBOOK("history")
  noErrors(c)
  c.login()
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("backups merge instead of overwriting")
do
  -- Character A plays with working account data.
  local a = fresh({ name = "Tavlius" })
  for _ = 1, 3 do
    a.enter("Deadmines", 36)
    a.tick(100)
    a.leave()
    a.system("Deadmines has been reset.")
  end
  local sa = a.savedCopy(false)
  -- Character B: account data fails to load; B only has its own (empty) backup.
  local b = H.boot({ saved = { db = nil, char = {}, wall = sa.wall, now = sa.now }, name = "Paladin" })
  b.login()
  b.enter("Wailing Caverns", 43)
  b.tick(100)
  b.leave()
  b.system("Wailing Caverns has been reset.")
  local sb = b.savedCopy(false)
  -- Back on A: the account file now holds B's (short) history; A's backup has its own runs.
  local a2 = H.boot({ saved = { db = sb.db, char = sa.char, wall = sb.wall, now = sb.now }, name = "Tavlius" })
  a2.login()
  eq("nothing lost: 3 of A's + 1 of B's", #a2.history(), 4)
  -- Deleting a run sticks, even though A's backup still had it.
  local id = a2.history()[2].id
  a2.slash("delete " .. id .. " yes")
  local s3 = a2.savedCopy(false)
  s3.char.mirror.history = sa.char.mirror.history  -- an old backup with the deleted run
  local a3 = H.boot({ saved = s3, name = "Tavlius" })
  a3.login()
  eq("deleted run stays deleted", #a3.history(), 3)
  -- clear yes also sticks.
  a3.slash("clear yes") a3.slash("clear yes")  -- (two characters: asked twice)
  local s4 = a3.savedCopy(false)
  s4.char.mirror.history = sa.char.mirror.history
  local a4 = H.boot({ saved = s4, name = "Tavlius" })
  a4.login()
  eq("cleared history stays cleared", #a4.history(), 0)
  noErrors(a, b, a2, a3, a4)
end

---------------------------------------------------------------------------
H.group("runs past the first 200 still count for stats and bests")
do
  local c = fresh()
  local function quick(t)
    c.enter("Deadmines", 36)
    c.tick(t - 30)
    c.encounter(1, "VanCleef", true, 30)
    c.leave()
    c.system("Deadmines has been reset.")
  end
  quick(300)            -- the best, run #1
  for _ = 1, 205 do quick(400) end
  eq("200 in detail", #c.history(), 200)
  eq("older in short form", #_G.VulcanRunBookDB.old, 6)
  local s = c.ns.DungeonStats()[1]
  eq("stats count every run", s.runs, 206)
  eq("best still the oldest run", s.best, 300)
  quick(350)
  check("no false new best", not anyPrinted(c, "New best clear for Deadmines: 5:50"))
  -- Short-form runs survive a reload.
  local r = H.boot({ saved = c.saved() })
  r.login()
  eq("stats after reload", r.ns.DungeonStats()[1].runs, 207)
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("partner identity")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36)
  local start = c.run().serverStart
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|60|100|0|0|0|0", start))
  eq("the RunBook user in your two-person group is the partner", _G.VulcanRunBookDB.partner, "Mirel")
  check("told who", c.printedMatch("Mirel also runs RunBook", true) ~= nil)
  c.party("Mirel", "Pug")
  c.addonMsg("Pug", string.format("S3|cafe02|36|Deadmines||%d|60|99999|0|0|0|0", start))
  check("told once that Pug isn't the partner", c.printedMatch("your sync partner is Mirel", true) ~= nil)
  c.addonMsg("Pug", string.format("N3|cafe02|36|Deadmines||%d|hello from pug", start))
  check("other RunBook users ignored", c.run().partners.Pug == nil and #c.run().notes == 0)
  check("live shows only your partner", not c.liveText():find("Pug:", 1, true), c.liveText())
  c.slash("partner off")
  eq("partner cleared", _G.VulcanRunBookDB.partner, nil)
  c.slash("partner mirel")
  eq("partner set by command (capitalized)", _G.VulcanRunBookDB.partner, "Mirel")
  -- In a raid, nobody becomes your partner automatically.
  local r = fresh()
  r.party("A", "B", "C", "D", "E", "F")
  r.raid = true
  r.enter("Molten Core", 409, { kind = "raid" })
  r.addonMsg("A", string.format("S3|abab01|409|Molten Core||%d|60|1|0|0|0|0", r.run().serverStart))
  eq("no automatic partner in a raid", _G.VulcanRunBookDB.partner, nil)
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("quiet mode and window text")
do
  local c = fresh()
  c.slash("quiet")
  c.clearPrinted()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.encounter(1, "Rhahk'Zor", true, 30)
  check("quiet: no start or boss line", not anyPrinted(c, "started") and not anyPrinted(c, "down at"))
  c.leave()
  c.system("Deadmines has been reset.")
  check("quiet: run summary still shown", anyPrinted(c, "Deadmines done (reset):"))
  c.slash("quiet")
  -- "Last:" line: no broken color codes even when cut short.
  c.slash("show")
  local last
  for _, l in ipairs(c.ns.LiveLines()) do if l:find("Last:", 1, true) then last = l end end
  check("last line well formed", last and not last:find("|c%x?%x?%x?%x?%x?%x?%x?%.%.%.") , last)
  -- Wipes before deaths; no "Wipes 0".
  c.party("Mirel")
  c.enter("Deadmines", 36)
  c.tick(5)
  c.member("Mirel").dead = true
  c.tick(1)
  local live = c.liveText()
  check("deaths without a wipe count", live:find("1 death (Mirel)", 1, true) ~= nil and not live:find("wipe"), live)
  c.die()
  c.tick(1)
  live = c.liveText()
  check("wipes first", live:find("1 wipe · 2 deaths", 1, true) ~= nil, live)
  -- After /runbook end inside: the window says so.
  c.slash("end")
  c.slash("show")
  check("ended run explained", c.liveText():find("/runbook start reopens it", 1, true) ~= nil, c.liveText())
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("csv columns")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.encounter(1, "Rhahk'Zor", true, 30)
  c.leave()
  c.system("Deadmines has been reset.")
  local lines = c.ns.ExportLines()
  check("splits column", lines[2]:find("Rhahk'Zor 2:10", 1, true) ~= nil, lines[2])
  check("readable status", lines[2]:find(",reset,", 1, true) ~= nil, lines[2])
  check("blank xp rate when no xp", lines[2]:find(",0,0,,", 1, true) ~= nil or lines[2]:find(",,,0,0,", 1, true)
    ~= nil, lines[2])
  noErrors(c)
end

os.exit(H.summary("tests_round2.lua") and 0 or 1)
