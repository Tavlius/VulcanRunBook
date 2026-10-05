-- RunBook tests for the audit round 3 fixes: relog outside, portals between
-- instances, clear/delete with reopen, per-character resets, partner picking,
-- boss sync, settings backup, hand-marked bosses, raid views, and more.
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

local DM = { name = "Deadmines", map = 36, diff = 1, kind = "party", uiMap = 10036 }
local function inside(c, inst) c.instance = { name = inst.name, map = inst.map, diff = inst.diff, kind = inst.kind,
  uiMap = inst.uiMap } end

---------------------------------------------------------------------------
H.group("log out inside, log back in outside, then an unseen reset")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(200)
  c.encounter(1144, "Rhahk'Zor", true, 30)
  c.leave()
  c.tick(30)
  c.enter("Deadmines", 36)   -- visit 2
  c.tick(60)
  local s = c.saved()        -- log out inside
  local r = H.boot({ saved = s, gap = 600 })
  r.login()                  -- back outside 10 minutes later
  r.enter("Deadmines", 36)   -- a fresh copy (reset unseen)
  r.tick(100)
  r.encounter(1144, "Rhahk'Zor", true, 30)
  check("the repeat kill splits the run", r.history()[1] ~= nil and r.run() ~= nil and #r.run().bosses == 1)
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("a portal from one instance straight into another")
do
  local c = fresh()
  c.enter("Blackrock Depths", 230)
  local brd = c.run()
  c.tick(300)
  -- Lothos Riftwaker: into Molten Core without leaving an instance.
  c.instance = { name = "Molten Core", map = 409, diff = 1, kind = "raid", uiMap = 10409 }
  c.fire("PLAYER_ENTERING_WORLD", false, false)
  check("BRD run ended", brd.ended and brd.endReason == "new dungeon")
  eq("Molten Core run started", c.run() and c.run().name, "Molten Core")
  eq("two cap entries", #_G.VulcanRunBookDB.entries, 2)
  c.encounter(663, "Lucifron", true, 30)
  eq("boss in the right run", #brd.bosses, 0)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("clear yes and delete don't eat runs that come after")
do
  -- clear yes while a run is going: that run survives a relog.
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.leave()
  c.system("Deadmines has been reset.")
  c.enter("Deadmines", 36)
  c.tick(100)
  c.slash("clear yes")
  c.leave()
  c.system("Deadmines has been reset.")
  eq("one run after the clear", #c.history(), 1)
  local r = H.boot({ saved = c.savedCopy(false) })
  r.login()
  eq("still there after relog", #r.history(), 1)
  -- end, delete it, start (reopen): the reopened run survives a relog.
  local d = fresh()
  d.enter("Deadmines", 36)
  d.tick(100)
  d.slash("end")
  d.slash("delete " .. d.history()[1].id .. " yes")
  d.slash("start")
  d.tick(70)
  d.leave()
  d.system("Deadmines has been reset.")
  eq("a fresh run after deleting the ended one", #d.history(), 1)
  local e = H.boot({ saved = d.savedCopy(false) })
  e.login()
  eq("it survives a relog", #e.history(), 1)
  noErrors(c, r, d, e)
end

---------------------------------------------------------------------------
H.group("reopening uses the saved copy (notes added after end)")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36)
  c.tick(100)
  c.slash("end")
  local r = H.boot({ saved = c.saved() })
  inside(r, DM)
  r.party("Mirel")
  r.login()
  local id = r.history()[1].id
  r.slash("note #" .. id .. " added after ending")
  r.slash("start")
  local found = false
  for _, n in ipairs(r.run().notes) do if n.text == "added after ending" then found = true end end
  check("note kept on reopen", found)
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("slow-loading loot value goes to the right run after a split")
do
  local c = fresh()
  c.item(500, "Slow Ring", 3, 10000, false)
  c.enter("Deadmines", 36)
  c.tick(100)
  c.lootMsg(nil, 500)                       -- visit 1, not priced yet
  c.encounter(1144, "Rhahk'Zor", true, 10)
  c.leave()
  c.tick(10)
  c.enter("Deadmines", 36)                  -- visit 2 (a new copy, as it turns out)
  c.tick(10)
  c.lootMsg(nil, 500, 2)                    -- visit 2: two more
  c.cached[500] = true
  c.fire("ITEM_DATA_LOAD_RESULT", 500, true) -- priced now, before the split is found
  c.tick(30)
  c.encounter(1144, "Rhahk'Zor", true, 30)  -- the split
  local old = c.history()[1]
  eq("old run: its one ring", old.loot, 10000)
  eq("new run: its two rings", c.run().loot, 20000)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("one character's reset doesn't end another's run")
do
  local main = fresh({ name = "Tavlius" })
  main.enter("Deadmines", 36)
  main.tick(100)
  main.leave()
  local s = main.savedCopy(false)
  -- The alt resets Deadmines (account data is shared; resets aren't).
  local alt = H.boot({ saved = { db = s.db, char = {}, wall = s.wall, now = s.now }, name = "Paladin" })
  alt.login()
  alt.system("Deadmines has been reset.")
  local s2 = alt.savedCopy(false)
  local back = H.boot({ saved = { db = s2.db, char = s.char, wall = s2.wall, now = s2.now }, name = "Tavlius" })
  back.login()
  back.enter("Deadmines", 36)
  check("main's run resumes", back.run() ~= nil and #back.history() == 0)
  noErrors(main, alt, back)
end

---------------------------------------------------------------------------
H.group("your own runs come first")
do
  local main = fresh({ name = "Tavlius" })
  main.enter("Deadmines", 36)
  main.tick(100)
  main.leave()
  main.system("Deadmines has been reset.")
  local s = main.savedCopy(false)
  local alt = H.boot({ saved = { db = s.db, char = {}, wall = s.wall, now = s.now }, name = "Paladin" })
  alt.login()
  alt.enter("Wailing Caverns", 43)
  alt.tick(100)
  alt.leave()
  alt.system("Wailing Caverns has been reset.")
  local s2 = alt.savedCopy(false)
  local back = H.boot({ saved = { db = s2.db, char = s.char, wall = s2.wall, now = s2.now }, name = "Tavlius" })
  back.login()
  back.slash("note my note")
  local dm
  for _, r in ipairs(back.history()) do if r.name == "Deadmines" then dm = r end end
  eq("note goes to your own last run", dm and #dm.notes, 1)
  noErrors(main, alt, back)
end

---------------------------------------------------------------------------
H.group("events before login")
do
  local c = H.boot()
  c.fire("ADDON_LOADED", "VulcanRunBook")
  c.tick(3)                      -- the clock ticks before PLAYER_LOGIN
  noErrors(c)
  c.fire("PLAYER_LOGIN")
  c.fire("PLAYER_ENTERING_WORLD", true, false)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("your Feign Death after a reload in a boss fight isn't a wipe")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36)
  c.tick(50)
  c.fire("ENCOUNTER_START", 1146, "Mr. Smite", 1, 5)
  local r = H.boot({ saved = c.saved() })
  inside(r, DM)
  r.party("Mirel")
  r.login()
  r.tick(2)
  r.dead = true                  -- feigning: shows dead, no death event
  r.fire("ENCOUNTER_END", 1146, "Mr. Smite", 1, 5, 0)
  r.tick(6)
  eq("no wipe", #r.run().wipes, 0)
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("an Unknown group member isn't logged")
do
  local c = fresh()
  c.party("Unknown", "Mirel")
  c.enter("Deadmines", 36)
  local names = table.concat(c.run().members, ",")
  check("no Unknown member", not names:find("Unknown", 1, true), names)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("Scarlet Monastery: stale map at the start, reload on another floor")
do
  local c = fresh()
  c.mapNames = { [1420] = "Tirisfal Glades", [302] = "Graveyard", [303] = "Library", [304] = "Library Upper" }
  c.mapGroups = { [303] = 9, [304] = 9 }
  c.enter("Scarlet Monastery", 189, { uiMap = 1420 })  -- the outdoor map, for a moment
  local run = c.run()
  eq("the outdoor map isn't a wing", run.label, "Scarlet Monastery")
  c.instance.uiMap = 302
  c.tick(4)
  check("corrected silently, same run", c.run() == run and run.label == "Scarlet Monastery - Graveyard", run.label)
  c.tick(100)
  -- Library has floors (one map group): a reload on its upper floor stays one run.
  c.leave()
  c.system("Scarlet Monastery has been reset.")
  c.enter("Scarlet Monastery", 189, { uiMap = 303 })
  local lib = c.run()
  c.tick(100)
  c.instance.uiMap = 304
  c.tick(10)
  local r = H.boot({ saved = c.saved() })
  r.mapNames, r.mapGroups = c.mapNames, c.mapGroups
  r.instance = { name = "Scarlet Monastery", map = 189, diff = 1, kind = "party", uiMap = 304 }
  r.login()
  r.tick(5)
  check("reload on another floor: same run", r.run() ~= nil and r.run().serverStart == lib.serverStart)
  eq("no extra cap entry", #_G.VulcanRunBookDB.entries, 2)
  -- Unreadable wing: the hint once per run, not every trip.
  local h = fresh()
  h.secret.uimap = true
  h.enter("Scarlet Monastery", 189)
  h.tick(15)
  h.leave()
  h.enter("Scarlet Monastery", 189)
  h.tick(15)
  local hints = 0
  for _, p in ipairs(h.printed) do if p:find("wings can't be told apart", 1, true) then hints = hints + 1 end end
  eq("hint once per run", hints, 1)
  noErrors(c, r, h)
end

---------------------------------------------------------------------------
H.group("normal dungeons ignore maps entirely")
do
  local c = fresh()
  c.mapNames = { [242] = "Detention Block", [243] = "Shadowforge City" }
  c.enter("Blackrock Depths", 230, { uiMap = 242 })
  local run = c.run()
  eq("no wing, plain label", run.label, "Blackrock Depths")
  c.tick(50)
  c.leave()
  c.enter("Blackrock Depths", 230, { uiMap = 243 })
  c.tick(5)
  check("another floor on the way in: same run", c.run() == run)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("partner picking")
do
  -- A pug's RunBook message first, in a 5-man: not your partner.
  local c = fresh()
  c.party("Mirel", "Pug", "A", "B")
  c.enter("Deadmines", 36)
  c.addonMsg("Pug", string.format("S3|cafe02|36|Deadmines||%d|60|1|0|0|0|0", c.run().serverStart))
  eq("no partner picked in a group of five", _G.VulcanRunBookDB.partner, nil)
  -- In a duo, the partner is picked.
  local d = fresh()
  d.party("Mirel")
  d.enter("Deadmines", 36)
  d.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|60|1|0|0|0|0", d.run().serverStart))
  eq("duo partner picked", _G.VulcanRunBookDB.partner, "Mirel")
  -- A newer version from someone who isn't your partner: no notice.
  d.party("Mirel", "Pug")
  d.addonMsg("Pug", "S9|cafe02|whatever")
  check("no version notice for a pug", not d.printedMatch("RunBook, so sync is off", true))
  noErrors(c, d)
end

---------------------------------------------------------------------------
H.group("boss kills sync between you")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(100)
  c.die()
  c.tick(1)
  c.leave()                       -- you released; Mirel kills the boss
  c.tick(20)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|1144|Rhahk'Zor", run.serverStart))
  eq("partner's kill recorded during your ghost run", #run.bosses, 1)
  -- Your own kill sends one.
  c.dead = false
  c.enter("Deadmines", 36)
  c.tick(10)
  c.encounter(1145, "Sneed", true, 30)
  c.tick(1)
  local sent
  for _, m in ipairs(c.addonSent) do if m.msg:find("^B3|") and m.msg:find("|1145|%d+|%d+|Sneed$") then sent = true end end
  check("your kill synced", sent)
  -- His message about a kill you already have: nothing changes.
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|1145|Sneed", run.serverStart))
  eq("no duplicate", #run.bosses, 2)
  -- And /runbook unboss doesn't send anything.
  local n = #c.addonSent
  c.slash("unboss")
  c.tick(1)
  local bs = 0
  for i = n + 1, #c.addonSent do if c.addonSent[i].msg:find("^B3|") then bs = bs + 1 end end
  eq("unboss sends no boss message", bs, 0)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("dead at login counts as dead")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36)
  c.tick(10)
  c.die()
  c.tick(1)
  local r = H.boot({ saved = c.saved() })
  inside(r, DM)
  r.party("Mirel")
  r.dead = true
  r.login()
  r.tick(1)
  r.member("Mirel").dead = true
  r.tick(1)
  eq("wipe seen after a reload while dead", #r.run().wipes, 1)
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("settings survive a failed account load")
do
  local c = fresh()
  c.slash("partner Mirel")
  c.slash("cap 7")
  c.slash("quiet")
  c.slash("quality 3")
  local s = c.savedCopy(true)   -- account data lost
  local r = H.boot({ saved = s })
  r.login()
  eq("partner", _G.VulcanRunBookDB.partner, "Mirel")
  eq("cap", _G.VulcanRunBookDB.cap, 7)
  eq("quiet", _G.VulcanRunBookDB.quiet, true)
  eq("quality", _G.VulcanRunBookDB.quality, 3)
  check("no second welcome", not r.printedMatch("starts on its own", true))
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("hand-marked bosses make clears too")
do
  local c = fresh()
  for _ = 1, 3 do
    c.enter("Gnomeregan", 90)
    for _ = 1, 3 do
      c.tick(120)
      c.slash("boss")
    end
    c.leave()
    c.system("Gnomeregan has been reset.")
  end
  local s = c.ns.DungeonStats()[1]
  eq("final boss from marks", s.final and s.final.name, "Boss 3")
  eq("three clears", s.clears, 3)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("end messages, short runs, unboss later")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.slash("end")
  check("end says how to reopen", anyPrinted(c, "/runbook start reopens it."))
  c.slash("start")
  c.slash("new yes")
  c.tick(5)
  c.slash("end")
  check("short run ended explained", anyPrinted(c, "Deadmines ended (too short to save)."))
  -- unboss on your last saved run.
  c.leave()
  c.enter("Wailing Caverns", 43)
  c.tick(100)
  c.slash("boss Kresh")
  c.leave()
  c.system("Wailing Caverns has been reset.")
  c.slash("unboss")
  eq("taken back from the saved run", #c.history()[1].bosses, 0)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("raid views")
do
  local c = fresh()
  c.slash("partner Mirel")
  c.party("Mirel", "A", "B", "C", "D", "E")
  c.raid = true
  c.enter("Molten Core", 409, { kind = "raid" })
  c.item(600, "Raider Epic", 4, 1000)
  c.item(601, "Mirel Epic", 4, 1000)
  for _ = 1, 5 do c.lootMsg("A", 600) end
  c.lootMsg("Mirel", 601)
  c.slash("show")
  local live = c.liveText()
  check("live drops: your two's only", live:find("Mirel Epic", 1, true) ~= nil and not live:find("Raider Epic", 1, true),
    live)
  for i = 1, 9 do
    c.tick(60)
    c.encounter(700 + i, "Raid Boss " .. i, true, 30)
  end
  live = c.liveText()
  check("boss list capped", live:find("(3 earlier)", 1, true) ~= nil, live)
  c.leave()
  c.tick(7300)
  eq("a single raid night isn't a clear", c.ns.ClearTime(c.history()[1]), nil)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("first run: dungeons tab")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.slash("stats")
  local lines = c.ns.HistoryContent()
  check("first run in progress", c.strip(lines[1][1]):find("your first is in progress", 1, true) ~= nil)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("chat report money")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.gainMoney(3000)
  c.tick(100)
  local lines = c.ns.ReportLines(c.run())
  check("silver spelled out", lines[1]:find("30 silver", 1, true) ~= nil, lines[1])
  noErrors(c)
end

os.exit(H.summary("tests_round3.lua") and 0 or 1)
