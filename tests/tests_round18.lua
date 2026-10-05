-- RunBook tests for the audit round 18 fixes.
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

local function names(run)
  local t = {}
  for _, b in ipairs(run.bosses) do t[#t + 1] = b.name end
  return table.concat(t, ",")
end

local function duo(c)
  c.party("Mirel")
  c.slash("partner Mirel")
end

---------------------------------------------------------------------------
H.group("one kill, named differently by each of you")
do
  local c = fresh()
  duo(c)
  c.enter("Blackrock Depths", 230)
  local run = c.run()
  c.tick(300)
  c.slash("boss Roccor")
  c.tick(3)
  c.addonMsg("Mirel", string.format("B3|beef01|230|Blackrock Depths||%d|k.1|0|Lord Roccor", run.serverStart))
  eq("one kill, the fuller name", names(run), "Lord Roccor")
  -- Theirs first, then yours.
  c.tick(120)
  c.addonMsg("Mirel", string.format("B3|beef01|230|Blackrock Depths||%d|k.2|0|Bael'Gar", run.serverStart))
  c.tick(3)
  c.slash("boss Baelgar")
  eq("still one more", #run.bosses, 2)
  -- Different names a minute apart: two kills.
  c.tick(60)
  c.slash("boss Magmus")
  c.tick(60)
  c.addonMsg("Mirel", string.format("B3|beef01|230|Blackrock Depths||%d|k.3|0|Emperor", run.serverStart))
  eq("two separate", #run.bosses, 4)
  noErrors(c)
end

H.group("a note added after the run, with entries 7 minutes apart")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(300)
  c.leave()
  c.system("Deadmines has been reset.")
  c.tick(10)
  c.addonMsg("Mirel", string.format("N3|beef01|36|Deadmines||%d|0|after the run", run.serverStart - 420))
  eq("note arrives", #c.history()[1].notes, 1)
  noErrors(c)
end

H.group("start doesn't bring back a run deleted or cleared since")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(200)
  c.slash("end")
  local id = c.history()[1].id
  c.slash("delete " .. id .. " yes")
  c.slash("start")
  check("a new run", c.run() and c.run().id == nil)
  c.tick(70)
  c.slash("end")
  c.slash("clear yes")
  c.slash("start")
  check("again a new one", c.run() and #c.run().bosses == 0 and c.run().elapsed < 5)
  noErrors(c)
end

H.group("two saved copies of a run: notes from both are kept")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(70)
  c.leave()
  c.system("Deadmines has been reset.")
  c.tick(5)
  local id = c.history()[1].id
  local base = c.savedCopy(false)
  c.slash("note #" .. id .. " from main")
  local mainCopy = c.savedCopy(false)
  -- The other copy got a different note later.
  local other = base.db.history[1]
  other.notes = { { who = "Altone", text = "from alt" } }
  other.modified = (mainCopy.db.history[1].modified or 0) + 10
  mainCopy.char.mirror.history = { other }
  mainCopy.char.mirror.savedAt = mainCopy.db.savedAt
  local r = H.boot({ saved = mainCopy })
  r.login()
  eq("both notes", #r.history()[1].notes, 2)
  noErrors(c, r)
end

H.group("stuck messages: a late start-over is ignored; the queue keeps drops")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(600)
  c.addonMsg("Mirel", string.format("X3|beef01|36|Deadmines||%d|1", c.ns.ServerTime() - 300))
  check("not restarted by an old message", c.run() == run)
  noErrors(c)
end

H.group("cap line counts a Scarlet Monastery entry while its wing is read")
do
  local c = fresh()
  c.secret.uimap = true
  c.enter("Scarlet Monastery", 189, { uiMap = 302 })
  c.tick(2)
  local text = c.strip(table.concat(c.ns.LiveLines(), "\n"))
  check("1/5 at once", text:find("Instances 1/5", 1, true) ~= nil, text)
  c.tick(15)
  eq("one entry after", #_G.VulcanRunBookDB.entries, 1)
  noErrors(c)
end

H.summary("tests_round18.lua")
