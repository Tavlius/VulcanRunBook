-- RunBook: what happens during a run - boss kills, deaths and wipes, drops,
-- coin, loot value and XP.
--
-- Sources (none of them combat data, which Forever hides from addons):
--   bosses   ENCOUNTER_END (success) / BOSS_KILL; /runbook boss as a fallback
--   wipes    a failed boss encounter in which someone died, or most of the
--            group dead at once
--   deaths   yours from the death event (so Feign Death never counts); the
--            group's from their dead/ghost state, checked once a second
--   drops    loot messages (yours and the group's); your bags as a fallback
--            when loot messages can't be read; your partner's via sync
--   coin/XP  changes to your money and XP while inside
local _, ns = ...
local plain = ns.plain

ns.WIPE_MERGE_SECONDS = 60     -- a boss wipe and "everyone's dead" are one wipe
ns.WIPE_SHARE = 0.8            -- this share of the group dead at once is a wipe
ns.PENDING_MAX_TRIES = 60      -- seconds to wait for an item's price to load
ns.LOOT_MATCH_SECONDS = 30     -- a loot message and the bag change it caused
ns.encounter = nil             -- { id, name, deaths } while a boss fight is on

ns.stats = { lootRead = 0, lootSecret = 0, bagLoot = 0, encounters = 0, capErrors = 0,  -- for /runbook check
  resetsSeen = 0, resetsMatched = 0, lastReset = nil }

local function RunTime(run)
  run = run or ns.run
  return math.floor((run and run.elapsed or 0) + 0.5)
end

-- Inside, or running back as a ghost: deaths are still watched then.
local function Watching()
  return ns.InRun() or ns.GhostRunning()
end

---------------------------------------------------------------------------
-- Group members
---------------------------------------------------------------------------
-- Unit tokens for everyone in your group, you included once.
function ns.GroupUnits()
  local n = ns.Call(GetNumGroupMembers) or 0
  if IsInRaid and IsInRaid() and n > 0 then
    local units = {}
    for i = 1, n do units[#units + 1] = "raid" .. i end  -- one of these is you
    return units
  end
  local units = { "player" }
  for i = 1, math.max(0, n - 1) do units[#units + 1] = "party" .. i end
  return units
end

local UNKNOWN = UNKNOWNOBJECT or "Unknown"

-- A group member's name, or nil (unreadable, or "Unknown" while still loading).
local function UnitShortName(unit)
  local name = plain(UnitName(unit))
  if type(name) ~= "string" or name == "" or name == UNKNOWN then return nil end
  return ns.ShortName(name)
end

-- Adds anyone new in the group to the run's member list.
-- A message's sender ("Name-Realm") is in your group right now? (If names
-- can't be read, it's taken on trust.)
function ns.SenderInGroup(sender)
  local short = ns.ShortName(sender)
  local realm = sender:match("%-(.+)$")
  local readable = false
  local mine = GetNormalizedRealmName and plain(GetNormalizedRealmName()) or nil
  for _, unit in ipairs(ns.GroupUnits()) do
    local n, r = UnitName(unit)
    n, r = plain(n), plain(r)
    if type(n) == "string" and n ~= "" and n ~= UNKNOWN and not ns.IsPlayerUnit(unit) then
      readable = true  -- (someone else's name: yours is always readable)
      if ns.SameName(ns.ShortName(n), short) then
        local theirs = (type(r) == "string" and r ~= "") and r or mine
        if not realm or type(theirs) ~= "string" or theirs:gsub("[%s%-]", "") == realm:gsub("[%s%-]", "") then
          return true
        end
      end
    end
  end
  return not readable
end

-- The group unit of a message's sender ("Name-Realm"), or nil.
local function SenderUnit(sender)
  local short = ns.ShortName(sender)
  local realm = type(sender) == "string" and sender:match("%-(.+)$")
  local mine = GetNormalizedRealmName and plain(GetNormalizedRealmName()) or nil
  for _, unit in ipairs(ns.GroupUnits()) do
    local n, r = UnitName(unit)
    n, r = plain(n), plain(r)
    if type(n) == "string" and not ns.IsPlayerUnit(unit) and ns.SameName(ns.ShortName(n), short) then
      local theirs = (type(r) == "string" and r ~= "") and r or mine
      if not realm or type(theirs) ~= "string" or theirs:gsub("[%s%-]", "") == realm:gsub("[%s%-]", "") then
        return unit
      end
    end
  end
  return nil
end

-- Is a message's sender on your friends list or a Battle.net friend? Also
-- their BattleTag when the game gives it (the same person on another
-- character has the same one). Asked again after 5 minutes.
local friendCache = {}
-- fresh: ask the game again now (a friend added since).
function ns.FriendInfo(sender, fresh)
  local c = friendCache[sender]
  if c and not fresh and GetTime() - c.at < 300 then return c.friend, c.tag end
  local friend, tag = false, nil
  local unit = SenderUnit(sender)
  local guid = unit and UnitGUID and plain(ns.Call(UnitGUID, unit))
  if type(guid) ~= "string" or guid == "" then guid = nil end
  if guid and C_BattleNet and C_BattleNet.GetAccountInfoByGUID then
    local ok, info = pcall(C_BattleNet.GetAccountInfoByGUID, guid)
    info = ok and plain(info) or nil
    if type(info) == "table" and plain(info.isFriend) ~= false then
      friend = true
      local t = plain(info.battleTag)
      if type(t) == "string" and t ~= "" then tag = t end
    end
  end
  if not friend and C_FriendList then
    if guid and C_FriendList.IsFriend then
      local ok, r = pcall(C_FriendList.IsFriend, guid)
      friend = ok and plain(r) == true
    end
    if not friend and C_FriendList.GetFriendInfo then
      -- (By the bare name only when they're on your realm: "Mirel-Other" is
      -- not your friend Mirel.)
      local realm = sender:match("%-(.+)$")
      local mine = GetNormalizedRealmName and plain(GetNormalizedRealmName()) or nil
      local names = { sender }
      if not realm or (type(mine) == "string" and realm:gsub("[%s%-]", "") == mine:gsub("[%s%-]", "")) then
        names[2] = ns.ShortName(sender)
      end
      for _, n in ipairs(names) do
        local ok, info = pcall(C_FriendList.GetFriendInfo, n)
        if not friend then friend = ok and type(plain(info)) == "table" end
      end
    end
  end
  friendCache[sender] = { friend = friend, tag = tag, at = GetTime() }
  return friend, tag
end
function ns.ForgetFriends() friendCache = {} end

-- Your sync partner in your group right now?
function ns.PartnerInGroup()
  local partner = ns.DB and ns.DB.partner
  if not partner then return false end
  for _, unit in ipairs(ns.GroupUnits()) do
    if not ns.IsPlayerUnit(unit) and ns.SameName(UnitShortName(unit), partner) then return true end
  end
  return false
end

function ns.SnapshotMembers()
  local run = ns.run
  if not run then return end
  local have = {}
  for _, n in ipairs(run.members) do have[n] = true end
  for _, unit in ipairs(ns.GroupUnits()) do
    local name = UnitShortName(unit)
    if name and not have[name] then
      have[name] = true
      run.members[#run.members + 1] = name
    end
  end
end

ns.On("GROUP_ROSTER_UPDATE", function()
  if ns.InRun() then ns.SnapshotMembers() end
end)

---------------------------------------------------------------------------
-- Bosses
---------------------------------------------------------------------------
local lastKill = { at = -math.huge }  -- the last boss kill recorded: { at = GetTime(), boss = }

local function FindBoss(run, boss)
  for i, b in ipairs(run.bosses) do
    if ns.SameBoss(b, boss) then return b, i end
  end
  -- A boss you marked by hand is the same as the automatic kill of that name.
  if boss.name then
    for i, b in ipairs(run.bosses) do
      if b.manual and b.name and ns.Fold(b.name) == ns.Fold(boss.name) then return b, i end
    end
  end
  return nil
end

-- Your mark and your partner's for the same kill: both of you press within
-- this many seconds of each other (short, so two bosses killed half a minute
-- apart and marked by one of you each stay two).
ns.SYNC_MATCH_SECONDS = 20

-- The number for an unnamed kill: one past the run's kills and any "Boss N"
-- already in it, so names never repeat after an unboss.
local function NextNumber(run)
  local n = #run.bosses
  for _, b in ipairs(run.bosses) do
    local k = tonumber(b.name and b.name:match("^Boss (%d+)$"))
    if k and k > n then n = k end
  end
  return n + 1
end

-- id and name may each be nil (the client hid them, or a hand-marked split).
-- source: nil (the game's event), "manual" (/runbook boss) or "sync" (your
-- partner's kill, for when you didn't see it: dead, or outside).
-- Returns the boss added (or named); or nil and the kill it was taken to be.
-- Marks from the two of you for the same kill pair up (either order, within
-- SYNC_MATCH_SECONDS): each kill is matched at most once, so two bosses killed close
-- together and marked by both of you stay two. Session only.
local killAt = setmetatable({}, { __mode = "k" })  -- [boss] = GetTime() recorded
local paired = setmetatable({}, { __mode = "k" })  -- [boss] = true once matched

-- Matched with the other side's kill. (Kept on the kill too, so a /reload
-- doesn't make it matchable again.)
local function Pair(b)
  paired[b] = true
  b.matched = true
end

-- The oldest recent kill from the given side (partner's = synced)
-- that isn't matched yet. (After a /reload, how recent comes from its server time.)
local function Unpaired(run, partnerSide)
  local now = GetTime()
  for _, b in ipairs(run.bosses) do
    local age = killAt[b] and (now - killAt[b])
      or (type(b.st) == "number" and ns.ServerTime() - b.st) or nil
    if age and age <= ns.SYNC_MATCH_SECONDS and not paired[b] and not b.matched
        and ((b.src == "sync") == partnerSide) then
      return b
    end
  end
  return nil
end

-- Recorded since your last trip back in? A kill from before isn't this kill:
-- if it dies again, the dungeon was reset. (That includes one your partner
-- made while you were outside: you can't see it die again in the same copy.)
local function ThisVisit(run, b)
  local snap = run.resumeSnap
  return not snap or (b.v or 1) >= snap.visit
end

local lastTouch = { at = -math.huge }  -- the kill you last marked, paired or recorded: { at, boss }
local keyCount = 0

-- The "To name it" tip was shown for this kill: naming it works for a while.
function ns.TouchKill(b)
  lastTouch.at, lastTouch.boss = GetTime(), b
end

-- Is a the fuller name for b ("Lord Roccor" for "Roccor")?
local function Longer(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then return false end
  local fa, fb = ns.Fold(a), ns.Fold(b)
  return #fa > #fb and fa:find(fb, 1, true) ~= nil
end

local AfterNaming  -- (below)

-- A name for an unnamed kill (and its id, if it had none).
local function NameKill(b, id, name)
  b.id = id or b.id
  if name then b.name, b.anonymous = name, nil end
  AfterNaming(b)
end

-- A boss that died in this run's copy before the run began (an earlier run
-- there, ended with /runbook end or by going elsewhere): its kill, or nil.
local function CopyKill(run, boss)
  local found
  for _, k in ipairs(type(run.copyKills) == "table" and run.copyKills or {}) do
    if type(k) == "table" and type(k.st) == "number" and ns.SameBoss(k, boss) then found = k end
  end
  return found
end

-- This run turns out to be in a new copy (a boss that died here before it
-- began died again, and there's no return to split at): it counts toward the
-- cap, and what died before is forgotten.
local function NewCopyHere(run, id, name)
  -- (Kept with the boss whose kill showed it, so /runbook unboss of that boss
  -- can take it back.)
  run.entryBy = { kills = run.copyKills, boss = { id = id, name = name } }
  run.copyKills = nil
  if not run.counted and not run.pendingEntry then
    ns.AddEntry(run.serverStart)
    run.counted = true
    run.entryBy.at = run.serverStart
  end
  ns.Print((name or "That boss") .. " died here before this run began, so the dungeon was reset before you came "
    .. "in: this run is in a new copy (it counts toward the instance cap).")
end

-- A kill that just got its name (the key, then /runbook boss <name>; or your
-- partner's or the game's name for it) may be one that died here before this
-- run began: then the copy was reset, as for a kill named straight away.
AfterNaming = function(b)
  local run = ns.run
  if not run or not ns.inside or not ns.HasBossEntry(run, b) then return end
  local ck = CopyKill(run, b)
  if not ck then return end
  local snap = run.resumeSnap
  if snap and (b.v or 1) >= snap.visit and ns.SplitAtResume("boss killed again") then
    ns.Print(b.name .. " died here before, so the dungeon was reset: this is a new run from when you came back in.")
    b.split = true
  else
    NewCopyHere(run, b.id, b.name)
  end
  if ns.SyncSplit then ns.SyncSplit(ns.run, nil, ck.st) end
end

local redoing  -- while an unnamed kill is recorded again under its name: what it keeps

-- An unnamed kill gets its name (your partner's name for their kill, or the
-- game's or your partner's for yours). If that boss is already in this run, or
-- died in this copy before the run began, the name is news: the kill is
-- recorded again, named, so it gets the same checks as a kill named from the
-- start (one kill; or a reset). It stays whose it was, keeps its tag (so your
-- partner's copy of it gets the name) and, in the same run, its place and time.
-- Otherwise it's just named.
local function NameOrRedo(b, id, name, source, key, theirEntry, theirManual, theirKillAt)
  local run = ns.run
  local boss = { id = id, name = name }
  local other = FindBoss(run, boss)
  local mine = b.src ~= "sync"
  if not ((other and other ~= b) or CopyKill(run, boss)) then
    NameKill(b, id, name)
    if mine then
      ns.Fire("BOSS", b, "named")  -- (and to your partner, under its tag)
    else
      ns.Fire("BOSS", b, "sync")
    end
    return b
  end
  local at
  for i, x in ipairs(run.bosses) do
    if x == b then at = i table.remove(run.bosses, i) break end
  end
  -- (lastKill and lastTouch may still point at it: both are checked against
  -- the run's kills before use.)
  ns.Fire("BOSS_REMOVED", b)
  local had = {}
  for _, x in ipairs(run.bosses) do had[x] = true end
  redoing = { run = run, at = at, key = b.key, t = b.t, st = b.st, v = b.v, out = b.out, untimed = b.untimed,
    split = b.split }
  local ok, added, same, why
  if mine then
    ok, added, same, why = pcall(ns.AddBoss, id, name, b.manual and "manual" or nil)
  else
    ok, added, same, why = pcall(ns.AddBoss, id, name, source, key, theirEntry, theirManual, theirKillAt)
  end
  redoing = nil
  if not ok then error(added, 0) end
  local new = added and not had[added]
  if mine and new and key and source == "sync" then
    added.peer = key  -- (your partner's tag for it too)
    Pair(added)
  end
  if mine and b.key and not (new and added.key == b.key) and ns.SyncBoss then
    -- It merged into a kill you have (or went nowhere): your partner's copy
    -- of it still gets the name, so theirs merges too.
    ns.SyncBoss(ns.run, { key = b.key, id = id, name = name, st = b.st, manual = b.manual })
  end
  return added, same, why
end

-- key: your partner's tag for their kill (so a name they give it later finds
-- it here). theirEntry: when your partner last came in (into the copy they're
-- in), theirKillAt: when they killed it (server time). theirManual: they
-- marked it by hand (it may have died before they joined, so it says nothing
-- about a reset).
function ns.AddBoss(id, name, source, key, theirEntry, theirManual, theirKillAt, retried)
  local run = ns.run
  if not run then return nil end
  local manual, sync = source == "manual", source == "sync"
  local last = lastKill.boss
  if last and not ns.HasBossEntry(run, last) then last = nil end
  local since = last and (GetTime() - lastKill.at) or math.huge
  local named = id or name

  if sync and key and key ~= "" and type(run.unbossed) == "table" and run.unbossed[key] then
    return nil  -- one you took back (/runbook unboss)
  end
  if sync and key and key ~= "" then
    -- A kill of theirs you already have (they named it since, or sent it again).
    for _, b in ipairs(run.bosses) do
      if b.key == key or b.peer == key then
        Pair(b)
        if named and b.anonymous then
          -- (Their mark that the game then named: their log made it the game's kill.)
          if b.src == "sync" and b.byHand and not theirManual then b.byHand = nil end
          return NameOrRedo(b, id, name, source, key, theirEntry, theirManual, theirKillAt)
        end
        if name and not b.anonymous and Longer(name, b.name) then
          b.name = name  -- their fuller name for the same kill
          ns.Fire("BOSS", b, "sync")
          return b
        end
        return nil, b
      end
    end
  end

  if sync or manual then
    local known = named and FindBoss(run, { id = id, name = name })
    local snap = run.resumeSnap
    -- Their game-reported kill of a boss you saw die minutes before it: a
    -- boss dies once per copy, so the dungeon was reset in between (whether
    -- or not either log saw it). theirEntry: when they last came in - into
    -- the copy they're in now. (A hand mark can be a kill from long before.)
    local diedAt = theirKillAt or ns.ServerTime()
    -- (retried: the second pass after a reset was acted on - never again.)
    local again = not retried and known and sync and not theirManual and theirEntry and known.st
      and diedAt > known.st + 120
    if again and not ns.inside and theirEntry > known.st
        and not (snap and run.leftServer and theirEntry < run.leftServer and not ThisVisit(run, known)) then
      -- You're outside, and they went into the new copy after you saw it die
      -- (and after you last left): your run is over; their kills go to a new
      -- run that starts counting when you go in. (If they went in before you
      -- last left, you were in the new copy with them: a split, below.)
      if ns.PartnerFoundReset(theirEntry) then
        ns.Print((name or "That boss") .. " was killed again, so the dungeon was reset: your run there has "
          .. "ended, and going back in starts the new one.")
        if ns.SyncSplit then ns.SyncSplit(ns.run, theirEntry, known.st) end  -- (their log may not know)
        return ns.AddBoss(id, name, source, key, theirEntry, theirManual, theirKillAt, true)
      end
      return nil, known
    end
    local at = again and ns.SplitPointFor(run, known.st) or nil
    if at then
      -- You came back in since you saw it die (alive, or as a ghost), and
      -- you're in their copy now: that was the new copy. The run splits there.
      if ns.SplitAtResume("boss killed again", nil, nil, theirEntry, at) then
        ns.Print((name or "That boss") .. " was killed again, so the dungeon was reset: this is a new run "
          .. "from when you came back in.")
        if ns.SyncSplit then ns.SyncSplit(ns.run, theirEntry, known.st) end  -- (their log may not know)
        return ns.AddBoss(id, name, source, key, nil, nil, theirKillAt, true)
      end
      return nil, known
    end
    local ck = not retried and not known and named and sync and not theirManual and theirEntry
      and CopyKill(run, { id = id, name = name })
    if ck and diedAt > ck.st + 120 then
      -- Died before your run began, in what you took for the same copy, and
      -- they killed it again: the copy was reset.
      if not ns.inside and theirEntry > ck.st
          and not (snap and run.leftServer and theirEntry < run.leftServer) then
        if ns.PartnerFoundReset(theirEntry) then
          ns.Print((name or "That boss") .. " was killed again, so the dungeon was reset: your run there has "
            .. "ended, and going back in starts the new one.")
          if ns.SyncSplit then ns.SyncSplit(ns.run, theirEntry, ck.st) end
          return ns.AddBoss(id, name, source, key, theirEntry, theirManual, theirKillAt, true)
        end
      elseif ns.LastReturn(run) and (ns.inside or theirEntry > ck.st) then
        -- (Outside too: you were in the new copy with them since you last
        -- came back in.)
        if ns.SplitAtResume("boss killed again", nil, nil, theirEntry, ns.LastReturn(run)) then
          ns.Print((name or "That boss") .. " was killed again, so the dungeon was reset: this is a new run "
            .. "from when you came back in.")
          if ns.SyncSplit then ns.SyncSplit(ns.run, theirEntry, ck.st) end
          return ns.AddBoss(id, name, source, key, nil, nil, theirKillAt, true)
        end
      elseif ns.inside then
        NewCopyHere(run, id, name)
        if ns.SyncSplit then ns.SyncSplit(run, theirEntry, ck.st) end
      end
    end
    if known and sync then
      -- You have it. (Otherwise a repeat kill from your partner doesn't split
      -- your run: your own kill or mark of it does.) Their fuller name wins.
      Pair(known)
      known.peer = known.peer or key
      if name and not known.anonymous and Longer(name, known.name) then
        known.name = name
        ns.Fire("BOSS", known, "sync")
        return known
      end
      return nil, known
    end
    if known and known.src == "sync" and (ThisVisit(run, known)
        or (manual and known.out and (known.v or 1) + 1 >= (snap and snap.visit or 0))) then
      -- Your partner marked it already (or killed it while you were just
      -- outside, and you're marking the kill you missed).
      Pair(known)
      return nil, known
    end
    local t = lastTouch.boss
    if manual and named and not known and not redoing and t and t.anonymous and GetTime() - lastTouch.at <= 10
        and ns.HasBossEntry(run, t) then
      -- The unnamed kill you pressed for (or that was recorded, or that the
      -- "To name it" tip was about) a moment ago: your name for it.
      local was = t.name
      NameKill(t, id, name)
      ns.Print(was .. " is now " .. t.name .. ".")
      ns.Fire("BOSS", t, "named")
      return t
    end
    if not known then
      -- The other side's kill from a moment ago: the same kill. Your name
      -- (or theirs) fills in an unnamed one; two different names are two kills.
      local other = not redoing and Unpaired(run, manual)
      if other and (not named or other.anonymous) then
        Pair(other)
        if sync then other.peer = other.peer or key end
        lastTouch.at, lastTouch.boss = GetTime(), other
        if not named then return nil, other end
        local was = other.name
        NameKill(other, id, name)
        if manual then ns.Print(was .. " is now " .. other.name .. ".") end
        ns.Fire("BOSS", other, sync and "sync" or "named")
        return other
      end
      local similar = other and name and type(other.name) == "string" and not other.anonymous
        and ns.NameSimilar(name, other.name)
      if other and named and similar then
        -- The same name spelled a little differently by each of you ("Bael'Gar",
        -- "Baelgar"; "Roccor", "Lord Roccor"), within the 20 seconds: one kill.
        -- The fuller name wins; otherwise the first. (Two different names are
        -- two kills: Sneed's Shredder and Sneed die seconds apart.)
        Pair(other)
        if sync then other.peer = other.peer or key end
        lastTouch.at, lastTouch.boss = GetTime(), other
        if name and Longer(name, other.name) then
          other.name, other.id = name, id or other.id
          ns.Fire("BOSS", other, sync and "sync" or "named")
          return other
        end
        return nil, other
      end
    end
    if manual and not named and since <= 10 then
      return nil, last  -- a second press (or a press right after your partner's)
    end
    if manual and named and last and since <= 10 and not last.manual and not last.anonymous
        and last.src ~= "sync" and ns.NameSimilar(name, last.name) then
      -- Your name for the kill the game reported a moment ago: the same kill
      -- (the fuller name wins).
      if Longer(name, last.name) then
        last.name = name
        ns.Fire("BOSS", last, "named")
      end
      return nil, last, "recent"
    end
  elseif not named then
    -- The other boss event, with nothing readable. (Not a kill from before
    -- this fight began: a boss killed seconds after the last one.)
    local enc = ns.encounter
    if since <= 10 and not (enc and enc.at and lastKill.at < enc.at) then return nil, last end
  elseif last and last.manual and since <= 10 and not FindBoss(run, { id = id, name = name })
      and (last.anonymous or not name or ns.NameSimilar(name, last.name)) then
    -- The game's event for the kill you marked a moment ago: it names the
    -- mark (or adds its id) and makes it the game's kill.
    last.manual, last.src, last.byHand = nil, nil, nil
    NameKill(last, id, name)
    ns.Fire("BOSS", last, "named")
    return last
  elseif last and last.anonymous and not last.manual and since <= 10
      and not FindBoss(run, { id = id, name = name }) then
    -- The game's other event right after a nameless kill: its name.
    NameKill(last, id, name)
    ns.Fire("BOSS", last, "named")
    return last
  end

  local boss = { id = id, name = name, manual = manual or nil, src = source, byHand = (manual or theirManual) or nil }
  local have = named and FindBoss(run, boss)
  local ck = not have and named and not sync and ns.inside and CopyKill(run, boss)
  if ck then
    -- Died in this copy before this run began, and died again: the copy was
    -- reset (while you were outside). Since your last return, if there's one;
    -- otherwise this whole run is in the new copy.
    if run.resumeSnap and ns.SplitAtResume("boss killed again") then
      ns.Print((name or "That boss") .. " died here before, so the dungeon was reset: this is a new run from "
        .. "when you came back in.")
      run = ns.run
      run.splitBy = true  -- (the kill recorded next is the one that split it)
    else
      NewCopyHere(run, id, name)
    end
    if ns.SyncSplit then ns.SyncSplit(run, nil, ck.st) end
  end
  if have then
    if have.manual and not manual and ThisVisit(run, have) then
      -- The game's kill takes over a hand-marked one (keeps its time).
      have.manual, have.anonymous, have.id, have.byHand = nil, nil, id or have.id, nil
      have.name = name or have.name
      return have
    end
    -- (Or killed before a ghost return since: the copy was reset while you
    -- were dead outside.) It splits where you last came back in after it.
    local at = ns.SplitPointFor(run, have.st)
    if ThisVisit(run, have) and not at then
      return nil, have, "visit"  -- the same kill again (reported twice, or already marked)
    end
    -- A boss killed before your last trip outside died again: this is a new
    -- copy of the dungeon (reset without you seeing it). Everything since you
    -- came back in becomes a new run.
    if not ns.SplitAtResume("boss killed again", nil, nil, nil, at) then return nil, have end
    ns.Print((name or "That boss") .. " was already down before you went out, so the dungeon was reset: "
      .. "this is a new run.")
    run = ns.run
    run.splitBy = true  -- (the next boss recorded here is the kill that split it)
    -- (Kept with the kill that split it, so /runbook unboss of a mistaken mark
    -- takes back the instance-cap entry the new run added.)
    run.entryBy = { boss = { id = id, name = name }, at = run.counted and run.serverStart or nil }
    if ns.SyncSplit then ns.SyncSplit(run, nil, have.st) end  -- (your partner's log may not have this boss)
    local other = manual and Unpaired(run, true)
    if other and other.anonymous then
      -- Your partner's mark of this kill, from a moment before: your name for it.
      Pair(other)
      other.split, run.splitBy = true, nil
      NameKill(other, id, name)
      ns.Fire("BOSS", other, "named")
      return other
    end
    if last and (last.manual or last.anonymous) and since <= 10 and ns.HasBossEntry(run, last) then
      -- A mark (or nameless report) of this kill a moment before moved into
      -- the new run: it's this kill.
      last.split, run.splitBy = true, nil
      last.manual, last.src, last.byHand = nil, nil, nil
      NameKill(last, id, name)
      ns.Fire("BOSS", last, "named")
      return last
    end
  end
  boss.anonymous = (name == nil) or nil
  boss.name = boss.name or ("Boss " .. NextNumber(run))
  boss.t = RunTime(run)
  boss.st = ns.ServerTime()  -- when it was recorded
  boss.v = run.visit
  -- Your partner's kill while you were outside; and if you weren't running
  -- back, your clock was paused, so its time isn't a real split.
  boss.out = (sync and not ns.inside) or nil
  boss.untimed = (boss.out and not (ns.GhostRunning and ns.GhostRunning())) or nil
  -- (Died before your clock started - your partner was in this copy before you -
  -- or before you last came back in: you were outside, whenever the message
  -- arrived.)
  local back = run.resumeSnap and run.resumeSnap.server or run.serverStart
  if sync and theirKillAt and back and theirKillAt < back - 1 then
    boss.out, boss.untimed = true, true
  elseif sync and theirKillAt and not boss.untimed and not redoing then
    -- (When it died, not when the message got here: held up in a boss fight,
    -- it can come a while later.)
    boss.t = math.max(0, boss.t - math.max(0, ns.ServerTime() - theirKillAt))
  end
  if sync then
    boss.peer = key ~= "" and key or nil
  else
    if redoing and redoing.key then
      boss.key = redoing.key  -- (an unnamed kill recorded again: its tag stays)
    else
      keyCount = keyCount + 1
      boss.key = ns.token .. "." .. keyCount  -- so a name you give it later reaches your partner's copy
    end
  end
  local redo = redoing and redoing.run == run and redoing
  if redo then
    -- (Recorded again in the same run: its time, as first recorded.)
    boss.t, boss.st, boss.v, boss.out, boss.untimed = redo.t, redo.st, redo.v, redo.out, redo.untimed
    boss.split = boss.split or redo.split
  end
  if manual then ns.DB.marked = true end
  if run.splitBy then boss.split, run.splitBy = true, nil end
  if redo and redo.at and redo.at <= #run.bosses then
    table.insert(run.bosses, redo.at, boss)  -- (and its place)
  else
    run.bosses[#run.bosses + 1] = boss
  end
  lastKill.at, lastKill.boss = GetTime(), boss
  lastTouch.at, lastTouch.boss = GetTime(), boss
  killAt[boss] = GetTime()
  if not ns.DB.quiet or manual then
    local best = ns.BestRun(ns.RunKey(run))
    local split = not boss.untimed and ns.BestSplit(best, boss, #run.bosses)
    local vs = split and (" (" .. ns.Delta(boss.t - split, true) .. " vs best)") or ""
    if boss.untimed then
      ns.Print(boss.name .. " down (from your partner, while you were outside).")
    else
      ns.Print(string.format("%s down at %s%s%s.", boss.name, ns.Clock(boss.t), vs,
        sync and " (from your partner)" or ""))
    end
  end
  ns.Log("boss", "%s (id %s) at %ds%s", boss.name, tostring(id), boss.t, source and (" " .. source) or "")
  ns.Fire("BOSS", boss, source)
  return boss
end

function ns.HasBossEntry(run, boss)
  for _, b in ipairs(run.bosses) do if b == boss then return true end end
  return false
end

-- /runbook unboss: takes back the last boss kill of this run, or of your last
-- saved run if you're not in one (a mistaken mark).
-- id: a saved run's number (#12). Without one: this run, or your last saved
-- run when you're not in one.
function ns.RemoveLastBoss(id)
  local run
  if id then
    run = (ns.run and ns.run.id == id) and ns.run or ns.FindRunById(id)
  else
    run = ns.RunOrLast()  -- (not a run you haven't gone into yet)
  end
  local b = run and table.remove(run.bosses)
  if b then
    ns.Touch(run)
    -- Taken back: your partner's later name for that kill doesn't bring it back.
    if b.key or b.peer then
      run.unbossed = run.unbossed or {}
      if b.key then run.unbossed[b.key] = true end
      if b.peer then run.unbossed[b.peer] = true end
    end
    if lastKill.boss == b then lastKill.at, lastKill.boss = -math.huge, nil end
    local e = run.entryBy
    if type(e) == "table" and type(e.boss) == "table" and ns.SameBoss(e.boss, b) then
      -- Its kill had made this run a new copy: that's taken back with it.
      if e.at then
        for i, t in ipairs(ns.DB.entries) do
          if t == e.at then table.remove(ns.DB.entries, i) break end
        end
        run.counted = nil
      end
      run.copyKills = e.kills
      run.entryBy = nil
      b.undidCopy = true
    end
    if run ~= ns.run then ns.ClearCache() end
    ns.Fire("BOSS_REMOVED", b)
    ns.Fire("HISTORY_CHANGED")
  end
  return b, run
end

-- Key binding: mark a boss kill (unnamed: "Boss 3").
function ns.MarkBoss()
  if not ns.DB then return end
  if not ns.InRun() then
    ns.Print("Only inside a dungeon run.")
    return
  end
  local added, same = ns.AddBoss(nil, nil, "manual")
  if not added and same and same.src == "sync" and ns.DB.quiet then
    -- (Quiet mode hid their line, so say it here.)
    ns.Print(same.name .. " was already marked by your partner.")
  elseif not added and same and same.src ~= "sync" then
    -- (Your partner's mark of it was announced a moment ago: nothing to add.)
    ns.Print(same.name .. " was just recorded." .. (same.anonymous
      and " To name it, type /runbook boss <name> within 10 seconds." or ""))
    if same.anonymous then ns.TouchKill(same) end
  end
end

local function AddWipe(bossName)
  local run = ns.run
  if not run then return end
  local now = RunTime(run)
  local last = run.wipes[#run.wipes]
  if last and now - last.t <= ns.WIPE_MERGE_SECONDS then
    -- Same wipe seen twice (the boss reset and everyone was dead): keep one,
    -- with the boss name if either had it.
    last.boss = last.boss or bossName
    return
  end
  run.wipes[#run.wipes + 1] = { t = now, boss = bossName, v = run.visit, st = ns.ServerTime() }
  ns.Log("wipe", "wipe%s at %ds", bossName and (" on " .. bossName) or "", now)
  ns.Fire("WIPE")
end
ns.AddWipe = AddWipe

-- A failed encounter is a wipe only if someone died in it (a boss that resets
-- after a Feign Death drop or a run-out isn't). Deaths in a fight may only be
-- readable once it ends, so this waits a few seconds for them.
local wipeCheck  -- { boss, deaths, untilAt }

ns.On("ENCOUNTER_START", function(id, name)
  ns.stats.encounters = ns.stats.encounters + 1
  id, name = plain(id), plain(name)
  ns.encounter = {
    id = type(id) == "number" and id or nil, name = type(name) == "string" and name or nil, at = GetTime(),
    deaths = ns.run and #ns.run.deaths or nil,  -- nil: no run when it began
  }
end)


ns.On("ENCOUNTER_END", function(id, name, _, _, success)
  if not ns.DB then return end
  id, name, success = plain(id), plain(name), plain(success)
  local enc = ns.encounter
  ns.encounter = nil
  if type(id) ~= "number" then id = enc and enc.id or nil end
  if type(name) ~= "string" then name = enc and enc.name or nil end
  if ns.InRun() then
    if success == 1 or success == true then
      ns.DB.bossEventsSeen = true
      local k = enc and enc.kill
      if k and ns.HasBossEntry(ns.run, k) then
        -- The kill event came during this fight: the same kill (its name, if
        -- the kill event didn't have one).
        if k.anonymous and name then
          -- (A mark the game names is the game's kill, as below.)
          if k.manual then k.manual, k.src, k.byHand = nil, nil, nil end
          NameOrRedo(k, id, name)
        elseif not k.anonymous and name and type(k.name) == "string" and not ns.NameSimilar(name, k.name)
            and (k.manual or (killAt[k] and enc.at and killAt[k] < enc.at)) then
          -- The kill event's kill has another name, and it was your mark (of
          -- another boss) or a kill from before this fight: a second kill.
          ns.AddBoss(id, name)
        end
      else
        ns.AddBoss(id, name)
      end
    elseif success == 0 or success == false then
      ns.DB.bossEventsSeen = true
      if not (enc and enc.deaths) and ns.AnyoneDead() then
        -- The fight began before a reload (or before the run), so its deaths
        -- weren't counted from the start; someone lying dead now means a wipe.
        AddWipe(name)
      else
        wipeCheck = { boss = name, deaths = enc and enc.deaths or #ns.run.deaths, untilAt = GetTime() + 5 }
      end
    end
  end
  ns.Fire("ENCOUNTER_OVER")
end)

ns.On("BOSS_KILL", function(id, name)
  if not ns.DB then return end
  id, name = plain(id), plain(name)
  if ns.InRun() then
    -- Even with the name and id hidden it's a kill ("Boss 3"); the other event
    -- for the same kill is merged with it. During a fight, the fight's own
    -- name and id fill in what's hidden.
    ns.DB.bossEventsSeen = true
    local enc = ns.encounter
    if type(id) ~= "number" then id = enc and enc.id or nil end
    if type(name) ~= "string" then name = enc and enc.name or nil end
    local added, same = ns.AddBoss(id, name)
    if enc then enc.kill = added or same end
  end
end)

-- A fight you left (hearth, disconnect, reload) never sends its end event.
local function ForgetEncounter() ns.encounter, wipeCheck = nil, nil end
ns.Listen("RUN_START", ForgetEncounter)
ns.Listen("RUN_LEFT", ForgetEncounter)
ns.On("PLAYER_ENTERING_WORLD", function() ns.encounter = nil end)

---------------------------------------------------------------------------
-- Deaths and wipes
---------------------------------------------------------------------------
local deadState = {}  -- [name] = true/false (last readable state of others)
local selfDied = false -- the death event fired and you haven't come back yet

local function AddDeath(name)
  local run = ns.run
  run.deaths[#run.deaths + 1] = { t = RunTime(run), who = name, v = run.visit, st = ns.ServerTime() }
  ns.Log("death", "%s died at %ds", name, RunTime(run))
  ns.Fire("DEATH", name)
end

ns.On("PLAYER_DEAD", function()
  selfDied = true
  if ns.DB and ns.InRun() then AddDeath(ns.PlayerName() or "You") end
end)

-- Dead (true), alive (false) or can't tell right now (nil). Others' Feign Death
-- isn't a death; your own is handled by only counting the death event.
local function UnitDead(unit, isSelf)
  local dead = plain(UnitIsDeadOrGhost(unit))
  if dead == nil then return nil end
  if isSelf then
    if not dead then selfDied = false end
    return dead and selfDied
  end
  if dead and UnitIsFeignDeath then
    local feign = plain(UnitIsFeignDeath(unit))
    if feign == nil then return nil end
    if feign then return false end
  end
  return dead and true or false
end

-- For /runbook check: group members, how many names and alive/dead states can
-- be read (if the game hides them, others' deaths can't be logged).
function ns.GroupReadability()
  local units = ns.GroupUnits()
  local names, deads = 0, 0
  for _, unit in ipairs(units) do
    if UnitShortName(unit) then names = names + 1 end
    if UnitDead(unit, ns.IsPlayerUnit(unit)) ~= nil then deads = deads + 1 end
  end
  return #units, names, deads
end

-- A group member out in the open world (killed on a repair trip): not a death
-- in the run. Outdoors: a zone or the small map of a spot in one (like a
-- dungeon's entrance) - and, while you're inside, not on your map or a floor
-- of it (a dungeon whose map is a zone). (Their map can't always be read;
-- then it counts.)
local OUTDOOR = { [1] = true, [2] = true, [3] = true, [5] = true }
local function OutsideWorld(unit)
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return false end
  local ui = ns.Call(C_Map.GetBestMapForUnit, unit)
  if type(ui) ~= "number" then return false end
  if ns.inside then
    local mine = ns.Call(C_Map.GetBestMapForUnit, "player")
    if mine == ui then return false end
    if type(mine) == "number" and C_Map.GetMapGroupID then
      local g1, g2 = ns.Call(C_Map.GetMapGroupID, ui), ns.Call(C_Map.GetMapGroupID, mine)
      if type(g1) == "number" and g1 > 0 and g1 == g2 then return false end
    end
  end
  local info = ns.Call(C_Map.GetMapInfo, ui)
  local kind = type(info) == "table" and plain(info.mapType) or nil
  return OUTDOOR[kind] == true
end

-- Anyone in the group dead right now (that can be read)? Feign Death isn't.
function ns.AnyoneDead()
  for _, unit in ipairs(ns.GroupUnits()) do
    local isSelf = ns.IsPlayerUnit(unit)
    if UnitDead(unit, isSelf) and (isSelf or not OutsideWorld(unit)) then return true end
  end
  return false
end

-- Logging in dead (a reload before releasing): you did die.
ns.Listen("LOGIN", function()
  if plain(UnitIsDeadOrGhost("player")) == true then selfDied = true end
end)

local awayDead = {}   -- [name] = true: lying dead out in the world

function ns.CheckDeaths()
  local run = ns.run
  if wipeCheck and run and #run.deaths > wipeCheck.deaths then
    AddWipe(wipeCheck.boss)
    wipeCheck = nil
  elseif wipeCheck and GetTime() > wipeCheck.untilAt then
    ns.Log("wipe", "%s reset with no deaths: not a wipe", tostring(wipeCheck.boss))
    wipeCheck = nil
  end
  if not run or not Watching() then return end
  local members, deadCount, allKnown, newlyDead = 0, 0, true, false
  for _, unit in ipairs(ns.GroupUnits()) do
    local name = UnitShortName(unit)
    local online = ns.IsPlayerUnit(unit) or not UnitIsConnected or ns.Call(UnitIsConnected, unit) ~= false
    local isSelf = ns.IsPlayerUnit(unit)
    local dead
    if name and online then dead = UnitDead(unit, isSelf) end
    -- (Dead out in the world: not in this run, nor in the count for a wipe.
    -- Looked up once as they die, not every second while they lie there.)
    local away = false
    if dead and not isSelf then
      if deadState[name] ~= true then awayDead[name] = OutsideWorld(unit) or nil end
      away = awayDead[name] == true
    elseif name then
      awayDead[name] = nil
    end
    if away then deadState[name] = true end
    if name and online and not away then
      members = members + 1
      if dead == nil then
        allKnown = false
      else
        if dead then deadCount = deadCount + 1 end
        if not isSelf and dead and deadState[name] == false then
          newlyDead = true
          AddDeath(name)
        elseif isSelf and dead and deadState[name] == false then
          newlyDead = true  -- your death was recorded by the event
        end
        deadState[name] = dead
      end
    end
  end
  -- A wipe: at least two of you, and (nearly) everyone dead at once.
  if newlyDead and allKnown and members >= 2
      and deadCount >= math.max(2, math.ceil(members * ns.WIPE_SHARE)) then
    AddWipe(ns.encounter and ns.encounter.name or nil)
  end
end

ns.Listen("TICK", function() ns.CheckDeaths() end)
-- A new run, or coming back from a trip outside alive: forget states so nobody
-- "dies" on arrival. After a ghost run they were being watched, so keep them.
ns.Listen("RUN_START", function() wipe(deadState) end)
ns.Listen("RUN_RESUME", function(_, wasGhost) if not wasGhost then wipe(deadState) end end)

---------------------------------------------------------------------------
-- Loot value
---------------------------------------------------------------------------
function ns.AuctionPrice(itemID)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not api or not api.GetAuctionPriceByItemID then return nil end
  local ok, price = pcall(api.GetAuctionPriceByItemID, ns.name, itemID)
  if ok and type(price) == "number" and price > 0 then return price end
  return nil
end

local function SellPrice(itemID)
  if not ns.GetItemInfo then return nil end
  local ok, a, _, _, _, _, _, _, _, _, _, price = pcall(ns.GetItemInfo, itemID)
  if not ok or plain(a) == nil then return nil end  -- not cached yet
  price = plain(price)
  return type(price) == "number" and price or 0
end

-- Your loot's value: vendor price, and the AH price (after the 5% cut) when
-- Auctionator knows one. Items whose data hasn't loaded wait in run.pending.
-- Items waiting for a price are kept per item and per visit, so a later split
-- can give each one's value to the run it was looted in.
local function AddValue(run, itemID, qty)
  local price = SellPrice(itemID)
  if price == nil then
    local v = run.visit or 1
    local key = itemID .. ":" .. v
    local p = run.pending[key]
    if not p then
      p = { id = itemID, n = 0, tries = 0, v = v }
      run.pending[key] = p
    end
    p.n = p.n + qty
    if ns.RequestItemLoad then pcall(ns.RequestItemLoad, itemID) end
    return
  end
  local vendor = price * qty
  local ah = ns.AuctionPrice(itemID)
  run.loot = run.loot + vendor
  run.lootAH = run.lootAH + (ah and math.max(vendor, math.floor(ah * 0.95) * qty) or vendor)
end

-- A late price for something looted before your last trip outside also goes
-- into that point's totals, so a split puts it in the right run.
local function AddLateValue(run, p)
  local snap = run.resumeSnap
  local before = run.loot
  local beforeAH = run.lootAH
  AddValue(run, p.id, p.n)
  if snap and (p.v or 1) < snap.visit then
    snap.loot = snap.loot + (run.loot - before)
    snap.lootAH = snap.lootAH + (run.lootAH - beforeAH)
  end
end

---------------------------------------------------------------------------
-- Drops
---------------------------------------------------------------------------
-- You and your partner count as "the duo": the partner you set (or that sync
-- set for you), or, until there is one, any RunBook user in a group of five.
local function IsDuo(who)
  if who == nil then return false end
  if who == ns.PlayerName() or who == "You" then return true end
  local partner = ns.DB.partner
  if partner then return ns.SameName(who, partner) or (ns.IsPartnerChar ~= nil and ns.IsPartnerChar(who)) end
  return ns.partnersSeen[who] ~= nil
end
ns.IsDuo = IsDuo

-- The duo of a saved run: whoever ran it (an alt's run counts that alt) and the
-- partner whose numbers it has, as well as you two now.
function ns.IsRunDuo(run, who)
  if IsDuo(who) or who == nil then return who ~= nil end
  if run.char and ns.SameName(who, ns.ShortName(run.char) or run.char) then return true end
  if type(run.partners) ~= "table" then return false end
  if run.partners[who] ~= nil then return true end
  for k in pairs(run.partners) do
    if type(k) == "string" and ns.SameName(ns.ShortName(k), who) then return true end
  end
  return false
end

-- Keep a drop in the list? Yours and your partner's from the quality setting
-- up (green by default); other players' from blue up, so a pug's or a raid's
-- greens don't bury yours.
function ns.KeepDrop(who, q)
  if q == nil then return true end  -- unknown yet; decided once it loads
  local min = ns.DB.quality or 2
  if not IsDuo(who) then min = math.max(min, 3) end
  return q >= min
end

-- Records one sighting of a drop. The same drop can be seen up to twice (its
-- loot message, and your bags or your partner's sync), so a sighting from a
-- new source first looks for a matching entry that source hasn't seen yet.
-- mode: nil (match an entry this source hasn't seen, else add one), "mark"
-- (only mark a match, never add), or "new" (always add).
-- when: when it was looted (server time; default now).
local function NoteDrop(run, who, itemID, qty, link, source, mode, when)
  when = when or ns.ServerTime()
  if mode ~= "new" then
    for _, d in ipairs(run.drops) do
      -- (Seen by another source about when it was looted: the same drop. One
      -- looted well before or after isn't.)
      if d.who == who and d.id == itemID and not d[source] and math.abs((d.st or 0) - when) <= 30 then
        d[source] = true
        if link and not d.link then d.link = link end
        return d, false
      end
    end
    if mode == "mark" then return nil, false end
  end
  local q = ns.ItemQuality(itemID, link)
  if q == nil and ns.RequestItemLoad then pcall(ns.RequestItemLoad, itemID) end  -- so it resolves soon
  if not ns.KeepDrop(who, q) then return nil, true end
  local d = {
    id = itemID, link = link, name = link and ns.LinkName(link) or ns.ItemName(itemID) or ("item:" .. itemID),
    q = q, n = qty, who = who, t = RunTime(run), v = run.visit, [source] = true, st = when,
  }
  run.drops[#run.drops + 1] = d
  ns.Touch(run)
  ns.Fire("DROP", d)
  return d, true
end
ns.NoteDrop = NoteDrop

-- Fills in names and qualities of drops whose item data has now loaded, removes
-- those below the quality setting, and values your pending loot (fromTick:
-- counts a retry; a give-up after a minute keeps the count, value 0).
function ns.ResolveItems(run, final, fromTick)
  run = run or ns.run
  if not run then return end
  for i = #run.drops, 1, -1 do
    local d = run.drops[i]
    if d.q == nil then
      d.q = ns.ItemQuality(d.id, d.link)
      if d.q ~= nil and not ns.KeepDrop(d.who, d.q) then table.remove(run.drops, i) end
    end
    if d.name and d.name:match("^item:%d+$") then d.name = ns.ItemName(d.id) or d.name end
  end
  for key, p in pairs(run.pending) do
    local price = SellPrice(p.id)
    if price ~= nil then
      run.pending[key] = nil
      AddLateValue(run, p)
    elseif final or fromTick then
      p.tries = p.tries + 1
      if final or p.tries >= ns.PENDING_MAX_TRIES then
        run.pending[key] = nil
        run.unpriced = run.unpriced + p.n
        local snap = run.resumeSnap
        if snap and (p.v or 1) < snap.visit then snap.unpriced = snap.unpriced + p.n end
      end
    end
  end
end

function ns.FlushPending(run)
  ns.ResolveItems(run, true)
end

ns.Listen("TICK", function() if ns.run then ns.ResolveItems(ns.run, false, true) end end)

-- Names and qualities that load late also fill in your last few saved runs
-- (and an open history window shows them).
local function ResolveNames(run)
  local changed = false
  local before = #run.drops
  for i = #run.drops, 1, -1 do
    local d = run.drops[i]
    if d.q == nil then
      d.q = ns.ItemQuality(d.id, d.link)
      if d.q ~= nil then
        changed = true
        if not ns.KeepDrop(d.who, d.q) then table.remove(run.drops, i) end
      end
    end
    if d.name and d.name:match("^item:%d+$") then
      local n = ns.ItemName(d.id)
      if n then d.name, changed = n, true end
    end
  end
  if changed then ns.Fire("HISTORY_CHANGED") end
  if changed or #run.drops ~= before then ns.Touch(run) end
end

-- Is this item one we're waiting on (a price, a name or a quality)?
local function Waiting(run, itemID)
  for _, p in pairs(run.pending or {}) do if p.id == itemID then return true end end
  for _, d in ipairs(run.drops or {}) do
    if d.id == itemID and (d.q == nil or (d.name and d.name:match("^item:%d+$"))) then return true end
  end
  return false
end

-- Fires for every item any addon loads (an auction scan loads thousands), so
-- only items we're waiting on do any work.
ns.On("ITEM_DATA_LOAD_RESULT", function(itemID, success)
  if not ns.DB or not plain(success) then return end
  itemID = plain(itemID)
  if type(itemID) ~= "number" then return end
  if ns.run and Waiting(ns.run, itemID) then
    ns.ResolveItems(ns.run)
    ns.Fire("DROP")
  end
  for i = 1, 3 do
    local r = ns.DB.history[i]
    if r and r.drops and Waiting(r, itemID) then ResolveNames(r) end
  end
end)

-- Your own loot, from whichever source saw it first; the other source's
-- sighting of the same item is matched up instead of counted again.
local credit = { chat = {}, bag = {} }  -- [source][itemID] = { n, at }

-- hidden: a bag gain counted while loot messages were hidden (its loot message
-- may never come, so a readable one well after it is a new loot).
local function Credit(source, itemID, qty, hidden)
  local c = credit[source][itemID]
  if not c or GetTime() - c.at > ns.LOOT_MATCH_SECONDS or (c.hidden or false) ~= (hidden or false) then
    c = { n = 0, hidden = hidden }
    credit[source][itemID] = c
  end
  c.n, c.at = c.n + qty, GetTime()
end

-- Takes up to qty from the other source's unmatched sightings; returns what's left.
local function Consume(other, itemID, qty)
  local c = credit[other][itemID]
  -- (A bag gain from while loot messages were hidden matches a loot message only
  -- a moment later - the same loot, out of order - not a later loot.)
  if not c or GetTime() - c.at > (c.hidden and 5 or ns.LOOT_MATCH_SECONDS) then return qty end
  local used = math.min(c.n, qty)
  c.n = c.n - used
  return qty - used
end

-- markOnly: a bag gain while loot messages are readable. It's only matched
-- up with a loot message, never counted on its own (it may be a crafted item,
-- a quest reward or a bag you took off).
local function OwnLoot(itemID, qty, link, source, markOnly)
  local run = ns.run
  local me = ns.PlayerName() or "You"
  local other = source == "chat" and "bag" or "chat"
  local rest = Consume(other, itemID, qty)
  if rest < qty then
    -- Already counted from the other source; just mark the drop as seen here.
    NoteDrop(run, me, itemID, 0, link, source, "mark")
  end
  if rest <= 0 or markOnly then return end
  Credit(source, itemID, rest, source == "bag")
  AddValue(run, itemID, rest)
  local d, isNew = NoteDrop(run, me, itemID, rest, link, source, "new")
  if d and isNew and ns.SyncDrop then
    ns.SyncDrop(run, d)
  elseif not d and isNew and ns.SyncDrop then
    -- Below your quality setting, but your partner's may be lower: greens and
    -- up go to them anyway (their setting decides what their log keeps).
    local q = ns.ItemQuality(itemID, link)
    if type(q) == "number" and q >= 2 then ns.SyncDrop(run, { id = itemID, n = rest, q = q, st = ns.ServerTime() }) end
  end
end

ns.On("CHAT_MSG_LOOT", function(msg)
  if not ns.InRun() then return end
  local text = plain(msg)
  if type(text) ~= "string" then
    -- Hidden by the client (during a boss fight, or in all of an instance).
    -- Your bags tell what you got (see below).
    ns.stats.lootSecret = ns.stats.lootSecret + 1
    ns.lastHiddenLootAt = GetTime()
    return
  end
  local who, link, itemID, qty = ns.ParseLoot(text)
  if not who then return end
  ns.stats.lootRead = ns.stats.lootRead + 1
  ns.Log("loot", "%s: item %d x%d", who, itemID, qty)
  if who == "self" then
    OwnLoot(itemID, qty, link, "chat")
  else
    NoteDrop(ns.run, ns.ShortName(who) or who, itemID, qty, link, "chat")
  end
end)

---------------------------------------------------------------------------
-- Bags: what you gained, a second source for your own loot. Equipped items
-- count too, so swapping gear isn't "new" items. Gains while a vendor, mailbox
-- or trade window is open (or just closed) are purchases, not loot.
---------------------------------------------------------------------------
local bagCounts       -- [itemID] = count, nil until the first scan
local bagLinks = {}   -- [itemID] = link seen in your bags
local bagDirtyAt      -- GetTime() of the last bag change not yet scanned

local function ScanBags()
  local counts = {}
  local C = C_Container
  if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return nil end
  local lastBag = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
  for bag = 0, lastBag do
    local slots = ns.Call(C.GetContainerNumSlots, bag) or 0
    for slot = 1, slots do
      local info = ns.Call(C.GetContainerItemInfo, bag, slot)
      if type(info) == "table" then
        local id, n = plain(info.itemID), plain(info.stackCount)
        if type(id) == "number" then
          counts[id] = (counts[id] or 0) + (type(n) == "number" and n or 1)
          local link = plain(info.hyperlink)
          if type(link) == "string" then bagLinks[id] = link end
        end
      end
    end
  end
  if GetInventoryItemID then
    -- Gear (not the ammo slot: its count is the ammo already in your bags) and
    -- the bags themselves, so equipping or swapping isn't "new".
    local slots = {}
    for slot = 1, 19 do slots[#slots + 1] = slot end
    if C.ContainerIDToInventoryID then
      for bag = 1, lastBag do
        local inv = ns.Call(C.ContainerIDToInventoryID, bag)
        if type(inv) == "number" then slots[#slots + 1] = inv end
      end
    end
    for _, slot in ipairs(slots) do
      local id = ns.Call(GetInventoryItemID, "player", slot)
      if type(id) == "number" then counts[id] = (counts[id] or 0) + 1 end
    end
  end
  return counts
end

function ns.BagBaseline()
  bagCounts = ScanBags()
  bagDirtyAt = nil
end

local BAG_DIP_SECONDS = 10
local bagDips = {}  -- [itemID] = { n = count before it dipped, at = when }

local function ProcessBags()
  -- (No run here: nothing to count, so no scan; a run takes its own baseline.)
  if not ns.InRun() then bagCounts = nil return end
  local new = ScanBags()
  if not new then return end
  local old = bagCounts
  bagCounts = new
  if not old or not ns.InRun() or ns.MoneyBlocked() then return end
  -- Bag gains count as loot only while loot messages are hidden; otherwise
  -- the loot message is the record and the bag change just confirms it.
  local hidden = ns.lastHiddenLootAt and GetTime() - ns.lastHiddenLootAt <= ns.LOOT_MATCH_SECONDS
  local now = GetTime()
  -- A stack that dipped a moment ago (split onto the cursor, moved between
  -- bags) and comes back isn't loot: only what's above where it was counts.
  for id, n in pairs(old) do
    if (new[id] or 0) < n then
      local d = bagDips[id]
      if not d or now - d.at > BAG_DIP_SECONDS then d = { n = n } end
      d.at = now
      bagDips[id] = d
    end
  end
  for id, n in pairs(new) do
    local was = old[id] or 0
    local d = bagDips[id]
    if d and now - d.at <= BAG_DIP_SECONDS then was = math.max(was, d.n) end
    local gained = n - was
    if gained > 0 then
      if hidden then ns.stats.bagLoot = ns.stats.bagLoot + 1 end
      ns.Log("loot", "bags: +%d of item %d%s", gained, id, hidden and "" or " (matched only)")
      OwnLoot(id, gained, bagLinks[id], "bag", not hidden)
    end
  end
end

ns.On("BAG_UPDATE_DELAYED", function() bagDirtyAt = GetTime() end)
ns.On("UNIT_INVENTORY_CHANGED", function(unit)
  if plain(unit) == "player" then bagDirtyAt = GetTime() end
end)
-- Scanned a second after the bags settle, so the loot message (if readable)
-- has arrived and the two can be matched.
ns.Listen("TICK", function()
  if bagDirtyAt and GetTime() - bagDirtyAt >= 1 then
    bagDirtyAt = nil
    ProcessBags()
  end
end)
ns.Listen("RUN_START", function() ns.BagBaseline() end)
ns.Listen("RUN_RESUME", function() ns.BagBaseline() end)
ns.Listen("RUN_START", function() credit.chat, credit.bag = {}, {} end)  -- sightings belong to one run
ns.Listen("RUN_RESUME", function() ns.SnapshotMembers() end)  -- who's with you now
ns.Listen("LOGIN", function() ns.BagBaseline() end)

---------------------------------------------------------------------------
-- Coin and XP: changes while inside. Money that changes hands at a vendor,
-- mailbox or trade window (and just after one closes) isn't run income.
---------------------------------------------------------------------------
local blockers, blockUntil = {}, 0
local lastMoney, lastXP, lastXPMax

function ns.SetMoneyWindow(key, open)
  if open then
    blockers[key] = true
  elseif blockers[key] then
    blockers[key] = nil
    blockUntil = GetTime() + 3
  end
  -- Purchases and trades land in your bags while the window is open: take a
  -- new bag baseline when it closes so they aren't counted as loot.
  if not open then
    bagDirtyAt = nil
    if ns.InRun() then ns.BagBaseline() else bagCounts = nil end
  end
end

function ns.MoneyBlocked()
  return next(blockers) ~= nil or GetTime() < blockUntil
end

function ns.ResetBaselines()
  lastMoney = plain(GetMoney())
  lastXP, lastXPMax = plain(UnitXP("player")), plain(UnitXPMax("player"))
end

ns.On("PLAYER_MONEY", function()
  local money = plain(GetMoney())
  if type(money) ~= "number" then return end
  if lastMoney and ns.InRun() and not ns.MoneyBlocked() and money > lastMoney then
    ns.run.coin = ns.run.coin + (money - lastMoney)
  end
  lastMoney = money
end)

ns.On("PLAYER_XP_UPDATE", function(unit)
  unit = plain(unit)
  if unit ~= nil and unit ~= "player" then return end
  local cur, max = plain(UnitXP("player")), plain(UnitXPMax("player"))
  if type(cur) ~= "number" or type(max) ~= "number" then return end
  if lastXP and ns.InRun() then
    local gained
    if cur >= lastXP then
      gained = cur - lastXP
    else
      gained = (lastXPMax or 0) - lastXP + cur  -- leveled: rest of the old bar + new progress
    end
    if gained > 0 then ns.run.xp = ns.run.xp + gained end
  end
  lastXP, lastXPMax = cur, max
end)

ns.On("PLAYER_ENTERING_WORLD", function() ns.ResetBaselines() end)
ns.Listen("LOGIN", function() ns.ResetBaselines() end)

for event, info in pairs({
  MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
  MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
  TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
}) do
  ns.On(event, function() ns.SetMoneyWindow(info[1], info[2]) end)
end

-- Newer clients report these windows through the interaction manager instead.
local INTERACTION_KEYS = {}
if Enum and Enum.PlayerInteractionType then
  local T = Enum.PlayerInteractionType
  for key, name in pairs({ Merchant = "merchant", MailInfo = "mail", TradePartner = "trade" }) do
    if T[key] then INTERACTION_KEYS[T[key]] = name end
  end
end
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind)
  local key = INTERACTION_KEYS[plain(kind) or false]
  if key then ns.SetMoneyWindow(key, true) end
end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind)
  local key = INTERACTION_KEYS[plain(kind) or false]
  if key then ns.SetMoneyWindow(key, false) end
end)

---------------------------------------------------------------------------
-- Notes
---------------------------------------------------------------------------
ns.NOTE_MAX_BYTES = 180

-- Adds a note to `run` (default: the run in progress, else your last run).
-- Returns the run it went to (or nil), whether the text was cut short, and the
-- note if it was added (nil if that exact note was already there).
function ns.AddNote(text, who, run)
  run = run or ns.RunOrLast()
  if not run or type(text) ~= "string" then return nil end
  local clean = ns.CleanText(text)
  -- Yours: short enough to reach your partner whole, so both logs match.
  local max = ns.NOTE_MAX_BYTES
  if not who and ns.SyncNoteRoom then max = math.max(40, math.min(max, ns.SyncNoteRoom(run))) end
  local cut = #clean > max
  clean = ns.Truncate(clean, max)
  if clean == "" then return nil end
  who = who or ns.PlayerName() or "You"
  for _, n in ipairs(run.notes) do
    if n.who == who and n.text == clean then return run, cut, nil end  -- already have it
  end
  -- Run time only for notes made during the run (a note added afterwards has none).
  local t
  if run == ns.run then t = RunTime(run) end
  local note = { who = who, text = clean, t = t, v = run.visit, st = ns.ServerTime() }
  run.notes[#run.notes + 1] = note
  ns.Touch(run)
  ns.Fire("NOTE", run)
  return run, cut, note
end
