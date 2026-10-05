-- RunBook: a copy window (WoW can't write files or touch the clipboard, so
-- exports open in a text box with everything selected: Ctrl+C, then paste
-- anywhere), the CSV export, and the chat report.
local _, ns = ...

local copyFrame, editBox

local function BuildCopyFrame()
  local f = CreateFrame("Frame", "VulcanRunBookCopyFrame", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(560, 360)
  f:SetPoint("CENTER")
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.92)
  end
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  f.title = title
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  local scroll = CreateFrame("ScrollFrame", "VulcanRunBookCopyScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -32)
  scroll:SetPoint("BOTTOMRIGHT", -30, 12)
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(true)
  box:SetFontObject(ChatFontNormal)
  box:SetWidth(510)
  box:SetScript("OnEscapePressed", function() f:Hide() end)
  scroll:SetScrollChild(box)
  if UISpecialFrames then table.insert(UISpecialFrames, "VulcanRunBookCopyFrame") end
  copyFrame, editBox = f, box
end

-- Shows text ready to copy. Returns the text (handy for tests).
function ns.ShowCopy(titleText, lines)
  if not copyFrame then BuildCopyFrame() end
  local text = table.concat(lines, "\n")
  copyFrame.title:SetText(titleText .. "  |cff888888(Ctrl+C to copy, Esc to close)|r")
  editBox:SetText(text)
  copyFrame:Show()
  editBox:SetFocus()
  editBox:HighlightText()  -- (after it has focus, so the selection holds)
  return text
end

---------------------------------------------------------------------------
-- CSV
---------------------------------------------------------------------------
local function CSVField(v)
  v = ns.StripColors(tostring(v == nil and "" or v))
  -- (Text a spreadsheet would run as a formula - a note starting with "=" -
  -- stays text.)
  -- ("-" only as a plain negative number.)
  if v:find("^[=+@\t\r]") or (v:find("^%-") and not v:find("^%-%d+%.?%d*$")) then v = "'" .. v end
  if v:find('[,"\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
  return v
end

ns.CSV_HEADER = "run,date,character,dungeon,difficulty,status,minutes,clear_minutes,bosses,boss_splits,deaths,"
  .. "wipes,coin_copper,loot_vendor_copper,loot_ah_copper,xp,gold_per_hour_copper,xp_per_hour,partner_gold_copper,"
  .. "partner_xp,notable_drops,notes,group_runbook_players,group_gold_copper,group_xp"

local STATUS = {
  ["new dungeon"] = "done", reset = "reset", split = "reset (found later)", timeout = "timed out",
  manual = "ended by hand", new = "started over", login = "logged out", wing = "changed wing",
}

local function Minutes(sec) return sec and string.format("%.1f", sec / 60) or "" end

function ns.CSVRow(run)
  local gold = ns.RunGold(run)
  local partnerGold, partnerXP = 0, 0
  for _, p in pairs(run.partners) do
    partnerGold = partnerGold + ns.PartnerGold(p)
    partnerXP = partnerXP + (p.xp or 0)
  end
  local drops = {}
  for _, d in ipairs(ns.NotableDrops(run, 3)) do
    if run.kind ~= "raid" or ns.IsRunDuo(run, d.who) then  -- in a raid, only you two's (as everywhere else)
      drops[#drops + 1] = (d.name or "?") .. (d.n > 1 and (" x" .. d.n) or "") .. " (" .. d.who .. ")"
    end
  end
  local splits = {}
  for _, b in ipairs(run.bosses) do splits[#splits + 1] = b.name .. (b.untimed and "" or (" " .. ns.Clock(b.t))) end
  local notes = {}
  for _, n in ipairs(run.notes) do notes[#notes + 1] = n.who .. ": " .. n.text end
  local gh, xh = ns.PerHour(gold, run.elapsed), ns.PerHour(run.xp, run.elapsed)
  local groupGold, groupXP, groupN = ns.GroupTotals(run, true)
  return table.concat({
    run.id or "", CSVField(run.startedAt and date and date("%Y-%m-%d %H:%M", run.startedAt) or ""),
    CSVField(run.char), CSVField(run.label or run.name), CSVField(run.diffName or run.diff or ""),
    CSVField(run.ended and (STATUS[run.endReason] or "done") or "in progress"),
    Minutes(run.elapsed), Minutes(ns.ClearTime(run)), #run.bosses, CSVField(table.concat(splits, "; ")),
    ns.DeathCount(run), #run.wipes, run.coin, run.loot, run.lootAH, run.xp,
    (gh and gold > 0) and string.format("%.0f", gh) or "", (xh and run.xp > 0) and string.format("%.0f", xh) or "",
    partnerGold, partnerXP, CSVField(table.concat(drops, "; ")), CSVField(table.concat(notes, " | ")),
    -- (Everyone with numbers: you, your partner and others in the group view.)
    groupN, groupGold, groupXP,
  }, ",")
end

function ns.ExportLines(what)
  if what == "debug" then
    local lines = { "RunBook diagnostics (" .. ns.Plural(#ns.DB.debugLog, "entry", "entries") .. ")" }
    for _, l in ipairs(ns.DB.debugLog) do lines[#lines + 1] = l end
    return lines
  end
  local lines = { ns.CSV_HEADER }
  if ns.run then lines[#lines + 1] = ns.CSVRow(ns.run) end
  for _, run in ipairs(ns.DB.history) do lines[#lines + 1] = ns.CSVRow(run) end
  return lines
end

---------------------------------------------------------------------------
-- Chat report: the run in progress, else your last run.
-- "RunBook: Deadmines 32:10, 5 bosses, 1 death, 14g 20s. Cleared at 30:55 (new best, was 31:40)."
-- "Drops: [Cruel Barb] Mirel, [Smite's Mighty Hammer] Tavlius"
-- In a raid only your and your partner's drops are listed, and at most two
-- drop lines are sent either way ("+N more"), so a report never floods chat.
---------------------------------------------------------------------------
ns.REPORT_DROP_LINES = 2

function ns.ReportLines(run, forRaid)
  run = run or ns.RunOrLast()
  if not run then return nil end
  forRaid = forRaid or run.kind == "raid"
  -- In a raid only your two's drops are listed, so the summary doesn't count everyone's.
  local first = "RunBook: " .. ns.StripColors(ns.RunSummary(run, true, false, forRaid))
  if run == ns.run then first = first:gsub("%.$", " (in progress).") end
  local clear = ns.ClearTime(run)
  if clear then
    local _, prevT = ns.BestRun(ns.RunKey(run), run)
    -- (Only a clear of the whole dungeon can be a new best.)
    if prevT and clear < prevT and ns.TimedClear(run) then
      first = first .. " Cleared at " .. ns.Clock(clear) .. " (new best, was " .. ns.Clock(prevT) .. ")."
    elseif prevT then
      first = first .. " Cleared at " .. ns.Clock(clear) .. " (best " .. ns.Clock(prevT) .. ")."
    else
      first = first .. " Cleared at " .. ns.Clock(clear) .. "."
    end
  end
  local lines = { first }
  local drops = {}
  for _, d in ipairs(ns.NotableDrops(run, 3)) do
    if not forRaid or ns.IsRunDuo(run, d.who) then
      drops[#drops + 1] = (d.link or ("[" .. (d.name or "?") .. "]")) .. ((d.n or 1) > 1 and (" x" .. d.n) or "")
        .. " " .. d.who
    end
  end
  -- Chat lines are capped at 255 characters; links are long, so split them.
  local line = "Drops:"
  for i, d in ipairs(drops) do
    if #line + #d + 2 > 240 then
      if #lines >= ns.REPORT_DROP_LINES then  -- the summary + the drop lines so far
        line = line .. " +" .. (#drops - i + 1) .. " more"
        break
      end
      lines[#lines + 1] = line
      line = "Drops:"
    end
    line = line .. (line == "Drops:" and " " or ", ") .. d
  end
  if line ~= "Drops:" then lines[#lines + 1] = line end
  return lines
end
