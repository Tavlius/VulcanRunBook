-- Duo fuzzer: per-gain expectation for partner coin. A gain by X counts in Y's
-- log iff Y had a run (ns.run) at the gain time.
package.path = "./?.lua;" .. package.path
dofile("duo_common.lua")
local SEED, STEPS = tonumber(arg[1]) or 1, tonumber(arg[2]) or 200
local CMDS = os.getenv("CMDS") or "end new"
math.randomseed(SEED)
local R = math.random
local A, B = duo()
local inside = { [A] = false, [B] = false }
local expP = { Tavlius = 0, Mirel = 0 } -- expected partner coin seen by name
local own = { Tavlius = 0, Mirel = 0 }
local world = { killed = 0 }
local BOSS = { { 1, "Rhahk'Zor" }, { 2, "Sneed" }, { 3, "Gilnid" }, { 4, "Van Cleef" } }
local log = {}
local function other(c) return c == A and B or A end
-- Gains that went into a run of the other's they haven't gone into yet (made
-- for a new copy while they were outside): not kept if they never go in.
local unentered = {}  -- { name =, start =, coin = }
local function settle()
  for i = #unentered, 1, -1 do
    local u = unentered[i]
    local c = u.name == "Tavlius" and A or B
    D.use(c)
    local cur = c.ns.run and c.ns.run.serverStart == u.start and c.ns.run
    local saved = false
    for _, r in ipairs(_G.VulcanRunBookDB.history) do if r.serverStart == u.start then saved = true end end
    if (cur and not cur.entryOnEntry) or saved then table.remove(unentered, i)
    elseif not cur then expP[u.name] = expP[u.name] - u.coin table.remove(unentered, i) end
  end
end
local function allRuns(c)
  D.use(c)
  local out = {}
  if c.ns.run then out[#out + 1] = c.ns.run end
  for _, r in ipairs(_G.VulcanRunBookDB.history) do out[#out + 1] = r end
  return out
end
local function coinSum(c) local n = 0 for _, r in ipairs(allRuns(c)) do n = n + r.coin end return n end
local function partnerSum(c) local n = 0 for _, r in ipairs(allRuns(c)) do for _, p in pairs(r.partners) do n = n + (p.coin or 0) end end return n end
local function fail(msg)
  P("SEED " .. SEED .. " FAIL: " .. msg)
  P("  ops: " .. table.concat(log, " ; ", math.max(1, #log - (tonumber(os.getenv("N")) or 25))))
  dump(A) dump(B)
  os.exit(1)
end
local function enter(c)
  if inside[c] then return "noop" end
  D.use(c) c.enter("Deadmines", 36) inside[c] = true
  D.use(other(c)) other(c).tick(15) D.relay(A, B)
  D.tick(A, B, 6)
  return c.name .. " enters"
end
local function leave(c)
  if not inside[c] then return "noop" end
  D.use(c) c.leave() inside[c] = false
  D.use(other(c)) other(c).tick(15) D.relay(A, B)
  return c.name .. " leaves"
end
local function gain(c)
  if not inside[c] then return "noop" end
  D.use(c)
  if not c.ns.InRun() then return "noop (no run)" end
  local o = other(c)
  D.use(o) local has = o.ns.run ~= nil
  if not has then D.tick(A, B, 6) D.use(o) has = o.ns.run ~= nil D.use(c) if not c.ns.InRun() then return "noop (no run)" end end
  D.use(o) local orun = o.ns.run D.use(c)
  if orun and math.abs(orun.serverStart - c.ns.run.serverStart) > 7000 then return "noop (2h gap)" end
  local n = R(1, 999)
  D.use(c) c.gainMoney(n)
  own[c.name] = own[c.name] + n
  if has then
    expP[o.name] = expP[o.name] + n
    D.use(o)
    local r = o.ns.run
    if r and r.entryOnEntry then
      local u
      for _, x in ipairs(unentered) do if x.name == o.name and x.start == r.serverStart then u = x end end
      if not u then u = { name = o.name, start = r.serverStart, coin = 0 } unentered[#unentered + 1] = u end
      u.coin = u.coin + n
    end
    D.use(c)
  end
  D.tick(A, B, 2)
  return c.name .. " +" .. n .. (has and "" or " (other no run)")
end
local function kill()
  if not (inside[A] or inside[B]) or world.killed >= #BOSS then return "noop" end
  world.killed = world.killed + 1
  local b = BOSS[world.killed]
  for _, c in ipairs({ A, B }) do
    if inside[c] then D.use(c) c.fire("ENCOUNTER_START", b[1], b[2], 1, 5) end
  end
  D.tick(A, B, 5)
  for _, c in ipairs({ A, B }) do
    if inside[c] then D.use(c) c.fire("BOSS_KILL", b[1], b[2]) c.fire("ENCOUNTER_END", b[1], b[2], 1, 5, 1) end
  end
  D.tick(A, B, 2)
  return "kill " .. b[2]
end
local function reload(c)
  D.use(c)
  local inst, dead, group, money = c.instance, c.dead, c.group, c.money
  local s = c.savedCopy()
  local n = D.boot(c.name, { saved = s, gap = 1, prelogin = function(x)
    x.instance = inst x.dead = dead x.group = group x.money = money end })
  n.sentIdx = #n.addonSent
  local o = other(c)
  if c == A then A = n else B = n end
  inside[n] = inside[c]
  D.use(o) o.tick(1) D.relay(A, B)
  D.tick(A, B, 2)
  return n.name .. " reloads"
end
local ops = {
  { 6, function() return enter(A) .. "/" .. enter(B) end },
  { 4, function() return leave(A) .. "/" .. leave(B) end },
  { 4, function() return enter(R() < 0.5 and A or B) end },
  { 4, function() return leave(R() < 0.5 and A or B) end },
  { 6, kill },
  { 8, function() local n = R(1, 120) D.tick(A, B, n) return "tick " .. n end },
  { 3, function() local n = R(1500, 2000) D.tick(A, B, math.floor(n/10), 10) return "longtick " .. n end },
  { 14, function() return gain(R() < 0.5 and A or B) end },
  { 2, function()
      if inside[A] or inside[B] then return "noop" end
      world.killed = 0
      local r = R()
      if r < 0.33 then D.use(A) A.system("Deadmines has been reset.") D.tick(A, B, 2) return "reset (Tavlius saw)" end
      if r < 0.66 then D.use(B) B.system("Deadmines has been reset.") D.tick(A, B, 2) return "reset (Mirel saw)" end
      return "reset unseen" end },
  { 2, function() return reload(R() < 0.5 and A or B) end },
  { 3, function()
      local c = R() < 0.5 and A or B
      local cmds = {} for w in CMDS:gmatch("%S+") do cmds[#cmds + 1] = w end
      local cmd = cmds[R(#cmds)]
      D.use(c) c.slash(cmd == "new" and "new yes" or cmd) D.tick(A, B, 2)
      return c.name .. " /runbook " .. cmd end },
  { 2, function()
      local c = R() < 0.5 and A or B
      if not inside[c] then return "noop" end
      D.use(c) c.die() D.tick(A, B, 3)
      D.use(c) c.leave() inside[c] = false D.use(other(c)) other(c).tick(15) D.relay(A, B)
      D.tick(A, B, R(20, 200))
      D.use(c) c.enter("Deadmines", 36) c.dead = false inside[c] = true D.use(other(c)) other(c).tick(15) D.relay(A, B)
      D.tick(A, B, 5)
      return c.name .. " dies, runs back" end },
}
local total = 0 for _, o in ipairs(ops) do total = total + o[1] end
local function pick() local x = R() * total for _, o in ipairs(ops) do x = x - o[1] if x <= 0 then return o end end return ops[#ops] end
for step = 1, STEPS do
  local d = pick()[2]()
  log[#log + 1] = step .. ":" .. d
  for _, c in ipairs({ A, B }) do D.use(c) local e = c.errors() if #e > 0 then fail("lua error " .. c.name .. ": " .. e[1]) end end
  settle()
  if coinSum(A) ~= own.Tavlius or coinSum(B) ~= own.Mirel then fail("own coin " .. coinSum(A) .. "/" .. own.Tavlius .. " " .. coinSum(B) .. "/" .. own.Mirel) end
  local pa, pb = partnerSum(A), partnerSum(B)
  if pa ~= expP.Tavlius or pb ~= expP.Mirel then
    fail(string.format("partner coin: Tavlius sees %d want %d; Mirel sees %d want %d", pa, expP.Tavlius, pb, expP.Mirel))
  end
end
P("seed " .. SEED .. " ok " .. own.Tavlius .. " " .. own.Mirel)
