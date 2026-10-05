-- RunBook tests for the audit round 25 fixes.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check, eq = H.check, H.eq
dofile("duo_common.lua")

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

local function kill(A, B, id, name, who)
  for _, c in ipairs(who) do D.use(c) c.fire("ENCOUNTER_START", id, name, 1, 5) end
  D.tick(A, B, 10)
  for _, c in ipairs(who) do D.use(c) c.fire("BOSS_KILL", id, name) c.fire("ENCOUNTER_END", id, name, 1, 5, 1) end
  D.tick(A, B, 3)
end

---------------------------------------------------------------------------
H.group("he finds the reset while you're outside: his kills in the new copy go to your new run")
do
  local A, B = duo()
  D.on(A, function(c) c.enter("Deadmines", 36) end)
  D.on(B, function(c) c.enter("Deadmines", 36) end)
  D.tick(A, B, 60)
  kill(A, B, 1, "Rhahk'Zor", { A, B })
  D.tick(A, B, 30)
  D.on(A, function(c) c.leave() end) D.on(B, function(c) c.leave() end)
  D.tick(A, B, 60)
  D.on(B, function(c) c.enter("Deadmines", 36) end)
  D.tick(A, B, 60)
  kill(A, B, 2, "Sneed", { B })
  D.tick(A, B, 60)
  kill(A, B, 1, "Rhahk'Zor", { B })
  D.tick(A, B, 10)
  D.use(A)
  eq("your old run", names(A.history()[1]), "Rhahk'Zor")
  eq("your new run", A.run() and names(A.run()), "Sneed,Rhahk'Zor")
  noErrors(A, B)
end

H.group("he was in the new copy before you: his kill and drop move to your new run")
do
  local A, B = duo()
  for _, c in ipairs({ A, B }) do D.use(c) c.item(500, "Blue Sword", 3, 100) end
  D.on(A, function(c) c.enter("Deadmines", 36) end)
  D.on(B, function(c) c.enter("Deadmines", 36) end)
  D.tick(A, B, 60)
  for _, c in ipairs({ A, B }) do D.use(c) c.fire("BOSS_KILL", 1, "Rhahk'Zor") end
  D.tick(A, B, 30)
  D.on(A, function(c) c.leave() end) D.on(B, function(c) c.leave() end)
  D.tick(A, B, 60)
  D.on(B, function(c) c.enter("Deadmines", 36) end)
  D.tick(A, B, 60)
  D.on(B, function(c) c.fire("BOSS_KILL", 2, "Sneed") end)
  D.tick(A, B, 5)
  D.on(B, function(c) c.lootReal(500, 1) end)
  D.tick(A, B, 60)
  D.on(A, function(c) c.enter("Deadmines", 36) end)
  D.tick(A, B, 60)
  for _, c in ipairs({ A, B }) do D.use(c) c.fire("BOSS_KILL", 1, "Rhahk'Zor") end
  D.tick(A, B, 10)
  D.use(A)
  eq("your old run", names(A.history()[1]), "Rhahk'Zor")
  eq("your new run", names(A.run()), "Sneed,Rhahk'Zor")
  eq("his drop in the new run", #A.run().drops, 1)
  eq("not in the old", #A.history()[1].drops, 0)
  noErrors(A, B)
end

---------------------------------------------------------------------------
H.group("a run for his new copy that you never go into isn't saved")
do
  local A, B = duo()
  D.on(A, function(c) c.enter("Deadmines", 36) end)
  D.on(B, function(c) c.enter("Deadmines", 36) end)
  D.tick(A, B, 60)
  kill(A, B, 1, "Rhahk'Zor", { A, B })
  D.tick(A, B, 60)
  D.on(B, function(c) c.leave() end)
  D.tick(A, B, 30)
  D.on(A, function(c) c.slash("new yes") end)
  D.tick(A, B, 60)
  kill(A, B, 1, "Rhahk'Zor", { A })
  kill(A, B, 2, "Sneed", { A })
  D.on(A, function(c) c.leave() end)
  D.tick(A, B, 40, 60)
  D.use(B)
  eq("his history: only the run he was in", #B.history(), 1)
  eq("that run", names(B.history()[1]), "Rhahk'Zor")
  noErrors(A, B)
end

H.group("his /runbook new while you run back as a ghost: still running back")
do
  local A, B = duo()
  D.on(A, function(c) c.enter("Deadmines", 36) end)
  D.on(B, function(c) c.enter("Deadmines", 36) end)
  D.tick(A, B, 120)
  D.on(A, function(c) c.die() end)
  D.tick(A, B, 5)
  D.on(A, function(c) c.leave() end)
  D.tick(A, B, 30)
  D.on(B, function(c) c.slash("new yes") end)
  D.tick(A, B, 3)
  D.use(A)
  check("ghost running", A.ns.GhostRunning())
  local before = A.run().elapsed
  D.tick(A, B, 100)
  D.use(A)
  check("the run back counts", A.run().elapsed >= before + 90)
  noErrors(A, B)
end

---------------------------------------------------------------------------
H.group("a run whose map ID was never readable is filed with the dungeon")
do
  local c = H.boot({}) c.login()
  local function run(secretMap, t)
    c.secret.map = secretMap
    c.enter("Deadmines", 36) c.tick(60)
    c.fire("BOSS_KILL", 1, "Rhahk'Zor") c.tick(t)
    c.fire("BOSS_KILL", 4, "Van Cleef") c.tick(30)
    c.leave() c.secret.map = nil c.tick(5)
    c.enter("Stockade", 34) c.tick(5)
    c.leave() c.tick(5)
  end
  run(false, 600)
  run(true, 300)
  local rows = 0
  for _, s in ipairs(c.ns.DungeonStats()) do if s.name:find("Deadmines", 1, true) then rows = rows + 1 end end
  eq("one Deadmines row", rows, 1)
  noErrors(c)
end

H.group("a newer short copy wins over an older full one")
do
  local c = H.boot({}) c.login()
  c.enter("Deadmines", 36) c.tick(70)
  c.encounter(1, "A") c.tick(10) c.encounter(2, "B")
  c.leave() c.system("Deadmines has been reset.") c.tick(5)
  local stale = c.savedCopy(false)                     -- (an alt's backup from now)
  c.slash("unboss")
  local fresh = c.savedCopy(false)
  local run = fresh.db.history[1]
  local short = c.ns.Lite(run)
  fresh.db.old = { short }                              -- account data: pruned to a short copy
  fresh.db.history = {}
  fresh.char.mirror.history = stale.db.history          -- a character's backup: the stale full copy
  fresh.char.mirror.old = {}
  local r = H.boot({ saved = fresh })
  r.login()
  local found
  for _, x in ipairs(r.history()) do if x.serverStart == run.serverStart then found = x end end
  for _, x in ipairs(_G.VulcanRunBookDB.old) do if x.serverStart == run.serverStart then found = found or x end end
  eq("one boss (the unboss kept)", found and #found.bosses, 1)
  noErrors(c, r)
end

---------------------------------------------------------------------------
H.group("note lines keep their spacing")
do
  local c = H.boot({}) c.login()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.slash("note fast pull")
  local text = c.strip(table.concat(c.ns.RunDetailLines(c.run()), "\n"))
  check("two spaces after the time", text:find("1:40  Tavlius: fast pull", 1, true) ~= nil, text)
  noErrors(c)
end

H.summary("tests_round25.lua")
