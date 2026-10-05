-- RunBook tests for the audit round 24 fixes.
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

local function duoSolo(c)
  c.party("Mirel")
  c.slash("partner Mirel")
end

---------------------------------------------------------------------------
H.group("a partner's split message 20 minutes after coming back in still splits")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(60) c.leave() c.tick(60) c.enter("Deadmines", 36)
  local back = c.ns.ServerTime()
  c.tick(120, 10)
  c.addonMsg("Mirel", string.format("P3|beef01|36|Deadmines||%d|%d", back + 5, c.ns.ServerTime()))
  check("split", c.run() ~= run and run.endReason == "split")
  noErrors(c)
end

H.group("a split message held up over 10 minutes is ignored")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(60) c.leave() c.tick(60) c.enter("Deadmines", 36)
  local back = c.ns.ServerTime()
  c.tick(120, 10)
  c.addonMsg("Mirel", string.format("P3|beef01|36|Deadmines||%d|%d", back + 5, back + 100))
  check("not split", c.run() == run)
  noErrors(c)
end

H.group("after a partner's split, the kills' new times are shown")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  c.tick(60) c.leave() c.tick(60) c.enter("Deadmines", 36)
  local back = c.ns.ServerTime()
  c.tick(100)
  c.encounter(644, "Rhahk'Zor")
  c.clearPrinted()
  c.addonMsg("Mirel", string.format("P3|beef01|36|Deadmines||%d|%d", back, c.ns.ServerTime()))
  check("new times line", anyPrinted(c, "In the new run: Rhahk'Zor"))
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("a send that keeps throwing through a boss fight isn't dropped")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  c.tick(5)
  local real = c.ns.SendAddon
  local fail = true
  c.ns.SendAddon = function(...) if fail then error("blocked") end return real(...) end
  c.slash("note one")
  c.slash("note two")
  c.tick(60)
  fail = false
  c.tick(5)
  local n = 0
  for _, m in ipairs(c.addonSent) do if m.msg:find("|one$") or m.msg:find("|two$") then n = n + 1 end end
  eq("both notes sent", n, 2)
  c.ns.SendAddon = real
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("his note on a solo run before you met up doesn't land on your run")
do
  local c = fresh()
  duoSolo(c)
  local soloStart = c.ns.ServerTime()
  c.tick(540, 10)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(600)
  c.addonMsg("Mirel", string.format("N3|beef01|36|Deadmines||%d|0|got the hat", soloStart))
  eq("not on your run", #run.notes, 0)
  noErrors(c)
end

H.group("his note finds the run his numbers reached, even if he began long before")
do
  local c = fresh()
  duoSolo(c)
  local his = c.ns.ServerTime()
  c.tick(300, 10)
  c.enter("Molten Core", 409, { kind = "raid" })
  local run = c.run()
  c.tick(30)
  c.addonMsg("Mirel", string.format("S3|beef01|409|Molten Core||%d|3000|500|0|0|0|0", his))
  c.tick(120, 5)
  c.leave()
  c.system("Molten Core has been reset.")
  c.tick(5)
  c.addonMsg("Mirel", string.format("N3|beef01|409|Molten Core||%d|0|great night", his))
  eq("on your raid", #run.notes, 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("his /runbook new while you're outside: his kills until you're back still count")
do
  local A, B = duo()
  local function kill(id, name, who)
    for _, c in ipairs(who) do D.use(c) c.fire("ENCOUNTER_START", id, name, 1, 5) end
    D.tick(A, B, 10)
    for _, c in ipairs(who) do D.use(c) c.fire("BOSS_KILL", id, name) c.fire("ENCOUNTER_END", id, name, 1, 5, 1) end
    D.tick(A, B, 3)
  end
  D.use(A) A.enter("Deadmines", 36) D.use(B) B.enter("Deadmines", 36) D.tick(A, B, 120)
  kill(1, "Rhahk'Zor", { A, B })
  D.tick(A, B, 60)
  D.use(A) A.leave() D.tick(A, B, 60)
  D.use(B) B.slash("new yes") D.tick(A, B, 5)
  kill(3, "Gilnid", { B })
  D.tick(A, B, 60)
  D.use(A) A.enter("Deadmines", 36) D.tick(A, B, 30)
  kill(4, "Van Cleef", { A, B })
  D.use(A) eq("your new run", names(A.run()), "Gilnid,Van Cleef")
  D.use(B) eq("his", names(B.run()), "Gilnid,Van Cleef")
  noErrors(A, B)
end

---------------------------------------------------------------------------
H.group("unboss of a kill that split the run says the split stays")
do
  local c = fresh()
  c.enter("Deadmines", 36)
  c.tick(100)
  c.encounter(1, "Sneed")
  c.tick(60) c.leave() c.tick(60) c.enter("Deadmines", 36) c.tick(30)
  c.slash("boss Sneed")
  check("split", #c.history() == 1)
  c.clearPrinted()
  c.slash("unboss")
  check("says the split stays", anyPrinted(c, "the earlier part stays a separate run"))
  c.tick(60)
  c.encounter(2, "Gilnid")
  c.clearPrinted()
  c.slash("unboss")
  check("an ordinary kill: no such line", not anyPrinted(c, "stays a separate run"))
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("your run time reaches his log when you step outside")
do
  local c = fresh()
  duoSolo(c)
  c.enter("Deadmines", 36)
  c.tick(95)
  c.addonSent = {}
  c.leave()
  c.tick(1)
  local s
  for _, m in ipairs(c.addonSent) do if m.msg:find("^S") then s = m.msg end end
  check("stats sent on leaving", s ~= nil)
  noErrors(c)
end

H.group("quiet mode: one line for /runbook new at the cap; none for his")
do
  local c = fresh()
  duoSolo(c)
  c.slash("quiet on")
  c.slash("cap 1")
  c.enter("Deadmines", 36)
  c.tick(200)
  c.clearPrinted()
  c.slash("new yes")
  local n = 0
  for _, p in ipairs(c.printed) do if c.strip(p):find("started", 1, true) then n = n + 1 end end
  eq("one 'started' line", n, 1)
  c.tick(200)
  c.clearPrinted()
  c.addonMsg("Mirel", string.format("X3|beef01|36|Deadmines||%d|1", c.ns.ServerTime()))
  check("no 'started over.'", not anyPrinted(c, "started over."))
  check("his line", anyPrinted(c, "so yours started over too"))
  noErrors(c)
end

H.summary("tests_round24.lua")
