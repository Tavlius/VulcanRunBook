-- RunBook tests for the audit round 19 fixes.
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

local function duo(c)
  c.party("Mirel")
  c.slash("partner Mirel")
end

---------------------------------------------------------------------------
H.group("a late joiner's note goes on the run he joined")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local a = c.run()
  c.tick(2000) c.leave() c.system("Deadmines has been reset.") c.tick(60)
  c.enter("Deadmines", 36)
  local b = c.run()
  c.tick(1500) c.leave() c.system("Deadmines has been reset.") c.tick(60)
  c.addonMsg("Mirel", string.format("N3|beef01|36|Deadmines||%d|0|late joiner note", a.serverStart + 600))
  eq("on the run he joined", #a.notes, 1)
  eq("not the next one", #b.notes, 0)
  -- One with no later run of yours isn't lost either.
  c.addonMsg("Mirel", string.format("N3|beef01|36|Deadmines||%d|0|second", b.serverStart + 900))
  eq("on the last run", #b.notes, 1)
  -- A run of his from before yours still finds yours.
  c.addonMsg("Mirel", string.format("N3|beef01|36|Deadmines||%d|0|early", a.serverStart - 120))
  eq("early start: first run", #a.notes, 2)
  noErrors(c)
end

H.group("a late joiner's hand mark of a boss you killed: no split")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(200)
  c.encounter(644, "Rhahk'Zor")
  c.tick(100)
  c.leave() c.tick(60)                         -- repair trip
  c.enter("Deadmines", 36)
  c.tick(300)
  local his = c.ns.ServerTime()
  c.tick(30)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.1!m|644|Rhahk'Zor", his))
  check("same run", c.run() == run)
  eq("one kill", names(run), "Rhahk'Zor")
  check("no reset line", not anyPrinted(c, "killed again"))
  check("paired", run.bosses[1].peer == "k.1")
  -- Outside, the same: your run doesn't end.
  c.leave()
  c.tick(30)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.2!m|644|Rhahk'Zor", his))
  check("still going", c.run() == run and not run.ended)
  noErrors(c)
end

H.group("his game-reported repeat kill still finds the reset")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(60)
  c.encounter(644, "Rhahk'Zor")
  c.tick(30)
  c.leave()
  c.tick(120)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.4|644|Rhahk'Zor", c.ns.ServerTime()))
  check("your run ended (reset)", run.ended and run.endReason == "reset")
  noErrors(c)
end

H.group("your hand marks are sent flagged")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  c.tick(60)
  c.slash("boss Rhahk'Zor")
  c.tick(2)
  local found = false
  for _, m in ipairs(c.addonSent) do
    if m.msg:find("^B") and m.msg:find("!m|%d+|%d+|%d+|Rhahk'Zor$") then found = true end
  end
  check("B message carries m", found)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a kill taken back stays gone when two copies merge")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.encounter(1, "Rhahk'Zor")
  c.tick(100)
  c.slash("boss Oops")
  c.tick(70) c.leave() c.system("Deadmines has been reset.") c.tick(5)
  local id = c.history()[1].id
  local base = c.savedCopy(false)
  c.slash("unboss #" .. id)
  local main = c.savedCopy(false)
  local other = base.db.history[1]
  other.notes = { { who = "Altone", text = "from alt" } }
  other.modified = (main.db.history[1].modified or 0) + 10
  main.db.history = { other }
  local r = H.boot({ saved = main })
  r.login()
  local run = r.history()[1]
  eq("bosses", names(run), "Rhahk'Zor")
  eq("note kept", #run.notes, 1)
  noErrors(c, r)
end

H.group("an unreadable difficulty doesn't end the run")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  local r = c.run()
  c.tick(120)
  local orig = _G.GetInstanceInfo
  _G.GetInstanceInfo = function() local a, b, _, e, f, g, h, i = orig() return a, b, c.SECRET, e, f, g, h, i end
  c.tick(10)
  _G.GetInstanceInfo = orig
  c.tick(10)
  check("same run", c.run() == r)
  eq("no saved run", #c.history(), 0)
  noErrors(c)
end

H.group("a run started while the difficulty was unreadable takes it later")
do
  local c = fresh()
  local orig = _G.GetInstanceInfo
  _G.GetInstanceInfo = function() local a, b, _, e, f, g, h, i = orig() return a, b, c.SECRET, e, f, g, h, i end
  c.enter("Deadmines", 36)
  local r = c.run()
  c.tick(10)
  _G.GetInstanceInfo = orig
  c.tick(10)
  check("same run", c.run() == r)
  check("difficulty filled in", not r.diffUnknown)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("debug export header")
do
  local c = fresh()
  c.ns.DB.debugLog = { "one line" }
  eq("1 entry", c.ns.ExportLines("debug")[1], "RunBook diagnostics (1 entry)")
  noErrors(c)
end

H.summary("tests_round19.lua")
