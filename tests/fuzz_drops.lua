package.path = "./?.lua;" .. package.path
dofile("duo_common.lua")
local SEED, STEPS = tonumber(arg[1]) or 1, tonumber(arg[2]) or 200
math.randomseed(SEED)
local R = math.random
local A, B = duo()
local function setup(c) c.item(100, "Cruel Barb", 3, 5000) c.item(101, "Green Ring", 2, 300) c.item(102, "Epic Axe", 4, 20000) end
D.use(A) setup(A) D.use(B) setup(B)
local inside = { [A] = false, [B] = false }
local expDrops = { Tavlius = 0, Mirel = 0 }  -- drops by X expected in the other's log
local expNotes = { Tavlius = {}, Mirel = {} }
local noteN = 0
-- Items sent into a run of the other's that they haven't gone into yet (made
-- for a new copy while they were outside): if they never go in, that run isn't
-- kept, and those items go with it (it was never their run).
local unentered = {}  -- { run =, client =, who =, drops =, notes = {} }
local function holding(o, who)
  D.use(o)
  local r = o.ns.run
  if not (r and r.entryOnEntry) then return nil end
  for _, u in ipairs(unentered) do if u.start == r.serverStart and u.who == who then return u end end
  local u = { start = r.serverStart, client = o, who = who, drops = 0, notes = {} }
  unentered[#unentered + 1] = u
  return u
end
local function settle()
  for i = #unentered, 1, -1 do
    local u = unentered[i]
    local c = (u.client.name == "Tavlius") and A or B
    D.use(c)
    -- (By its start: a reload makes new tables.)
    local found
    if c.ns.run and c.ns.run.serverStart == u.start then found = c.ns.run end
    for _, r in ipairs(_G.VulcanRunBookDB.history) do if r.serverStart == u.start then found = r end end
    if found and found.entryOnEntry == nil and found == c.ns.run then table.remove(unentered, i)  -- went in
    elseif found and found ~= c.ns.run then table.remove(unentered, i)                          -- kept
    elseif not found then                                                                         -- dropped
      expDrops[u.who] = expDrops[u.who] - u.drops
      for _, t in ipairs(u.notes) do
        for j = #expNotes[u.who], 1, -1 do if expNotes[u.who][j] == t then table.remove(expNotes[u.who], j) end end
      end
      table.remove(unentered, i)
    end
  end
end
local log = {}
local function other(c) return c == A and B or A end
local function allRuns(c)
  D.use(c)
  local out = {}
  if c.ns.run then out[#out + 1] = c.ns.run end
  for _, r in ipairs(_G.VulcanRunBookDB.history) do out[#out + 1] = r end
  return out
end
local function fail(msg)
  P("SEED " .. SEED .. " FAIL: " .. msg)
  P("  ops: " .. table.concat(log, " ; ", math.max(1, #log - 25)))
  dump(A) dump(B)
  os.exit(1)
end
local function dropCount(c, who)
  local n = 0
  for _, r in ipairs(allRuns(c)) do for _, d in ipairs(r.drops) do if d.who == who then n = n + 1 end end end
  return n
end
local function noteCount(c, text)
  local n = 0
  for _, r in ipairs(allRuns(c)) do for _, x in ipairs(r.notes) do if x.text == text then n = n + 1 end end end
  return n
end
local function enter(c)
  if inside[c] then return "noop" end
  D.use(c) c.enter("Deadmines", 36) inside[c] = true
  D.use(other(c)) other(c).tick(15) D.relay(A, B)
  D.tick(A, B, 31)
  return c.name .. " enters"
end
local function leave(c)
  if not inside[c] then return "noop" end
  D.use(c) c.leave() inside[c] = false
  D.use(other(c)) other(c).tick(15) D.relay(A, B)
  return c.name .. " leaves"
end
local BOSS = { { 1, "Rhahk'Zor" }, { 2, "Sneed" }, { 3, "Gilnid" }, { 4, "Van Cleef" } }
local world = { killed = 0 }
local function kill()
  if not (inside[A] or inside[B]) or world.killed >= #BOSS then return "noop" end
  world.killed = world.killed + 1
  local b = BOSS[world.killed]
  for _, c in ipairs({ A, B }) do if inside[c] then D.use(c) c.fire("ENCOUNTER_START", b[1], b[2], 1, 5) end end
  D.tick(A, B, 5)
  for _, c in ipairs({ A, B }) do if inside[c] then D.use(c) c.fire("BOSS_KILL", b[1], b[2]) c.fire("ENCOUNTER_END", b[1], b[2], 1, 5, 1) end end
  D.tick(A, B, 2)
  return "kill " .. b[2]
end
local function loot(c)
  if not inside[c] then return "noop" end
  local o = other(c)
  D.use(o) local oRun, oIn = o.ns.run, o.ns.InRun()
  D.use(c) local cIn = c.ns.InRun()
  if not oRun then return "noop (other no run)" end
  if not cIn then return "noop (looter no run)" end
  local id = ({ 100, 101, 102 })[R(3)]
  D.use(c) c.lootReal(id, 1)
  if inside[o] then D.use(o) o.lootMsg(c.name, id) end
  expDrops[c.name] = expDrops[c.name] + 1
  local u = holding(o, c.name)
  if u then u.drops = u.drops + 1 end
  D.tick(A, B, 2)
  return c.name .. " loots " .. id .. (cIn and "" or " (no run)") .. (oIn and "" or " (other outside/ended)")
end
local function note(c)
  D.use(c) if not c.ns.run then return "noop" end
  local o = other(c)
  D.use(o) local has = o.ns.run ~= nil
  noteN = noteN + 1
  local t = "n" .. noteN
  D.use(c) c.slash("note " .. t)
  if has then
    expNotes[c.name][#expNotes[c.name] + 1] = t
    local u = holding(o, c.name)
    if u then u.notes[#u.notes + 1] = t end
  end
  D.tick(A, B, 2)
  return c.name .. " note " .. t .. (has and "" or " (other no run)")
end
local function reload(c)
  D.use(c)
  local inst, dead, group, money, items, cached, bag = c.instance, c.dead, c.group, c.money, c.items, c.cached, c.bagSlots
  local s = c.savedCopy()
  local n = D.boot(c.name, { saved = s, gap = 1, prelogin = function(x)
    x.instance = inst x.dead = dead x.group = group x.money = money x.items = items x.cached = cached x.bagSlots = bag end })
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
  { 3, function() return leave(A) .. "/" .. leave(B) end },
  { 3, function() return enter(R() < 0.5 and A or B) end },
  { 3, function() return leave(R() < 0.5 and A or B) end },
  { 5, kill },
  { 8, function() local n = R(1, 120) D.tick(A, B, n) return "tick " .. n end },
  { 12, function() return loot(R() < 0.5 and A or B) end },
  { 5, function() return note(R() < 0.5 and A or B) end },
  { 2, function() if inside[A] or inside[B] then return "noop" end world.killed = 0
      if R() < 0.5 then D.use(A) A.system("Deadmines has been reset.") D.tick(A, B, 2) return "reset seen" end
      return "reset unseen" end },
  { 2, function() return reload(R() < 0.5 and A or B) end },
  { 3, function()
      local c = R() < 0.5 and A or B
      local cmds = {} for w in (os.getenv("CMDS") or "end start new"):gmatch("%S+") do cmds[#cmds + 1] = w end
      local cmd = cmds[R(#cmds)]
      D.use(c) c.slash(cmd == "new" and "new yes" or cmd) D.tick(A, B, 2)
      return c.name .. " /runbook " .. cmd end },
}
local total = 0 for _, o in ipairs(ops) do total = total + o[1] end
local function pick() local x = R() * total for _, o in ipairs(ops) do x = x - o[1] if x <= 0 then return o end end return ops[#ops] end
for step = 1, STEPS do
  local d = pick()[2]()
  log[#log + 1] = step .. ":" .. d
  for _, c in ipairs({ A, B }) do D.use(c) local e = c.errors() if #e > 0 then fail("lua error " .. c.name .. ": " .. e[1]) end end
  settle()
  local da, db = dropCount(A, "Mirel"), dropCount(B, "Tavlius")
  if da ~= expDrops.Mirel or db ~= expDrops.Tavlius then fail(string.format("drops: Tavlius has %d of Mirel's (want %d); Mirel has %d of Tavlius's (want %d)", da, expDrops.Mirel, db, expDrops.Tavlius)) end
  for who, list in pairs(expNotes) do
    local c = who == "Tavlius" and B or A
    for _, t in ipairs(list) do local n = noteCount(c, t) if n ~= 1 then fail(who .. "'s note " .. t .. " seen " .. n .. " times") end end
  end
end
P("seed " .. SEED .. " ok drops " .. expDrops.Tavlius .. "/" .. expDrops.Mirel)
