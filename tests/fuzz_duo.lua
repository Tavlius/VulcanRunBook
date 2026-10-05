dofile("duo_common.lua")
local SEED, STEPS = tonumber(arg[1]) or 1, tonumber(arg[2]) or 200
local MODE = arg[3] or "events"   -- events | marks | anon
local NORESET = os.getenv("NORESET")
-- (Marks only, with a reset nobody saw: a partner's hand mark of a boss you
-- have is the same kill - a documented limit - so the count can't be predicted.)
local NOUNSEEN = os.getenv("NOUNSEEN") or (MODE == "marks" and not os.getenv("UNSEEN"))
local NOSPLITOPS = os.getenv("NOSPLITOPS")
math.randomseed(SEED)
local R = math.random
local A, B = duo()
if os.getenv("TRACE") then
  D.trace = function(from, to, m)
    if os.getenv("ONLY") and not m:find("^[" .. os.getenv("ONLY") .. "]") then return end
    if to ~= (os.getenv("TO") == "A" and A or B) then return end
    local t = {}
    if to.ns.run then t[#t+1] = "cur " .. to.ns.run.serverStart .. ":" .. pinfo(to.ns.run) end
    for i = 1, 2 do local r = _G.VulcanRunBookDB.history[i] if r then t[#t+1] = "#" .. r.id .. " " .. r.serverStart .. ":" .. pinfo(r) end end
    P("   >" .. to.name .. " got " .. m .. "  || " .. table.concat(t, " | "))
  end
end
local WK = {}
local expect = { [A] = 0, [B] = 0 }
local BOSS = { { 1, "Rhahk'Zor" }, { 2, "Sneed" }, { 3, "Gilnid" }, { 4, "Van Cleef" } }
local world = { killed = 0, copyId = 1 }  -- current copy's kills
local inside = { [A] = false, [B] = false }
local trueKills = 0
local earned = { [A] = 0, [B] = 0 }
local log = {}
local function L(s) log[#log + 1] = s end
local function fail(msg)
  P("SEED " .. SEED .. " " .. MODE .. " FAIL: " .. msg)
  P("  ops: " .. table.concat(log, " ; ", os.getenv("ALL") and 1 or math.max(1, #log - 30)))
  dump(A) dump(B)
  os.exit(1)
end
local function other(c) return c == A and B or A end
local function allRuns(c)
  D.use(c)
  local out = {}
  if c.ns.run then out[#out + 1] = c.ns.run end
  for _, r in ipairs(_G.VulcanRunBookDB.history) do out[#out + 1] = r end
  return out
end
local function bossCount(c) local n = 0 for _, r in ipairs(allRuns(c)) do n = n + #r.bosses end return n end
local function coinSum(c) local n = 0 for _, r in ipairs(allRuns(c)) do n = n + r.coin end return n end
local function partnerSum(c) local n = 0 for _, r in ipairs(allRuns(c)) do for _, p in pairs(r.partners) do n = n + (p.coin or 0) end end return n end

local unentered = {}
local function kill()
  if not (inside[A] or inside[B]) then return "kill noop" end
  if world.killed >= #BOSS then return "kill noop (all dead)" end
  D.tick(A, B, 25)
  if not (inside[A] or inside[B]) then return "kill noop" end
  world.killed = world.killed + 1
  trueKills = trueKills + 1
  -- A kill reaches a log if that client has a run and saw it, or a client
  -- that saw it has a run to send it from.
  local hasRun, inc = {}, nil
  for _, c in ipairs({ A, B }) do D.use(c) hasRun[c] = c.ns.run ~= nil end
  for _, c in ipairs({ A, B }) do
    local o = other(c)
    if hasRun[c] and (inside[c] or (inside[o] and hasRun[o])) then
      expect[c] = expect[c] + 1 inc = inc or {} inc[c] = true
    end
  end
  local b = BOSS[world.killed]
  local desc = "kill " .. b[2]
  do
    local rec = { name = b[2], T = {}, here = {} }
    for _, c in ipairs({ A, B }) do D.use(c) rec.T[c.name] = c.ns.ServerTime() rec.here[c.name] = inside[c] or c.dead end
    WK[#WK + 1] = rec
  end
  if MODE == "events" then
    for _, c in ipairs({ A, B }) do
      if inside[c] then D.use(c) c.fire("ENCOUNTER_START", b[1], b[2], 1, 5) end
    end
    D.tick(A, B, R(5, 20))
    for _, c in ipairs({ A, B }) do
      if inside[c] then D.use(c) c.fire("BOSS_KILL", b[1], b[2]) c.fire("ENCOUNTER_END", b[1], b[2], 1, 5, 1) end
    end
  elseif MODE == "anon" then
    for _, c in ipairs({ A, B }) do
      if inside[c] then D.use(c) c.fire("BOSS_KILL", c.SECRET, c.SECRET) end
    end
  else -- marks
    local who = {}
    for _, c in ipairs({ A, B }) do D.use(c) if inside[c] and c.ns.run then who[#who + 1] = c end end
    if #who == 0 then world.killed = world.killed - 1 trueKills = trueKills - 1
      for _, c in ipairs({ A, B }) do if inc and inc[c] then expect[c] = expect[c] - 1 end end
      return "kill noop (nobody can mark)" end
    local style = R(1, 5)
    local pressers
    if #who == 2 and R() < 0.4 then pressers = { who[1], who[2] } if R() < 0.5 then pressers = { who[2], who[1] } end
    else pressers = { who[R(#who)] } end
    for i, c in ipairs(pressers) do
      D.use(c)
      local named = (style == 1) or (style == 2 and i == 1) or (style == 3 and i == 2)
      if named then c.slash("boss " .. b[2]) desc = desc .. " " .. c.name .. "(named)"
      else _G.VulcanRunBook_MarkBoss() desc = desc .. " " .. c.name .. "(key)" end
      if i < #pressers then local w = R(0, 15) D.tick(A, B, w) desc = desc .. " +" .. w end
    end
  end
  D.tick(A, B, 2)
  return desc
end

local DUN = { "Deadmines", 36 }
local function enter(c)
  if inside[c] then return "enter noop" end
  D.loading(c, other(c), 15)
  D.use(c) c.enter(DUN[1], DUN[2]) inside[c] = true
  D.relay(A, B)
  D.tick(A, B, 31)
  return c.name .. " enters"
end
local function leave(c)
  if not inside[c] then return "leave noop" end
  D.loading(c, other(c), 15)
  D.use(c) c.leave() inside[c] = false
  D.relay(A, B)
  return c.name .. " leaves"
end

local ops = {
  { 6, function() local a = enter(A) local b = enter(B) return a .. "/" .. b end },
  { 4, function() local a = leave(A) local b = leave(B) return a .. "/" .. b end },
  { 2, function() return enter(R() < 0.5 and A or B) end },
  { 2, function() return leave(R() < 0.5 and A or B) end },
  { 10, kill },
  { 10, function() local n = R(1, 90) D.tick(A, B, n) return "tick " .. n end },
  { 6, function()
      local c = R() < 0.5 and A or B
      if not inside[c] or not inside[other(c)] then return "money noop" end
      D.use(A) local ra = A.ns.run D.use(B) local rb = B.ns.run
      if not ra or not rb then return "money noop (no run)" end
      local n = R(1, 999) D.use(c) c.gainMoney(n) earned[c] = earned[c] + n D.tick(A, B, 2) return c.name .. " +" .. n end },
  { NORESET and 0 or 2, function()
      if inside[A] or inside[B] then return "reset noop" end
      world.killed = 0 world.copyId = world.copyId + 1
      if NOUNSEEN or R() < 0.5 then D.use(A) A.system("Deadmines has been reset.") D.tick(A, B, 3) return "reset (Tavlius saw)" end
      return "reset unseen"
    end },
}
local function reload(c)
  D.use(c)
  local inst, dead, group, money = c.instance, c.dead, c.group, c.money
  local s = c.savedCopy()
  local wasInside = inside[c]
  do -- deliver what the old client flushed at logout
    local o = other(c)
    local msgs = {}
    for i = c.sentIdx + 1, #c.addonSent do msgs[#msgs + 1] = c.addonSent[i].msg end
    c.sentIdx = #c.addonSent
    D.use(o) for _, m in ipairs(msgs) do o.addonMsg(c.name .. "-Realm", m) end
    D.use(c)
  end
  local n = D.boot(c.name, { saved = s, gap = 1, prelogin = function(x)
    x.instance = inst x.dead = dead x.group = group x.money = money
  end })
  n.sentIdx = 0
  local o = other(c)
  if c == A then A = n else B = n end
  inside[n] = wasInside inside[c] = nil
  expect[n] = expect[c] expect[c] = nil
  earned[n] = earned[c]
  D.clock = D.clock + 1
  D.use(o) o.tick(1)
  D.relay(A, B)
  return n.name .. " reloads"
end
table.insert(ops, { tonumber(os.getenv("W_RELOAD") or 2), function() return reload(R() < 0.5 and A or B) end })
table.insert(ops, { tonumber(os.getenv("W_SLASH") or 2), function()
  local c = R() < 0.5 and A or B
  local cmds = {} for w in (os.getenv("CMDS") or "end start new"):gmatch("%S+") do cmds[#cmds + 1] = w end
  local cmd = cmds[R(#cmds)]
  D.use(c) c.slash(cmd == "new" and "new yes" or cmd) D.tick(A, B, 2)
  return c.name .. " /runbook " .. cmd
end })
table.insert(ops, { tonumber(os.getenv("W_DIE") or 2), function()
  local c = R() < 0.5 and A or B
  if not inside[c] then return "die noop" end
  D.use(c) c.die() D.tick(A, B, 5)
  -- release and run back as a ghost
  D.loading(c, other(c), 15) D.use(c) c.leave() inside[c] = false D.relay(A, B)
  D.tick(A, B, R(20, 200))
  D.loading(c, other(c), 15) D.use(c) c.enter(DUN[1], DUN[2]) c.dead = false inside[c] = true D.relay(A, B)
  D.tick(A, B, 31)
  return c.name .. " dies and runs back"
end })
local total = 0 for _, o in ipairs(ops) do total = total + o[1] end
local function pick() local x = R() * total for _, o in ipairs(ops) do x = x - o[1] if x <= 0 then return o end end return ops[#ops] end

for step = 1, STEPS do
  local d = pick()[2]()
  L(step .. ":" .. d)
  if os.getenv("TRACE") then P(step .. ":" .. d) end
  -- Kills in a run not gone into yet (made for a new copy while outside): gone
  -- with it if they never go in.
  for _, c in ipairs({ A, B }) do
    D.use(c)
    local r = c.ns.run
    if r and r.entryOnEntry then
      local key = c.name .. "@" .. r.serverStart
      unentered[key] = { name = c.name, start = r.serverStart, n = #r.bosses }
    end
  end
  if os.getenv("PRINTS") then for _, c in ipairs({ A, B }) do D.use(c) for i = (c.pi or 0) + 1, #c.printed do P("    [" .. c.name .. " print] " .. c.strip(c.printed[i])) end c.pi = #c.printed end end
  for _, c in ipairs({ A, B }) do D.use(c) local e = c.errors() if #e > 0 then fail("lua error " .. c.name .. ": " .. e[1]) end end
end
D.tick(A, B, 60)
for _, u in pairs(unentered) do
  local c = u.name == "Tavlius" and A or B
  D.use(c)
  local found = c.ns.run and c.ns.run.serverStart == u.start
  for _, r in ipairs(_G.VulcanRunBookDB.history) do if r.serverStart == u.start then found = true end end
  if not found then expect[c] = expect[c] - u.n end
end
for _, c in ipairs({ A, B }) do
  for _, r in ipairs(allRuns(c)) do
    for _, b in ipairs(r.bosses) do
      if not b.untimed and MODE == "events" then
        local best
        for _, k in ipairs(WK) do if k.name == b.name and k.T[c.name] <= (b.st or 0) + 1 then best = k end end
        if not best then fail("timed kill with no world kill: " .. c.name .. " " .. b.name)
        elseif not best.here[c.name] then fail("timed kill while absent: " .. c.name .. " " .. b.name .. " st " .. tostring(b.st) .. " t " .. b.t .. " run " .. r.serverStart .. " killT " .. best.T[c.name]) end
      end
      if not b.untimed and b.t > r.elapsed + 1 then fail("kill time past run time " .. c.name .. " " .. b.name .. " " .. b.t .. " > " .. r.elapsed) end
    end
  end
end
local ba, bb = bossCount(A), bossCount(B)
local msg = string.format("bosses true=%d expect %d/%d Tavlius=%d Mirel=%d; coin Tavlius=%d (Mirel sees %d) Mirel=%d (Tavlius sees %d)",
  trueKills, expect[A], expect[B], ba, bb, coinSum(A), partnerSum(B), coinSum(B), partnerSum(A))
if ba ~= expect[A] or bb ~= expect[B] then fail("boss count mismatch: " .. msg) end
if partnerSum(A) ~= coinSum(B) or partnerSum(B) ~= coinSum(A) then fail("partner sum mismatch: " .. msg) end
P("seed " .. SEED .. " " .. MODE .. " ok " .. msg)
