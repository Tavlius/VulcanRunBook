-- RunBook: the live window. Shows the run clock, boss splits against your best
-- run, deaths and wipes, coin and XP (yours, your partner's and together), the
-- latest drops, the latest note, and the instance cap. Drag to move;
-- right-click opens the history.
local _, ns = ...

local WIDTH = 290
local LINE_H = 14
local MAX_DROPS = 4
local LINE_CHARS = 47        -- what fits on one line of the live window
local MAX_BOSSES = 6         -- boss lines shown (the latest ones)
local GREY, GOLD, RED, YELLOW = "|cff9d9d9d", "|cffffd100", "|cffff5050", "|cffffff00"

---------------------------------------------------------------------------
-- Content (plain strings, so it can be tested without a client)
---------------------------------------------------------------------------
-- The daily limit, only once it's close (the hourly one is the one you hit).
function ns.DayCapLine()
  local day, dayWait = ns.DayStatus()
  local capDay = ns.DB.capDay or 0
  if capDay <= 0 or day < capDay - 5 then return nil end
  local color = day >= capDay and RED or YELLOW
  local text = string.format("%sInstances %d/%d today", color, day, capDay)
  if day >= capDay and dayWait then text = text .. " - next in " .. ns.Clock(dayWait) end
  return text .. "|r"
end

function ns.CapLine()
  local cap = ns.DB.cap or 0
  if cap <= 0 then return nil end
  local count, wait = ns.CapStatus()
  local color = count >= cap and RED or (count == cap - 1 and YELLOW or GREY)
  local text = string.format("%sInstances %d/%d this hour", color, count, cap)
  if count >= cap and wait then text = text .. " - next in " .. ns.Clock(wait) end
  return text .. "|r"
end

-- "You: 3g 20s · 4,200 XP", then (after 5 minutes) a grey rates line.
local Shown, ShownText = ns.ShownMoney, function(v) return ns.ShownMoneyText(v, true) end

local function AddStats(lines, label, gold, xp, elapsed)
  gold = Shown(gold)
  local parts = {}
  if gold > 0 then parts[#parts + 1] = ShownText(gold) end
  if xp > 0 then parts[#parts + 1] = ns.Short(xp) .. " XP" end
  lines[#lines + 1] = label .. (#parts > 0 and table.concat(parts, " · ") or (GREY .. "nothing yet|r"))
  local rates = {}
  local g = ns.PerHour(gold, elapsed)
  if g and gold > 0 then rates[#rates + 1] = ns.Money(Shown(g)) .. "/hr" end
  local x = ns.PerHour(xp, elapsed)
  if x and xp > 0 then rates[#rates + 1] = ns.Short(x) .. " XP/hr" end
  if #rates > 0 then lines[#lines + 1] = GREY .. "    " .. table.concat(rates, " · ") .. "|r" end
end

-- "1 wipe · 3 deaths (Mirel x2, Tavlius, +1)": names as many as fit. Wipes
-- come first so they can't be cut off.
local function DeathsLine(run)
  -- (A raid: you two's deaths only, as everywhere else.)
  local deaths = run.deaths
  if run.kind == "raid" then
    deaths = {}
    for _, d in ipairs(run.deaths) do if ns.IsDuo(d.who) then deaths[#deaths + 1] = d end end
  end
  local count, order = {}, {}
  for _, d in ipairs(deaths) do
    if not count[d.who] then
      count[d.who] = 0
      order[#order + 1] = d.who
    end
    count[d.who] = count[d.who] + 1
  end
  table.sort(order, function(a, b)
    local da, db = ns.IsDuo(a), ns.IsDuo(b)
    if da ~= db then return da end
    if count[a] ~= count[b] then return count[a] > count[b] end
    return a < b
  end)
  -- Names in a small group (only you two in a raid), as many as fit on the
  -- line with the rest as "+N".
  local head = (#run.wipes > 0 and (ns.Plural(#run.wipes, "wipe") .. " · ") or "")
    .. ns.Plural(#deaths, "death")
  local function Fit(noRest)
    -- Full names if they fit; otherwise shortened to 10 characters.
    local names, shown, missed
    local best
    for _, cut in ipairs({ 24, 10 }) do
      names, shown, missed = {}, 0, false
      for _, n in ipairs(order) do
        local label = ns.Ellipsis(n, cut)
        if count[n] > 1 then label = label .. " x" .. count[n] end
        local left = #deaths - shown - count[n]
        local trial = head .. " (" .. table.concat(names, ", ") .. (#names > 0 and ", " or "") .. label
          .. ((left > 0 and not noRest) and (", +" .. left) or "") .. ")"
        local wanted = run.kind ~= "raid" or ns.IsDuo(n)
        if wanted and ns.Len(trial) <= LINE_CHARS then
          names[#names + 1] = label
          shown = shown + count[n]
        elseif wanted then
          missed = true
        end
      end
      -- (Shortened names only if that names more of them.)
      if best and shown <= best[2] then names, shown, missed = best[1], best[2], best[3] end
      best = { names, shown, missed }
      if shown == #deaths then break end
    end
    return names, shown, missed
  end
  local names, shown, missed = Fit(false)
  local noRest = false
  if missed and run.kind == "raid" then
    -- (A raid: both your names matter more than "+N", which the total shows.)
    local n2, s2, m2 = Fit(true)
    if not m2 then names, shown, noRest = n2, s2, true end
  end
  if shown > 0 and shown < #deaths and not noRest then names[#names + 1] = "+" .. (#deaths - shown) end
  local text = #run.wipes > 0 and ("|cffff5050" .. ns.Plural(#run.wipes, "wipe") .. "|r") or ""
  if #deaths > 0 then
    if text ~= "" then text = text .. " · " end
    text = text .. ns.Plural(#deaths, "death")
      .. (#names > 0 and (GREY .. " (" .. table.concat(names, ", ") .. ")|r") or "")
  end
  return text
end

function ns.LiveLines()
  local lines = {}
  local run = ns.run
  if not run then
    local char = VulcanRunBookCharDB
    local held = char and type(char.suppress) == "table"
    -- (Reopen only if the ended run is still there: it may have been deleted.)
    local me = held and type(char.manualEnded) == "table" and char.manualEnded
    local canReopen = me and not ns.Gone(me)
    lines[1] = GOLD .. "RunBook|r " .. GREY .. (held and (canReopen and "- run ended (/runbook start reopens it)|r"
      or "- ended (/runbook start: new run)|r") or "- not in a dungeon|r")
    local last = ns.LastOwnRun()
    if last then
      -- Short: name, time, gold, XP (the numbers you farm for).
      local gold = ns.ShownMoney(ns.RunGold(last))  -- (rounded as everywhere else)
      local money
      if gold >= 100000 then
        money = ns.Commas(math.floor(gold / 10000 + 0.5)) .. "g"  -- 10g+: whole gold is enough here
      elseif gold > 0 then
        money = ns.ShownMoneyText(gold)  -- ("5 silver", not "5s" next to a time)
      end
      local xp = (last.xp or 0) > 0 and (ns.Short(last.xp) .. " XP") or nil
      -- As much as fits: the name shortens first, then the XP goes.
      local text
      for _, labelMax in ipairs({ 40, 18, 14, 10 }) do
        local parts = { ns.Ellipsis(ns.ShortLabel(last), labelMax) .. " " .. ns.Clock(last.elapsed) }
        if money then parts[#parts + 1] = money end
        if xp then parts[#parts + 1] = xp end
        text = "Last: " .. table.concat(parts, " · ")
        if ns.Len(text) <= LINE_CHARS then break end
      end
      if ns.Len(text) > LINE_CHARS and xp then
        text = "Last: " .. ns.Ellipsis(ns.ShortLabel(last), 18) .. " " .. ns.Clock(last.elapsed)
          .. (money and (" · " .. money) or "")
      end
      lines[#lines + 1] = GREY .. text .. "|r"
    end
    lines[#lines + 1] = ns.CapLine()
    lines[#lines + 1] = ns.DayCapLine()
    return lines
  end

  local state, width = "", 38
  if not ns.inside then
    state = ns.GhostRunning() and (GREY .. "  (ghost)|r") or (GREY .. "  (paused)|r")
    width = 32
  end
  lines[1] = GOLD .. ns.Ellipsis(run.label or run.name or "?", width) .. "|r  " .. ns.Clock(run.elapsed) .. state

  -- Boss splits vs your fastest clear of this dungeon.
  local key = ns.RunKey(run)
  local max = ns.BossTotal(key)
  local best, bestT = ns.BestRun(key)
  if #run.bosses > 0 or max > 0 then
    local count = (max > 0 and #run.bosses <= max) and (#run.bosses .. "/" .. max) or tostring(#run.bosses)
    lines[#lines + 1] = "Bosses " .. count .. (bestT and (GREY .. " · best " .. ns.Clock(bestT) .. "|r") or "")
  end
  local first = math.max(1, #run.bosses - MAX_BOSSES + 1)
  if first > 1 then lines[#lines + 1] = GREY .. "  (" .. (first - 1) .. " earlier)|r" end
  for i = first, #run.bosses do
    local b = run.bosses[i]
    local split = not b.untimed and ns.BestSplit(best, b, i)
    lines[#lines + 1] = "  " .. ns.Ellipsis(b.name, 30) .. "  " .. (b.untimed and "-" or ns.Clock(b.t))
      .. (split and ("  " .. ns.Delta(b.t - split, true)) or "")
  end

  if #run.deaths > 0 or #run.wipes > 0 then
    local line = DeathsLine(run)
    if line ~= "" then lines[#lines + 1] = line end
  end

  AddStats(lines, "You: ", ns.RunGold(run), run.xp, run.elapsed)
  local names = {}
  for name in pairs(run.partners) do names[#names + 1] = name end
  table.sort(names)
  local duo = Shown(ns.RunGold(run))
  for _, name in ipairs(names) do
    local p = run.partners[name]
    duo = duo + Shown(ns.PartnerGold(p))
    -- Their time as of their last numbers (they're sent when gold or XP
    -- change): plus the time since, so their rates aren't high.
    local heard = 0
    for _, part in pairs(type(p.parts) == "table" and p.parts or {}) do
      if type(part) == "table" and (part.at or 0) > heard then heard = part.at end
    end
    -- (Not while you're outside: your clock is paused too, and theirs likely is.)
    local since = (ns.inside and heard > 0) and math.max(0, math.min(30, time() - heard)) or 0
    AddStats(lines, name .. ": ", ns.PartnerGold(p), p.xp or 0, (p.elapsed or 0) + since)
  end
  if #names > 0 and duo > 0 then
    local hr = ns.PerHour(duo, run.elapsed)
    hr = hr and Shown(hr)
    local total = ShownText(duo)
    lines[#lines + 1] = "Together: " .. total .. (hr and (GREY .. " · " .. ns.Money(hr) .. "/hr|r") or "")
  end
  -- Others in the group who run RunBook: one line (the Group tab has each).
  if ns.HasGroupStats(run) then
    local gold, xp, n = ns.GroupTotals(run)
    local parts = { "Group (" .. n .. " with RunBook): " .. ShownText(gold) }
    if xp > 0 then parts[#parts + 1] = ns.Short(xp) .. " XP" end
    lines[#lines + 1] = table.concat(parts, " · ")
  end

  -- In a raid, only your two's drops (everyone's would bury them).
  local drops = run.drops
  if run.kind == "raid" then
    drops = {}
    for _, d in ipairs(run.drops) do if ns.IsDuo(d.who) then drops[#drops + 1] = d end end
  end
  if #drops > 0 then
    lines[#lines + 1] = #drops > MAX_DROPS and string.format("Drops (latest %d of %d):", MAX_DROPS, #drops)
      or "Drops:"
    for i = #drops, math.max(1, #drops - MAX_DROPS + 1), -1 do
      local d = drops[i]
      lines[#lines + 1] = "  " .. ns.ColoredName({ q = d.q, name = ns.Ellipsis(d.name or "?", 28) })
        .. (d.n > 1 and ("x" .. d.n) or "") .. GREY .. " - " .. d.who .. "|r"
    end
  end

  if #run.notes > 0 then
    local n = run.notes[#run.notes]
    lines[#lines + 1] = GREY .. n.who .. ": |r" .. ns.Ellipsis(n.text, 46 - #n.who)
  end
  lines[#lines + 1] = ns.CapLine()
  lines[#lines + 1] = ns.DayCapLine()
  return lines
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
local frame
local fontStrings = {}
ns.manualShown = nil   -- /runbook toggle: overrides auto show/hide until the next zone change

-- Saved in screen units (offsets times the window's scale), so a new scale
-- keeps the window where it is.
local function SavePosition()
  local point, _, relPoint, x, y = frame:GetPoint()
  local s = ns.DB.scale or 1
  ns.DB.point = { point, relPoint, (x or 0) * s, (y or 0) * s }
end

local function Build()
  frame = CreateFrame("Frame", "VulcanRunBookFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(WIDTH, 40)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) if not ns.DB.locked then self:StartMoving() end end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
  end)
  frame:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and ns.ToggleHistory then ns.ToggleHistory() end
  end)
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.75)
  end
  frame:Hide()
end

function ns.ApplyPosition()
  if not frame then return end
  local p = ns.DB.point
  local s = ns.DB.scale or 1
  frame:SetScale(s)
  frame:ClearAllPoints()
  frame:SetPoint(p[1] or "CENTER", UIParent, p[2] or "CENTER", (p[3] or 0) / s, (p[4] or 0) / s)
end

function ns.RenderLive()
  if not frame or not frame:IsShown() then return end
  local lines = ns.LiveLines()
  for i, text in ipairs(lines) do
    local fs = fontStrings[i]
    if not fs then
      fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("TOPLEFT", 10, -8 - (i - 1) * LINE_H)
      fs:SetWidth(WIDTH - 20)
      fs:SetJustifyH("LEFT")
      if fs.SetWordWrap then fs:SetWordWrap(false) end
      fontStrings[i] = fs
    end
    fs:SetText(text)
    fs:Show()
  end
  for i = #lines + 1, #fontStrings do fontStrings[i]:Hide() end
  frame:SetHeight(16 + #lines * LINE_H)
end

-- Auto: shown inside a run, hidden outside. A /runbook toggle wins until the
-- next zone change.
function ns.UpdateVisibility()
  if not frame then return end
  local show
  if ns.manualShown ~= nil then
    show = ns.manualShown
  else
    -- Also right after /runbook end inside, so you see how to reopen it.
    show = ns.DB.autoShow
      and (ns.InRun() or ns.GhostRunning() or type(VulcanRunBookCharDB.suppress) == "table") or false
  end
  if show then
    frame:Show()
    ns.RenderLive()
  else
    frame:Hide()
  end
end

function ns.ToggleLive()
  local shown = frame and frame:IsShown()
  ns.manualShown = not shown
  ns.UpdateVisibility()
  return ns.manualShown
end

function ns.LiveShown() return frame and frame:IsShown() or false end

ns.Listen("READY", function()
  Build()
  ns.ApplyPosition()
end)
ns.Listen("LOGIN", function() ns.UpdateVisibility() end)
-- Your show/hide choice lasts until you change zones (not through /runbook end,
-- start or new, or a split, where you stay put).
for _, cb in ipairs({ "RUN_START", "RUN_RESUME", "RUN_END" }) do
  ns.Listen(cb, function() ns.UpdateVisibility() end)
end
ns.Listen("RUN_LEFT", function()
  ns.manualShown = nil
  ns.UpdateVisibility()
end)
ns.On("PLAYER_ENTERING_WORLD", function()
  ns.manualShown = nil
  if ns.UpdateVisibility then ns.UpdateVisibility() end
end)
for _, cb in ipairs({ "BOSS", "BOSS_REMOVED", "WIPE", "DEATH", "DROP", "NOTE", "PARTNER" }) do
  ns.Listen(cb, function() ns.RenderLive() end)
end
-- Once a second: the clock, and showing/hiding as a ghost run starts or ends.
local wasGhost = false
ns.Listen("TICK", function()
  local ghost = ns.GhostRunning()
  if ghost ~= wasGhost then
    wasGhost = ghost
    ns.UpdateVisibility()
  end
  ns.RenderLive()
end)
