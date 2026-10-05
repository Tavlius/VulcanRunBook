-- Improvement loop 2, two-client checks: Tavlius's and Mirel's clients wired
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
local function runsOf(c)
  D.use(c)
  local runs = { c.ns.run }
  for _, r in ipairs(_G.VulcanRunBookDB.history) do runs[#runs + 1] = r end
  return runs
end

Group("a kill held up while your partner started over stays out of his new run")
do
  local A, B = duo()
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.enter("Deadmines", 36) end) end
  D.tick(A, B, 200)
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.fire("ENCOUNTER_START", 3, "Gilnid", 1, 5) end) end
  D.tick(A, B, 30)
  for _, c in ipairs({ A, B }) do
    D.on(c, function(x) x.fire("BOSS_KILL", 3, "Gilnid") x.fire("ENCOUNTER_END", 3, "Gilnid", 1, 5, 1) end)
  end
  D.on(A, function(c) c.tick(1) end)
  D.on(B, function(c) c.tick(2) c.slash("new yes") end)  -- (before Tavlius's kill message arrives)
  D.relay(A, B)
  D.tick(A, B, 30)
  D.use(B)
  check("Mirel's new run has no Gilnid", #B.ns.run.bosses == 0, names(B.ns.run))
  check("his old run has it once", names(_G.VulcanRunBookDB.history[1]) == "Gilnid", names(_G.VulcanRunBookDB.history[1]))
end

Group("a drop held up while your partner started over goes to his old run")
do
  local A, B = duo()
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.item(5000, "Cruel Barb", 3, 5000) x.enter("Deadmines", 36) end) end
  D.tick(A, B, 200)
  D.on(A, function(c) c.lootMsg(nil, 5000, 1) c.tick(1) end)
  D.on(B, function(c) c.tick(2) c.slash("new yes") end)
  D.relay(A, B)
  D.tick(A, B, 30)
  local runs = runsOf(B)
  check("not in his new run", #runs[1].drops == 0, #runs[1].drops)
  check("in his old run", runs[2] and #runs[2].drops == 1 and runs[2].drops[1].who == "Tavlius")
end

Group("unnamed kills moved by a reset your partner found are numbered in order")
do
  local A, B = duo()
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.enter("Deadmines", 36) end) end
  D.tick(A, B, 60)
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.fire("BOSS_KILL", 644, "Rhahk'Zor") end) end
  D.tick(A, B, 60)
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.fire("BOSS_KILL", 643, "Sneed") end) end
  D.tick(A, B, 60)
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.leave() end) end
  D.tick(A, B, 300)
  D.on(A, function(c) c.enter("Deadmines", 36) end)
  D.tick(A, B, 60)
  D.on(A, function(c) c.fire("BOSS_KILL", c.SECRET, c.SECRET) end)
  D.tick(A, B, 60)
  D.on(A, function(c) c.fire("BOSS_KILL", 644, "Rhahk'Zor") end)
  D.tick(A, B, 30)
  D.use(A) local a = names(A.ns.run)
  D.use(B) local b = B.ns.run and names(B.ns.run) or "-"
  check("Mirel's new run", b == "Boss 1,Rhahk'Zor", b)
  check("both logs agree", a == b, a .. " / " .. b)
end

Group("/runbook check shows whether the two logs agree on kills")
do
  local A, B = duo()
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.enter("Deadmines", 36) end) end
  D.tick(A, B, 60)
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.fire("BOSS_KILL", 644, "Rhahk'Zor") end) end
  D.tick(A, B, 30)
  D.on(A, function(c) c.clearPrinted() c.slash("check") end)
  check("agree", A.printedMatch("Kills this run: yours 1, Mirel's log 1$") ~= nil)
  D.on(B, function(c) c.slash("unboss") end)  -- (one log differs)
  D.tick(A, B, 5)
  D.on(A, function(c) c.clearPrinted() c.slash("check") end)
  check("differ", A.printedMatch("Kills this run: yours 1, Mirel's log 0", true) ~= nil)
end

Group("his kill arriving after his split message still lands in your new run")
do
  local A, B = duo()
  local DMB = { "Rhahk'Zor", "Sneed", "Gilnid", "Van Cleef" }
  local function kill(cs, i)
    for _, c in ipairs(cs) do D.on(c, function() c.fire("ENCOUNTER_START", i, DMB[i], 1, 5) end) end
    D.tick(A, B, 20)
    for _, c in ipairs(cs) do D.on(c, function() c.fire("ENCOUNTER_END", i, DMB[i], 1, 5, 1) end) end
    D.tick(A, B, 2)
  end
  local function zone(c, o, fn) D.use(o) o.tick(15) D.use(c) fn(c) end
  zone(A, B, function(c) c.enter("Deadmines", 36) end) zone(B, A, function(c) c.enter("Deadmines", 36) end)
  D.relay(A, B) D.tick(A, B, 330)
  kill({ A, B }, 4)
  zone(A, B, function(c) c.leave() end) zone(B, A, function(c) c.leave() end) D.relay(A, B)
  D.tick(A, B, 120)
  zone(B, A, function(c) c.enter("Deadmines", 36) end) D.relay(A, B) D.tick(A, B, 30)
  for i = 1, 3 do D.tick(A, B, 120) kill({ B }, i) end
  D.tick(A, B, 60)
  D.on(B, function(c) c.fire("ENCOUNTER_START", 4, DMB[4], 1, 5) end) D.tick(A, B, 20)
  D.on(B, function(c) c.fire("ENCOUNTER_END", 4, DMB[4], 1, 5, 1) c.tick(1) end)
  D.use(B) B.tick(14)
  D.use(A) A.enter("Deadmines", 36)
  D.relay(A, B) D.tick(A, B, 60)
  D.use(A)
  check("all four in your new run", names(A.ns.run) == "Rhahk'Zor,Sneed,Gilnid,Van Cleef", names(A.ns.run))
  local vc = A.ns.run.bosses[4]
  check("before your clock started", vc and vc.untimed == true)
end

Group("a /reload just after an unnamed kill doesn't make it two")
do
  local A, B = duo()
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.enter("Deadmines", 36) end) end
  D.tick(A, B, 60)
  D.delay = 2
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.fire("BOSS_KILL", x.SECRET, x.SECRET) end) end
  D.tick(A, B, 1)
  -- Tavlius reloads before Mirel's message arrives
  D.use(A)
  local inst, grp = A.instance, A.group
  local saved = A.savedCopy()
  local A2 = D.boot("Tavlius", { saved = saved, gap = 1, prelogin = function(x) x.instance = inst x.group = grp end })
  A2.sentIdx = 0
  D.tick(A2, B, 10)
  D.delay = 0
  D.use(A2)
  check("one kill after the reload", #A2.ns.run.bosses == 1, names(A2.ns.run))
  D.use(B)
  check("one kill on his side", #B.ns.run.bosses == 1, names(B.ns.run))
  -- a kill matched before another /reload stays matched: his next one is a new kill
  D.use(A2)
  local saved2 = A2.savedCopy()
  local A3 = D.boot("Tavlius", { saved = saved2, gap = 1, prelogin = function(x) x.instance = inst x.group = grp end })
  A3.sentIdx = 0
  D.on(B, function(x) x.fire("BOSS_KILL", x.SECRET, x.SECRET) end)  -- (only he sees it)
  D.tick(A3, B, 5)
  D.use(A3)
  check("his second kill is a second kill", #A3.ns.run.bosses == 2, names(A3.ns.run))
end

Group("his kill and drop in the wing you just left stay with that wing's run")
do
  local A, B = duo()
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.item(700, "Whitemane's Chapeau", 3, 5000) end) end
  local function both(fn) D.on(A, fn) D.on(B, fn) end
  both(function(c) c.enter("Scarlet Monastery", 189, { uiMap = 305 }) end)
  D.tick(A, B, 310)
  both(function(c) c.fire("ENCOUNTER_START", 51, "Scarlet Commander Mograine", 1, 5) end)
  D.tick(A, B, 30)
  both(function(c) c.fire("ENCOUNTER_END", 51, "Scarlet Commander Mograine", 1, 5, 1) end)
  D.tick(A, B, 60)
  D.on(A, function(c) c.leave() end)
  D.tick(A, B, 60)
  D.on(B, function(c) c.fire("ENCOUNTER_START", 52, "High Inquisitor Whitemane", 1, 5) end)
  D.tick(A, B, 20)
  D.on(A, function(c) c.enter("Scarlet Monastery", 189, { uiMap = 303 }) end)
  D.tick(A, B, 1)
  D.on(B, function(c)
    c.fire("ENCOUNTER_END", 52, "High Inquisitor Whitemane", 1, 5, 1) c.lootMsg(nil, 700, 1) c.slash("note she's down")
  end)
  D.tick(A, B, 30)
  D.use(A)
  local cath = _G.VulcanRunBookDB.history[1]
  check("the Cathedral run keeps his kill", cath and names(cath) == "Scarlet Commander Mograine,High Inquisitor Whitemane",
    cath and names(cath))
  check("and his drop and note", cath and #cath.drops == 1 and #cath.notes == 1)
  check("the Library run has none of them", #A.ns.run.bosses == 0 and #A.ns.run.drops == 0 and #A.ns.run.notes == 0,
    names(A.ns.run))
end

io.write(string.format("tests_il2_duo.lua: %d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
