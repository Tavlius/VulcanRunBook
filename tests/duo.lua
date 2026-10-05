-- Two clients with swapped globals and real message relay.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local D = {}
local G = {}       -- [name] = globals snapshot
local cur
local function snap() local t = {} for k, v in pairs(_G) do t[k] = v end return t end
local function restore(t)
  for k in pairs(_G) do if t[k] == nil then _G[k] = nil end end
  for k, v in pairs(t) do _G[k] = v end
end
D.clients = {}
function D.use(c)
  if cur == c then return c end
  if cur then G[cur] = snap() end
  restore(G[c])
  cur = c
  return c
end
function D.boot(name, opts)
  if cur then G[cur] = snap() end
  opts = opts or {}
  opts.name = name
  local c = H.boot(opts)
  if opts.prelogin then opts.prelogin(c) end
  c.login()
  G[c] = snap()
  cur = c
  D.clients[#D.clients + 1] = c
  D.byName = D.byName or {}
  D.byName[name] = c
  c.sentIdx = 0
  return c
end
-- Messages take D.delay seconds (DELAY in the environment; 0 = at once),
-- in order, counted in D.tick seconds. (Experimental: each client's clock
-- jumps on its own loading screens, so the two drift apart and results that
-- hang on timing between them can't be trusted with a delay.)
D.delay = tonumber(os.getenv("DELAY") or "0") or 0
D.clock = 0
local held = {}  -- { from, to, msg, due }
-- deliver pending addon messages between the two
function D.relay(a, b)
  if D.delay > 0 then
    for _, pair in ipairs({ { a, b }, { b, a } }) do
      local from, to = pair[1], pair[2]
      D.use(from)
      for i = from.sentIdx + 1, #from.addonSent do
        held[#held + 1] = { from = from, to = to.name, msg = from.addonSent[i].msg, due = D.clock + D.delay }
      end
      from.sentIdx = #from.addonSent
    end
    local i = 1
    while held[i] and held[i].due <= D.clock do
      local m = held[i]
      if D.loadingName == m.to then i = i + 1 else
      table.remove(held, i)
      local to = D.byName[m.to]
      D.use(to)
      to.addonMsg(m.from.name .. "-Realm", m.msg)
      if D.trace then D.trace(m.from, to, m.msg) end
      end
    end
    return
  end
  for round = 1, 5 do
    local any = false
    for _, pair in ipairs({ { a, b }, { b, a } }) do
      local from, to = pair[1], pair[2]
      D.use(from)
      local msgs = {}
      for i = from.sentIdx + 1, #from.addonSent do msgs[#msgs + 1] = from.addonSent[i].msg end
      from.sentIdx = #from.addonSent
      if #msgs > 0 then
        any = true
        D.use(to)
        for _, m in ipairs(msgs) do
          to.addonMsg(from.name .. "-Realm", m)
          if D.trace then D.trace(from, to, m) end
        end
      end
    end
    if not any then break end
  end
end
-- tick both, n seconds, relaying each second
function D.tick(a, b, n, step)
  for _ = 1, n or 1 do
    D.clock = D.clock + 1
    D.use(a) a.tick(1, step)
    D.use(b) b.tick(1, step)
    D.relay(a, b)
  end
end
-- c is on a loading screen for n seconds: the other ticks, messages flow (none to c).
function D.loading(c, other, n)
  D.loadingName = c.name
  for _ = 1, n do
    D.clock = D.clock + 1
    D.use(other) other.tick(1)
    D.relay(c, other)
  end
  D.loadingName = nil
end
function D.on(c, fn) D.use(c) return fn(c) end
return D
