-- RunBook tests for the audit round 10 fixes.
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

local function names(run)
  local t = {}
  for _, b in ipairs(run.bosses) do t[#t + 1] = b.name end
  return table.concat(t, ",")
end

local function sm(c)
  c.mapGroups = { [302] = 50, [303] = 50, [304] = 50, [305] = 50 }
  c.mapNames = { [302] = "Scarlet Monastery", [303] = "Scarlet Monastery" }
  c.groupFloors = { [50] = { { mapID = 302, name = "Graveyard" }, { mapID = 303, name = "Library" },
    { mapID = 304, name = "Armory" }, { mapID = 305, name = "Cathedral" } } }
end

-- Your last B message sent.
local function lastB(c)
  for i = #c.addonSent, 1, -1 do
    local m = c.addonSent[i].msg
    if m:sub(1, 1) == "B" then return m end
  end
  return nil
end

---------------------------------------------------------------------------
H.group("a mark named later reaches your partner's copy of the kill")
do
  -- Your side: you press, then name it; both messages go out.
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  c.tick(100)
  _G.VulcanRunBook_MarkBoss()
  c.tick(2)
  local first = lastB(c)
  check("anonymous mark sent with a tag", first and first:find("|%x+%.%d+!m|0|%d+|%d+|$") ~= nil, first)
  c.slash("boss Sneed")
  c.tick(2)
  local second = lastB(c)
  check("named mark sent with the same tag", second and second:find("|0|%d+|%d+|Sneed$") ~= nil, second)
  local tag1 = first:match("|([%x]+%.%d+)|0|$")
  local tag2 = second:match("|([%x]+%.%d+)|0|Sneed$")
  eq("same tag", tag2, tag1)
  -- Mirel's side gets both: one boss, named.
  local k = fresh({ name = "Mirel" })
  k.party("Tavlius")
  k.slash("partner Tavlius")
  k.enter("Deadmines", 36)
  local run = k.run()
  k.tick(100)
  local function relay(msg)
    local body = msg:gsub("^B3|%x+|36|Deadmines||%d+|", "")
    k.addonMsg("Tavlius", string.format("B3|beef01|36|Deadmines||%d|%s", run.serverStart, body))
  end
  relay(first)
  k.tick(5)
  relay(second)
  eq("one boss on his side, named", names(run), "Sneed")
  -- He pressed too (paired), then your name arrives: still one.
  k.tick(100)
  _G.VulcanRunBook_MarkBoss()
  k.tick(3)
  k.addonMsg("Tavlius", string.format("B3|beef01|36|Deadmines||%d|abc123.9|0|", run.serverStart))
  k.tick(5)
  k.addonMsg("Tavlius", string.format("B3|beef01|36|Deadmines||%d|abc123.9|0|Gilnid", run.serverStart))
  eq("still two, named", names(run), "Sneed,Gilnid")
  noErrors(c, k)
end

H.group("press, partner's mark pairs, then you name it")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(100)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k1.1|0|", run.serverStart))
  c.tick(3)
  _G.VulcanRunBook_MarkBoss()
  c.tick(3)
  c.slash("boss Sneed")
  eq("one boss, named", names(run), "Sneed")
  c.tick(31)
  local m = lastB(c)
  check("sent with his tag", m and m:find("|k1%.1|0|%d+|%d+|Sneed$") ~= nil, m)
  -- A nameless game kill, then your name for it.
  c.tick(100)
  c.fire("BOSS_KILL", c.SECRET, c.SECRET)
  c.tick(4)
  c.slash("boss Gilnid")
  eq("named, not added", names(run), "Sneed,Gilnid")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("partner numbers: what he made during each of your runs")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local a = c.run()
  local p = a.serverStart
  local function S(el, coin, final)
    c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|%d|%d|0|0|%d|%d", p, el, coin, coin / 100,
      final and 1 or 0))
  end
  c.tick(100) S(100, 10000)
  c.slash("end")
  c.tick(5)
  c.slash("start")                     -- reopened: same run
  c.slash("end")
  c.leave()
  c.tick(60)
  S(200, 20000)                        -- he earns while you have no run
  c.enter("Deadmines", 36)
  local b = c.run()
  c.tick(100) S(300, 30000)
  c.slash("end")
  c.leave()
  c.tick(60)
  S(400, 40000)
  c.enter("Deadmines", 36)
  local cc = c.run()
  c.tick(100) S(500, 60000)
  eq("A: 10k", a.partners.Mirel.coin, 10000)
  eq("B: 10k (20k to 30k)", b.partners.Mirel.coin, 10000)
  eq("C: 20k (40k to 60k)", cc.partners.Mirel.coin, 20000)
  eq("C: XP since", cc.partners.Mirel.xp, 200)
  -- His final word, much later: not into your ended runs.
  c.tick(600)
  S(1200, 90000, true)
  eq("B unchanged", b.partners.Mirel.coin, 10000)
  noErrors(c)
end

H.group("a detour to another dungeon and back to the same copy keeps sync")
do
  local c = fresh()
  c.party("Mirel")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local a = c.run()
  local p = a.serverStart
  c.tick(200)
  c.leave()
  c.enter("Wailing Caverns", 43)
  c.tick(70)
  c.leave()
  c.enter("Deadmines", 36)
  local back = c.run()
  check("new run", back ~= a)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|400|40000|0|0|0|0", p))
  c.tick(60)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|460|50000|0|0|0|0", p))
  eq("his numbers in the run you're in", back.partners.Mirel and back.partners.Mirel.coin, 10000)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.1|643|Sneed", p))
  eq("his kill too", names(back), "Sneed")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("wing reading: outdoor map, unreadable, name only")
do
  local c = fresh()
  sm(c)
  c.mapNames[1420] = "Tirisfal Glades"
  c.enter("Scarlet Monastery", 189, { uiMap = 303 })
  local lib = c.run()
  c.tick(300)
  c.leave()
  c.enter("Scarlet Monastery", 189, { uiMap = 1420 })   -- outdoors for a moment
  c.tick(4)
  c.instance.uiMap = 303
  c.tick(4)
  check("same library run", c.run() == lib)
  eq("one entry", #_G.VulcanRunBookDB.entries, 1)
  -- Unreadable on arrival in another wing: not taken for the copy you ended.
  local d = fresh()
  sm(d)
  d.enter("Scarlet Monastery", 189, { uiMap = 303 })
  d.tick(200)
  d.slash("end")
  d.leave()
  d.secret.uimap = true
  d.enter("Scarlet Monastery", 189, { uiMap = 304 })
  d.secret.uimap = nil
  d.tick(4)
  eq("counted once the wing is read", #_G.VulcanRunBookDB.entries, 2)
  eq("armory", d.run().label, "Scarlet Monastery - Armory")
  check("started line names the wing", anyPrinted(d, "Scarlet Monastery - Armory started"))
  check("no false hint", not anyPrinted(d, "can't be told apart"))
  noErrors(c, d)
end

H.group("a wing map with no name still gets its own label")
do
  local c = fresh()
  c.mapGroups = { [9001] = 77 }
  c.mapNames = { [9001] = "Scarlet Monastery" }
  c.enter("Scarlet Monastery", 189, { uiMap = 9001 })
  c.tick(4)
  eq("label", c.run().label, "Scarlet Monastery - map 9001")
  noErrors(c)
end

H.group("/runbook new twice in a row counts one instance")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(5)
  c.slash("new yes")
  c.tick(5)
  c.slash("new yes")
  eq("one entry", #_G.VulcanRunBookDB.entries, 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("messages: unboss, no-boss hint, Stratholme")
do
  local c = fresh()
  c.slash("unboss #99")
  check("no such run", anyPrinted(c, "No run #99."))
  c.enter("Deadmines", 36)
  c.tick(5)
  c.slash("unboss")
  check("points to #N", anyPrinted(c, "(/runbook unboss #12 for run #12)"))
  _G.VulcanRunBook_MarkBoss()
  c.slash("unboss")
  c.tick(400)
  c.leave()
  c.system("Deadmines has been reset.")
  c.tick(2)
  check("no 'no boss kills' hint after marking", not anyPrinted(c, "No boss kills were reported"))
  local s = fresh()
  s.enter("Stratholme", 329, { uiMap = 317 })
  s.tick(5)
  check("stratholme: one copy, no hint", not anyPrinted(s, "can't be told apart"))
  noErrors(c, s)
end

H.summary("tests_round10.lua")
