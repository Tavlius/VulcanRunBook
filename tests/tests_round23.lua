-- RunBook tests for the audit round 23 fixes.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check, eq = H.check, H.eq
dofile("duo_common.lua")

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

local function duoSolo(c)
  c.party("Mirel")
  c.slash("partner Mirel")
end

---------------------------------------------------------------------------
H.group("while you run back as a ghost, his death outside doesn't count")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  c.tick(60)
  c.die()
  c.tick(3)
  c.away = { Mirel = 1429 }
  c.leave()
  c.tick(5)
  check("ghost running", c.ns.GhostRunning())
  c.member("Mirel").dead = true
  c.tick(3)
  eq("only your death", #c.run().deaths, 1)
  eq("no wipe", #c.run().wipes, 0)
  noErrors(c)
end

H.group("him lying dead outside doesn't make your death a wipe")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  c.tick(60)
  c.away = { Mirel = 1429 }
  c.tick(3)
  c.member("Mirel").dead = true
  c.tick(3)
  c.tick(20)
  c.die()
  c.tick(3)
  eq("one death", #c.run().deaths, 1)
  eq("no wipe", #c.run().wipes, 0)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a reset his log finds by a repeat kill reaches your log")
do
  local A, B = duo()
  local function kill(id, name, who)
    for _, c in ipairs(who) do D.use(c) c.fire("ENCOUNTER_START", id, name, 1, 5) end
    D.tick(A, B, 10)
    for _, c in ipairs(who) do D.use(c) c.fire("BOSS_KILL", id, name) c.fire("ENCOUNTER_END", id, name, 1, 5, 1) end
    D.tick(A, B, 3)
  end
  D.use(B) B.enter("Deadmines", 36) D.tick(A, B, 30)
  kill(1, "Rhahk'Zor", { B })
  D.tick(A, B, 60)
  D.use(A) A.enter("Deadmines", 36) D.tick(A, B, 30)
  kill(2, "Sneed", { A, B })
  D.tick(A, B, 60)
  D.use(A) A.leave() D.use(B) B.leave() D.tick(A, B, 60)
  D.use(A) A.enter("Deadmines", 36) D.use(B) B.enter("Deadmines", 36) D.tick(A, B, 60)
  kill(1, "Rhahk'Zor", { A, B })
  D.tick(A, B, 5)
  D.use(A)
  eq("your new run", names(A.run()), "Rhahk'Zor")
  eq("your old run", A.history()[1] and names(A.history()[1]), "Sneed")
  noErrors(A, B)
end

H.group("a partner's split from long ago, or another dungeon, changes nothing")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(60) c.leave() c.tick(60) c.enter("Deadmines", 36)
  local back = c.ns.ServerTime()
  c.tick(300)
  c.addonMsg("Mirel", string.format("P3|beef01|36|Deadmines||%d", back - 200))
  check("not split (came back in at another time)", c.run() == run)
  c.addonMsg("Mirel", string.format("P3|beef01|43|Wailing Caverns||%d", back))
  check("not split (another dungeon)", c.run() == run)
  c.addonMsg("Mirel", string.format("P3|beef01|36|Deadmines||%d", back + 10))
  check("split", c.run() ~= run and run.endReason == "split")
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("scale keeps the window's place")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.slash("show")
  local f
  for _, x in ipairs(c.frames) do if x.scripts and x.scripts.OnDragStop and x.scale then f = x end end
  check("found the window", f ~= nil)
  c.ns.DB.point = { "CENTER", "CENTER", -320, 120 }
  c.slash("scale 2")
  local p = f and f.lastPoint
  check("offsets halved at scale 2", p and p[4] == -160 and p[5] == 60, p and (tostring(p[4]) .. "," .. tostring(p[5])))
  noErrors(c)
end

H.group("a send that throws is retried, not dropped")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  c.tick(5)
  local real = _G.C_ChatInfo.SendAddonMessage
  local fail = true
  _G.C_ChatInfo.SendAddonMessage = function(...) if fail then error("blocked") end return real(...) end
  c.ns.SendAddon = _G.C_ChatInfo.SendAddonMessage
  c.slash("note keep me")
  c.tick(2)
  fail = false
  c.tick(2)
  local sent = false
  for _, m in ipairs(c.addonSent) do if m.msg:find("keep me", 1, true) then sent = true end end
  check("note sent after the error", sent)
  c.ns.SendAddon = real
  _G.C_ChatInfo.SendAddonMessage = real
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("deaths line: full names when shortening doesn't name more")
do
  local c = fresh()
  c.party("Mirel", "Bigpugwarrior", "Healzforyou", "Aoemagelolol")
  c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(100)
  local t = run.elapsed
  for _, w in ipairs({ "Aoemagelolol", "Aoemagelolol", "Bigpugwarrior", "Bigpugwarrior", "Healzforyou", "Mirel",
    "Tavlius" }) do
    run.deaths[#run.deaths + 1] = { who = w, t = t }
  end
  local line
  for _, l in ipairs(c.ns.LiveLines()) do if c.strip(l):find("deaths", 1, true) then line = c.strip(l) end end
  check("no '...' when not needed", line and not line:find("...", 1, true), line)
  noErrors(c)
end

H.summary("tests_round23.lua")
