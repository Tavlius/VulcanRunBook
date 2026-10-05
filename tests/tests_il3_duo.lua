-- Improvement loop 3, two-client checks: Tavlius's and Mirel's clients wired
-- together (duo.lua).
package.path = "./?.lua;" .. package.path
dofile("duo_common.lua")
local passed, failed, group = 0, 0, "?"
local function Group(g) group = g end
local function check(name, ok, detail)
  if ok then passed = passed + 1 else
    failed = failed + 1
    io.write("FAIL [" .. group .. "] " .. name .. (detail ~= nil and ("  [" .. tostring(detail) .. "]") or "") .. "\n")
  end
end
local function both(A, B, f) for _, c in ipairs({ A, B }) do D.use(c) f(c) end end
local function noErrors(A, B)
  for _, c in ipairs({ A, B }) do D.use(c) check("no errors", #c.errors() == 0, c.errors()[1]) end
end

local DM = { { 1, "Rhahk'Zor" }, { 2, "Sneed" }, { 3, "Gilnid" }, { 4, "Mr. Smite" }, { 5, "Edwin VanCleef" } }

Group("away 30+ minutes while your partner stays inside: back in the same copy")
do
  local A, B = duo()
  local function kill(i) both(A, B, function(c) c.encounter(DM[i][1], DM[i][2], true, 30) end) D.tick(A, B, 1) end
  both(A, B, function(c) c.enter("Deadmines", 36) end)
  for i = 1, 5 do D.tick(A, B, 300) kill(i) end
  D.tick(A, B, 30)
  both(A, B, function(c) c.leave() end) D.tick(A, B, 60)
  both(A, B, function(c) c.system("Deadmines has been reset.") end) D.tick(A, B, 5)
  both(A, B, function(c) c.enter("Deadmines", 36) end)
  for i = 1, 2 do D.tick(A, B, 300) kill(i) end
  D.use(A) local t0 = A.ns.ServerTime()
  A.leave()
  D.tick(A, B, 35 * 60)
  D.use(A) A.enter("Deadmines", 36)
  D.tick(A, B, 30)
  for i = 3, 5 do D.tick(A, B, 120) kill(i) end
  D.tick(A, B, 30)
  D.use(A)
  local n = 0
  for _, e in ipairs(_G.VulcanRunBookDB.entries) do if e >= t0 then n = n + 1 end end
  check("no new cap entry", n == 0, n)
  check("the run is late", A.ns.LateRun(A.ns.run))
  check("said why", (function()
    for _, p in ipairs(A.printed) do if A.strip(p):find("stayed in this copy", 1, true) then return true end end
  end)())
  local _, bt = A.ns.BestRun(A.ns.RunKey(A.ns.run))
  check("the best clear is the whole one", bt and bt > 1400, bt)
  noErrors(A, B)
end

Group("he left too: back in after 30+ minutes is a new copy")
do
  local A, B = duo()
  both(A, B, function(c) c.enter("Deadmines", 36) end)
  D.tick(A, B, 300)
  both(A, B, function(c) c.encounter(1, "Rhahk'Zor", true, 30) end) D.tick(A, B, 60)
  both(A, B, function(c) c.leave() end)
  D.tick(A, B, 35 * 60)
  D.use(A) local t0 = A.ns.ServerTime()
  D.use(B) B.enter("Deadmines", 36) D.tick(A, B, 120)   -- (he goes in first: a run of his you weren't in)
  D.use(A) A.enter("Deadmines", 36) D.tick(A, B, 120)
  D.use(B) B.encounter(2, "Sneed", true, 30) D.tick(A, B, 30)
  D.use(A)
  local n = 0
  for _, e in ipairs(_G.VulcanRunBookDB.entries) do if e >= t0 then n = n + 1 end end
  check("a new cap entry", n == 1, n)
  check("not late", not A.ns.LateRun(A.ns.run))
  noErrors(A, B)
end

Group("his repeat kill of an earlier run's boss while you're outside splits your run")
do
  local A, B = duo()
  both(A, B, function(c) c.enter("Deadmines", 36) end)
  D.tick(A, B, 120)
  both(A, B, function(c) c.encounter(644, "Rhahk'Zor", true, 20) end) D.tick(A, B, 60)
  both(A, B, function(c) c.slash("end") end) D.tick(A, B, 5)
  both(A, B, function(c) c.leave() end) D.tick(A, B, 60)
  both(A, B, function(c) c.enter("Deadmines", 36) end) D.tick(A, B, 60)
  both(A, B, function(c) c.encounter(645, "Sneed", true, 20) end) D.tick(A, B, 60)
  both(A, B, function(c) c.leave() end) D.tick(A, B, 300)
  both(A, B, function(c) c.enter("Deadmines", 36) end) D.tick(A, B, 120)
  D.use(A) A.leave() D.tick(A, B, 60)
  D.use(B) B.encounter(644, "Rhahk'Zor", true, 20) D.tick(A, B, 30)
  D.use(A)
  check("split while outside", A.history()[1] and A.history()[1].endReason == "split",
    A.history()[1] and A.history()[1].endReason)
  check("Sneed stays in the old run", A.history()[1] and names(A.history()[1]) == "Sneed",
    A.history()[1] and names(A.history()[1]))
  check("his kill in the new run", A.ns.run and names(A.ns.run) == "Rhahk'Zor", A.ns.run and names(A.ns.run))
  noErrors(A, B)
end

io.write(string.format("tests_il3_duo.lua: %d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
