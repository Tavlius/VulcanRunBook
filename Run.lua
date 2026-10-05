-- RunBook: when a run starts, resumes and ends, and the run clock.
--
-- A run starts when you zone into a dungeon or raid. Leaving and coming back
-- (a repair trip, a corpse run) resumes it. It ends when:
--   * you enter a different dungeon (or Scarlet Monastery wing, or
--     difficulty), including by a portal from one instance into another,
--   * the dungeon is reset (you saw the message, or your partner's RunBook did),
--   * a boss you killed before your last trip outside dies again (so the
--     dungeon was reset without you seeing it),
--   * you've been outside, alive, for 30 minutes (2 hours for raids),
--   * you type /runbook end (or /runbook new to start over).
-- Forever keeps creature IDs secret inside instances, so two copies of the same
-- dungeon can't be told apart directly; those rules stand in for that.
--
-- Run time counts while you're inside, plus up to 10 minutes of running back
-- as a ghost after dying inside. Repair trips and breaks outside don't count.
local _, ns = ...
local plain = ns.plain

ns.inside = false     -- inside the run's instance right now
local lastTick
local tickCount = 0
local wingCheck       -- { at, split } re-read the wing once the map has settled
local zonedAt = -math.huge  -- GetTime() of the last loading screen into a zone (not a login or reload)

-- Instances whose wings are separate copies sharing one instance ID (Classic's
-- Scarlet Monastery and Dire Maul). In any other dungeon, floors and map
-- changes never matter.
local MULTI_WING = { [189] = true, [429] = true }
local MULTI_WING_NAMES = { ["Scarlet Monastery"] = true, ["Dire Maul"] = true }
-- Wings read from the map: only Scarlet Monastery, where each wing is one map.
-- Dire Maul's wings span several floors each, so a floor can't name its wing:
-- there, /runbook new when you switch. (Stratholme's two sides and Lower/Upper
-- Blackrock Spire are one copy each in Classic, so they're one run.)
local READ_WING = { [189] = true }
local READ_WING_NAMES = { ["Scarlet Monastery"] = true }
-- Classic's Scarlet Monastery wing maps, for when the map has no wing name.
local SM_WINGS = { [302] = "Graveyard", [303] = "Library", [304] = "Armory", [305] = "Cathedral" }

---------------------------------------------------------------------------
-- Where am I?
---------------------------------------------------------------------------
-- The wing you're in: its map (each wing has its own, even when the wings are
-- listed as "floors" of one map group), and its name - the map's own, or its
-- floor name in that group.
local function ReadWing(dungeon)
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local ui = ns.Call(C_Map.GetBestMapForUnit, "player")
  if type(ui) ~= "number" then return nil end
  local info = ns.Call(C_Map.GetMapInfo, ui)
  local wingName = type(info) == "table" and plain(info.name) or nil
  if type(wingName) ~= "string" then wingName = nil end
  local group = ns.Call(C_Map.GetMapGroupID, ui)
  -- Only a map of the dungeon itself: right after a loading screen the map can
  -- still be the zone outside, which isn't a wing.
  -- (By name only if it's a dungeon map: "Scarlet Monastery Entrance" is the
  -- small outdoor map at the doors.)
  local kind = type(info) == "table" and plain(info.mapType) or nil
  local dungeonMap = type(kind) ~= "number" or kind == 4 or kind == 6
  local ofDungeon = SM_WINGS[ui] or (type(group) == "number" and group > 0)
    or (dungeonMap and wingName and dungeon and wingName:find(dungeon, 1, true))
  if not ofDungeon then return nil end
  if type(group) == "number" and group > 0 and C_Map.GetMapGroupMembersInfo then
    local members = ns.Call(C_Map.GetMapGroupMembersInfo, group)
    if type(members) == "table" then
      for _, m in ipairs(members) do
        if type(m) == "table" and plain(m.mapID) == ui and type(plain(m.name)) == "string" then
          wingName = plain(m.name)
        end
      end
    end
  end
  if (not wingName or wingName:find("Scarlet Monastery", 1, true)) and SM_WINGS[ui] then wingName = SM_WINGS[ui] end
  return "m" .. ui, wingName
end

-- Map data inside instances may be restricted (reading it can throw); then
-- the wing just can't be read.
local function Wing(dungeon)
  local ok, wing, wingName = pcall(ReadWing, dungeon)
  if not ok then return nil end
  return wing, wingName
end

local function IsMultiWing(mapID, name)
  if mapID then return MULTI_WING[mapID] == true end
  return MULTI_WING_NAMES[name] == true
end

-- Returns the dungeon or raid you're in as { map, mapID, name, label, wing,
-- diff, diffName, kind }; nil outside; or nil, "unknown" if you're in an
-- instance that can't be read right now (then nothing should change).
function ns.CurrentInstance()
  if not IsInInstance or not GetInstanceInfo then return nil end
  local inInstance, kind = IsInInstance()
  inInstance, kind = plain(inInstance), plain(kind)
  if inInstance == nil then return nil, "unknown" end
  if not inInstance then return nil end
  if kind ~= nil and kind ~= "party" and kind ~= "raid" then return nil end  -- battleground, arena, scenario
  local name, itype, diff, diffName, _, _, _, mapID = GetInstanceInfo()
  name, itype, diff, diffName, mapID = plain(name), plain(itype), plain(diff), plain(diffName), plain(mapID)
  if type(name) ~= "string" or name == "" then return nil, "unknown" end
  kind = (itype == "party" or itype == "raid") and itype or kind
  if kind ~= "party" and kind ~= "raid" then return nil end
  if type(mapID) ~= "number" then mapID = nil end
  local wing, label = nil, name
  if (mapID and READ_WING[mapID]) or (not mapID and READ_WING_NAMES[name]) then
    local wingName
    wing, wingName = Wing(name)
    -- "Scarlet Monastery - Graveyard", but never "Dire Maul - Dire Maul".
    if wingName and not name:find(wingName, 1, true) and not wingName:find(name, 1, true) then
      label = name .. " - " .. wingName
    elseif wing then
      label = name .. " - map " .. wing:sub(2)  -- no name for it: still told apart
    end
  end
  return {
    map = mapID or name, mapID = mapID, name = name, label = label, wing = wing, multiWing = IsMultiWing(mapID, name),
    diff = type(diff) == "number" and diff or 0, diffUnknown = type(diff) ~= "number" or nil,
    diffName = type(diffName) == "string" and diffName or nil,
    kind = kind,
  }
end

-- Same dungeon and difficulty? IDs are compared when both have them; otherwise
-- names, so an ID that can't be read doesn't split a run. Wings are checked
-- separately (only on the way in). A difficulty that can't be read matches
-- any (the run takes it once it can be read).
function ns.SameDungeon(run, inst)
  if run.mapID and inst.mapID then
    if run.mapID ~= inst.mapID then return false end
  elseif run.name ~= inst.name then
    return false
  elseif inst.mapID and not run.mapID and run.name == inst.name then
    -- (Its ID couldn't be read when it started: it takes it now, so it's
    -- filed with the other runs of this dungeon.)
    run.mapID, run.map = inst.mapID, inst.map
    if ns.ClearCache then ns.ClearCache() end
  end
  if inst.diffUnknown then return true end
  if run.diffUnknown then
    run.diff, run.diffName, run.diffUnknown = inst.diff, inst.diffName, nil
    return true
  end
  return (run.diff or 0) == (inst.diff or 0)
end

local function OtherWing(run, inst)
  return run.wing ~= nil and inst.wing ~= nil and run.wing ~= inst.wing
end

local function IsDead()
  return plain(UnitIsDeadOrGhost("player")) == true
end

-- The run you mean by "this run": the one going, unless it's one you haven't
-- gone into yet (made for your partner's new copy while you were outside) -
-- then your last one, which you were just in.
function ns.RunOrLast()
  if ns.run and not ns.run.entryOnEntry then return ns.run end
  return ns.LastOwnRun() or ns.run
end

-- Your last return into the copy: alive, or as a ghost if that came later.
function ns.LastReturn(run)
  local a, g = run.resumeSnap, run.ghostSnap
  if a and g then return (g.server > a.server) and g or a end
  return a or g
end

-- Where a boss that died at server time st and died again splits the run:
-- the last time you came back in alive after that death, else a ghost return
-- after it (the copy was reset while you were dead outside). nil: no return
-- since - the same kill. (Alive first: a reset with your corpse inside is
-- the less likely one. A later return stays in the new run, so another boss
-- killed twice splits it again there.)
function ns.SplitPointFor(run, st)
  st = st or 0
  if run.resumeSnap and st < run.resumeSnap.server then return run.resumeSnap end
  if run.ghostSnap and st < run.ghostSnap.server then return run.ghostSnap end
  return nil
end

function ns.InRun()
  return ns.run ~= nil and ns.inside
end

-- Running back to the dungeon as a ghost after dying in it.
function ns.GhostRunning()
  local run = ns.run
  return run ~= nil and not ns.inside and run.ghost == true and run.leftAt ~= nil
    and time() - run.leftAt <= ns.GHOST_MAX and IsDead()
end

local function Timeout(run)
  return run.kind == "raid" and ns.RAID_TIMEOUT or ns.RUN_TIMEOUT
end

-- A run worth keeping: a minute or more, or anything happened in it. (Not
-- one you never went into: started for your partner's new copy.)
local function WorthKeeping(run)
  if run.entryOnEntry then return false end
  if run.elapsed >= ns.MIN_KEEP_SECONDS or #run.bosses > 0 or #run.drops > 0 or #run.deaths > 0
      or #run.wipes > 0 or #run.notes > 0 or run.coin > 0 or run.xp > 0 or run.loot > 0 or run.unpriced > 0
      or next(run.pending or {}) ~= nil then
    return true
  end
  -- Your partner's numbers count only if they got something (their client
  -- sends zeros the moment they zone in).
  for _, p in pairs(run.partners) do
    if (p.coin or 0) > 0 or (p.loot or 0) > 0 or (p.xp or 0) > 0 then return true end
  end
  return false
end

local function Say(msg)
  if not ns.DB.quiet then ns.Print(msg) end
end

local function Resets()
  if type(VulcanRunBookCharDB.resets) ~= "table" then VulcanRunBookCharDB.resets = {} end
  return VulcanRunBookCharDB.resets
end

---------------------------------------------------------------------------
-- Visits and resume points
--
-- Each time you come back in starts a new visit, and everything recorded
-- carries the visit it happened in (`v`). If it later turns out you came back
-- into a new copy of the dungeon (a boss you'd killed dies again, a reset
-- message arrives late, or it's another wing), everything from that visit on
-- becomes a new run, and the old run ends where you left it.
---------------------------------------------------------------------------
-- Back from a ghost run: where this entry began, in case it turns out to be
-- another wing (then the run splits here, not at the last return). Session only.
local ghostEntry  -- { run, snap }

local function Snap(run)
  return {
    visit = run.visit, elapsed = run.elapsed, coin = run.coin, loot = run.loot, lootAH = run.lootAH, xp = run.xp,
    unpriced = run.unpriced, wall = time(), server = ns.ServerTime(),
  }
end

local function Snapshot(run)
  run.visit = (run.visit or 1) + 1
  run.resumeSnap = Snap(run)
  run.ghostSnap = nil  -- (a return alive comes after any ghost return)
end

---------------------------------------------------------------------------
-- Start / end
---------------------------------------------------------------------------
-- entryAt: server time you entered (for the cap; default now; false = same
-- instance as before, no new entry)
local function Begin(run, entryAt)
  ns.run = run
  VulcanRunBookCharDB.run = run
  ns.inside = true
  run.lastIn = time()
  if entryAt ~= false then ns.AddEntry(entryAt) end
  run.counted = (entryAt ~= false) or nil  -- this start added a cap entry
  ns.SnapshotMembers()
  ns.Fire("RUN_START", run)
end

-- Scarlet Monastery / Dire Maul when the wing can't be read: say once per run
-- that switching wings needs /runbook new.
local hintedWings = {}  -- [dungeon] = true: said this session
local function MultiWingHint(run, inst)
  if inst.multiWing and not inst.wing and not run.hinted and not hintedWings[inst.name] then
    run.hinted, hintedWings[inst.name] = true, true
    ns.Print(inst.name .. "'s wings can't be told apart here. If you switch wings, type /runbook new.")
  end
end

---------------------------------------------------------------------------
-- Copies you left that may still be there (not reset, not timed out): going
-- back into one is a new run but not a new instance for the cap.
-- VulcanRunBookCharDB.copies = { { name, diff, kind, wing, left = server time you
-- left it (nil while still inside) } }
---------------------------------------------------------------------------
local function Copies()
  local c = VulcanRunBookCharDB.copies
  if type(c) ~= "table" then
    c = {}
    VulcanRunBookCharDB.copies = c
  end
  return c
end

-- (A wing that couldn't be read isn't taken for one that was: better to count
-- an instance twice than to miss one.)
-- (A difficulty that couldn't be read matches any.)
local function SameCopyKey(c, x)
  return type(c) == "table" and c.name == x.name and c.wing == x.wing
    and (c.diffUnknown or x.diffUnknown or (c.diff or 0) == (x.diff or 0))
end

-- The bosses that died in a run's copy (its own kills, and those of earlier
-- runs in the same copy): one killed again there means the copy was reset.
local function CopyKillsOf(run)
  local out = {}
  for _, k in ipairs(type(run.copyKills) == "table" and run.copyKills or {}) do out[#out + 1] = k end
  for _, b in ipairs(run.bosses) do
    if not b.anonymous and (b.id or b.name) and type(b.st) == "number" and #out < 40 then
      out[#out + 1] = { id = b.id, name = b.name, st = b.st }
    end
  end
  return out
end

-- Your partners' runs that were in this run's copy: "name@start" -> true.
local function PartnerStarts(run)
  local out, n = {}, 0
  for name, entry in pairs(type(run.partners) == "table" and run.partners or {}) do
    if type(name) == "string" and type(entry) == "table" and type(entry.parts) == "table" then
      for key in pairs(entry.parts) do
        if tonumber(key) and n < 8 then out[name .. "@" .. tonumber(key)] = true n = n + 1 end
      end
    end
  end
  return out
end

-- Your partner is still in a run of theirs that was in the copy of a run of
-- yours that timed out (you were away too long, they stayed inside): the
-- run you're in now is in that copy too. Taken out of the copies you
-- remember. nil otherwise.
function ns.PartnerKeptCopy(run, sender, start)
  for i, c in ipairs(Copies()) do
    if SameCopyKey(c, run) and type(c.partners) == "table" and c.partners[sender .. "@" .. tostring(start)]
        and type(c.left) == "number" and c.left < (run.serverStart or 0)
        and (Resets()[ns.DungeonKey(c.name)] or 0) < c.left then
      table.remove(Copies(), i)
      if type(c.kills) == "table" then ns.FixItems(c.kills) end
      return c
    end
  end
  return nil
end

-- This run turns out to carry on in copy `c` (see PartnerKeptCopy): it began
-- part way through it (its clear time isn't a whole one), and coming back
-- into the same copy doesn't count toward the instance cap again.
function ns.RejoinCopy(run, c, who)
  if type(c.kills) == "table" and #c.kills > 0 then run.copyKills = c.kills end
  run.late = true
  run.pendingEntry = nil
  if run.counted then
    local list = ns.DB.entries
    for i = #list, 1, -1 do
      if type(list[i]) == "number" and math.abs(list[i] - (run.serverStart or 0)) <= 5 then
        table.remove(list, i)
        break
      end
    end
    run.counted = nil
  end
  ns.Print(ns.CharLabel(who) .. " stayed in this copy of " .. tostring(run.name) .. " while you were away, so this run "
    .. "carries on in it: it doesn't count toward the instance cap again, and its clear time isn't a whole one.")
  ns.Fire("HISTORY_CHANGED")
end

function ns.RememberCopy(run, left)
  local list = Copies()
  for i = #list, 1, -1 do
    if type(list[i]) ~= "table" or SameCopyKey(list[i], run) then table.remove(list, i) end
  end
  -- A raid with bosses down stays saved until the weekly reset (when the game
  -- says when that is).
  local expires
  if run.kind == "raid" and #run.bosses > 0 and C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
    local ok, s = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
    s = ok and ns.plain(s) or nil
    if type(s) == "number" and s > 0 and s <= 8 * 86400 then expires = ns.ServerTime() + s end
  end
  list[#list + 1] = { name = run.name, diff = run.diff, diffUnknown = run.diffUnknown, kind = run.kind,
    wing = run.wing, left = left, kills = CopyKillsOf(run), expires = expires, start = run.serverStart,
    partners = PartnerStarts(run) }
  while #list > 8 do table.remove(list, 1) end
end

-- Takes the copy you're going back into, if it may still be there.
function ns.TakeCopy(inst)
  local list = Copies()
  local found, kills = false, nil
  for i = #list, 1, -1 do
    local c = list[i]
    if SameCopyKey(c, inst) then
      local timeout = c.kind == "raid" and ns.RAID_TIMEOUT or ns.RUN_TIMEOUT
      local saved = type(c.expires) == "number" and ns.ServerTime() < c.expires
      local unreset = type(c.left) == "number" and (Resets()[ns.DungeonKey(c.name)] or 0) < c.left
      local take = not found and unreset and (saved or ns.ServerTime() - c.left <= timeout)
      -- (One your partner was in stays known for a while: if they're still in
      -- it, so are you - see PartnerKeptCopy.)
      local keep = not take and unreset and type(c.partners) == "table" and next(c.partners) ~= nil
        and ns.ServerTime() - c.left <= 6 * 3600
      if not keep then table.remove(list, i) end
      if take then
        found = true
        if type(c.kills) == "table" then
          ns.FixItems(c.kills)  -- (checked like a saved run's)
          kills = c.kills
        end
      end
    end
  end
  return found, kills
end

-- A copy of this dungeon you may go back into?
function ns.HasCopy(name)
  local key = ns.DungeonKey(name)
  for _, c in ipairs(Copies()) do if type(c) == "table" and ns.DungeonKey(c.name) == key then return true end end
  return false
end

-- The first look at where you are after loading the UI (logging in).
local loginCheck = true

-- You've left: the copies you were still inside now have a leaving time.
-- (Logged in outside: you left by the time you logged out.)
local function LeftCopies()
  local now = ns.ServerTime()
  if loginCheck and (ns.lastSaved or 0) > 0 then now = math.min(now, ns.lastSaved) end
  for _, c in ipairs(Copies()) do
    if type(c) == "table" and not c.left then c.left = now end
  end
end

-- "Deadmines started." (quiet mode: only when at the cap, which you'll want to
-- know before the next one).
local overCapHinted = false
local function Announce(run)
  local count, wait = ns.CapStatus()
  local cap = ns.DB.cap or 0
  local day, dayWait = ns.DayStatus()
  local capDay = ns.DB.capDay or 0
  if cap > 0 and count > cap and not overCapHinted then
    -- The game let you in past the cap: Forever's may be higher.
    overCapHinted = true
    ns.Print(string.format("The game let you into a new instance past %d this hour, so Forever's limit may be "
      .. "higher. /runbook cap <number> sets it.", cap))
  end
  if capDay > 0 and day >= capDay then
    ns.Print(string.format("%s started. That's %d/%d instances today; the next one frees up in %s.",
      run.label, day, capDay, ns.Clock(dayWait or 0)))
  elseif cap > 0 and count >= cap then
    ns.Print(string.format("%s started. That's %d/%d instances this hour; the next one frees up in %s.",
      run.label, count, cap, ns.Clock(wait)))
  else
    Say(run.label .. " started.")
  end
end

-- sameEntry: this copy was already counted for the instance cap (/runbook new
-- right after the run started on its own).
function ns.StartRun(inst, sameEntry)
  local read = inst
  local run = ns.NewRun(inst)
  -- Back into a copy you left (within the timeout, not reset): a new run, but
  -- not a new instance for the cap.
  local readsWing = (inst.mapID and READ_WING[inst.mapID]) or (not inst.mapID and READ_WING_NAMES[inst.name])
  if sameEntry then
    Begin(run, false)
    run.counted = true  -- counted by the run it replaced
  elseif readsWing and not read.wing then
    -- Which copy this is depends on the wing: decided once it's read.
    Begin(run, false)
    run.pendingEntry = ns.ServerTime()
  else
    local same, kills = ns.TakeCopy(read)
    if same then
      run.copyKills = kills  -- (what died here before this run)
      Begin(run, false)
    else
      Begin(run)
    end
  end
  ns.Log("run", "start %s (map %s, wing %s, diff %s, %s)", tostring(inst.label), tostring(inst.map),
    tostring(inst.wing), tostring(inst.diff), tostring(inst.kind))
  if readsWing and not read.wing then
    run.announce = true  -- said once the wing is read (or can't be)
  else
    Announce(run)
    MultiWingHint(run, read)
  end
  -- The map can be stale right after a loading screen: read the wing again soon.
  if inst.multiWing then wingCheck = { at = GetTime() + 3, split = false } end
  return run
end

local END_TEXT = {
  ["new dungeon"] = "done", reset = "done (reset)", manual = "ended", new = "ended (starting over)",
  login = "done (logged out)", split = "done (reset)", wing = "done",
}

-- Saves a finished run and announces it. endedAt: when it ended (default now).
-- Returns whether it was kept.
local function Finish(run, reason, endedAt)
  ns.FlushPending(run)
  run.ended = true
  run.endedAt = endedAt or time()
  run.serverEnd = ns.ServerTime() - (time() - run.endedAt)
  run.endReason = reason
  run.pending = nil
  -- Kept for /runbook start after /runbook end (a later repeat kill still shows a reset).
  run.reopenSnap = reason == "manual" and run.resumeSnap or nil
  run.resumeSnap, run.ghostSnap = nil, nil
  run.startTotals, run.splitBy = nil, nil
  run.ghost = nil
  run.reloadedInside = nil
  local kept = WorthKeeping(run)
  if kept and (not run.mapID or run.diffUnknown) then
    -- Its map ID or difficulty couldn't be read the whole time: take them from
    -- your last run of the same name, so it's filed with that dungeon's runs.
    for _, r in ipairs(ns.DB.history) do
      if r ~= run and r.name == run.name and r.wing == run.wing and r.mapID and not r.diffUnknown then
        if not run.mapID then run.mapID, run.map = r.mapID, r.map end
        if run.diffUnknown then run.diff, run.diffName, run.diffUnknown = r.diff, r.diffName, nil end
        break
      end
    end
  end
  if kept then
    local key = ns.RunKey(run)
    local prevFinal = ns.FinalBoss(key)
    local _, prevBest = ns.BestRun(key)  -- before saving: the previous best
    local short = ns.Archive(run)  -- (nil, "short" or "dropped")
    ns.lastRun = (not short) and run or nil
    local text = END_TEXT[reason]
    if reason == "timeout" then text = run.kind == "raid" and "done (away 2+ hours)" or "done (away 30+ min)" end
    ns.Print(string.format("%s %s: %s", run.label, text or "done", ns.RunSummary(run, false, true))
      .. ((reason == "manual" and ns.endingInside) and " /runbook start reopens it." or "")
      .. (short == "short" and (" (Older than your last " .. ns.HISTORY_MAX .. " runs, so it's kept in short form.)")
        or short == "dropped" and " (Older than every run kept, so it isn't saved.)" or ""))
    -- Only a best if it's measured to the same final boss as the old one.
    local final = ns.FinalBoss(key)
    local clear = ns.TimedClear(run)
    if clear and prevBest and prevFinal and final and ns.SameBoss(prevFinal, final) and clear < prevBest
        and short ~= "dropped" then  -- (a run not kept isn't a best)
      ns.Print(string.format("New best clear for %s: %s (%s).", run.label, ns.Clock(clear),
        ns.Delta(clear - prevBest, true)))
    end
    -- A run with no boss kills on a client that has never reported one: say
    -- how to mark them (once per session).
    if #run.bosses == 0 and run.elapsed >= 300 and not ns.DB.bossEventsSeen and not ns.DB.marked
        and not ns.noBossHint then
      ns.noBossHint = true
      ns.Print("No boss kills were reported in that run. If the game doesn't report them in dungeons, "
        .. "type /runbook boss <name> after each kill (or set a key for it under Key Bindings > AddOns).")
    end
  elseif reason == "manual" then
    ns.Print(run.label .. (run.entryOnEntry and " ended (you never went in, so it isn't saved)."
      or " ended (too short to save)."))
  end
  ns.Log("run", "end %s (%s), %ds, kept=%s", tostring(run.label), reason, run.elapsed, tostring(kept))
  ns.Fire("RUN_END", run, kept)
  return kept
end

-- reason: "new dungeon", "reset", "timeout", "manual", "new", "login", "wing"
-- Your partner, in a new copy of the dungeon you're outside of, killed a boss
-- again: the copy you were in is gone. Your run there ends, and a new one
-- (outside, empty) takes their kills; it counts as an instance when you go in.
-- theirStart: when their run in the new copy began.
-- Moves list items recorded in visit `visit` or later (or, with `since`, at
-- that server time or later: your partner's, from the new copy, while you were
-- still outside) from one run to another, shifting their times to the new
-- run's clock (which starts at `from`).
local function Theirs(item)
  if item.src == "sync" then return true end
  return type(item.who) == "string" and item.who ~= "You" and item.who ~= ns.PlayerName()
end

local function MoveFrom(src, dst, visit, from, since, wing)
  local keep = {}
  for _, item in ipairs(src) do
    -- (By time, only others' things: yours from then were written where you
    -- were - outside, or in the old copy - and stay on that run. Into another
    -- wing, not your partner's things from the wing you left.)
    local move = (item.v or 1) >= visit or (since and type(item.st) == "number" and item.st >= since and Theirs(item))
    if move and wing and type(item.wing) == "string" and item.wing ~= wing then move = false end
    if move then
      if item.t then item.t = math.max(0, item.t - from) end
      item.v = math.max(1, (item.v or 1) - visit + 1)  -- (its visit, counted in the new run)
      dst[#dst + 1] = item
    else
      keep[#keep + 1] = item
    end
  end
  for i = #src, 1, -1 do src[i] = nil end
  for i, item in ipairs(keep) do src[i] = item end
end

-- Unnamed kills are numbered by their place in their run ("Boss 1"...): after
-- kills move between runs, again.
function ns.RenumberUnnamed(run)
  for i, b in ipairs(type(run.bosses) == "table" and run.bosses or {}) do
    if type(b) == "table" and b.anonymous and type(b.name) == "string" and b.name:match("^Boss %d+$") then
      b.name = "Boss " .. i
    end
  end
end

-- Moves what was recorded in a saved run at server time `since` or later (your
-- partner's, in the new copy before you came in) into this run. Returns how many.
function ns.MoveSince(from, to, since)
  local n = 0
  for _, k in ipairs({ "bosses", "drops", "deaths", "wipes", "notes" }) do
    if type(from[k]) == "table" and type(to[k]) == "table" then
      local moved = {}
      MoveFrom(from[k], moved, math.huge, math.huge, since)
      for i = #moved, 1, -1 do
        local item = moved[i]
        if k == "bosses" then item.untimed, item.out = true, true end  -- (before your clock started)
        table.insert(to[k], 1, item)
      end
      n = n + #moved
    end
  end
  if n > 0 then
    ns.RenumberUnnamed(to)  -- (what's left in `from` came first: its numbers hold)
    ns.Touch(from)
    ns.Touch(to)
    ns.ClearCache()
    ns.Fire("HISTORY_CHANGED")
  end
  return n
end

-- Your partner's (and the group's) runs that began at `from` or later belong
-- to the new run.
function ns.MoveParts(old, new, from)
  for _, field in ipairs({ "partners", "group" }) do
    for name, entry in pairs(type(old[field]) == "table" and old[field] or {}) do
      if type(entry) == "table" and type(entry.parts) == "table" then
        for key, part in pairs(entry.parts) do
          if (tonumber(key) or 0) >= from then
            entry.parts[key] = nil
            if type(new[field]) ~= "table" then new[field] = {} end
            new[field][name] = new[field][name] or { parts = {} }
            new[field][name].parts[key] = part
          end
        end
        if ns.SumPartner then
          ns.SumPartner(entry)
          if type(new[field]) == "table" and new[field][name] then ns.SumPartner(new[field][name]) end
        end
      end
    end
  end
end

-- reason: how your old run ended ("reset"; "new" when they started over).
-- (Callers only pass a start after the boss's first death, so that kill stays.)
function ns.PartnerFoundReset(theirStart, reason)
  local old = ns.run
  if not old or ns.inside then return nil end
  -- Their kills, drops and notes since their new run began are from the new copy.
  local moved = {}
  for _, k in ipairs({ "bosses", "drops", "deaths", "wipes", "notes" }) do
    moved[k] = {}
    if theirStart then MoveFrom(old[k], moved[k], math.huge, math.huge, theirStart) end
  end
  local ghost, leftAt, leftServer, deadAt = old.ghost, old.leftAt, old.leftServer, old.deadAt  -- (before it ends)
  ns.EndRun(reason or "reset")
  local run = ns.NewRun(old)
  for k, list in pairs(moved) do for _, item in ipairs(list) do run[k][#run[k] + 1] = item end end
  ns.RenumberUnnamed(run)
  -- Their numbers from the new copy go with it.
  if theirStart then ns.MoveParts(old, run, theirStart - 60) end
  run.leftAt, run.leftServer, run.lastIn = time(), ns.ServerTime(), time()
  -- (Running back as a ghost: still running back, into the new copy.)
  if ghost then run.leftAt, run.leftServer, run.ghost = leftAt, leftServer, ghost end
  run.deadAt = deadAt
  run.entryOnEntry = true
  if theirStart then run.copyFrom = theirStart end  -- (their messages from then on are this run's)
  ns.run = run
  VulcanRunBookCharDB.run = run
  ns.inside = false
  ns.Fire("RUN_START", run)
  return run
end

-- endedAt: when it ended (default: now, or when you left it if you're outside).
function ns.EndRun(reason, endedAt)
  local run = ns.run
  if not run then return nil end
  ns.run = nil
  VulcanRunBookCharDB.run = nil
  local wasInside = ns.inside
  ns.inside = false
  wingCheck = nil
  if run.pendingEntry then ns.AddEntry(run.pendingEntry) end  -- its wing was never read
  run.pendingEntry = nil
  local kept = Finish(run, reason, endedAt or ((not wasInside) and run.leftAt) or nil)
  -- A copy you may come back into: ended by hand, or left for another dungeon.
  -- (Or timed out: a raid's bosses stay dead until the weekly reset, and your
  -- partner may still be inside a dungeon's.)
  if (reason == "manual" or reason == "new dungeon" or reason == "timeout")
      and not run.entryOnEntry then  -- (never went in)
    ns.RememberCopy(run, (not (reason == "manual" and wasInside)) and (run.leftServer or ns.ServerTime()) or nil)
  end
  return run, kept
end

-- Money for a one-line summary. Plain text (chat) spells out amounts under a
-- gold, so "30 silver" can't be read as 30 seconds.
function ns.PlainMoney(copper)
  if copper >= 10000 then return ns.Money(copper) end
  if copper >= 100 then return math.floor(copper / 100) .. " silver" end
  return copper .. " copper"
end

-- "32:10, 5 bosses, 1 death, 14g 20s, 4,200 XP, 2 blues."
-- noDrops: leave out the drop counts (a raid report lists only your two's).
function ns.RunSummary(run, plainText, noName, noDrops)
  local parts = { (noName and "" or ((run.label or run.name or "?") .. " ")) .. ns.Clock(run.elapsed) }
  if #run.bosses > 0 then parts[#parts + 1] = ns.Plural(#run.bosses, "boss", "bosses") end
  local deaths, wipes = ns.DeathCount(run), ns.WipeCount(run)
  if deaths > 0 then parts[#parts + 1] = ns.Plural(deaths, "death") end
  if wipes > 0 then parts[#parts + 1] = ns.Plural(wipes, "wipe") end
  -- (Shown as in the live window and the details: to the silver.)
  local gold = ns.ShownMoney(ns.RunGold(run))
  if gold > 0 then parts[#parts + 1] = ns.ShownMoneyText(gold, not plainText) end
  local theirs = 0
  for _, p in pairs(type(run.partners) == "table" and run.partners or {}) do
    if type(p) == "table" and ns.PartnerGold then theirs = theirs + ns.ShownMoney(ns.PartnerGold(p)) end
  end
  if theirs > 0 then parts[#parts + 1] = "together " .. ns.ShownMoneyText(gold + theirs, not plainText) end
  if (run.xp or 0) > 0 then parts[#parts + 1] = ns.Short(run.xp) .. " XP" end
  if not noDrops then
    local blues, epics = ns.DropCounts(run)
    if epics > 0 then parts[#parts + 1] = ns.Plural(epics, "epic") end
    if blues > 0 then parts[#parts + 1] = ns.Plural(blues, "blue") end
  end
  return table.concat(parts, ", ") .. "."
end

-- Splits the run at the last time you came back in. reason: how the old run
-- is described ("split" = reset found later, "wing" = another wing); inst: the
-- wing and label for the new run, if they differ.
-- Returns the new run, or nil if there's no resume point to split at.
-- since: when your partner's run in the new copy began, if known.
-- at: the return to split at (default: your last return alive).
function ns.SplitAtResume(why, reason, inst, since, at)
  local old = ns.run
  local s = at or (old and old.resumeSnap)
  if not s then return nil end
  local outside = not ns.inside  -- (your partner's log found it while you're out)
  local new = ns.NewRun({ map = old.map, mapID = old.mapID, name = old.name, label = inst and inst.label or old.label,
    wing = inst and inst.wing or old.wing, diff = old.diff, diffName = old.diffName, kind = old.kind,
    diffUnknown = old.diffUnknown })
  new.startedAt, new.serverStart = s.wall, s.server
  -- (Your partner was in this copy from `since`: their messages from then on are this run's.)
  if since and since < s.server then new.copyFrom = since end
  local from = s.elapsed
  for _, k in ipairs({ "bosses", "drops", "deaths", "wipes", "notes" }) do
    MoveFrom(old[k], new[k], s.visit, from, since, reason == "wing" and inst and inst.wing or nil)
  end
  -- Unnamed kills are numbered in their run: "Boss 1" again in the new one.
  ns.RenumberUnnamed(new)
  for _, k in ipairs({ "elapsed", "coin", "loot", "lootAH", "xp", "unpriced" }) do
    new[k] = math.max(0, old[k] - s[k])
    old[k] = s[k]
  end
  -- Items still waiting for a price go with the run they were looted in.
  for key, p in pairs(old.pending) do
    if (p.v or 1) >= s.visit then
      old.pending[key] = nil
      p.v = (p.v or 1) - s.visit + 1
      new.pending[key] = p
    end
  end
  for _, m in ipairs(old.members) do new.members[#new.members + 1] = m end
  -- Your partner's runs that began after this point belong to the new run.
  ns.MoveParts(old, new, s.server - 60)
  new.keepAfterClear = old.keepAfterClear
  ns.Log("run", "split %s at %ds (%s)", tostring(old.label), from, why)
  ns.run = nil
  wingCheck = nil
  local carry = { resumeSnap = old.resumeSnap, ghostSnap = old.ghostSnap }  -- (Finish clears them)
  Finish(old, reason or "split", s.wall)
  local sameCopy = false
  if reason == "wing" then
    -- The wing you came from is still there; one you were in earlier may be too.
    ns.RememberCopy(old, old.prevLeft or s.server)
    local kills
    if inst then sameCopy, kills = ns.TakeCopy(inst) end
    if sameCopy then new.copyKills = kills end  -- (what died in that wing before)
  end
  Begin(new, (not sameCopy) and s.server or false)
  -- Your visits since, counted in the new run; a return after this one (a
  -- ghost return after a trip alive) stays a split point there.
  new.visit = math.max(1, (old.visit or 1) - (s.visit or 1) + 1)
  for _, k in ipairs({ "resumeSnap", "ghostSnap" }) do
    local o = carry[k]
    if type(o) == "table" and o.server > s.server and (o.visit or 1) > (s.visit or 1) then
      local r = { visit = o.visit - s.visit + 1, wall = o.wall, server = o.server }
      for _, f in ipairs({ "elapsed", "coin", "loot", "lootAH", "xp", "unpriced" }) do
        r[f] = math.max(0, (o[f] or 0) - (s[f] or 0))
      end
      new[k] = r
    end
  end
  if outside then
    -- Still outside: the new run is paused where the old one was.
    ns.inside = false
    new.leftAt, new.leftServer, new.ghost, new.deadAt = old.leftAt, old.leftServer, old.ghost, old.deadAt
    if ns.UpdateVisibility then ns.UpdateVisibility() end
    return new
  end
  Announce(new)
  -- Read the new run's wing again once the map settles.
  if (inst and inst.multiWing) or IsMultiWing(new.mapID, new.name) then
    wingCheck = { at = GetTime() + 3, split = false }
  end
  return new
end

---------------------------------------------------------------------------
-- Zone changes. Called on loading screens and every few seconds.
---------------------------------------------------------------------------
-- Should entering `inst` start a fresh run instead of resuming `run`?
local function StartsFresh(run, inst)
  if not ns.SameDungeon(run, inst) then return "new dungeon" end
  local reset = Resets()[ns.DungeonKey(run.name)]
  if reset and run.leftServer and reset > run.leftServer then return "reset" end
  local away = run.leftAt or run.lastIn
  if away and run.deadAt and run.deadAt > away then away = run.deadAt end  -- (time dead outside doesn't count)
  if away and time() - away > Timeout(run) and not run.staleLogin then return "timeout" end
  return nil
end

local function SuppressedHere(inst)
  local s = VulcanRunBookCharDB.suppress
  return type(s) == "table" and s.name == inst.name
    and (s.diffUnknown or inst.diffUnknown or (s.diff or 0) == (inst.diff or 0))
end

local function Resume(run, inst)
  ns.Log("run", "back in %s", tostring(run.label))
  local wasGhost = run.ghost
  local reloaded = run.reloadedInside
  if run.entryOnEntry then
    -- Started outside from your partner's kills: this is your first time in.
    run.entryOnEntry = nil
    if not ns.TakeCopy(inst) then
      ns.AddEntry()
      run.counted = true
    end
    Announce(run)
  end
  if run.groupChanged then
    -- (In Classic a new group gets a new copy, with no reset message.)
    run.groupChanged = nil
    ns.Print("Your group changed while you were outside. If this is a new copy of the dungeon, type /runbook new.")
  end
  run.prevLeft = run.leftServer  -- when you left the copy you were in (for a wing change)
  run.leftAt, run.leftServer, run.ghost, run.reloadedInside, run.staleLogin = nil, nil, nil, nil, nil
  ns.inside = true
  run.lastIn = time()
  -- After a /reload inside you never left: same visit, same resume point (or
  -- none), so no split - just a fresh reading.
  if not reloaded then
    if wasGhost then
      -- Back from a ghost run: the same copy you died in, so the point where
      -- a missed reset would split the run stays where it was (or, on your
      -- first visit, there still isn't one: your partner's kills while you ran
      -- back keep their times).
      run.visit = (run.visit or 1) + 1
      ghostEntry = inst.multiWing and { run = run, snap = Snap(run) } or nil
      -- (Kept apart: only a boss that died before this return and dies again -
      -- a reset while you were dead outside - splits the run here.)
      run.ghostSnap = Snap(run)
    else
      ghostEntry = nil
      Snapshot(run)
    end
  end
  if inst.multiWing then
    if not reloaded and run.wing and (OtherWing(run, inst) or not inst.wing) then
      -- Another wing (or not readable yet): checked once the map settles.
      wingCheck = { at = GetTime() + 3, split = true, tries = 0 }
    elseif not run.wing or OtherWing(run, inst) then
      wingCheck = { at = GetTime() + 3, split = false, tries = 0 }
    end
  end
  ns.Fire("RUN_RESUME", run, wasGhost)
  if not (inst.mapID and READ_WING[inst.mapID]) and not (not inst.mapID and READ_WING_NAMES[inst.name]) then
    MultiWingHint(run, inst)  -- (where wings are read, only once reading has failed)
  end
end

-- A few seconds after coming in: read the wing again. Right after a run
-- starts, a different reading just corrects it; after coming back in, it
-- means another wing (a new copy), so the run splits there.
local function CheckWing()
  if not wingCheck or GetTime() < wingCheck.at then return end
  local check = wingCheck
  wingCheck = nil
  local run = ns.run
  if not run or not ns.inside then return end
  local inst = ns.CurrentInstance()
  if (not inst or not inst.wing) and (check.tries or 0) < 5 then
    -- Not readable yet: try again in a moment.
    check.tries, check.at = (check.tries or 0) + 1, GetTime() + 2
    wingCheck = check
    return
  end
  if run.pendingEntry then
    -- Now that the wing is known (or can't be): a copy you were in, or a new one.
    local at = run.pendingEntry
    run.pendingEntry = nil
    local same, kills = false, nil
    if inst then same, kills = ns.TakeCopy(inst) end
    if same then
      run.copyKills = kills
    else
      ns.AddEntry(at)
      run.counted = true
    end
  end
  local entry = ghostEntry
  ghostEntry = nil
  if not inst or not inst.wing or inst.wing == run.wing then
    if run.announce then
      run.announce = nil  -- started where the wing couldn't be read (still can't, or the same)
      Announce(run)
    end
    if inst and not inst.wing then MultiWingHint(run, inst) end  -- gave up reading it
    return
  end
  if not check.split or not run.wing then
    run.wing, run.label = inst.wing, inst.label
    ns.ClearCache()
    if run.announce then
      run.announce = nil
      Announce(run)
    end
    return
  end
  -- (Into another wing as a ghost: that wing's run starts here, at this entry.)
  if entry and entry.run == run then run.resumeSnap = entry.snap end
  ns.SplitAtResume("another wing", "wing", inst)
end

function ns.CheckInstance()
  if not ns.DB then return end
  local inst, state = ns.CurrentInstance()
  if state == "unknown" then return end  -- in an instance we can't read right now: change nothing
  local first = loginCheck
  loginCheck = false
  local char = VulcanRunBookCharDB
  local run = ns.run
  if not inst then
    if run and run.staleLogin then
      -- Logged out inside long ago, and back outside: it ended then.
      run.staleLogin = nil
      ns.inside = false
      ns.EndRun("login", run.leftAt)
      run = nil
    end
    local held = char.suppress ~= nil
    loginCheck = first
    LeftCopies()
    loginCheck = false
    char.suppress = nil  -- left the dungeon /runbook end was used in
    char.manualEnded = nil
    if held and ns.UpdateVisibility then ns.UpdateVisibility() end
    if run then run.reloadedInside = nil end  -- logged back in outside: whatever comes next is a new visit
    if ns.inside and run then
      ns.inside = false
      wingCheck = nil
      if run.pendingEntry then ns.AddEntry(run.pendingEntry) end  -- left before the wing was read
      run.pendingEntry = nil
      run.leftAt = time()
      run.leftServer = ns.ServerTime()
      run.ghost = IsDead() or nil
      run.leftGrouped = (IsInGroup and IsInGroup()) and true or false
      run.groupChanged = nil
      ns.Log("run", "left %s%s", tostring(run.label), run.ghost and " (dead)" or "")
      ns.Fire("RUN_LEFT", run)
    end
    ns.inside = false
    return
  end
  if ns.inside and run then
    -- Already inside. A portal or summon straight into another instance is a
    -- new run; anything else (floors, map changes) never ends one.
    if not ns.SameDungeon(run, inst) then
      ns.EndRun("new dungeon")
      ns.StartRun(inst)
    end
    return
  end
  if SuppressedHere(inst) then return end
  char.suppress = nil
  if run then
    local why = StartsFresh(run, inst)
    if why then
      ns.EndRun(why)
      run = nil
    end
  end
  if not run then
    ns.StartRun(inst)
    return
  end
  Resume(run, inst)
end

-- Did we just come through a loading screen into this zone (not a login or
-- /reload)? Set by PLAYER_ENTERING_WORLD.
function ns.Zoning()
  return GetTime() - zonedAt <= 10
end

-- A dungeon was reset (we saw the message, or a partner's RunBook told us).
function ns.NoteReset(name, fromPartner)
  if not ns.DB or type(name) ~= "string" or name == "" then return end
  local key = ns.DungeonKey(name)
  Resets()[key] = ns.ServerTime()
  ns.Log("run", "reset: %s%s", name, fromPartner and " (from partner)" or "")
  local run = ns.run
  if not fromPartner then
    -- (For /runbook check: whether reset messages are seen and match your runs.)
    local last = ns.LastOwnRun and ns.LastOwnRun()
    ns.stats.resetsSeen = ns.stats.resetsSeen + 1
    ns.stats.lastReset = name
    if (run and ns.DungeonKey(run.name) == key) or ns.HasCopy(name) or (last and ns.DungeonKey(last.name) == key) then
      ns.stats.resetsMatched = ns.stats.resetsMatched + 1
    end
  end
  if run and ns.DungeonKey(run.name) == key then
    if not ns.inside then
      ns.EndRun("reset")
    elseif ns.LastReturn(run) and ns.ServerTime() - ns.LastReturn(run).server <= 120
        and not IsMultiWing(run.mapID, run.name) then
      -- We're inside, so this copy can't be the one that was reset: the message
      -- arrived late and we're already in the fresh copy. (Not for a dungeon
      -- with wings: the message doesn't say which wing, and it may be another.)
      ns.Print(name .. " was reset just before you went back in, so this is a new run.")
      ns.SplitAtResume("late reset message", nil, nil, nil, ns.LastReturn(run))
    end
  end
  if not fromPartner and ns.SyncReset then ns.SyncReset(name) end
end

-- /runbook end: finish now. Inside, auto-start is held off until you leave
-- (or /runbook start, which reopens this same run).
function ns.ManualEnd()
  local run = ns.run
  if not run then return false end
  local inst, state = ns.CurrentInstance()
  -- Inside it (or inside something that can't be read right now, while the run
  -- thinks you're in it).
  local here = (inst and ns.SameDungeon(run, inst)) or (not inst and state == "unknown" and ns.inside)
  if here then
    -- Set first, so the window (updated as the run ends) knows it's on hold.
    VulcanRunBookCharDB.suppress = { name = run.name, diff = run.diff, diffUnknown = run.diffUnknown }
    VulcanRunBookCharDB.manualEnded = run  -- kept (even if too short to save) so start can reopen it
  end
  ns.endingInside = here
  ns.EndRun("manual")
  ns.endingInside = nil
  return true
end

-- /runbook start: inside a dungeon after /runbook end, reopen the run you ended
-- (it's the same copy of the dungeon); otherwise start one.
function ns.ManualStart()
  local inst = ns.CurrentInstance()
  if not inst then return false, "outside" end
  if ns.run then return false, "running" end
  VulcanRunBookCharDB.suppress = nil
  local old = VulcanRunBookCharDB.manualEnded
  VulcanRunBookCharDB.manualEnded = nil
  -- (Not one that's been deleted or cleared since - maybe by another character.)
  if type(old) == "table" and ns.SameDungeon(old, inst) and not ns.Gone(old) then
    -- The saved copy may have had notes or partner numbers added since: use it.
    local uid = ns.RunUID(old)
    for i, r in ipairs(ns.DB.history) do
      if r == old or ns.RunUID(r) == uid then
        old = table.remove(ns.DB.history, i)
        break
      end
    end
    ns.ClearCache()
    if ns.lastRun and ns.RunUID(ns.lastRun) == uid then ns.lastRun = nil end
    ns.FixRun(old)
    ns.TakeCopy(inst)  -- it's this run again, not a copy to come back to
    old.ended, old.endedAt, old.serverEnd, old.endReason = nil, nil, nil, nil
    old.resumeSnap, old.reopenSnap = old.reopenSnap, nil
    ns.run = old
    VulcanRunBookCharDB.run = old
    ns.inside = true
    old.lastIn = time()  -- same copy, same visit: no new resume point
    ns.Print(old.label .. " reopened.")
    ns.Fire("RUN_REOPEN", old)
    ns.Fire("HISTORY_CHANGED")
    ns.Fire("RUN_RESUME", old)
    return true, "reopened"
  end
  -- A new run in the copy you ended (it may have been deleted): still inside
  -- it, so not a new instance.
  for _, c in ipairs(Copies()) do
    if type(c) == "table" and not c.left and c.name == inst.name then c.left = ns.ServerTime() end
  end
  ns.CheckInstance()
  return ns.InRun(), "started"
end

-- /runbook new: end the current run and start a fresh one here. You're saying
-- this is a new copy of the dungeon, so it counts toward the instance cap.
function ns.ManualNew(fromPartner)
  local inst = ns.CurrentInstance()
  if not inst then return false end
  -- Started a moment ago on its own, with nothing in it: that start already
  -- counted this copy for the cap.
  local old = ns.run
  if old and old.pendingEntry then
    -- Its wing wasn't read yet: decide its cap entry now.
    if not ns.TakeCopy(inst) then
      ns.AddEntry(old.pendingEntry)
      old.counted = true
    end
    old.pendingEntry = nil
  end
  local fresh = old and old.counted and ns.SameDungeon(old, inst) and (old.visit or 1) == 1 and old.elapsed < 120
    and #old.bosses == 0 and #old.drops == 0 and #old.deaths == 0 and old.coin == 0 and old.xp == 0
  if old then ns.EndRun("new") end
  VulcanRunBookCharDB.suppress, VulcanRunBookCharDB.manualEnded = nil, nil
  ns.TakeCopy(inst)  -- you're saying the copy here is a new one
  -- Your partner, in the same copy, starts over too, so both logs match (told
  -- before your new run's numbers go out).
  if not fromPartner and ns.SyncNewRun then
    ns.SyncNewRun({ mapID = inst.mapID, name = inst.name, wing = inst.wing, diff = inst.diff,
      diffUnknown = inst.diffUnknown, serverStart = ns.ServerTime() })
  end
  local run = ns.StartRun(inst, fresh)
  -- Quiet mode: one line (not when the cap line just said it started, or when
  -- your partner's message says why).
  local count = ns.CapStatus()
  local atCap = (ns.DB.cap or 0) > 0 and count >= ns.DB.cap
  if ns.DB.quiet and not fromPartner and not atCap then ns.Print(run.label .. " started over.") end
  return true
end

---------------------------------------------------------------------------
-- Clock: once a second
---------------------------------------------------------------------------
local capWasFull = false

local function Tick()
  local now = GetTime()
  local dt = lastTick and (now - lastTick) or 0
  lastTick = now
  if not ns.DB or not ns.loggedIn then return end
  tickCount = tickCount + 1
  if tickCount % 5 == 0 then ns.CheckInstance() end
  CheckWing()

  local run = ns.run
  -- dt >= 10 means a client stall; don't count it.
  local step = (dt > 0 and dt < 10) and dt or 0
  if run and not ns.inside and run.ghost
      and ((not IsDead() and not ns.Zoning()) or time() - (run.leftAt or 0) > ns.GHOST_MAX) then
    -- Revived outside (at the graveyard), or past the time a run back counts:
    -- no longer a ghost run back, so going in again is a return like any other.
    run.ghost = nil
  end
  if run then
    if ns.inside then
      run.elapsed = run.elapsed + step
      run.lastIn = time()
    elseif ns.GhostRunning() then
      run.elapsed = run.elapsed + step
      run.deadAt = time()  -- running back counts as run time, not as time away
    elseif run.leftAt and IsDead() then
      run.deadAt = time()  -- dead outside: the 30 minutes count from when you're alive again
    elseif run.leftAt and not run.staleLogin and time() - math.max(run.leftAt, run.deadAt or 0) > Timeout(run) then
      ns.EndRun("timeout")
    end
  end

  -- Tell you once when an instance slot frees up while you're capped (by the
  -- hour or the day: free means under both).
  local cap, capDay = ns.DB.cap or 0, ns.DB.capDay or 0
  if (cap > 0 or capDay > 0) and tickCount % 5 == 0 then
    local count = ns.CapStatus(true)  -- (not a run whose wing is still being read)
    local day = ns.DayStatus(true)
    if (cap > 0 and count >= cap) or (capDay > 0 and day >= capDay) then
      capWasFull = true
    elseif capWasFull then
      capWasFull = false
      local parts = {}
      if cap > 0 then parts[#parts + 1] = string.format("%d/%d this hour", count, cap) end
      if capDay > 0 then parts[#parts + 1] = string.format("%d/%d today", day, capDay) end
      ns.Print("An instance slot is free again (" .. table.concat(parts, ", ") .. ").")
    end
  end

  ns.Fire("TICK", tickCount)
end
ns.Tick = Tick

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(name)
  if plain(name) ~= ns.name then return end
  ns.LoadSavedData()
  ns.Fire("READY")
end)

ns.On("PLAYER_LOGIN", function()
  if not ns.DB then return end
  ns.loggedIn = true
  ns.PlayerName()  -- cache while readable (sync echo filter)
  ns.CharKey()     -- and the realm (it can be unreadable during loading screens)
  -- A run left over from last time that went stale while logged out ends now.
  local run = ns.run
  if run then
    local last = run.leftAt or run.lastIn or 0
    if run.deadAt and run.deadAt > last then last = run.deadAt end  -- (time dead outside doesn't count)
    if time() - last > Timeout(run) and run.leftAt then
      ns.inside = false
      ns.EndRun("login", run.leftAt or run.lastIn)
    elseif not run.leftAt then
      -- (Logged out inside, a long time ago: if you're back inside after
      -- loading, it's the same copy - a reset one sends you out - so the run
      -- goes on; if you're outside, it ended when you logged out.)
      run.staleLogin = time() - last > Timeout(run) or nil
      -- Logged out (or reloaded) inside. If we're back inside after loading,
      -- this is the same visit; if not, the outside time counts from logout.
      run.leftAt = run.lastIn or time()
      run.leftServer = ns.ServerTime() - (time() - run.leftAt)
      run.reloadedInside = true
    end
  end
  local restored = ns.restoredFromBackup
  if restored then
    ns.Print(string.format("Account data didn't load, so this character's backup was used: %s restored%s.",
      ns.Plural(restored.full, "run"), restored.short > 0 and (" (and " .. restored.short .. " older ones in short "
      .. "form)") or ""))
  end
  ns.Fire("LOGIN")
end)

ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
  lastTick = GetTime()  -- the loading screen isn't run time
  isLogin, isReload = plain(isLogin), plain(isReload)
  if not isLogin and not isReload then zonedAt = GetTime() end
  if ns.loggedIn then ns.CheckInstance() end
end)
ns.On("ZONE_CHANGED_NEW_AREA", function() if ns.loggedIn then ns.CheckInstance() end end)

ns.On("PLAYER_LOGOUT", function()
  ns.SaveBackup()
end)

ns.On("CHAT_MSG_SYSTEM", function(msg)
  msg = plain(msg)
  if type(msg) ~= "string" or not ns.DB then return end
  local name = ns.ParseReset(msg)
  if name then ns.NoteReset(name) return end
  if ns.IsTooManyInstances(msg) then ns.TooManyInstances() end
end)

ns.On("UI_ERROR_MESSAGE", function(_, msg)
  msg = plain(msg)
  if ns.DB and ns.IsTooManyInstances(msg) then ns.TooManyInstances() end
end)

local lastCapNotice = -math.huge
function ns.TooManyInstances()
  ns.stats.capErrors = (ns.stats.capErrors or 0) + 1
  if GetTime() - lastCapNotice < 10 then return end  -- the error repeats per attempt
  lastCapNotice = GetTime()
  local count, wait = ns.CapStatus()
  local cap = ns.DB.cap or 0
  local day, dayWait = ns.DayStatus()
  local capDay = ns.DB.capDay or 0
  if capDay > 0 and day >= capDay and dayWait then
    ns.Print(string.format("Instance cap reached for today. RunBook counts %s in the last 24 hours; you're under "
      .. "it again in %s.", ns.Plural(day, "entry", "entries"), ns.Clock(dayWait)))
  elseif count > 0 and wait and cap > 0 and count >= cap then
    ns.Print(string.format("Instance cap reached. RunBook counts %s this hour; you're under the cap again in %s.",
      ns.Plural(count, "entry", "entries"), ns.Clock(wait)))
  elseif count > 0 then
    -- Fewer than the cap on record: the game counts entries RunBook didn't see
    -- (or a different cap), so when a slot frees up can't be told.
    ns.Print(string.format("Instance cap reached. RunBook only knows of %s this hour (entries from before "
      .. "installing it or from another PC aren't counted, and Forever's cap may differ), so it can't tell when "
      .. "a slot frees up.", ns.Plural(count, "entry", "entries")))
  else
    ns.Print("Instance cap reached, but RunBook has no entries this hour on record (entries made "
      .. "before installing it, or on another PC, aren't counted).")
  end
end

C_Timer.NewTicker(1, function()
  local ok, err = pcall(Tick)
  if not ok then ns.ReportError("clock", err) end
end)

-- Leaving or joining a group while outside: the copy you go back into may be a
-- new one (said when you go back in).
ns.On("GROUP_ROSTER_UPDATE", function()
  local run = ns.run
  if not run or ns.inside or run.leftGrouped == nil then return end
  local grouped = (IsInGroup and IsInGroup()) and true or false
  if grouped ~= run.leftGrouped then run.groupChanged = true end
end)
