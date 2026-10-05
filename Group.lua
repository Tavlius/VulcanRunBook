-- RunBook: the group view. Everyone in your group or raid, with the same
-- numbers your log keeps: gold, XP and rates from each player who runs Run
-- Log (their client sends them), and deaths and drops from your own log.
-- It's for showing only: nothing here changes your run's numbers or the
-- duo's "Together" line.
local _, ns = ...

local GREY, GOLD = "|cff9d9d9d", "|cffffd100"

local function Count(list, name)
  local n = 0
  for _, x in ipairs(type(list) == "table" and list or {}) do
    if type(x) == "table" and ns.SameName(x.who, name) then n = n + 1 end
  end
  return n
end

-- One row per player: { name, label, you, partner, log, gold, xp, elapsed,
-- deaths, drops }. log: their numbers are known (they run RunBook, or it's
-- you). Rows with numbers come first, the most gold first.
function ns.GroupRows(run)
  local rows, seen = {}, {}
  if type(run) ~= "table" or run.lite then return rows end
  -- (Two players with one name - your partner from another realm and someone
  -- from yours - are two rows. A name from the member list is only added when
  -- nobody by that name is listed.)
  local function add(key, row, member)
    local short = ns.ShortName(key) or key
    if member and seen[short] then return end
    seen[short] = true
    row.name = key
    row.label = row.label or key
    row.deaths = Count(run.deaths, short)
    row.drops = Count(run.drops, short)
    rows[#rows + 1] = row
  end
  local me = (run.char and ns.ShortName(run.char)) or ns.PlayerName() or "You"
  seen[me] = nil
  add(me, { label = me .. " (you)", you = true, log = true, gold = ns.ShownMoney(ns.RunGold(run)),
    copper = ns.RunGold(run), xp = run.xp or 0, elapsed = run.elapsed or 0 })
  for _, field in ipairs({ "partners", "group" }) do
    local list = type(run[field]) == "table" and run[field] or {}
    local names = {}
    for key, p in pairs(list) do
      if type(key) == "string" and type(p) == "table" then names[#names + 1] = key end
    end
    table.sort(names)
    for _, key in ipairs(names) do
      local p = list[key]
      add(key, { label = key .. (field == "partners" and " (partner)" or ""), partner = field == "partners",
        log = true, gold = ns.ShownMoney(ns.PartnerGold(p)), copper = ns.PartnerGold(p), xp = p.xp or 0,
        elapsed = p.elapsed or 0 })
    end
  end
  for _, m in ipairs(type(run.members) == "table" and run.members or {}) do
    if type(m) == "string" then add(m, { log = false, gold = 0, xp = 0, elapsed = 0 }, true) end
  end
  table.sort(rows, function(a, b)
    if a.log ~= b.log then return a.log end
    if a.gold ~= b.gold then return a.gold > b.gold end
    if a.xp ~= b.xp then return a.xp > b.xp end
    return a.name < b.name
  end)
  return rows
end

-- Gold and XP over the players whose numbers are known, and how many.
-- exact: gold to the copper (the CSV); otherwise as shown (to the silver).
function ns.GroupTotals(run, exact)
  local gold, xp, n = 0, 0, 0
  for _, r in ipairs(ns.GroupRows(run)) do
    if r.log then gold, xp, n = gold + (exact and r.copper or r.gold), xp + r.xp, n + 1 end
  end
  return gold, xp, n
end

-- Others in the group view (not you, not your partner)?
function ns.HasGroupStats(run)
  return type(run) == "table" and type(run.group) == "table" and next(run.group) ~= nil
end

local function RateText(gold, xp, elapsed)
  local out = {}
  local g = ns.PerHour(gold, elapsed)
  if g and gold > 0 then out[#out + 1] = ns.Money(ns.ShownMoney(g)) .. "/hr" end
  local x = ns.PerHour(xp, elapsed)
  if x and xp > 0 then out[#out + 1] = ns.Short(x) .. " XP/hr" end
  return #out > 0 and (GREY .. "  (" .. table.concat(out, ", ") .. ")|r") or ""
end

-- The group view as lines (the Group tab, and a run's details).
function ns.GroupLines(run)
  local lines = {}
  if type(run) ~= "table" then return lines end
  if run.lite then
    lines[1] = GREY .. "This run is in short form (past your newest 200): no group numbers kept.|r"
    return lines
  end
  local rows = ns.GroupRows(run)
  local gold, xp, n = ns.GroupTotals(run)
  lines[#lines + 1] = string.format("%s · %d with RunBook", ns.Plural(#rows, "player"), n)
  if n > 1 then
    lines[#lines + 1] = "All of you: " .. ns.ShownMoneyText(gold, true) .. (xp > 0 and ("  ·  " .. ns.Commas(xp)
      .. " XP") or "") .. RateText(gold, xp, run.elapsed)
  end
  for _, r in ipairs(rows) do
    local parts = {}
    if r.log then
      parts[#parts + 1] = (r.gold > 0 or r.xp > 0) and (ns.ShownMoneyText(r.gold, true)
        .. (r.xp > 0 and ("  ·  " .. ns.Commas(r.xp) .. " XP") or "") .. RateText(r.gold, r.xp, r.elapsed))
        or (GREY .. "nothing yet|r")
    else
      parts[#parts + 1] = GREY .. "no RunBook|r"
    end
    local extra = {}
    if r.deaths > 0 then extra[#extra + 1] = ns.Plural(r.deaths, "death") end
    if r.drops > 0 then extra[#extra + 1] = ns.Plural(r.drops, "drop") end
    lines[#lines + 1] = "  " .. ns.Ellipsis(r.label, 34) .. ": " .. table.concat(parts, "")
      .. (#extra > 0 and (GREY .. "  ·  " .. table.concat(extra, ", ") .. "|r") or "")
  end
  if n <= 1 and #rows > 1 then
    lines[#lines + 1] = GREY .. "Gold and XP show for players who run RunBook too (sync on).|r"
  end
  return lines
end

-- The Group tab: your run in progress, else your last run.
function ns.GroupTabLines()
  local run = ns.run or ns.LastOwnRun()
  if not run then return { GREY .. "No runs yet: the group view fills in during a run.|r" }, "Group" end
  local lines = { GOLD .. ns.Ellipsis(run.label or run.name or "?", 40) .. "|r  " .. ns.Clock(run.elapsed)
    .. GREY .. (run == ns.run and "  (in progress)" or "  (your last run)") .. "|r" }
  for _, l in ipairs(ns.GroupLines(run)) do lines[#lines + 1] = l end
  return lines, "Group"
end
