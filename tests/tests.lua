-- RunBook tests: run lifecycle, bosses, deaths, drops, coin/XP, stats, cap.
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
  c.item(101, "Linen Cloth", 1, 15)
  c.item(102, "Broken Tooth", 0, 7)
  c.item(103, "Lucky Charm", 2, 300)
  c.item(104, "Smite's Hammer", 4, 20000)
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
H.group("login")
do
  local c = fresh()
  noErrors(c)
  check("no run outside", c.run() == nil)
  check("welcome printed", c.printedMatch("starts on its own", true) ~= nil)
  check("live window hidden outside", not _G.VulcanRunBookFrame:IsShown())
  local c2 = H.boot({ saved = c.saved() })
  c2.login()
  check("welcome only once", c2.printedMatch("starts on its own", true) == nil)
end

---------------------------------------------------------------------------
H.group("start and time")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  local run = c.run()
  check("run started", run ~= nil)
  eq("run name", run and run.name, "Deadmines")
  eq("run map", run and run.mapID, 36)
  eq("no number until it's saved", run and run.id, nil)
  check("start printed", c.printedMatch("Deadmines started.", true) ~= nil)
  eq("one cap entry", #_G.VulcanRunBookDB.entries, 1)
  check("live window shown in dungeon", _G.VulcanRunBookFrame:IsShown())
  c.tick(60)
  eq("60s counted (loading screen not)", math.floor(run.elapsed + 0.5), 60)
  check("live shows dungeon and clock", c.liveText():find("Deadmines  1:00", 1, true) ~= nil, c.liveText())
  check("live says nothing yet", c.liveText():find("You: nothing yet", 1, true) ~= nil, c.liveText())
  c.tick(1, 12)
  eq("stall not counted", math.floor(run.elapsed + 0.5), 60)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("bosses")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36)
  c.tick(60)
  c.encounter(1144, "Rhahk'Zor", true, 30)
  local run = c.run()
  eq("one boss", #run.bosses, 1)
  eq("boss name", run.bosses[1].name, "Rhahk'Zor")
  eq("boss split at 1:30", run.bosses[1].t, 90)
  check("kill printed", c.printedMatch("Rhahk'Zor down at 1:30.", true) ~= nil)
  c.fire("BOSS_KILL", 1144, "Rhahk'Zor")
  c.fire("ENCOUNTER_END", 1144, "Rhahk'Zor", 1, 5, 1)
  eq("duplicate kill ignored", #run.bosses, 1)
  -- The other event with everything hidden, right after: the same kill.
  c.fire("ENCOUNTER_END", H.SECRET, H.SECRET, 1, 5, 1)
  eq("unreadable second event is the same kill", #run.bosses, 1)
  c.tick(20)
  c.fire("BOSS_KILL", 1145, "Sneed")
  eq("boss kill event alone", #run.bosses, 2)
  -- Hand-marked, then the client's event for the same boss: one boss.
  c.tick(20)
  c.slash("boss Gilnid")
  eq("manual boss", #run.bosses, 3)
  check("manual flagged", run.bosses[3].manual == true)
  c.fire("BOSS_KILL", 1146, "Gilnid")
  eq("auto kill takes over the manual one", #run.bosses, 3)
  check("no longer manual", run.bosses[3].manual == nil and run.bosses[3].id == 1146)
  c.slash("boss Gilnid")
  check("already marked", c.printedMatch("Gilnid was just recorded", true) ~= nil)
  c.slash("boss")
  check("unnamed mark right after a kill is refused", #run.bosses == 3 and c.printedMatch("was just recorded", true))
  c.tick(11)
  c.slash("boss")
  eq("unnamed manual boss", run.bosses[4].name, "Boss 4")
  -- A failed encounter where nobody died isn't a wipe (Feign Death drop, evade).
  c.encounter(1147, "Mr. Smite", false, 20)
  c.tick(6)
  eq("reset without deaths isn't a wipe", #run.wipes, 0)
  -- With a death in it, it is.
  c.fire("ENCOUNTER_START", 1147, "Mr. Smite", 1, 5)
  c.tick(10)
  c.member("Mirel").dead = true
  c.tick(1)
  c.fire("ENCOUNTER_END", 1147, "Mr. Smite", 1, 5, 0)
  c.tick(1)
  eq("failed encounter with a death = wipe", #run.wipes, 1)
  eq("wipe named", run.wipes[1].boss, "Mr. Smite")
  -- Deaths only readable after the fight: still a wipe.
  c.member("Mirel").dead = false
  c.tick(120)
  c.fire("ENCOUNTER_START", 1147, "Mr. Smite", 1, 5)
  c.member("Mirel").secretDead = true
  c.member("Mirel").dead = true
  c.tick(5)
  c.fire("ENCOUNTER_END", 1147, "Mr. Smite", 1, 5, 0)
  c.member("Mirel").secretDead = false
  c.tick(2)
  eq("late-readable death still makes it a wipe", #run.wipes, 2)
  eq("no boss for wipes", #run.bosses, 4)
  -- Outside a dungeon, boss events are ignored.
  c.leave()
  c.fire("BOSS_KILL", 999, "World Boss")
  eq("boss outside ignored", #run.bosses, 4)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("same boss again = unseen reset")
do
  local c = fresh()
  items(c)
  c.enter("Deadmines", 36)
  local run1 = c.run()
  c.tick(200)
  c.encounter(1144, "Rhahk'Zor", true, 30)
  c.leave()                    -- a pug leader resets; you never see the message
  c.tick(60)
  c.enter("Deadmines", 36)
  check("resumed (reset unseen)", c.run() == run1)
  c.tick(100)
  c.lootMsg(nil, 100)
  c.encounter(1144, "Rhahk'Zor", true, 30)
  local run2 = c.run()
  check("split into a new run", run2 ~= nil and run2 ~= run1)
  eq("old run ended at the resume", math.floor(run1.elapsed + 0.5), 230)
  eq("old run keeps its boss", #run1.bosses, 1)
  eq("old run reason", run1.endReason, "split")
  eq("new run has the boss", #run2.bosses, 1)
  eq("new run time since coming back", math.floor(run2.elapsed + 0.5), 130)
  eq("new run boss time rebased", run2.bosses[1].t, 130)
  eq("drop moved to new run", #run2.drops, 1)
  eq("drop time rebased", run2.drops[1].t, 100)
  eq("loot value moved", run2.loot, 5000)
  eq("old run value", run1.loot, 0)
  eq("cap counts both instances", #_G.VulcanRunBookDB.entries, 2)
  check("explained", c.printedMatch("was already down before you went out", true) ~= nil)
  check("old run archived", c.history()[1] == run1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("deaths and wipes")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(5)
  c.member("Mirel").dead = true
  c.tick(1)
  eq("partner death", #run.deaths, 1)
  eq("death who", run.deaths[1].who, "Mirel")
  c.tick(5)
  eq("still dead is one death", #run.deaths, 1)
  -- Your own Feign Death: the client may show you dead, but the death event
  -- doesn't fire, so it's not a death (and not a wipe with Mirel dead).
  c.dead = true
  c.tick(3)
  eq("your feign death ignored", #run.deaths, 1)
  eq("feign isn't a wipe", #run.wipes, 0)
  c.dead = false
  c.tick(1)
  -- His Feign Death isn't one either.
  c.member("Mirel").dead = false
  c.tick(1)
  c.member("Mirel").dead, c.member("Mirel").feign = true, true
  c.tick(2)
  eq("partner feign ignored", #run.deaths, 1)
  c.member("Mirel").dead, c.member("Mirel").feign = false, false
  c.tick(1)
  -- Both really dead = a wipe.
  c.member("Mirel").dead = true
  c.tick(1)
  c.die()
  c.tick(1)
  eq("your death (event)", #run.deaths, 3)
  eq("both dead = wipe", #run.wipes, 1)
  -- Res and die again later: a second wipe.
  c.dead, c.member("Mirel").dead = false, false
  c.tick(120)
  c.member("Mirel").dead = true
  c.die()
  c.tick(1)
  eq("two more deaths", #run.deaths, 5)
  eq("second wipe", #run.wipes, 2)
  noErrors(c)

  -- Five-man: four of five dead is a wipe (one feigned or vanished).
  local f = fresh()
  f.party("Mirel", "A", "B", "C")
  f.enter("Deadmines", 36)
  f.tick(2)
  for _, n in ipairs({ "Mirel", "A", "B" }) do f.member(n).dead = true end
  f.tick(1)
  eq("3/5 dead isn't a wipe", #f.run().wipes, 0)
  f.die()
  f.tick(1)
  eq("4/5 dead is a wipe", #f.run().wipes, 1)
  -- An offline member doesn't block a wipe.
  local o = fresh()
  o.party("Mirel", "Away")
  o.member("Away").offline = true
  o.enter("Deadmines", 36)
  o.tick(2)
  o.member("Mirel").dead = true
  o.die()
  o.tick(1)
  eq("offline member ignored", #o.run().wipes, 1)
  -- Solo: dying is a death, not a wipe.
  local s = fresh()
  s.enter("Deadmines", 36)
  s.tick(2)
  s.die()
  s.tick(1)
  eq("solo death", #s.run().deaths, 1)
  eq("solo death no wipe", #s.run().wipes, 0)
  -- Arriving dead (a ghost zoning in) isn't a new death.
  local g = fresh()
  g.party("Mirel")
  g.member("Mirel").dead = true
  g.enter("Deadmines", 36)
  g.tick(3)
  eq("dead on arrival isn't a death", #g.run().deaths, 0)
  noErrors(f, o, s, g)
end

---------------------------------------------------------------------------
H.group("raid: units, deaths")
do
  local c = fresh()
  c.party("Mirel", "A", "B", "C", "D")
  c.raid = true
  c.enter("Molten Core", 409, { kind = "raid" })
  c.tick(2)
  local units = c.ns.GroupUnits()
  eq("raid units: you once", #units, 6)
  c.dead = true  -- your feign in a raid
  c.tick(2)
  eq("raid: your feign ignored", #c.run().deaths, 0)
  c.dead = false
  c.member("A").dead = true
  c.tick(1)
  eq("raid member death", #c.run().deaths, 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("feign death without the API")
do
  local c = fresh({ noFeign = true })
  c.party("Mirel")
  c.enter("Deadmines", 36)
  c.tick(2)
  c.member("Mirel").dead = true
  c.tick(1)
  eq("death still counted without feign API", #c.run().deaths, 1)
end

---------------------------------------------------------------------------
H.group("drops and loot value")
do
  local c = fresh()
  items(c)
  c.party("Mirel")
  c.addonMsg("Mirel", "S3|abc123|36|Deadmines||0|0|0|0|0|0|0")  -- Mirel runs RunBook (no matching run yet)
  eq("partner set by first sync", _G.VulcanRunBookDB.partner, "Mirel")
  c.party("Mirel", "Pug")
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(10)
  c.lootMsg(nil, 100)                 -- your blue
  c.lootMsg(nil, 101, 3)              -- your linen x3
  c.lootMsg(nil, 102)                 -- your grey
  c.lootMsg("Mirel", 104)             -- his epic
  c.lootMsg("Mirel", 103)             -- his green (partner: kept)
  c.lootMsg("Pug-OtherRealm", 103)    -- a pug's green (others: blue and up only)
  c.lootMsg("Pug-OtherRealm", 100)    -- a pug's blue
  eq("loot value counted (yours only)", run.loot, 5000 + 45 + 7)
  local names = {}
  for _, d in ipairs(run.drops) do names[#names + 1] = d.name .. "/" .. d.who end
  local list = table.concat(names, ",")
  eq("drop list", list, "Cruel Barb/Tavlius,Smite's Hammer/Mirel,Lucky Charm/Mirel,Cruel Barb/Pug")
  -- Old-style hex color links.
  c.lootMsg(nil, 103, nil, true)
  eq("hex link quality", run.drops[#run.drops].q, 2)
  -- Uncached item: valued once its data loads.
  c.item(105, "Mystery Ring", 3, 900, false)
  c.lootMsg(nil, 105)
  local before = run.loot
  eq("uncached not valued yet", run.loot, before)
  check("load requested", #c.loadRequests > 0)
  c.cached[105] = true
  c.fire("ITEM_DATA_LOAD_RESULT", 105, true)
  eq("valued once loaded", run.loot, before + 900)
  -- Quality unknown (no color in the line, not cached), below the bar: kept
  -- while unknown, removed once known.
  c.item(106, "Rough Stone", 1, 2, false)
  c.fire("CHAT_MSG_LOOT", "Mirel receives loot: |Hitem:106::::|h[Rough Stone]|h.", "Mirel")
  check("unknown quality kept for now", run.drops[#run.drops].id == 106)
  c.cached[106] = true
  c.tick(1)
  check("dropped once known to be white", run.drops[#run.drops].id ~= 106)
  -- An item that never loads: a minute of tries, then counted as unpriced.
  -- Unrelated item loads in between don't use up its tries.
  c.item(107, "Ghost Item", 2, 50, false)
  c.lootMsg(nil, 107)
  for _ = 1, 100 do c.fire("ITEM_DATA_LOAD_RESULT", 999, true) end
  local waiting = false
  for _, p in pairs(run.pending) do if p.id == 107 then waiting = true end end
  check("other loads don't use up tries", run.unpriced == 0 and waiting)
  c.tick(61)
  eq("given up", run.unpriced, 1)
  check("no pending left", next(run.pending) == nil)
  -- Loot outside a run is ignored.
  c.leave()
  local n = #run.drops
  c.lootMsg(nil, 100)
  eq("loot outside ignored", #run.drops, n)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("bags as a second loot source")
do
  local c = fresh()
  items(c)
  c.bagSlots = { { id = 101, n = 5 } }
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(5)
  -- Loot lines hidden by the client: your bags still show what you got.
  c.lootReal(100, 1, true)
  c.tick(2)
  eq("hidden loot found in bags", #run.drops, 1)
  eq("bag loot valued", run.loot, 5000)
  -- Loot line readable: the bag change is the same item, not a second one.
  c.lootReal(104, 1, false)
  c.tick(2)
  eq("chat + bags = one drop", #run.drops, 2)
  eq("valued once", run.loot, 25000)
  -- Bag change first, loot line after (out of order): still one.
  c.toBags(103, 1)
  c.tick(2)
  c.lootMsg(nil, 103)
  eq("bags then chat = one drop", #run.drops, 3)
  eq("valued once (out of order)", run.loot, 25300)
  -- Stacks: 3 more linen counts 3, value 45, not listed (white).
  c.lootReal(101, 3, true)
  c.tick(2)
  eq("stack added", run.loot, 25345)
  eq("white not listed", #run.drops, 3)
  -- Equipping gear from your bags isn't loot (equipped items are counted too).
  for i, it in ipairs(c.bagSlots) do if it.id == 103 then table.remove(c.bagSlots, i) break end end
  c.equipped[11] = 103
  c.fire("BAG_UPDATE_DELAYED")
  c.tick(2)
  eq("equipping isn't loot", run.loot, 25345)
  -- Buying from a vendor isn't loot.
  c.fire("MERCHANT_SHOW")
  c.toBags(102, 5)
  c.tick(2)
  c.fire("MERCHANT_CLOSED")
  c.tick(5)
  eq("purchase isn't loot", run.loot, 25345)
  check("bag loot counted for check", c.ns.stats.bagLoot >= 3)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("raid drop filter and quality setting")
do
  local c = fresh()
  items(c)
  c.party("Mirel", "A", "B", "C", "D", "E")
  c.raid = true
  c.slash("partner mirel")
  c.enter("Molten Core", 409, { kind = "raid" })
  local run = c.run()
  c.lootMsg("A", 103)        -- stranger's green: skipped
  c.lootMsg("Mirel", 103)    -- partner's green: kept
  c.lootMsg("B", 100)        -- stranger's blue: kept
  local who = {}
  for _, d in ipairs(run.drops) do who[#who + 1] = d.who .. ":" .. d.q end
  eq("raid filter", table.concat(who, ","), "Mirel:2,B:3")
  check("raid kind", run.kind == "raid")
  c.slash("quality 3")
  c.lootMsg(nil, 103)
  eq("your green skipped at quality 3", #run.drops, 2)
  c.slash("quality 9")
  check("bad quality rejected", c.printedMatch("Usage: /runbook quality", true) ~= nil)
end

---------------------------------------------------------------------------
H.group("coin and XP")
do
  local c = fresh()
  c.gainMoney(500)          -- outside: not counted
  c.enter("Deadmines", 36)
  local run = c.run()
  c.gainMoney(1234)
  eq("coin inside", run.coin, 1234)
  c.fire("MERCHANT_SHOW")
  c.gainMoney(800)
  c.fire("MERCHANT_CLOSED")
  c.gainMoney(100)          -- within 3s of closing: still blocked
  eq("vendor money not counted", run.coin, 1234)
  c.tick(4)
  c.gainMoney(66)
  eq("counted again later", run.coin, 1300)
  c.money = c.money - 5000
  c.fire("PLAYER_MONEY")
  eq("spending ignored", run.coin, 1300)
  c.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 1)  -- trade window (new style)
  c.gainMoney(999)
  c.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 1)
  eq("trade money not counted", run.coin, 1300)
  c.gainXP(1000)
  eq("xp", run.xp, 1000)
  c.xp = 4900
  c.fire("PLAYER_XP_UPDATE", "player")
  c.gainXP(300)                          -- levels up
  eq("xp across level-up", run.xp, 1000 + 2900 + 300)
  c.leave()
  c.gainXP(50)
  c.gainMoney(50)
  eq("xp outside ignored", run.xp, 4200)
  eq("coin outside ignored", run.coin, 1300)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("leave, resume, ghost run, timeout")
do
  local c = fresh()
  c.party("Mirel")
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(100)
  c.leave()
  check("window hides outside", not _G.VulcanRunBookFrame:IsShown())
  c.slash("show")
  check("paused shown", c.liveText():find("(paused)", 1, true) ~= nil, c.liveText())
  c.tick(300)
  eq("time outside not counted", math.floor(run.elapsed + 0.5), 100)
  c.enter("Deadmines", 36)
  check("same run resumed", c.run() == run)
  eq("no new cap entry on resume", #_G.VulcanRunBookDB.entries, 1)
  check("window back on (toggle reset by zoning)", _G.VulcanRunBookFrame:IsShown())
  c.tick(50)
  eq("time continues", math.floor(run.elapsed + 0.5), 150)
  -- Die inside, release, run back as a ghost: that time counts (up to 10 min).
  c.die()
  c.tick(1)
  c.leave()
  check("window stays up on a ghost run", _G.VulcanRunBookFrame:IsShown())
  check("live shows ghost run", c.liveText():find("(ghost)", 1, true) ~= nil, c.liveText())
  -- Mirel dies while you run back: still his death in this run.
  c.member("Mirel").dead = true
  c.tick(120)
  eq("partner death during your ghost run", #run.deaths, 2)
  eq("ghost run counts", math.floor(run.elapsed + 0.5), 271)
  c.tick(600)
  eq("ghost time capped at 10 min from leaving", math.floor(run.elapsed + 0.5), 151 + 600)
  check("window hides after the ghost cap", not _G.VulcanRunBookFrame:IsShown())
  c.dead = false
  c.member("Mirel").dead = false
  c.enter("Deadmines", 36)
  check("still the same run", c.run() == run)
  -- A repair trip, then dying in the open world: not run time.
  c.leave()
  c.tick(30)
  c.die()
  c.tick(100)
  eq("open-world death isn't run time", math.floor(run.elapsed + 0.5), 751)
  c.dead = false
  -- 30+ minutes outside, alive: the run ends.
  c.tick(1801)
  check("timed out", c.run() == nil)
  eq("archived", c.history()[1], run)
  eq("end reason", run.endReason, "timeout")
  check("end message says why", c.printedMatch("Deadmines done (away 30+ min):", true) ~= nil)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("raid timeout is longer")
do
  local c = fresh()
  c.enter("Molten Core", 409, { kind = "raid" })
  c.tick(100)
  c.leave()
  c.tick(3600)
  check("raid run still open after an hour", c.run() ~= nil)
  c.tick(3601)
  check("raid run ends after two hours", c.run() == nil)
end

---------------------------------------------------------------------------
H.group("new run: reset, other dungeon, wing, difficulty, short runs")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  local run1 = c.run()
  c.tick(120)
  c.leave()
  c.system("Deadmines has been reset.")
  check("reset ends the run", c.run() == nil)
  eq("reset reason", run1.endReason, "reset")
  c.enter("Deadmines", 36)
  check("new run after reset", c.run() ~= nil and c.run() ~= run1)
  eq("two cap entries", #_G.VulcanRunBookDB.entries, 2)
  local run2 = c.run()
  c.tick(90)
  c.leave()
  c.enter("Wailing Caverns", 43)
  eq("other dungeon ends the old run", run2.endReason, "new dungeon")
  eq("new dungeon run", c.run().name, "Wailing Caverns")
  c.system("Deadmines has been reset.")
  eq("other dungeon's reset ignored", c.run().name, "Wailing Caverns")
  local wc = c.run()
  c.tick(70)
  c.leave()
  c.enter("Shadowfang Keep", 33)
  c.tick(5)
  c.leave()
  c.enter("Deadmines", 36)
  local hist = {}
  for _, r in ipairs(c.history()) do hist[#hist + 1] = r.name end
  eq("short SFK run not kept", table.concat(hist, ","), "Wailing Caverns,Deadmines,Deadmines")
  eq("all entries counted", #_G.VulcanRunBookDB.entries, 5)
  check("wc kept", c.history()[1] == wc)
  local dm = c.run()
  c.tick(70)
  c.leave()
  c.enter("Deadmines", 36, { diff = 2 })
  eq("difficulty change ends run", dm.endReason, "new dungeon")
  -- Scarlet Monastery: four wings, one instance ID, told apart by their maps.
  c.mapNames = { [302] = "Graveyard", [303] = "Library" }
  c.leave()
  c.enter("Scarlet Monastery", 189, { uiMap = 302 })
  local gy = c.run()
  eq("wing label", gy.label, "Scarlet Monastery - Graveyard")
  c.tick(300)
  c.leave()
  c.enter("Scarlet Monastery", 189, { uiMap = 303 })
  c.tick(4)  -- the wing is read again once the map settles
  check("another wing is a new run", c.run() ~= gy and gy.endReason == "wing", gy.endReason)
  eq("library label", c.run().label, "Scarlet Monastery - Library")
  -- A dungeon whose floors share a map group: coming back in on another floor
  -- stays one run.
  c.mapGroups = { [500] = 77, [501] = 77 }
  c.leave()
  c.enter("Blackrock Depths", 230, { uiMap = 500 })
  local brd = c.run()
  c.tick(100)
  c.leave()
  c.enter("Blackrock Depths", 230, { uiMap = 501 })
  check("floors of one dungeon: same run", c.run() == brd)
  eq("no wing label for floors", brd.label, "Blackrock Depths")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("unreadable instance info")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(50)
  c.fire("ENCOUNTER_START", 1144, "Rhahk'Zor", 1, 5)
  c.secret.iname = true          -- the dungeon name is hidden for a while
  c.tick(10)
  check("still inside", c.ns.inside and c.run() == run)
  c.fire("ENCOUNTER_END", 1144, "Rhahk'Zor", 1, 5, 1)
  eq("boss still recorded", #run.bosses, 1)
  c.secret.iname = false
  -- The map ID hidden mid-run: the name stands in, the run continues.
  c.secret.map = true
  c.leave()
  c.enter("Deadmines", 36)
  check("same run with map hidden", c.run() == run)
  eq("no extra entry", #_G.VulcanRunBookDB.entries, 1)
  c.slash("end")
  c.tick(10)
  check("end holds with map hidden", c.run() == nil)
  -- The wing hidden: the run continues too.
  c.secret.map = false
  c.slash("start")
  c.secret.uimap = true
  c.leave()
  c.enter("Deadmines", 36)
  check("same run with wing hidden", c.run() == run)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("manual end, start, new")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(70)
  c.encounter(1144, "Rhahk'Zor", true, 30)
  c.slash("end")
  check("ended", c.run() == nil and run.endReason == "manual")
  check("end message", c.printedMatch("Deadmines ended:", true) ~= nil)
  c.tick(10)
  check("doesn't restart inside after end", c.run() == nil)
  c.slash("start")
  check("start reopens the same run", c.run() == run)
  eq("reopened run left history", #c.history(), 0)
  eq("reopen isn't a new instance", #_G.VulcanRunBookDB.entries, 1)
  eq("bosses kept", #run.bosses, 1)
  c.tick(10)
  eq("time continues", math.floor(run.elapsed + 0.5), 110)
  c.slash("start")
  check("start while running explained", c.printedMatch("A run is already going", true) ~= nil)
  c.slash("new yes")
  check("new starts fresh", c.run() ~= nil and c.run() ~= run and run.endReason == "new")
  eq("new counts as a new instance", #_G.VulcanRunBookDB.entries, 2)
  c.slash("end")
  c.leave()
  c.enter("Deadmines", 36)
  check("leaving clears the hold", c.run() ~= nil)
  c.leave()
  c.slash("new yes")
  check("new outside refused", c.printedMatch("Only inside a dungeon.", true) ~= nil)
  -- /runbook end survives a reload inside, and start still reopens.
  local d = fresh()
  d.enter("Deadmines", 36)
  d.tick(70)
  local dr = d.run()
  d.slash("end")
  local e = H.boot({ saved = d.saved() })
  e.instance = { name = "Deadmines", map = 36, diff = 1, kind = "party", uiMap = 10036 }
  e.login()
  e.tick(6)
  check("hold kept across reload", e.run() == nil)
  e.slash("start")
  check("reopened after reload", e.run() ~= nil and e.run().id == dr.id)
  noErrors(c, d, e)
end

---------------------------------------------------------------------------
H.group("reload and relog")
do
  local c = fresh()
  items(c)
  c.enter("Deadmines", 36)
  c.tick(200)
  c.encounter(1144, "Rhahk'Zor", true, 30)
  c.lootMsg(nil, 100)
  local s = c.saved()
  local r = H.boot({ saved = s })
  r.instance = { name = "Deadmines", map = 36, diff = 1, kind = "party", uiMap = 10036 }
  r.login()
  check("run restored", r.run() ~= nil and r.run().name == "Deadmines")
  eq("bosses kept", #r.run().bosses, 1)
  eq("drops kept", #r.run().drops, 1)
  eq("no new entry on reload", #_G.VulcanRunBookDB.entries, 1)
  r.tick(10)
  eq("time continues after reload", math.floor(r.run().elapsed + 0.5), 240)
  -- Log out inside, back an hour later (outside): the old run is archived at login.
  local later = H.boot({ saved = r.saved(), gap = 3600 })
  later.login()
  check("stale run ended at login", later.run() == nil)
  eq("archived at login", later.history()[1].endReason, "login")
  -- Log out inside, back after 20 min outside: ends 30 min after logout.
  local t = fresh()
  t.enter("Deadmines", 36)
  t.tick(100)
  local back = H.boot({ saved = t.saved(), gap = 1200 })
  back.login()
  check("still open after 20 min", back.run() ~= nil)
  back.tick(590)
  check("open at 29m50", back.run() ~= nil)
  back.tick(20)
  check("ends 30 min after logout", back.run() == nil)
  -- A saved run missing its timestamps still times out.
  local u = fresh()
  u.enter("Deadmines", 36)
  u.tick(100)
  local su = u.saved()
  su.char.run.lastIn, su.char.run.leftAt = nil, nil
  local v = H.boot({ saved = su })
  v.login()
  v.tick(1810)
  check("run without timestamps times out", v.run() == nil)
  noErrors(c, r, later, back, v)
end

---------------------------------------------------------------------------
H.group("clears, best times and splits")
do
  local c = fresh()
  local function clear(times, ids)
    c.enter("Deadmines", 36)
    local last = 0
    for i, t in ipairs(times) do
      c.tick(t - last - 30)
      local id = ids and ids[i] or (1000 + i)
      c.encounter(id, "Boss" .. (id - 1000), true, 30)
      last = t
    end
    c.leave()
    c.system("Deadmines has been reset.")
  end
  clear({ 300, 600, 900 })
  eq("one run: its last kill is the final boss for now", c.ns.FinalBoss(c.ns.RunKey(c.history()[1])).name, "Boss3")
  clear({ 320, 620, 950 })
  local key = c.ns.RunKey(c.history()[1])
  eq("two runs ending on Boss3: the final boss", c.ns.FinalBoss(key).name, "Boss3")
  clear({ 280, 650, 850 })
  check("best clear message", anyPrinted(c, "New best clear for Deadmines: 14:10 (-0:50)."))
  check("split vs best printed", anyPrinted(c, "Boss2 down at 10:50 (+0:50 vs best)."))
  local best, bestT = c.ns.BestRun(key)
  eq("best is the faster run", bestT, 850)
  check("best run object", best == c.history()[1])
  -- Skipping the middle boss but killing the final one is still a clear.
  clear({ 250, 700 }, { 1001, 1003 })
  eq("skip-a-boss run is a clear", c.ns.ClearTime(c.history()[1]), 700)
  check("and the new best", anyPrinted(c, "New best clear for Deadmines: 11:40"))
  -- Two bosses but not the final one: not a clear.
  clear({ 100, 200 })
  eq("partial run isn't a clear", c.ns.ClearTime(c.history()[1]), nil)
  -- A rare boss killed last once doesn't change the final boss.
  clear({ 200, 400, 600, 800 }, { 1001, 1002, 1003, 1009 })
  eq("final boss holds", c.ns.FinalBoss(key).id, 1003)
  local stats = c.ns.DungeonStats()
  eq("one dungeon", #stats, 1)
  eq("runs", stats[1].runs, 6)
  eq("clears", stats[1].clears, 5)
  eq("best", stats[1].best, 600)
  eq("avg clear", stats[1].avgClear, (900 + 950 + 850 + 700 + 600) / 5)
  -- Live window: splits only where the boss order matches the best run (Boss1, Boss2, Boss3, rare).
  c.enter("Deadmines", 36)
  c.tick(170)
  c.encounter(1001, "Boss1", true, 30)
  local live = c.liveText()
  check("live boss count: bosses up to the final one (the rare doesn't count)", live:find("Bosses 1/3", 1, true)
    ~= nil, live)
  check("live split delta", live:find("Boss1  3:20  +0:00", 1, true) ~= nil or live:find("Boss1  3:20  ±0:00", 1, true)
    ~= nil, live)
  check("live best", live:find("best 10:00", 1, true) ~= nil, live)
  c.tick(10)
  c.encounter(1003, "Boss3", true, 30)
  live = c.liveText()
  check("different order: no split shown", live:find("Boss3  4:00\n", 1, true) ~= nil, live)
  -- First run of a dungeon: no "/max" yet.
  local f = fresh()
  f.enter("Wailing Caverns", 43)
  f.tick(100)
  f.encounter(2001, "Kresh", true, 30)
  check("first run: count only", f.liveText():find("Bosses 1\n", 1, true) ~= nil, f.liveText())
  noErrors(c, f)
end

---------------------------------------------------------------------------
H.group("instance cap")
do
  local c = fresh()
  for i = 1, 5 do
    c.enter("Dungeon" .. i, 100 + i)
    c.tick(70)
    c.leave()
    c.tick(60)
  end
  local count = c.ns.CapStatus()
  eq("5 entries", count, 5)
  local line = c.strip(c.ns.CapLine())
  check("cap line at cap", line:find("Instances 5/5 this hour - next in", 1, true) ~= nil, line)
  check("5th start warns", c.printedMatch("That's 5/5 instances this hour", true) ~= nil)
  c.system("You have entered too many instances recently.")
  check("too many instances explained", c.printedMatch("Instance cap reached. RunBook counts 5", true) ~= nil)
  c.clearPrinted()
  c.tick(3600 - 5 * 145 + 20, 1)
  eq("a slot freed", (c.ns.CapStatus()), 4)
  check("slot free notice", c.printedMatch("An instance slot is free again (4/5", true) ~= nil)
  c.slash("cap OFF")
  check("cap off (any case)", c.ns.CapLine() == nil)
  c.slash("cap 3")
  eq("cap set", _G.VulcanRunBookDB.cap, 3)
  c.slash("cap 99")
  check("cap bad value", c.printedMatch("Usage: /runbook cap", true) ~= nil)
  c.fire("UI_ERROR_MESSAGE", 1, "You have entered too many instances recently.")
  -- Server time briefly unreadable: entries aren't lost.
  c.secret.server = true
  eq("entries kept when server time is hidden", (c.ns.CapStatus()), 4)
  c.secret.server = false
  noErrors(c)
end

os.exit(H.summary("tests.lua") and 0 or 1)
