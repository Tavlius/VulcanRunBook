-- Improvement loop 1, two-client checks (audit cycle 7): Tavlius's and Mirel's
-- clients wired together (duo.lua).
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

Group("a split that leaves an empty part doesn't count partner gold twice")
do
  local A, B = duo()
  D.on(A, function(c) c.enter("Deadmines", 36) end)
  D.tick(A, B, 60)
  D.on(A, function(c) c.fire("BOSS_KILL", 644, "Rhahk'Zor") end)
  D.tick(A, B, 30)
  D.on(A, function(c) c.leave() end)
  D.tick(A, B, 120)
  -- (reset nobody saw) both go in, step out briefly, come back
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.enter("Deadmines", 36) end) end
  D.tick(A, B, 40)
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.leave() end) end
  D.tick(A, B, 30)
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.enter("Deadmines", 36) end) end
  D.tick(A, B, 20)
  D.on(B, function(c) c.gainMoney(787) end)
  D.tick(A, B, 40)
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.fire("BOSS_KILL", 644, "Rhahk'Zor") end) end
  D.tick(A, B, 120)
  D.use(A)
  local s = 0
  for _, r in ipairs(_G.VulcanRunBookDB.history) do s = s + ((r.partners.Mirel or {}).coin or 0) end
  s = s + ((A.ns.run.partners.Mirel or {}).coin or 0)
  check("Mirel's gold counted once", s == 787, s)
end

Group("kills your partner's split moves over are numbered in order")
do
  local A, B = duo()
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.enter("Deadmines", 36) end) end
  D.tick(A, B, 60)
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.fire("BOSS_KILL", 644, "Rhahk'Zor") end) end
  D.tick(A, B, 30)
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.leave() end) end
  D.tick(A, B, 60)
  D.on(B, function(c) c.enter("Deadmines", 36) end)
  D.tick(A, B, 60)
  D.on(B, function() _G.VulcanRunBook_MarkBoss() end)
  D.tick(A, B, 60)
  D.on(B, function() _G.VulcanRunBook_MarkBoss() end)
  D.tick(A, B, 60)
  D.on(A, function(c) c.enter("Deadmines", 36) end)
  D.tick(A, B, 60)
  D.on(A, function() _G.VulcanRunBook_MarkBoss() end)
  D.tick(A, B, 30)
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.fire("BOSS_KILL", 644, "Rhahk'Zor") end) end
  D.tick(A, B, 30)
  D.use(A)
  check("Tavlius's run", names(A.ns.run) == "Boss 1,Boss 2,Boss 3,Rhahk'Zor", names(A.ns.run))
  D.use(B)
  check("Mirel's run", names(B.ns.run) == "Boss 1,Boss 2,Boss 3,Rhahk'Zor", names(B.ns.run))
end

io.write(string.format("tests_il1_duo.lua: %d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
