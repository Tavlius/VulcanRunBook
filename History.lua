-- RunBook: the history window. "Runs" lists your saved runs, newest first (and
-- the one in progress); click one for its splits, deaths, drops and notes.
-- "Dungeons" shows per-dungeon stats: runs, clears, best and average clear,
-- gold and XP per hour.
local _, ns = ...

local W, H = 600, 420
local ROW_H = 16
local GREY, GOLD = "|cff9d9d9d", "|cffffd100"

---------------------------------------------------------------------------
-- Content (plain strings, so it can be tested without a client)
---------------------------------------------------------------------------
local function When(t)
  if not t or t <= 0 or not date then return "?" end
  return date("%b %d %H:%M", t)
end
ns.When = When

local DropCounts = function(run) return ns.DropCounts(run) end

-- Splits long text into lines of about `width` characters at spaces (rows
-- don't wrap), each after the first indented. head: put before the first
-- line as it is (its spacing kept).
local function Wrap(text, width, indent, head)
  text = tostring(text)
  local out, line = {}, head or text:match("^(%s*)")  -- keep the first line's own indent
  local lead = line
  for word in text:gmatch("%S+") do
    if line ~= lead and #line + 1 + #word > width then
      out[#out + 1] = line
      line = indent .. word
    else
      line = (line == lead) and (line .. word) or (line .. " " .. word)
    end
  end
  if line ~= lead then out[#out + 1] = line end
  return out
end
ns.Wrap = Wrap

-- Difficulty shown only when it isn't a dungeon's normal one.
local function DiffText(run)
  local dn = run.diffName
  if run.diff and run.diff ~= 0 and run.diff ~= 1 and dn and dn ~= "" then return " (" .. dn .. ")" end
  return ""
end

-- One line per run: "#12  Oct 02 21:05  Deadmines  32:10  5/5  1 death  14g 20s  2 blues"
function ns.RunRowText(run)
  local max = ns.BossTotal(ns.RunKey(run))
  local parts = {
    GREY .. "#" .. tostring(run.id or "?") .. "|r", When(run.startedAt), GOLD .. ns.Ellipsis(ns.ShortLabel(run), 32)
      .. "|r", ns.Clock(run.elapsed),
  }
  -- (Runs of all your characters share the list: whose, when there's more than one.)
  if ns.CharacterCount() > 1 then
    table.insert(parts, 3, GREY .. ns.Ellipsis(ns.CharLabel(run.char), 16) .. "|r")
  end
  if max > 0 and #run.bosses <= max then
    parts[#parts + 1] = #run.bosses .. "/" .. max
  elseif #run.bosses > 0 then
    parts[#parts + 1] = ns.Plural(#run.bosses, "boss", "bosses")
  end
  if #run.notes > 0 then parts[#parts + 1] = GREY .. "*|r" end  -- has a note
  local deaths = ns.DeathCount(run)
  if deaths > 0 then parts[#parts + 1] = ns.Plural(deaths, "death") end
  local gold = ns.ShownMoney(ns.RunGold(run))  -- (rounded as everywhere else)
  if gold >= 100000 then
    parts[#parts + 1] = ns.Commas(math.floor(gold / 10000 + 0.5)) .. "|cffffd700g|r"  -- 10g+: whole gold
  elseif gold > 0 then
    parts[#parts + 1] = ns.ShownMoneyText(gold, true)  -- ("65 silver", not "65s" next to a time)
  end
  local blues, epics = DropCounts(run)
  if epics > 0 then parts[#parts + 1] = "|cffa335ee" .. ns.Plural(epics, "epic") .. "|r" end
  if blues > 0 then parts[#parts + 1] = "|cff0070dd" .. ns.Plural(blues, "blue") .. "|r" end
  return table.concat(parts, "  ")
end

local function Rates(gold, xp, elapsed)
  local out = {}
  local g = ns.PerHour(gold, elapsed)
  if g and gold > 0 then out[#out + 1] = ns.Money(ns.ShownMoney(g)) .. "/hr" end  -- (rounded as live)
  local x = ns.PerHour(xp, elapsed)
  if x and xp > 0 then out[#out + 1] = ns.Short(x) .. " XP/hr" end
  return #out > 0 and (GREY .. "  (" .. table.concat(out, ", ") .. ")|r") or ""
end

local END_REASONS = {
  ["new dungeon"] = "ended: entered another dungeon", reset = "ended: dungeon reset",
  split = "ended: dungeon reset (found later)", timeout = "ended: away 30+ min", manual = "ended by hand",
  new = "ended: started over", login = "ended: logged out", wing = "ended: entered another wing",
}

local function EndText(run)
  if not run.ended then return "in progress" end
  if run.endReason == "timeout" and run.kind == "raid" then return "ended: away 2+ hours" end
  return END_REASONS[run.endReason] or "ended"
end

function ns.RunDetailLines(run)
  local lines = {}
  local function add(text) lines[#lines + 1] = text end
  add(GOLD .. (run.label or run.name or "?") .. "|r" .. DiffText(run) .. "  " .. When(run.startedAt) .. GREY .. "  ("
    .. ns.CharLabel(run.char) .. ")|r")
  local clear = ns.ClearTime(run)
  -- (A clear that began after bosses here were down: not a best time.)
  local part = (clear and ns.LateRun(run)) and " (began after bosses here were down: not a best time)" or ""
  add("Time " .. ns.Clock(run.elapsed) .. (clear and ("  ·  cleared at " .. ns.Clock(clear) .. part) or "")
    .. GREY .. "  ·  " .. EndText(run) .. "|r")
  if #run.members > 10 then
    -- (A raid: who's in it would take lines; the two of you and a count.)
    local duo = {}
    local me = run.char and ns.ShortName(run.char)
    for _, m in ipairs(run.members) do
      if ns.IsRunDuo(run, m) and m ~= me then duo[#duo + 1] = m end  -- (your partner; not you)
    end
    add("Group: " .. #run.members .. " players" .. (#duo > 0 and (", with " .. table.concat(duo, ", ")) or ""))
  elseif #run.members > 1 then
    for _, l in ipairs(Wrap("Group: " .. table.concat(run.members, ", "), 90, "    ")) do add(l) end
  end

  -- Compared with your fastest other clear (so the best run shows how much it gained).
  local best, bestT = ns.BestRun(ns.RunKey(run), run)
  if #run.bosses > 0 then
    add(" ")
    add(GOLD .. "Bosses|r" .. (bestT and (GREY .. "  (vs your fastest other clear, " .. ns.Clock(bestT) .. ")|r")
      or ""))
    for i, b in ipairs(run.bosses) do
      local split = not b.untimed and ns.BestSplit(best, b, i)
      add("  " .. (b.untimed and "    -" or ns.Clock(b.t)) .. "  " .. b.name
        .. (split and ("  " .. ns.Delta(b.t - split, true)) or "")
        .. ((b.manual or b.byHand) and (GREY .. "  (marked by hand)|r") or "")
        .. (b.untimed and (GREY .. "  (your partner's, while you were outside)|r") or ""))
    end
  end
  if #run.wipes > 0 or #run.deaths > 0 then
    add(" ")
    add(GOLD .. "Deaths and wipes|r")
    local events = {}
    -- In a raid, each of you two's deaths is listed; everyone else's are counted.
    local big = run.kind == "raid"
    local others = 0
    for _, d in ipairs(run.deaths) do
      if big and not ns.IsRunDuo(run, d.who) then
        others = others + 1
      else
        events[#events + 1] = { t = d.t, text = d.who .. " died" }
      end
    end
    for _, w in ipairs(run.wipes) do
      events[#events + 1] = { t = w.t, text = "|cffff5050Wipe|r" .. (w.boss and (" on " .. w.boss) or "") }
    end
    table.sort(events, function(a, b) return a.t < b.t end)
    for _, e in ipairs(events) do add("  " .. ns.Clock(e.t) .. "  " .. e.text) end
    if others > 0 then add(GREY .. "  + " .. ns.Plural(others, "death") .. " of other players|r") end
  end

  add(" ")
  add(GOLD .. "Gold and XP|r")
  -- (To the silver, as in the live window, so the lines add up.)
  local mine, coin = ns.ShownMoney(ns.RunGold(run)), ns.ShownMoney(run.coin or 0)
  if mine >= 100 then coin = math.floor((run.coin or 0) / 100 + 0.5) * 100 end  -- (the same unit as the total)
  if mine == 0 and (run.xp or 0) == 0 then
    add("  You: " .. GREY .. "nothing|r")
  else
    local split = (coin > 0 and mine > coin) and (GREY .. " (coin " .. ns.ShownMoneyText(coin) .. ", loot "
      .. ns.ShownMoneyText(mine - coin) .. ")|r") or ""
    add("  You: " .. ns.ShownMoneyText(mine, true) .. split .. ((run.xp or 0) > 0 and ("  ·  "
      .. ns.Commas(run.xp) .. " XP") or "") .. Rates(mine, run.xp or 0, run.elapsed))
  end
  if (run.unpriced or 0) > 0 then
    add(GREY .. "  " .. ns.Plural(run.unpriced, "looted item") .. " had no price (item data never loaded).|r")
  end
  local names = {}
  for name in pairs(run.partners) do names[#names + 1] = name end
  table.sort(names)
  local duo = mine
  for _, name in ipairs(names) do
    local p = run.partners[name]
    local theirs = ns.ShownMoney(ns.PartnerGold(p))
    duo = duo + theirs
    add("  " .. name .. ": " .. ns.ShownMoneyText(theirs, true) .. ((p.xp or 0) > 0 and ("  ·  "
      .. ns.Commas(p.xp) .. " XP") or "") .. Rates(theirs, p.xp or 0, p.elapsed))
  end
  if #names > 0 then add("  Together: " .. ns.ShownMoneyText(duo, true) .. Rates(duo, 0, run.elapsed)) end
  if ns.HasGroupStats(run) then
    -- Everyone in the group, with the numbers of those who run RunBook.
    add(" ")
    add(GOLD .. "Group|r" .. GREY .. "  (shown only: not in your totals)|r")
    for _, l in ipairs(ns.GroupLines(run)) do add("  " .. l) end
  end

  -- In a raid, only you two's drops (as everywhere else).
  local shown = {}
  for _, d in ipairs(run.drops) do
    if run.kind ~= "raid" or ns.IsRunDuo(run, d.who) then shown[#shown + 1] = d end
  end
  if #shown > 0 then
    add(" ")
    add(GOLD .. "Drops|r" .. (run.kind == "raid" and (GREY .. " (you two)|r") or ""))
    for _, d in ipairs(shown) do
      add("  " .. ns.Clock(d.t) .. "  " .. ns.ColoredName(d) .. (d.n > 1 and ("x" .. d.n) or "") .. GREY .. " - "
        .. d.who .. "|r")
    end
  end
  if #run.notes > 0 then
    add(" ")
    add(GOLD .. "Notes|r")
    for _, n in ipairs(run.notes) do
      local head = "  " .. (n.t and (ns.Clock(n.t) .. "  ") or "")
      for _, l in ipairs(Wrap(n.who .. ": " .. n.text, 90, "      ", head)) do add(l) end
    end
  end
  if run.ended and run.id then
    add(" ")
    add(GREY .. "/runbook note #" .. run.id .. " <text> adds a note; /runbook delete " .. run.id
      .. " removes this run.|r")
  end
  return lines
end

function ns.DungeonLines()
  local lines = {}
  local stats = ns.DungeonStats()
  if #stats == 0 then
    return { GREY .. (ns.run and "No finished runs yet (your first is in progress)."
      or "No runs yet. Zone into a dungeon and it starts on its own.") .. "|r" }
  end
  for _, s in ipairs(stats) do
    lines[#lines + 1] = GOLD .. s.name .. "|r" .. GREY .. "  " .. ns.Plural(s.runs, "run")
      .. ", last " .. When(s.last) .. "|r"
    local clear = {}
    if s.final then
      clear[#clear + 1] = string.format("%s (to %s%s)", ns.Plural(s.clears, "clear"),
        ns.Ellipsis(s.final.name or "?", 30), s.pinned and ", pinned" or "")
      if s.best then
        clear[#clear + 1] = "best " .. ns.Clock(s.best) .. (s.bestId and (" (#" .. s.bestId .. ")") or "")
      end
      if s.avgClear then clear[#clear + 1] = "avg " .. ns.Clock(s.avgClear) end
    elseif s.maxBosses > 0 then
      clear[#clear + 1] = "up to " .. ns.Plural(s.maxBosses, "boss", "bosses")
        .. " · final boss after 2 nights ending on it, or /runbook final <boss> there"
    else
      clear[#clear + 1] = "no boss kills recorded"
    end
    lines[#lines + 1] = "  " .. table.concat(clear, " · ")
    local more = {}
    if s.goldHr and s.gold > 0 then more[#more + 1] = ns.Money(ns.ShownMoney(s.goldHr)) .. "/hr" end
    if s.duoGoldHr and (s.duoGold or 0) > s.gold then
      more[#more + 1] = "together " .. ns.Money(ns.ShownMoney(s.duoGoldHr)) .. "/hr"
    end
    if s.xpHr then more[#more + 1] = ns.Short(s.xpHr) .. " XP/hr" end
    more[#more + 1] = s.deaths > 0 and string.format("%.1f deaths/run", s.deaths / s.runs) or "no deaths"
    if s.wipes > 0 then more[#more + 1] = ns.Plural(s.wipes, "wipe") end
    if s.epics > 0 then more[#more + 1] = "|cffa335ee" .. ns.Plural(s.epics, "epic") .. "|r" end
    if s.blues > 0 then more[#more + 1] = "|cff0070dd" .. ns.Plural(s.blues, "blue") .. "|r" end
    lines[#lines + 1] = "  " .. table.concat(more, " · ")
  end
  return lines
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
local frame, scroll, child, title, backBtn, tabs
local rows = {}
local view = { tab = "runs", detail = nil }  -- detail = the run being viewed (a run table)

local function Row(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, child)
  r:SetSize(W - 60, ROW_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  if r.SetHighlightTexture then r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD") end
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.text:SetPoint("LEFT", 4, 0)
  r.text:SetWidth(W - 68)
  r.text:SetJustifyH("LEFT")
  if r.text.SetWordWrap then r.text:SetWordWrap(false) end
  r:SetScript("OnClick", function(self)
    if self.run then
      view.detail = self.run
      ns.RenderHistory()
    end
  end)
  rows[i] = r
  return r
end

-- lines: { text } or { text, run } (clickable)
local function Fill(lines, toTop)
  for i, line in ipairs(lines) do
    local r = Row(i)
    r.text:SetText(line[1])
    r.run = line[2]
    if r.EnableMouse then r:EnableMouse(line[2] ~= nil) end
    r:Show()
  end
  for i = #lines + 1, #rows do
    rows[i].run = nil
    rows[i]:Hide()
  end
  child:SetHeight(math.max(1, #lines * ROW_H))
  if toTop and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
end

local function InHistory(run)
  if run == ns.run then return true end
  for _, r in ipairs(ns.DB.history) do if r == run then return true end end
  return false
end

function ns.HistoryContent()
  local lines = {}
  local history = ns.DB.history
  -- A run that was deleted (or reopened) while open goes back to the list.
  if view.tab == "runs" and view.detail and InHistory(view.detail) then
    for _, text in ipairs(ns.RunDetailLines(view.detail)) do lines[#lines + 1] = { text } end
    return lines, view.detail.id and ("Run #" .. view.detail.id) or "Run in progress"
  end
  view.detail = nil
  if view.tab == "dungeons" then
    for _, text in ipairs(ns.DungeonLines()) do lines[#lines + 1] = { text } end
    return lines, "Dungeons"
  end
  if view.tab == "group" then
    local texts, heading = ns.GroupTabLines()
    for _, text in ipairs(texts) do lines[#lines + 1] = { text } end
    return lines, heading
  end
  if ns.run then
    lines[#lines + 1] = { "|cff40ff40Now:|r  " .. ns.Ellipsis(ns.run.label, 30) .. "  " .. ns.Clock(ns.run.elapsed)
      .. GREY .. "  (in progress)|r", ns.run }
  end
  if #history == 0 and not ns.run then
    lines[1] = { GREY .. "No runs yet. Zone into a dungeon and it starts on its own.|r" }
  end
  for _, run in ipairs(history) do
    -- (One damaged run can't keep the list from opening.)
    local ok, text = pcall(ns.RunRowText, run)
    lines[#lines + 1] = { ok and text or (GREY .. "#" .. tostring(run.id) .. " (can't be shown)|r"), run }
    if not ok then ns.Log("error", "row %s: %s", tostring(run.id), tostring(text)) end
  end
  return lines, string.format("Runs (%d)", #history)
end

-- Re-rendering in place (a note or partner update arrived) keeps the scroll
-- position; switching tab or run jumps back to the top.
local lastView
function ns.RenderHistory()
  if not frame or not frame:IsShown() then return end
  local lines, heading = ns.HistoryContent()
  title:SetText("RunBook - " .. heading)
  if view.detail then backBtn:Show() else backBtn:Hide() end
  for name, b in pairs(tabs) do
    -- The open tab's button is greyed out, so you can see which one you're on.
    if b.SetEnabled then b:SetEnabled(name ~= view.tab or view.detail ~= nil) end
  end
  local key = view.tab .. ":" .. tostring(view.detail and (view.detail.id or "now"))
  Fill(lines, key ~= lastView)
  lastView = key
end

local function Build()
  frame = CreateFrame("Frame", "VulcanRunBookHistoryFrame", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(W, H)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.92)
  end
  title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)

  tabs = {}
  for i, spec in ipairs({ { "runs", "Runs" }, { "dungeons", "Dungeons" }, { "group", "Group" } }) do
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(90, 20)
    b:SetPoint("TOPLEFT", 12 + (i - 1) * 96, -30)
    b:SetText(spec[2])
    b:SetScript("OnClick", function()
      view.tab, view.detail = spec[1], nil
      ns.RenderHistory()
    end)
    tabs[spec[1]] = b
  end
  -- Buttons added by optional modules (Persist.lua), after the tabs.
  for i, spec in ipairs(ns.extraHistoryButtons or {}) do
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(90, 20)
    b:SetPoint("TOPLEFT", 12 + (2 + i) * 96, -30)
    b:SetText(spec.label)
    b:SetScript("OnClick", spec.run)
  end
  backBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  backBtn:SetSize(70, 20)
  backBtn:SetPoint("TOPRIGHT", -32, -30)
  backBtn:SetText("Back")
  backBtn:SetScript("OnClick", function()
    view.detail = nil
    ns.RenderHistory()
  end)

  scroll = CreateFrame("ScrollFrame", "VulcanRunBookHistoryScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -56)
  scroll:SetPoint("BOTTOMRIGHT", -32, 12)
  child = CreateFrame("Frame", nil, scroll)
  child:SetSize(W - 60, 1)
  scroll:SetScrollChild(child)

  if UISpecialFrames then table.insert(UISpecialFrames, "VulcanRunBookHistoryFrame") end
  frame:SetScript("OnShow", function() ns.RenderHistory() end)
  frame:Hide()
end

-- tab: "runs" | "dungeons" | "group" | nil (keep); detail: a run to open.
function ns.ShowHistory(tab, detail)
  if not ns.DB then return end
  if not frame then Build() end
  if tab then view.tab = tab end
  view.detail = detail
  if frame:IsShown() then
    ns.RenderHistory()
  else
    frame:Show()  -- renders from OnShow
  end
end

function ns.ToggleHistory()
  if not ns.DB then return end
  if frame and frame:IsShown() then
    frame:Hide()
  else
    ns.ShowHistory()
  end
end

function ns.HistoryShown() return frame and frame:IsShown() or false end

-- Keep an open window current as runs end, notes arrive or runs are deleted,
-- and (every few seconds) while it shows the run in progress.
for _, cb in ipairs({ "RUN_START", "RUN_END", "NOTE", "PARTNER", "GROUP", "HISTORY_CHANGED", "BOSS", "BOSS_REMOVED",
    "WIPE", "DEATH", "DROP" }) do
  ns.Listen(cb, function() ns.RenderHistory() end)
end
ns.Listen("TICK", function(count)
  if count % 5 == 0 and ns.run and frame and frame:IsShown()
      and ((view.tab == "runs" and (view.detail == nil or view.detail == ns.run)) or view.tab == "group") then
    ns.RenderHistory()
  end
end)
