-- Cap accounting fuzzer: model the real instance copies and compare entries.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local SEED, STEPS = tonumber(arg[1]) or 1, tonumber(arg[2]) or 300
math.randomseed(SEED)
local R = math.random
local c = H.boot() c.login()
c.mapGroups = { [302] = 50, [303] = 50, [304] = 50, [305] = 50 }
c.groupFloors = { [50] = { { mapID = 302, name = "Graveyard" }, { mapID = 303, name = "Library" },
  { mapID = 304, name = "Armory" }, { mapID = 305, name = "Cathedral" } } }
c.ns.CAP_WINDOW = 1e9  -- never prune: count all entries
c.ns.CAP_DAY = 1e9
local D = { { "Deadmines", 36 }, { "Wailing Caverns", 43 }, { "Scarlet Monastery", 189 } }
local copies = {}   -- [key] = { left = wall or nil }
local trueEntries = 0
local here       -- key we're inside
local log = {}
local function key(name, ui) return name .. (ui and (":" .. ui) or "") end
local function enter()
  local d = D[R(#D)]
  local ui = d[2] == 189 and (301 + R(4)) or nil
  local k = key(d[1], ui)
  if here then -- leave first
    c.leave()
    copies[here].left = c.wall
    here = nil
  end
  local cp = copies[k]
  if not cp or (cp.left and c.wall + 15 - cp.left > 1800) then
    copies[k] = { }
    trueEntries = trueEntries + 1
  else
    cp.left = nil
  end
  c.enter(d[1], d[2], { uiMap = ui }) c.tick(6)
  here = k
  return "enter " .. k
end
local ops = {
  { 5, enter },
  { 4, function() if here then c.leave() copies[here].left = c.wall here = nil end return "leave" end },
  { 8, function() local n = R(1, 200) c.tick(n) return "tick " .. n end },
  { 2, function() c.tick(R(100, 250), 10) return "long wait" end },
  { 2, function()
      if here then return "reset noop (inside)" end
      local d = D[R(#D)]
      for k in pairs(copies) do if k:sub(1, #d[1]) == d[1] then copies[k] = nil end end
      c.system(d[1] .. " has been reset.")
      return "reset " .. d[1]
    end },
  { 2, function() c.slash("end") return "/runbook end" end },
  { 2, function() c.slash("start") return "/runbook start" end },
  { 1, function() BN = (BN or 0) + 1 c.slash("boss B" .. BN) return "boss" end },
  { 1, function() c.die() c.dead = false return "die" end },
  { 2, function()
      local gap = here and 1 or R(1, 5000)
      local inst, money = c.instance, c.money
      local saved = c.savedCopy()
      local n = H.boot({ saved = saved, gap = gap })
      n.mapGroups, n.groupFloors = c.mapGroups, c.groupFloors
      n.instance = inst
      n.ns.CAP_WINDOW = 1e9
      n.ns.CAP_DAY = 1e9
      n.login()
      c = n
      return "relog gap " .. gap
    end },
  { 1, function()
      if not here then return "new noop" end
      c.tick(125) c.slash("new yes") c.tick(6)
      copies[here] = {}
      trueEntries = trueEntries + 1
      return "/runbook new"
    end },
}
local total = 0 for _, o in ipairs(ops) do total = total + o[1] end
for step = 1, STEPS do
  local x, o = R() * total
  for _, op in ipairs(ops) do x = x - op[1] if x <= 0 then o = op break end end
  o = o or ops[#ops]
  log[#log + 1] = step .. ":" .. o[2]()
  if os.getenv("DUMP") and step >= tonumber(os.getenv("DUMP")) then
    local r = c.ns.run
    io.write(string.format("\n%s | run=%s wing=%s inside=%s counted=%s | copies:", log[#log], r and r.label or "-", r and tostring(r.wing) or "-", tostring(c.ns.inside), r and tostring(r.counted) or "-"))
    for _, cp in ipairs(_G.VulcanRunBookCharDB.copies or {}) do io.write(" [" .. cp.name .. " " .. tostring(cp.wing) .. " left " .. tostring(cp.left and (c.wall - cp.left)) .. "]") end
    io.write(" entries " .. #_G.VulcanRunBookDB.entries .. " true " .. trueEntries)
  end
  local got = #_G.VulcanRunBookDB.entries
  if got ~= trueEntries then
    io.write("\n", string.format("SEED %d step %d: entries %d, true %d", SEED, step, got, trueEntries))
    io.write("\n", "  " .. table.concat(log, " ; ", math.max(1, #log - 14)))
    os.exit(1)
  end
  if #c.errors() > 0 then print("ERR " .. c.errors()[1]) os.exit(1) end
end
io.write("\n", "seed " .. SEED .. " ok entries " .. trueEntries)
