-- RunBook: duo sync. If your group partner also runs RunBook, each of you sends
-- your run's coin, loot value and XP, your notable drops, your notes, and any
-- dungeon reset you saw, over the hidden addon channel. So your log shows their
-- numbers and drops even when the client hides their loot messages.
--
-- Addon messages are blocked during boss fights (and throttled), so messages
-- wait in a queue and go out as soon as the client allows.
--
-- Messages: "<kind><version>|<session tag>|<fields>", kind S (stats), N (note),
-- D (drop), B (boss kill), R (reset), X (started over with /runbook new). A run is named by map ID, dungeon name,
-- wing and its start in server time, so both of you can find the matching run.
local _, ns = ...
local plain = ns.plain

local PREFIX = "VulcanRunBook"
local PROTOCOL = 3           -- 2: kill flags (!m/!o), split messages, checked numbers; 3: kill count in stats
local OLDEST_ACCEPTED = 3
local SEND_EVERY = 30        -- seconds between stats updates during a run
local MATCH = 1800           -- your run and theirs started within this (server time)
local QUEUE_MAX = 100        -- (stats updates go first when it's full)
local HOLD_SECONDS = 600     -- a message waiting (out of a group, or over a /reload) this long is too old to send
local ENDED_GRACE = 5        -- a run of yours that ended still takes what was on its way this long

ns.partnersSeen = {}         -- [name] = GetTime() last heard from (your partner)
ns.heardFrom = {}            -- [name] = true: any RunBook user heard this session
ns.partnerKills = {}         -- [name] = { start, n, d, at }: kills in their latest run, as last heard
local versionNoticed = {}
-- The player whose message is being handled (set before a handler runs):
-- their GroupKey.
local msgIdent
local otherNoticed = {}      -- [name] = true once told they aren't your partner
local tagAsked = {}          -- [name] = true once your partner's BattleTag was looked up

local registered = false
local queue = {}             -- { kind, key, msg }
local lastSig                -- your run's numbers when last sent

-- Result codes: nil/true on older clients, 0 = sent. 3 = throttled, 8 =
-- channel throttled and 11 = locked down (boss fight): try again later.
-- 5 = not in a group (while the group changes, or on a loading screen) and 9 =
-- general error: try again for up to 10 minutes, like a send that threw.
-- Anything else (a bad message): give up on that message.
local RETRY = { [3] = true, [8] = true, [11] = true }
local RETRY_A_WHILE = { [5] = true, [9] = true }

local function Clean(text)
  return (tostring(text or ""):gsub("|+", "/"))
end

local function InGroup()
  return IsInGroup and IsInGroup() or false
end

local function CanSend()
  return registered and ns.DB and ns.DB.sync and ns.SendAddon and InGroup()
end

-- A dungeon-finder group talks on the instance channel; a normal group on
-- party or raid.
local function Channel()
  if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and LE_PARTY_CATEGORY_HOME
      and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
    return "INSTANCE_CHAT"
  end
  return (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
end
ns.GroupChannel = Channel

-- Queues a message. A newer stats message for the same run replaces the old one.
local function Queue(kind, key, msg)
  if not (ns.DB and ns.DB.sync and InGroup()) then return end
  if kind == "S" then
    for _, q in ipairs(queue) do
      if q.kind == "S" and q.key == key then
        q.msg = msg
        return
      end
    end
  end
  if #queue >= QUEUE_MAX then
    -- Full (messages held for a long time): drop an old stats update - a newer
    -- one says the same - before any drop, kill or note.
    local dropAt = 1
    for i, q in ipairs(queue) do if q.kind == "S" then dropAt = i break end end
    table.remove(queue, dropAt)
  end
  queue[#queue + 1] = { kind = kind, key = key, msg = msg, at = time() }
end

function ns.FlushSync()
  if not CanSend() then return end
  while queue[1] do
    local ok, result = pcall(ns.SendAddon, PREFIX, queue[1].msg, Channel())
    if ok and (result == nil or result == true or result == 0) then
      table.remove(queue, 1)
    elseif ok and RETRY[result] then
      return  -- wait for the next tick
    elseif (not ok or result == false or RETRY_A_WHILE[result])
        and GetTime() - (queue[1].failedAt or GetTime()) < 600 then
      -- (It threw - blocked for now, in a boss fight? - or an older client said
      -- "not now"): try again next tick, for up to 10 minutes.
      queue[1].failedAt = queue[1].failedAt or GetTime()
      return
    else
      ns.Log("sync", "send failed (%s), dropped", tostring(result))
      table.remove(queue, 1)
    end
  end
end

-- The run: map ID (or empty), dungeon name, wing (or empty), start in server time.
local function Header(kind, run)
  return string.format("%s%d|%s|%s|%s|%s|%d", kind, PROTOCOL, ns.token, Clean(run.mapID or ""), Clean(run.name),
    Clean(run.wing or ""), run.serverStart or 0)
end

-- Stats: run time, coin, loot (vendor), loot (AH), XP, and 1 once the run has ended.
function ns.SyncStats(run)
  run = run or ns.run
  if not run then return end
  -- (With how many kills the run has, so /runbook check can show whether the
  -- two logs agree.)
  Queue("S", run.serverStart, string.format("%s|%d|%d|%d|%d|%d|%d|%d", Header("S", run), math.floor(run.elapsed),
    run.coin, run.loot, run.lootAH, run.xp, run.ended and 1 or 0, #run.bosses))
end

-- How many bytes of note fit in one message for this run (so both logs keep
-- the same text).
function ns.SyncNoteRoom(run)
  return 255 - #Header("N", run) - 3
end

-- 1: written in the run you're in now; 0: a note on an earlier run (#12).
function ns.SyncNote(run, text)
  Queue("N", nil, ns.Truncate(Header("N", run) .. "|" .. (run == ns.run and 1 or 0) .. "|" .. Clean(text), 255))
end

-- With when it was looted (server time), so a late message still matches the
-- loot line your partner's client showed you.
function ns.SyncDrop(run, d)
  Queue("D", nil, string.format("%s|%d|%d|%d|%d", Header("D", run), d.id, d.n or 1, d.q or -1,
    d.st or ns.ServerTime()))
end

-- A boss kill (so a kill one of you missed - dead, or outside - still counts).
function ns.SyncBoss(run, b)
  -- An unnamed kill goes without its name ("Boss 3" is only yours); your
  -- partner matches it to their kill from the last minute, if any.
  -- With its tag, so a name given to it later updates the same kill.
  local name = b.anonymous and "" or Clean(b.name)
  -- Flags on the tag: "m" a kill marked by hand (/runbook boss), which may be
  -- one that died before they joined; "o" this run began in a copy you'd been
  -- in before (/runbook end and back in). Neither is a sign of a reset.
  -- With when it died and when you last came in (into the copy it died in),
  -- so a boss your partner saw die earlier shows a reset in between.
  local flags = b.manual and "!m" or ""
  local entry = run.resumeSnap and run.resumeSnap.server or run.serverStart or 0
  Queue("B", nil, ns.Truncate(string.format("%s|%s%s|%d|%d|%d|%s", Header("B", run), Clean(b.key or b.peer or ""),
    flags, b.id or 0, b.st or ns.ServerTime(), entry, name), 255))
end

-- Your log found a reset by a boss killed again and split your run where you
-- came back in (this run's start): your partner's log may not have that boss.
-- at: when the new copy was entered, if not this run's start (your partner's
-- entry, when their kill showed your log the reset: their log may not know).
-- after: when the boss died the first time - the reset came after that.
function ns.SyncSplit(run, at, after)
  local h = Header("P", at and { mapID = run.mapID, name = run.name, wing = run.wing, serverStart = at } or run)
  Queue("P", nil, h .. "|" .. ns.ServerTime() .. "|" .. (after or ""))  -- (and when it was sent)
end

-- You started over here (/runbook new): your partner's run starts over too.
function ns.SyncNewRun(run)
  Queue("X", nil, Header("X", run) .. "|" .. (run.diffUnknown and "" or (run.diff or 0)))
end

function ns.SyncReset(name)
  Queue("R", nil, string.format("R%d|%s|%s", PROTOCOL, ns.token, Clean(name)))
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
-- The run of yours that matches theirs: same dungeon, started closest in time.
-- A run of yours that ended before theirs started can't be it (back-to-back
-- runs of one dungeon).
local function FindRun(mapID, name, wing, start)
  local best, bestGap
  local candidates = {}
  if ns.run then candidates[#candidates + 1] = ns.run end
  for _, r in ipairs(ns.DB.history) do
    if #candidates >= 6 then break end
    if ns.IsOwnRun(r) then candidates[#candidates + 1] = r end  -- not another character's
  end
  for _, r in ipairs(candidates) do
    local same
    if mapID and r.mapID then same = r.mapID == mapID else same = r.name == name end
    if same and wing and r.wing and wing ~= r.wing then same = false end
    -- Theirs can't have begun after yours ended, or long before yours began.
    local endedBefore = r.serverEnd and start > r.serverEnd + 5
    if same and not endedBefore and start >= (r.serverStart or 0) - 4 * MATCH then
      local gap = math.abs((r.serverStart or 0) - start)
      if not bestGap or gap < bestGap then best, bestGap = r, gap end
    end
  end
  return best
end

-- Where their message goes: your run in progress when it's the same dungeon
-- (what they send now happens there, even when their run began before yours);
-- otherwise the run of yours that matches theirs.
local function TargetRun(mapID, name, wing, start)
  local cur = ns.run
  if cur then
    local same
    if mapID and cur.mapID then same = cur.mapID == mapID else same = cur.name == name end
    if same and not (wing and cur.wing and wing ~= cur.wing) then return cur end
  end
  return FindRun(mapID, name, wing, start)
end

local function Notice(name, ver)
  if versionNoticed[name] then return end
  versionNoticed[name] = true
  ns.Print(string.format("%s runs %s RunBook, so sync is off between you. Both of you need the "
    .. "latest version.", name, ver > PROTOCOL and "a newer" or "an older"))
end

-- "map|name|wing|start|rest" -> run (or nil), rest
-- Your run that is their run, anywhere in your history: for a note on an
-- earlier run of theirs (#12). None: nil. The runs their numbers reached come
-- first (sure to be theirs); otherwise it goes by time.
local function SameRun(mapID, name, wing, start, sender)
  local key = tostring(start)
  local function Reached(r)
    local e = sender and type(r.partners) == "table" and (r.partners[msgIdent or sender] or r.partners[sender])
    return type(e) == "table" and type(e.parts) == "table" and e.parts[key] ~= nil
  end
  local function Pick(onlyReached)
    local going, goingGap, after, afterGap
    local function try(r)
      if not (r and ns.IsOwnRun(r)) then return end
      if onlyReached and not Reached(r) then return end
      local same
      if mapID and r.mapID then same = r.mapID == mapID else same = r.name == name end
      if same and wing and r.wing and wing ~= r.wing then same = false end
      -- Theirs began while yours was going (they joined late) or up to two
      -- hours before it (you joined late).
      local s = r.serverStart or 0
      if not same or start > (r.serverEnd or math.huge) + 5 or start < s - 4 * MATCH then return end
      if start >= s then
        if not goingGap or start - s < goingGap then going, goingGap = r, start - s end
      elseif not afterGap or s - start < afterGap then
        after, afterGap = r, s - start
      end
    end
    try(ns.run)
    for _, r in ipairs(ns.DB.history) do try(r) end
    -- (Without their numbers, one of yours that began well after theirs may
    -- be a different run: a solo run of theirs before you two met up.)
    if not onlyReached and after and afterGap > 600 then after = nil end
    -- The run of yours that was going when theirs began (the latest-started),
    -- unless it ended where the next one began just after theirs: you both
    -- went on to a new run, them a moment first (split where each of you came
    -- back in, up to a minute apart; or started over with /runbook new, which
    -- reaches you a few seconds later).
    local soon = going and after and ((going.endReason == "split" and afterGap <= 60)
      or (going.endReason == "new" and afterGap <= 10))
    if after and (not going or (soon and (going.serverEnd or 0) >= (after.serverStart or 0) - 5)) then
      return after
    end
    return going
  end
  return Pick(true) or Pick(false)
end

-- closest: the run of yours that is theirs, even if you're in another (a note
-- written on a run of theirs belongs with your copy of that run).
local function RunFrom(body, closest, sender)
  local map, name, wing, start, rest = body:match("^([^|]*)|([^|]*)|([^|]*)|(%d+)|?(.*)$")
  if not map then return nil end
  start = tonumber(start)
  local find = closest and SameRun or TargetRun
  return find(tonumber(map), name, wing ~= "" and wing or nil, start, sender), rest, start, name,
    wing ~= "" and wing or nil
end

-- n whole numbers, each finite and within reason (a value from a broken or
-- hostile client can't make your totals infinite). The first may be -1 for
-- "unknown" where a field allows it.
local function Numbers(rest, n)
  local f = {}
  for v in rest:gmatch("[^|]+") do f[#f + 1] = tonumber(v) end
  if #f ~= n then return nil end
  for i = 1, n do
    local x = f[i]
    if type(x) ~= "number" or x ~= x or x < -1 or x > 2e9 or x ~= math.floor(x) then return nil end
  end
  return f
end

local HANDLERS = {}

-- Their numbers are totals for their run. Each run of yours gets what they made
-- while it was going: all of a run of theirs that began with or after yours,
-- otherwise their totals since yours began (as last heard then, or from the
-- first numbers it gets). One run of yours can span
-- several of theirs (they started over and you didn't), so it keeps a part per
-- run of theirs and shows the sum. A run of yours that has ended takes no
-- more growth (they played on after you stopped) - only corrections down (their
-- log split a run yours didn't) and, for ENDED_GRACE, what was on its way.
local FIELDS = { "elapsed", "coin", "loot", "lootAH", "xp" }

-- Their latest totals per run of theirs (this session), so a run of yours that
-- starts while theirs is going knows where theirs stood.
-- Kept with your character's data (a reload doesn't lose them); a few hours.
local totalsChecked
local function Totals()
  local t = VulcanRunBookCharDB and VulcanRunBookCharDB.partnerTotals
  if type(t) ~= "table" then
    t = {}
    if VulcanRunBookCharDB then VulcanRunBookCharDB.partnerTotals = t end
  end
  if totalsChecked ~= t then
    -- (From the saved file: anything damaged is dropped.)
    totalsChecked = t
    for k, v in pairs(t) do
      if type(k) ~= "string" or not ns.FiveNumbers(v) or not ns.Finite(v.at) or type(v.d) ~= "string" then
        t[k] = nil
      end
    end
  end
  return t
end

-- After a reload that's gone: the latest totals an earlier run of yours got.
local function LastSeen(sender, start, except, field)
  local key = tostring(start)
  for i, r in ipairs(ns.DB.history) do
    if i > 6 then break end
    local e = r ~= except and type(r[field or "partners"]) == "table" and r[field or "partners"][sender]
    local p = type(e) == "table" and type(e.parts) == "table" and e.parts[key]
    if type(p) == "table" and type(p.rawv) == "table" then return p.rawv end
  end
  return nil
end

-- Their log split a run yours had (a reset it found): the final word on the old
-- one comes lower, and what it lost now belongs to their new run. It's kept
-- here until that new run's first numbers arrive, so it moves instead of
-- vanishing. [sender] = { v = { elapsed, coin, loot, lootAH, xp }, d, from, at }
local moved = {}
-- Their last final word per sender (a run of theirs ended): if their next run
-- turns out to have begun before yours (their log split it off), this tells
-- how much of it was already there when yours began.
local finals = {}  -- [sender] = { from = start, v = { ... }, d, at }

-- field: "partners" (your partner), or "group" (anyone else in your group who
-- runs RunBook: shown, never part of your run's numbers).
local GROUP_MAX, GROUP_PARTS = 40, 4
-- sender: the player's key (name, with the realm when it isn't yours), for
-- your partner's entries and the group view's alike: what's kept between
-- messages goes by it, so a namesake from another realm never shares it, and
-- a player moved between the two keeps theirs.
local function UpdatePart(run, sender, start, f, final, create, noGrowth, field)
  field = field or "partners"
  local state = sender
  local list = run[field]
  local entry = type(list) == "table" and list[sender]
  if type(entry) ~= "table" or type(entry.parts) ~= "table" then entry = nil end
  local key = tostring(start)
  local part = entry and entry.parts[key]
  local isNew = part == nil
  if isNew then
    if not create then return false end
    if field == "group" then
      -- (Someone else's client can't grow your saved data without end: a few
      -- runs of theirs per run of yours, and a raid's worth of players.)
      local n = 0
      for _ in pairs(entry and entry.parts or {}) do n = n + 1 end
      if n >= GROUP_PARTS then return false end
      if not entry then
        n = 0
        for _ in pairs(type(list) == "table" and list or {}) do n = n + 1 end
        if n >= GROUP_MAX then return false end
      end
    end
    local base
    if run == ns.run then
      -- Where theirs stood when yours began (known if you were getting their
      -- numbers then; after a reload, the last ones an earlier run of yours
      -- got) - or, for one that began well before yours, from now on.
      local at = type(run.startTotals) == "table" and run.startTotals[state .. "@" .. start]
      if type(at) ~= "table" then at = LastSeen(sender, start, run, field) end
      -- (Nothing known: a run of theirs that began well before yours counts from
      -- now; one that began within a minute of yours is taken to have begun with
      -- it - a loading screen apart.)
      if type(at) ~= "table" and run.serverStart and start < run.serverStart - 60 then at = f end
      local fin = finals[state]
      if type(at) ~= "table" and run.serverStart and start < run.serverStart and fin and fin.from ~= start
          and fin.d == run.name and time() - fin.at <= 600 and type(run.startTotals) == "table" then
        -- Split off their earlier run: what that run had beyond its final word
        -- when yours began was already in this one.
        local was = run.startTotals[state .. "@" .. fin.from]
        if type(was) == "table" then
          at = {}
          for i = 1, 5 do at[i] = math.max(0, (was[i] or 0) - (fin.v[i] or 0)) end
        end
      end
      if type(at) == "table" then base = { at[1], at[2], at[3], at[4], at[5] } end
    end
    -- What their split took from your other run comes along with it.
    local m = moved[state]
    local credit
    if m and m.d == run.name and m.from ~= start and time() - m.at <= 600 then
      if base or run.ended then
        base = base or { f[1], f[2], f[3], f[4], f[5] }
        credit = {}
        for i = 1, 5 do
          credit[i] = math.min(m.v[i], base[i])
          base[i] = base[i] - credit[i]
        end
      end
      moved[state] = nil
    end
    part = { base = base, credit = credit }
  elseif not final and (part.raw or 0) > f[1] + 5 then
    return false  -- an older message (a run's time only grows)
  end
  local net = {}
  for i = 1, 5 do
    net[i] = math.max(0, f[i] - (type(part.base) == "table" and tonumber(part.base[i]) or 0))
  end
  if run.ended and (noGrowth or time() - (run.endedAt or 0) > ENDED_GRACE) then
    for i = 1, 5 do
      -- Growth after your run ended (unless it's what their split moved).
      local allowed = (part[FIELDS[i]] or 0) + (type(part.credit) == "table" and part.credit[i] or 0)
      if net[i] > allowed then return false end
    end
  end
  if not isNew and final then
    -- A correction down (their log split this run of theirs): what it took is
    -- on its way to their new run.
    local lost, any = {}, false
    for i = 1, 5 do
      lost[i] = math.max(0, (part[FIELDS[i]] or 0) - net[i])
      if lost[i] > 0 then any = true end
    end
    if any then
      local m = moved[state]
      if not m or m.d ~= run.name or m.from ~= start then m = { v = { 0, 0, 0, 0, 0 }, d = run.name } end
      for i = 1, 5 do m.v[i] = m.v[i] + lost[i] end
      m.at, m.from = time(), start
      moved[state] = m
    end
  end
  part.credit = nil
  for i = 1, 5 do part[FIELDS[i]] = net[i] end
  part.at = time()
  ns.Touch(run)
  part.raw = f[1]
  part.rawv = { f[1], f[2], f[3], f[4], f[5] }
  if isNew then
    if not entry then
      entry = { parts = {} }
      if type(run[field]) ~= "table" then run[field] = {} end
      run[field][sender] = entry
    end
    entry.parts[key] = part
  end
  ns.SumPartner(entry)
  return true
end

-- The sum over their runs is what the windows show.
function ns.SumPartner(entry)
  for _, k in ipairs(FIELDS) do entry[k] = 0 end
  for _, p in pairs(entry.parts or {}) do
    if type(p) == "table" then
      for _, k in ipairs(FIELDS) do entry[k] = entry[k] + (tonumber(p[k]) or 0) end
    end
  end
end

local ApplyStats
local TOTALS_MAX = 200

function HANDLERS.S(sender, body)
  local target, rest, start, dungeon = RunFrom(body)
  local f = Numbers(rest or "", 7) or Numbers(rest or "", 6)  -- (6: without the kill count)
  if not f or not start then return end
  for i = 1, #f do if f[i] < 0 then return end end
  -- (Still in a run of theirs that was in the copy of a run of yours that
  -- timed out while you were away: the run you're in now is in that copy too.)
  local now = ns.run
  if now and ns.inside and now.serverStart and start < now.serverStart - 60 and dungeon == now.name
      and not now.late then
    local c = ns.PartnerKeptCopy(now, msgIdent or sender, start)
    if c then ns.RejoinCopy(now, c, sender) end
  end
  if f[7] then
    ns.partnerKills[sender] = { start = start, n = f[7], d = dungeon, at = GetTime(), final = f[6] == 1 }
  end
  -- (Your partner's entries are named like the group view's: with the realm
  -- when it isn't yours, so two characters of one name never share one.)
  ApplyStats(msgIdent or sender, target, start, dungeon, f, "partners")
end

-- Their totals reach the runs of yours they belong to (see UpdatePart).
-- field "group": only your run in progress gets a new part (it's for showing).
ApplyStats = function(sender, target, start, dungeon, f, field)
  local final = f[6] == 1
  local state = sender
  if final then finals[state] = { from = start, v = { f[1], f[2], f[3], f[4], f[5] }, d = dungeon, at = time() } end
  local totals = Totals()
  totals[state .. "@" .. start] = { f[1], f[2], f[3], f[4], f[5], at = time(), d = dungeon }
  -- Kept 6 hours; at most 4 runs per player and TOTALS_MAX in all (one
  -- player's flood can't push out your partner's), the oldest going first.
  local prefix = state .. "@"
  local n, oldest, oldestAt, mineN, myOldest, myOldestAt = 0, nil, math.huge, 0, nil, math.huge
  for k, v in pairs(totals) do
    if type(v) ~= "table" or time() - (tonumber(v.at) or 0) > 6 * 3600 then
      totals[k] = nil
    else
      n = n + 1
      local at = tonumber(v.at) or 0
      if at < oldestAt then oldest, oldestAt = k, at end
      if k:sub(1, #prefix) == prefix then
        mineN = mineN + 1
        if at < myOldestAt and k ~= prefix .. start then myOldest, myOldestAt = k, at end
      end
    end
  end
  if mineN > 4 and myOldest then
    totals[myOldest] = nil
  elseif n > TOTALS_MAX and oldest then
    totals[oldest] = nil
  end
  local changed = false
  -- Your runs that already have a part for this run of theirs...
  local seen = {}
  -- (While you have a run going, what they make now goes there only: an ended
  -- one takes no more, not even what might have been on its way.)
  local busy = ns.run ~= nil
  local function visit(r, create)
    if not r or seen[r] then return end
    seen[r] = true
    if field == "group" and create and r ~= ns.run then create = false end
    if UpdatePart(r, sender, start, f, final, create, busy, field) then changed = true end
  end
  visit(ns.run, false)
  for i, r in ipairs(ns.DB.history) do
    if i > 6 then break end
    visit(r, false)
  end
  -- ...and the one it's for, if it doesn't have one yet.
  if target then
    seen[target] = nil
    visit(target, true)
  end
  if changed then ns.Fire(field == "group" and "GROUP" or "PARTNER", sender) end
end

-- Stats from someone in your group who isn't your partner: shown in the group
-- view, never added to your run's numbers. key: their name (with the realm
-- when it isn't yours).
-- field: "partners" for another character of your partner's online too (two
-- game accounts side by side): their numbers are your partner's.
function ns.GroupStats(key, body, field)
  local target, rest, start, dungeon = RunFrom(body)
  local f = Numbers(rest or "", 7) or Numbers(rest or "", 6)
  if not f or not start then return end
  for i = 1, #f do if f[i] < 0 then return end end
  ApplyStats(key, target, start, dungeon, f, field or "group")
end

function HANDLERS.N(sender, body)
  -- A note on the run they're in goes where their numbers go; one on an
  -- earlier run, to your run that matches it.
  local live, rest = body:match("^[^|]*|[^|]*|[^|]*|%d+|([01])|(.*)$")
  local run, text, _, _, wing = RunFrom(body, live ~= "1", sender)
  if live then text = rest end
  if run and text and text ~= "" then
    local _, _, note = ns.AddNote(text, sender, run)
    if note and wing then note.wing = wing end  -- (the wing it was written in)
  end
end

-- When this run's part of the copy began (server time): its start, or earlier
-- when your partner was in the copy before you (a split their log found).
function ns.CopyBegan(run)
  if not run.serverStart then return nil end
  return math.min(run.serverStart, tonumber(run.copyFrom) or math.huge)
end

-- A kill or drop (server time t) from before your run here began, while a run
-- of yours here was going (you started over, or a split, and the message was
-- held up): that run. nil otherwise.
local function EarlierRun(run, t)
  if not (run and t and ns.CopyBegan(run) and t < ns.CopyBegan(run) - 1) then return nil end
  local n = 0
  for _, r in ipairs(ns.DB.history) do
    if ns.IsOwnRun(r) then
      n = n + 1
      if n > 6 then break end
      local same
      if run.mapID and r.mapID then same = run.mapID == r.mapID else same = run.name == r.name end
      if same and r.wing == run.wing and type(r.serverStart) == "number" and type(r.serverEnd) == "number"
          and r.serverStart <= t + 1 and r.serverEnd >= t - 1 and r.serverEnd >= run.serverStart - 60 then
        return r
      end
    end
  end
  return nil
end

function HANDLERS.D(sender, body)
  local run, rest, _, _, wing = RunFrom(body)
  local f = run and (Numbers(rest, 4) or Numbers(rest, 3))
  if not f or f[1] <= 0 or f[2] <= 0 then return end
  local earlier = run == ns.run and EarlierRun(run, f[4])
  if earlier then
    -- (Looted before your run began, in the one you had going then.)
    if time() - (earlier.endedAt or 0) > 120 then return end
    run = earlier
  elseif run == ns.run and f[4] and ns.CopyBegan(run) and f[4] < ns.CopyBegan(run) - 1 then
    return  -- (looted before your run began, with no run of yours going then)
  elseif run.ended and f[4] and run.serverEnd then
    -- (Its loot time says which: before your run ended - held up on its way, up
    -- to 2 minutes - or after.)
    if f[4] > run.serverEnd + 1 or time() - (run.endedAt or 0) > 120 then return end
  elseif run.ended and time() - (run.endedAt or 0) > ENDED_GRACE then
    return  -- looted after your run ended (an older client's message: no loot time)
  end
  local d, isNew = ns.NoteDrop(run, sender, f[1], f[2], nil, "sync", nil, f[4])
  if d and isNew and wing then d.wing = wing end  -- (the wing it dropped in)
  -- Their client knew the quality; use it until the item loads here (and apply
  -- your quality setting to it).
  if d and isNew and d.q == nil and f[3] >= 0 then
    d.q = f[3]
    if not ns.KeepDrop(d.who, d.q) then
      for i = #run.drops, 1, -1 do if run.drops[i] == d then table.remove(run.drops, i) end end
    end
  end
end

function HANDLERS.B(_, body)
  local run, rest, start, _, wing = RunFrom(body)
  if not run or run ~= ns.run then return end
  -- key|id|died|came in|name (or, from tests and older builds, key|id|name).
  local key, id, at, entry, name = rest:match("^([^|]*)|(%d+)|(%d+)|(%d+)|(.*)$")
  if not key then key, id, name = rest:match("^([^|]*)|(%d+)|(.*)$") end
  if not key then id, name = rest:match("^(%d+)|(.*)$") key = "" end  -- (without a tag)
  id, at, entry = tonumber(id), tonumber(at), tonumber(entry)
  if not id or id > 2e9 then return end
  local flags = key:match("!(%a*)$") or ""
  key = key:gsub("!%a*$", "")
  -- (A name as typed or read on their side: cleaned and capped like yours.)
  name = ns.Truncate(ns.CleanText(name or ""), 100)
  -- (A kill from before your run began - held up on its way while you came
  -- in, or started over - isn't this run's: sent at once, it would have
  -- found no run, or your earlier one.)
  if at and ns.CopyBegan(run) and at < ns.CopyBegan(run) - 1 then return end
  local b = ns.AddBoss(id > 0 and id or nil, name ~= "" and name or nil, "sync", key, entry or start,
    flags:find("m") ~= nil, at)
  if b and b.src == "sync" and wing then b.wing = wing end  -- (the wing it died in)
end

-- Their log found a reset (a boss killed again) and split where they came back
-- in (`start`): their new run is in a new copy, the one you're in with them.
-- Your run, if it began before theirs, splits where you last came back in
-- (you can only have come into the new copy then). If your log already split
-- it, what they did in the new copy before you came in moves over too.
function HANDLERS.P(sender, body)
  local map, name, wing, start, sent, after = body:match("^([^|]*)|([^|]*)|([^|]*)|(%d+)|?(%d*)|?(%d*)")
  local run = ns.run
  start, sent, after = tonumber(start), tonumber(sent), tonumber(after)
  if not (run and start) then return end
  if sent and ns.ServerTime() - sent > 600 then return end  -- (held up too long to tell)
  map = tonumber(map)
  local same
  if map and run.mapID then same = run.mapID == map else same = run.name == name end
  if wing ~= "" and run.wing and wing ~= run.wing then same = false end
  if not same then return end
  -- The reset came after the boss's first death, so the time you last came in
  -- (alive, or as a ghost) must be after it (otherwise you've been in that
  -- copy since: no reset).
  local snap
  if after then snap = ns.SplitPointFor(run, after) else snap = ns.LastReturn(run) end
  local once = snap ~= nil
  -- (Only while you're inside: outside, their kill messages end your run when
  -- they show it's a new copy, and you may not even go back in.)
  if snap and once and ns.inside and (run.serverStart or 0) < start - 60 then
    ns.Print(sender .. "'s log found a reset (a boss killed again), so this is a new run from when you came "
      .. "back in.")
    if ns.SplitAtResume("partner found a reset", nil, nil, start, snap) and ns.run and #ns.run.bosses > 0 then
      -- (Their times as announced were in the old run.)
      local t = {}
      for _, b in ipairs(ns.run.bosses) do t[#t + 1] = b.name .. " " .. ns.Clock(b.t or 0) end
      ns.Print("In the new run: " .. table.concat(t, ", ") .. ".")
    end
    return
  end
  local prev = ns.LastOwnRun and ns.LastOwnRun()
  if prev and prev.endReason == "split" and start < (run.serverStart or 0)
      and math.abs((prev.serverEnd or 0) - (run.serverStart or 0)) <= 5 and ns.MoveSince then
    local n = ns.MoveSince(prev, run, start)
    if n > 0 then
      ns.Print(sender .. " was in the new copy before you: what was recorded there before you came in is "
        .. "now in this run.")
    end
  end
end

function HANDLERS.X(sender, body)
  local map, name, wing, start, diff = body:match("^([^|]*)|([^|]*)|([^|]*)|(%d+)|?(%d*)")
  local run = ns.run
  start = tonumber(start)
  if not (run and start) then return end
  -- Held up a long while (messages blocked inside): too late to start over by.
  if ns.ServerTime() - start > 120 then return end
  map, diff = tonumber(map), tonumber(diff)
  local same
  if map and run.mapID then same = run.mapID == map else same = run.name == name end
  if wing ~= "" and run.wing and wing ~= run.wing then same = false end   -- another wing
  if diff and not run.diffUnknown and (run.diff or 0) ~= diff then same = false end  -- another difficulty
  -- Your run must be older than theirs by a minute: if you started over at
  -- the same moment (or after), there's nothing to do.
  if not same or start - (run.serverStart or 0) < 60 then return end
  if ns.inside then
    if ns.ManualNew(true) then
      ns.Print(sender .. " started a new run here (/runbook new), so yours started over too.")
    end
  else
    -- You're outside: this run is over; their kills from now on go to the new
    -- one, which starts counting when you go back in.
    ns.PartnerFoundReset(start, "new")
    ns.Print(sender .. " started a new run of " .. run.name .. " (/runbook new), so yours ended; going back in "
      .. "starts the new one.")
  end
end

function HANDLERS.R(_, body)
  -- Only a dungeon you have a run of: anything else can't affect you.
  local name = body
  local key = ns.DungeonKey(name)
  local known = (ns.run and ns.DungeonKey(ns.run.name) == key) or ns.HasCopy(name)
  local last = ns.LastOwnRun()
  if last and ns.DungeonKey(last.name) == key then known = true end
  if known then ns.NoteReset(name, true) end
end

-- A player's key in the group view: the name, with the realm when it isn't
-- yours (realm: as in a message's sender, spaces and dashes taken out).
function ns.GroupKey(name, realm)
  local mine = GetNormalizedRealmName and plain(GetNormalizedRealmName()) or nil
  if realm and type(mine) == "string" and not ns.SameName(realm, (mine:gsub("[%s%-]", ""))) then
    return name .. "-" .. realm
  end
  return name
end

---------------------------------------------------------------------------
-- Your partner as a person: the characters of theirs you've synced with
-- (db.partnerChars: GroupKey(name, realm) -> realm, or true when the realm
-- isn't known). Following them onto another character of the same
-- Battle.net account adds it; setting someone else by hand (or turning it
-- off) starts over.
---------------------------------------------------------------------------
local CHARS_MAX = 20
local PartnerHeard
local function CharKey(name, realm) return ns.GroupKey(name, realm) end
local function PartnerChars()
  local db = ns.DB
  if type(db.partnerChars) ~= "table" then db.partnerChars = {} end
  local key = db.partner and CharKey(db.partner, db.partnerRealm)
  if key and db.partnerChars[key] == nil then
    -- (Your partner's realm learned: the entry without it is theirs.)
    if db.partnerRealm and db.partnerChars[db.partner] == true then db.partnerChars[db.partner] = nil end
    -- (At most CHARS_MAX: one other than this one makes room.)
    local n, other = 0, nil
    for k in pairs(db.partnerChars) do
      n = n + 1
      other = other or k
    end
    if n >= CHARS_MAX and other then db.partnerChars[other] = nil end
  end
  -- (Your partner's own entry is always as set: a damaged one is put right.)
  if key then db.partnerChars[key] = db.partnerRealm or true end
  return db.partnerChars
end

local function ShortOf(key) return (key:match("^([^%-]+)")) or key end

-- Your partner's characters you've had messages from (GroupKey -> true): only
-- these are followed without a BattleTag (one typed by hand may be on a
-- realm you guessed).
PartnerHeard = function()
  local db = ns.DB
  if type(db.partnerHeard) ~= "table" then db.partnerHeard = {} end
  local n = 0
  for k, v in pairs(db.partnerHeard) do
    n = n + 1
    if type(k) ~= "string" or v ~= true or n > CHARS_MAX then db.partnerHeard[k] = nil end
  end
  return db.partnerHeard
end

-- The realm saved with one of your partner's characters: a realm, or nil
-- when it isn't known (only when the game doesn't give yours: then whoever
-- is heard first, as everywhere else).
local function CharRealm(_, r)
  if r ~= true then return r end
  return nil
end

-- The realm of one of your partner's characters by that name, if there's
-- exactly one (for switching back to it by name).
function ns.PartnerCharRealm(name)
  local found
  for k, r in pairs(type(ns.DB.partnerChars) == "table" and ns.DB.partnerChars or {}) do
    if ns.SameName(ShortOf(k), name) and type(r) == "string" then
      if found then return nil end
      found = r
    end
  end
  return found
end

-- One of your partner's characters? realm: theirs, when known (the same
-- name on another realm is someone else).
function ns.IsPartnerChar(name, realm)
  if type(name) ~= "string" or not ns.DB.partner then return false end
  for k, r in pairs(PartnerChars()) do
    r = CharRealm(k, r)
    if ns.SameName(ShortOf(k), name) and not (realm and type(r) == "string" and not ns.SameName(r, realm)) then
      return true
    end
  end
  return false
end

-- Your partner is online with you: their character (by name and realm) in
-- your group and connected. (When the group's names can't be read: heard
-- from in the last 5 minutes - messages wait during boss fights.)
local function PartnerHere()
  local db = ns.DB
  local readable = false
  local mine = ns.MyRealm()
  for _, unit in ipairs(ns.GroupUnits()) do
    if not ns.IsPlayerUnit(unit) then
      local n, r = UnitName(unit)
      n, r = ns.ShortName(plain(n)), plain(r)
      r = (type(r) == "string" and r ~= "") and r:gsub("[%s%-]", "") or mine
      if n and n ~= (UNKNOWNOBJECT or "Unknown") then readable = true end
      if n and ns.SameName(n, db.partner) and not (db.partnerRealm and r and not ns.SameName(r, db.partnerRealm)) then
        local on = UnitIsConnected and plain(ns.Call(UnitIsConnected, unit))
        if on ~= false then return true end
      end
    end
  end
  if readable then return false end
  for who, at in pairs(ns.partnersSeen) do
    if ns.IsPartnerChar(who) and GetTime() - at < 300 then return true end
  end
  return false
end

-- Your run's partner numbers are your partner's characters' only: anyone
-- else's (a partner you changed from, or turned off) go to the group view, so
-- they're no longer in your Together line.
function ns.ReconcilePartners(run)
  if type(run) ~= "table" or type(run.partners) ~= "table" then return end
  -- (An entry's realm is in its name; none there: yours.)
  local function RealmOf(k) return k:match("%-(.+)$") or ns.MyRealm() end
  for k, e in pairs(run.partners) do
    if type(k) == "string" and not ns.IsPartnerChar(ShortOf(k), RealmOf(k)) then
      if type(run.group) ~= "table" then run.group = {} end
      if run.group[k] == nil then run.group[k] = e end
      run.partners[k] = nil
    end
  end
  -- And your partner's numbers that were in the group view are your partner's.
  if type(run.group) == "table" and ns.DB.partner then
    for gk, e in pairs(run.group) do
      if type(gk) == "string" and ns.IsPartnerChar(ShortOf(gk), RealmOf(gk)) then
        local have = run.partners[gk]
        if have == nil then
          run.partners[gk] = e
        elseif type(have) == "table" and type(have.parts) == "table" and type(e) == "table"
            and type(e.parts) == "table" then
          for key, part in pairs(e.parts) do
            if have.parts[key] == nil then have.parts[key] = part end
          end
          ns.SumPartner(have)
        end
        run.group[gk] = nil
      end
    end
  end
end

---------------------------------------------------------------------------
-- Friends who run RunBook, heard while you have no partner: after FRIEND_WAIT
-- seconds, the only one still in your group becomes your partner, and what
-- they sent meanwhile (drops, notes, kills) is taken then. With more than
-- one, none does (you're told to pick) while you're in that group. Kept with
-- your character's data, so a /reload doesn't lose it.
---------------------------------------------------------------------------
local FRIEND_WAIT = 35
local FRIEND_HELD = 50
local function FriendsMany() return VulcanRunBookCharDB ~= nil and VulcanRunBookCharDB.friendsMany == true end
-- { first = time(), list = { [key] = { name, realm, sender, held = { { kind, body } } } } }, checked.
local function Wait()
  local w = VulcanRunBookCharDB and VulcanRunBookCharDB.friendWait
  if type(w) ~= "table" or type(w.first) ~= "number" or w.first ~= w.first or w.first > time() + 60
      or type(w.list) ~= "table" then
    if VulcanRunBookCharDB then VulcanRunBookCharDB.friendWait = nil end
    return nil
  end
  for k, f in pairs(w.list) do
    if type(k) ~= "string" or type(f) ~= "table" or type(f.name) ~= "string" or type(f.sender) ~= "string"
        or (f.realm ~= nil and type(f.realm) ~= "string") or type(f.held) ~= "table" then
      w.list[k] = nil
    else
      for i = #f.held, 1, -1 do
        local m = f.held[i]
        if type(m) ~= "table" or type(m.kind) ~= "string" or type(m.body) ~= "string" then table.remove(f.held, i) end
      end
    end
  end
  return w
end
local function FriendHeard(name, realm, sender, kind, body)
  if FriendsMany() or not VulcanRunBookCharDB then return end
  local w = Wait()
  if not w then
    w = { first = time(), list = {} }
    VulcanRunBookCharDB.friendWait = w
  end
  local key = ns.GroupKey(name, realm)
  local f = w.list[key] or { held = {} }
  f.name, f.realm, f.sender = name, realm, sender
  if kind ~= "S" and #f.held < FRIEND_HELD then f.held[#f.held + 1] = { kind = kind, body = body } end
  w.list[key] = f
end

-- What a friend sent while they were waited on, now that they're your partner.
local function TakeHeld(f)
  for i = 1, math.min(#f.held, FRIEND_HELD) do
    local m = f.held[i]
    local handler = HANDLERS[m.kind]
    if handler then
      msgIdent = ns.GroupKey(f.name, f.realm)
      local ok, err = pcall(handler, f.name, m.body)
      if not ok then ns.Log("error", "held %s: %s", m.kind, tostring(err)) end
    end
  end
end

ns.Listen("TICK", function()
  -- (Several friends, and who was heard in a bigger group: for that group only.)
  if not InGroup() and VulcanRunBookCharDB then
    VulcanRunBookCharDB.friendsMany, VulcanRunBookCharDB.bigGroup = nil, nil
  end
  local w = Wait()
  if not w or time() - w.first < FRIEND_WAIT then return end
  if ns.DB.partner or not InGroup() then
    VulcanRunBookCharDB.friendWait = nil
    return
  end
  local here = {}
  for key, f in pairs(w.list) do
    if not ns.SenderInGroup or ns.SenderInGroup(f.sender) then here[#here + 1] = key end
  end
  table.sort(here)
  if #here == 1 then
    local f = w.list[here[1]]
    ns.SetPartner(f.name, f.realm, f.sender)  -- (takes what they sent meanwhile)
    ns.Print(f.name .. " (a friend of yours) also runs RunBook, so you'll see each other's gold, drops and notes. "
      .. "(/runbook partner <name> to change.)")
  else
    VulcanRunBookCharDB.friendWait = nil
    if #here > 1 then
      VulcanRunBookCharDB.friendsMany = true
      ns.Print("Friends of yours here run RunBook (" .. table.concat(here, ", ") .. "), so none was picked as "
        .. "your sync partner: /runbook partner <name> to pick one.")
    end
  end
end)

-- Your partner changed (set by hand, cleared, or picked up on their own).
-- samePerson: they're on another character of the one you had (the same
-- Battle.net account): it's added to their characters. Otherwise their
-- characters start over, and anyone else's numbers in your run go to the
-- group view. Their BattleTag is looked up again (sender: their "Name-Realm"
-- when a message of theirs made them your partner). A friend you were
-- waiting on: what they sent meanwhile is taken now.
function ns.PartnerChanged(sender, samePerson)
  local db = ns.DB
  if not samePerson then
    db.partnerChars = {}
    db.partnerHeard = {}
    db.partnerTag = nil
  end
  PartnerChars()
  tagAsked = {}
  for who in pairs(ns.partnersSeen) do
    if not ns.IsPartnerChar(who) then ns.partnersSeen[who] = nil end
  end
  if sender and ns.FriendInfo and not db.partnerTag then
    local _, tag = ns.FriendInfo(sender)
    db.partnerTag = tag
  end
  local w = Wait()
  local waited = w and db.partner and w.list[ns.GroupKey(db.partner, db.partnerRealm)]
  if VulcanRunBookCharDB then VulcanRunBookCharDB.friendWait, VulcanRunBookCharDB.friendsMany = nil, nil end
  ns.ReconcilePartners(ns.run)
  if waited then TakeHeld(waited) end
  ns.Fire("PARTNER", db.partner)
end

function ns.SetPartner(name, realm, sender, samePerson)
  ns.DB.partner, ns.DB.partnerRealm = name, realm
  ns.PartnerChanged(sender, samePerson)
end

-- Only your group's channels: a whisper (from anyone, anywhere) can't start
-- your runs over or end them.
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
-- [key] = true: heard in a group of more than two (not a friend). Kept with
-- your character's data while you're in a group (a /reload too).
local function BigGroup()
  local b = VulcanRunBookCharDB and VulcanRunBookCharDB.bigGroup
  if type(b) ~= "table" then
    b = {}
    if VulcanRunBookCharDB then VulcanRunBookCharDB.bigGroup = b end
  end
  local n = 0
  for k, v in pairs(b) do
    n = n + 1
    if type(k) ~= "string" or v ~= true or n > 80 then b[k] = nil end
  end
  return b
end

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
  if not (ns.DB and ns.DB.sync) then return end
  prefix, text, channel, sender = plain(prefix), plain(text), plain(channel), plain(sender)
  if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" then return end
  if type(channel) == "string" and not GROUP_CHANNELS[channel] then return end
  if ns.SenderInGroup and not ns.SenderInGroup(sender) then return end
  local name = ns.ShortName(sender)
  if not name or name == ns.PlayerName() then return end
  local realm = sender:match("%-(.+)$")
  realm = realm and realm:gsub("[%s%-]", "") or nil
  local kind, ver, token, body = text:match("^(%a)(%d+)|(%x+)|(.*)$")
  ver = tonumber(ver)
  if not kind or not ver then return end
  if token == ns.token then return end  -- our own message, echoed back
  -- Your partner: the one you set, or the only other player in a two-person
  -- group, or a friend of yours (friends list or Battle.net) in any group.
  -- Everyone else's stats go to the group view only, with a one-time note in
  -- a small group in case they're who you meant.
  local db = ns.DB
  ns.heardFrom[name] = true
  local key = ns.GroupKey(name, realm)
  local current = ver <= PROTOCOL and ver >= OLDEST_ACCEPTED
  local function Others()
    if kind == "S" and current then ns.GroupStats(key, body) end
  end
  if not db.partner then
    local size = ns.Call(GetNumGroupMembers) or 0
    local two = size == 2 and not (IsInRaid and IsInRaid())
    -- (In a two-person group only asked about someone first heard in a bigger one.)
    local friend = (not two or BigGroup()[key]) and ns.FriendInfo and ns.FriendInfo(sender, two)
    -- Another version: no sync with them, so never picked.
    if (friend or two) and not current then
      Notice(name, ver)
      return
    end
    if friend and not two then
      -- A friend of yours: your partner if they're the only one here who runs
      -- RunBook (decided once everyone's numbers have had time to come in).
      FriendHeard(name, realm, sender, kind, body)
      Others()
      return
    end
    -- (Someone heard in a bigger group who isn't a friend - a dungeon-finder
    -- group thinning out - isn't picked when it's down to the two of you.)
    if not two or (BigGroup()[key] and not friend) then
      if not two then BigGroup()[key] = true end
      Others()
      -- Not just the two of you: don't guess, but say how to set it.
      local noted = two and ("2:" .. name) or name
      if size <= 5 and not otherNoticed[noted] then
        otherNoticed[noted] = true
        ns.Print(name .. " runs RunBook too. If that's your duo partner, type /runbook partner " .. name
          .. " to sync with them.")
      elseif size > 5 and not otherNoticed["*raid"] then
        -- (A raid: one note, not one per RunBook user in it.)
        otherNoticed["*raid"] = true
        ns.Print(name .. " and maybe others here run RunBook. To sync with your duo partner, type "
          .. "/runbook partner <name>.")
      end
      return
    end
    ns.SetPartner(name, realm, sender)
    ns.Print(name .. " also runs RunBook, so you'll see each other's gold, drops and notes. (/runbook partner "
      .. "<name> to change.)")
  elseif not ns.SameName(db.partner, name)
      or (realm and type(db.partnerRealm) == "string" and not ns.SameName(realm, db.partnerRealm)) then
    -- Your partner on another character (the same Battle.net account): you
    -- sync with that one now. (Not while your partner's character is online
    -- with you: two game accounts on one Battle.net account, side by side.)
    local tag = type(db.partnerTag) == "string" and current and not PartnerHere() and ns.FriendInfo
      and select(2, ns.FriendInfo(sender))
    local known = current and ns.IsPartnerChar(name, realm) and PartnerHeard()[ns.GroupKey(name, realm)] == true
    if known and PartnerHere() then
      -- Another character of your partner's, online with this one: their
      -- numbers are your partner's too (nothing else of theirs is used).
      if kind == "S" then ns.GroupStats(key, body, "partners") end
      return
    end
    if known or (tag and tag == db.partnerTag) then
      local was = ns.GroupKey(db.partner, db.partnerRealm)
      ns.SetPartner(name, realm, sender, true)
      ns.Print(was .. " is on " .. name .. " now (the same Battle.net account), so you sync with " .. name
        .. ". (/runbook partner " .. was .. " to switch back.)")
    else
      Others()
      -- (Another player, or the same name on another realm: named in full then.)
      if ns.SameName(db.partner, name) then name = sender end
      local size = ns.Call(GetNumGroupMembers) or 0
      -- (In a raid too when it's a friend of yours: they may be who you meant.)
      if not otherNoticed[name] and (size <= 5 or (ns.FriendInfo and ns.FriendInfo(sender))) then
        otherNoticed[name] = true
        -- (Your partner isn't here: this may be them on another character.)
        local alt = not PartnerHere() and (", or /runbook partner " .. name .. " alt if that's " .. db.partner
          .. " on another character") or ""
        ns.Print(name .. " also runs RunBook; your sync partner is " .. db.partner .. ". (/runbook partner "
          .. name .. " to switch" .. alt .. ".)")
      end
      return
    end
  elseif db.partnerTag == nil and not tagAsked[name] and ns.FriendInfo then
    -- (Their BattleTag, once, so their other characters are known too.)
    tagAsked[name] = true
    local _, tag = ns.FriendInfo(sender)
    if tag then db.partnerTag = tag end
  end
  if ver > PROTOCOL or ver < OLDEST_ACCEPTED then
    Notice(name, ver)
    return
  end
  local handler = HANDLERS[kind]
  if not handler then return end
  -- (Your partner set without a realm: the first one heard is theirs.)
  if realm and db.partnerRealm == nil then
    db.partnerRealm = realm
    PartnerChars()
  end
  ns.partnersSeen[name] = GetTime()
  PartnerHeard()[key] = true
  ns.Log("sync", "from %s: %s", name, kind)
  msgIdent = key
  handler(name, body)
end)

---------------------------------------------------------------------------
-- When to send
---------------------------------------------------------------------------
ns.Listen("READY", function()
  if ns.RegisterPrefix then
    -- 0 = registered, 1 = already registered (also fine); older clients: true.
    local ok, result = pcall(ns.RegisterPrefix, PREFIX)
    registered = ok and (result == nil or result == true or result == 0 or result == 1) or false
  end
  -- Messages saved at the last logout or /reload, first in line.
  local saved = VulcanRunBookCharDB and VulcanRunBookCharDB.syncQueue
  if VulcanRunBookCharDB then VulcanRunBookCharDB.syncQueue = nil end
  if type(saved) == "table" then
    local back = {}
    for _, q in ipairs(saved) do
      if type(q) == "table" and type(q.kind) == "string" and type(q.msg) == "string" and #q.msg <= 255
          and type(q.at) == "number" and time() - q.at <= HOLD_SECONDS then
        back[#back + 1] = { kind = q.kind, key = tonumber(q.key), msg = q.msg, at = q.at }
      end
    end
    for i = #back, 1, -1 do table.insert(queue, 1, back[i]) end
    while #queue > QUEUE_MAX do table.remove(queue) end
  end
end)

ns.Listen("TICK", function(count)
  if not InGroup() then
    -- (Kept a while: a group that breaks for a moment - a disconnect, a
    -- re-invite - still gets them.)
    for i = #queue, 1, -1 do
      if time() - (queue[i].at or 0) > HOLD_SECONDS then table.remove(queue, i) end
    end
    return
  end
  -- Your numbers go out when they change (at most once a second), and every
  -- SEND_EVERY seconds anyway.
  local run = ns.run
  if run then
    local sig = table.concat({ run.serverStart or 0, run.coin, run.loot, run.lootAH, run.xp, #run.bosses }, ":")
    if sig ~= lastSig or count % SEND_EVERY == 0 then
      lastSig = sig
      ns.SyncStats()
    end
  end
  ns.FlushSync()
end)

ns.Listen("RUN_START", function(run)
  -- Where your partner's runs here stood as yours began.
  run.startTotals = {}
  for k, v in pairs(Totals()) do
    if type(v) == "table" and v.d == run.name then run.startTotals[k] = v end
  end
  ns.SyncStats(run)
end)
ns.Listen("BOSS", function(b, source)
  ns.SyncStats()
  if source ~= "sync" and ns.run and b then ns.SyncBoss(ns.run, b) end
end)
-- A run's final numbers, kept or not: a run that a split left empty and too
-- short to keep still tells your partner's log it ended with nothing (what
-- it had moved to the new run, which your partner's log also counts).
ns.Listen("RUN_END", function(run) ns.SyncStats(run) end)
-- Stepping outside: your run time as it stands (it doesn't grow outside), so
-- a log whose run ends before yours does still has it.
ns.Listen("RUN_LEFT", function() ns.SyncStats() end)
-- A run you reopened (/runbook start) gets nothing your partner made while it
-- was ended: their numbers count from where they stand now.
ns.Listen("RUN_REOPEN", function(run)
  local totals = Totals()
  -- Runs of theirs that began while yours was ended count from now, too.
  run.startTotals = {}
  for k, v in pairs(totals) do
    if type(v) == "table" and v.d == run.name then run.startTotals[k] = v end
  end
  for _, field in ipairs({ "partners", "group" }) do
    for name, entry in pairs(type(run[field]) == "table" and run[field] or {}) do
      if type(entry) == "table" and type(entry.parts) == "table" then
        for key, part in pairs(entry.parts) do
          local now = totals[name .. "@" .. key]  -- (entries are named by the player's key)
          if type(part) == "table" and type(now) == "table" and type(part.rawv) ~= "table" then
            part.base = { now[1], now[2], now[3], now[4], now[5] }  -- nothing counted yet: from now
            part.rawv = { now[1], now[2], now[3], now[4], now[5] }
          elseif type(part) == "table" and type(now) == "table" then
            part.base = part.base or { 0, 0, 0, 0, 0 }
            for i = 1, 5 do
              part.base[i] = (tonumber(part.base[i]) or 0) + math.max(0, (now[i] or 0) - (part.rawv[i] or 0))
            end
            part.rawv = { now[1], now[2], now[3], now[4], now[5] }
          end
        end
      end
    end
  end
  -- (Your partner may have changed while it was ended: after the counting
  -- above, which goes by where each one's numbers were.)
  ns.ReconcilePartners(run)
end)
ns.Listen("ENCOUNTER_OVER", function() ns.FlushSync() end)
-- Logging out or reloading: what's waiting goes out now, not never.
ns.On("PLAYER_LOGOUT", function()
  if ns.run then ns.SyncStats() end
  ns.FlushSync()
  -- What couldn't go (throttled, a boss fight): saved, and sent after the
  -- /reload or the next login if it isn't too old by then.
  if VulcanRunBookCharDB then
    local keep = {}
    for _, q in ipairs(queue) do keep[#keep + 1] = { kind = q.kind, key = q.key, msg = q.msg, at = q.at } end
    VulcanRunBookCharDB.syncQueue = #keep > 0 and keep or nil
  end
end)

function ns.SyncQueueSize() return #queue end
function ns.SyncRegistered() return registered end
