package.path = "./?.lua;" .. package.path
local here = ""
D = dofile(here .. "duo.lua")
function P(...) local t={} for i=1,select("#",...) do t[#t+1]=tostring(select(i,...)) end io.write(table.concat(t," "),"\n") end
local SEED, STEPS = tonumber(arg[1]) or 1, tonumber(arg[2]) or 200
math.randomseed(SEED)
local R = math.random
local A = D.boot("Tavlius") local B = D.boot("Mirel")
D.on(A, function(c) c.party("Mirel") c.slash("partner Mirel") end)
D.on(B, function(c) c.party("Tavlius") c.slash("partner Tavlius") end)
local inside = { [A] = false, [B] = false }
local log = {}
local function other(c) return c == A and B or A end
local function runs(c)
  D.use(c) local out = {}
  if c.ns.run then out[#out+1] = c.ns.run end
  for _, r in ipairs(_G.VulcanRunBookDB.history) do out[#out+1] = r end
  return out
end
local function span(c, r) D.use(c) return r.serverStart, r.serverEnd or c.ns.ServerTime() end
local expect = {}
local noteN = 0
local function fail(msg)
  P("SEED " .. SEED .. " FAIL: " .. msg)
  P("  ops: " .. table.concat(log, " ; ", math.max(1, #log - 30)))
  for _, c in ipairs({A,B}) do P("== "..c.name) for _, r in ipairs(runs(c)) do
    local ns = {} for _, n in ipairs(r.notes) do ns[#ns+1] = n.who..":"..n.text end
    P(string.format("  #%s start=%d end=%s el=%d ended=%s notes=[%s]", tostring(r.id), r.serverStart, tostring(r.serverEnd), r.elapsed, tostring(r.ended), table.concat(ns, ","))) end end
  os.exit(1)
end
local function enter(c) if inside[c] then return "noop" end D.use(c) c.enter("Deadmines", 36) inside[c] = true D.tick(A,B,R(1,40)) return c.name.." enters" end
local function leave(c) if not inside[c] then return "noop" end D.use(c) c.leave() inside[c] = false D.tick(A,B,2) return c.name.." leaves" end
local function note(c)
  local list = runs(c)
  if #list == 0 then return "noop" end
  noteN = noteN + 1
  local t = "n" .. noteN
  local target, cmd
  D.use(c)
  if R() < 0.5 then
    target = c.ns.run or c.ns.LastOwnRun()
    cmd = "note " .. t
  else
    local h = _G.VulcanRunBookDB.history
    if #h == 0 then return "noop" end
    target = h[R(math.min(#h, 4))]
    cmd = "note #" .. target.id .. " " .. t
  end
  if not target then return "noop" end
  local s0, e0 = span(c, target)
  c.slash(cmd == "new" and "new yes" or cmd)
  -- partner runs that overlap the target in time
  local o = other(c)
  local ov = {}
  for _, r in ipairs(runs(o)) do
    local s1, e1 = span(o, r)
    if s1 <= e0 and s0 <= e1 + 5 and s1 - s0 <= 7200 then ov[r] = true end
  end
  -- (A note on the run you're in goes to theirs if they're in one there, at
  -- any time; only one on an earlier run is matched by time.)
  local old = target ~= c.ns.run
  -- (Into a run of theirs they haven't gone into yet: gone if they never do.)
  D.use(o)
  local into = o.ns.run and o.ns.run.entryOnEntry and o.ns.run.serverStart
  D.use(c)
  if next(ov) then expect[#expect+1] = { who = c.name, c = c, target = target, old = old, into = into, text = t, o = o, ov = ov, desc = string.format("target start %d-%d", s0, e0) } end
  D.tick(A, B, 2)
  return c.name .. " " .. cmd .. " (" .. string.format("%d-%d", s0, e0) .. ")"
end
local ops = {
  { 6, function() return enter(A) .. "/" .. enter(B) end },
  { 3, function() return leave(A) .. "/" .. leave(B) end },
  { 3, function() return enter(R() < 0.5 and A or B) end },
  { 3, function() return leave(R() < 0.5 and A or B) end },
  { 8, function() local n = R(1, 400) D.tick(A, B, n) return "tick " .. n end },
  { 6, function() return note(R() < 0.5 and A or B) end },
  { 2, function() if inside[A] or inside[B] then return "noop" end D.use(A) A.system("Deadmines has been reset.") D.tick(A, B, 2) return "reset" end },
  { 3, function() local c = R() < 0.5 and A or B local cmd = ({ "end", "start", "new" })[R(3)] D.use(c) c.slash(cmd == "new" and "new yes" or cmd) D.tick(A, B, 2) return c.name .. " /runbook " .. cmd end },
}
local total = 0 for _, o in ipairs(ops) do total = total + o[1] end
local function pick() local x = R() * total for _, o in ipairs(ops) do x = x - o[1] if x <= 0 then return o end end return ops[#ops] end
for step = 1, STEPS do
  local d = pick()[2]()
  log[#log+1] = step .. ":" .. d
  for _, c in ipairs({A,B}) do D.use(c) local e = c.errors() if #e > 0 then fail("lua error "..e[1]) end end
  for i = #expect, 1, -1 do
    local x = expect[i]
    if x.into then
      D.use(x.o)
      local cur = x.o.ns.run and x.o.ns.run.serverStart == x.into and x.o.ns.run
      local saved = false
      for _, r in ipairs(_G.VulcanRunBookDB.history) do if r.serverStart == x.into then saved = true end end
      if (cur and not cur.entryOnEntry) or saved then x.into = nil
      elseif not cur then table.remove(expect, i) end
    end
  end
  for _, x in ipairs(expect) do
    local n, onOv = 0, false
    for _, r in ipairs(runs(x.o)) do for _, nt in ipairs(r.notes) do if nt.text == x.text and nt.who == x.who then n = n + 1 if x.ov[r] then onOv = true end end end end
    if n ~= 1 then fail(x.who .. "'s note " .. x.text .. " seen " .. n .. " times in partner log (" .. x.desc .. ")") end
    if not onOv and x.old then
      -- (A run of theirs that began since - their copy of your run - counts too.)
      -- (The two harness clocks drift apart on loading screens: compare on one,
      -- with a minute of slack for drift since the runs were made.)
      local s0, e0 = span(x.c, x.target)
      D.use(x.c) local skew = x.c.ns.ServerTime()
      D.use(x.o) skew = skew - x.o.ns.ServerTime()
      for _, r in ipairs(runs(x.o)) do
        local s1, e1 = span(x.o, r)
        s1, e1 = s1 + skew, e1 + skew
        -- (Or the run of theirs your numbers for that run reached, live.)
        local e = r.partners and r.partners[x.who]
        local reached = type(e) == "table" and type(e.parts) == "table" and e.parts[tostring(x.target.serverStart)]
        for _, nt in ipairs(r.notes) do
          if nt.text == x.text and nt.who == x.who and (reached or (s1 <= e0 + 60 and s0 <= e1 + 60)) then
            onOv = true
          end
        end
      end
    end
    if not onOv and x.old then fail(x.who .. "'s note " .. x.text .. " on a run that doesn't overlap (" .. x.desc .. ")") end
  end
end
P("seed " .. SEED .. " ok notes " .. #expect)
