-- RunBook: saved data, history, and per-dungeon stats.
--   VulcanRunBookDB      (account): settings, run history, instance entries (for the cap)
--   VulcanRunBookCharDB  (per character): the run in progress, recent dungeon resets,
--                 plus a backup of the account data (see LoadSavedData)
local _, ns = ...

---------------------------------------------------------------------------
-- Tunables
---------------------------------------------------------------------------
ns.HISTORY_MAX = 200         -- runs kept in full detail
ns.OLD_MAX = 2000            -- older runs kept in short form, for stats and best times
ns.DELETED_MAX = 5000        -- remembered deletions at most (so a backup can't bring runs back)
ns.CAP_WINDOW = 3600         -- the instance cap counts entries in the last hour
ns.CAP_DAY = 86400           -- and the daily cap, in the last 24 hours
ns.RUN_TIMEOUT = 1800        -- out of a dungeon this long (alive) ends the run
ns.RAID_TIMEOUT = 7200       -- raids: breaks are longer
ns.GHOST_MAX = 600           -- a corpse run counts toward run time for at most this long
ns.MIN_KEEP_SECONDS = 60     -- shorter runs with nothing in them aren't kept
ns.MIN_RATE_SECONDS = 300    -- no per-hour rates off less than 5 minutes
ns.FINAL_VOTES = 2           -- runs that must end on a boss before it's the final boss
ns.DB_VERSION = 1

-- Settings: also kept in each character's backup, so a failed account load
-- doesn't reset them.
local SETTINGS = {
  autoShow = true,       -- live window shows itself in dungeons and hides outside
  locked = false, scale = 1,
  sync = true,
  quiet = false,         -- true: no chat line per boss kill or run start
  cap = 5,               -- instances per hour; 0 = don't track
  capDay = 30,           -- instances per day (Classic's other limit); 0 = don't track
  quality = 2,           -- lowest quality listed for you and your partner (2 = green)
  priceSource = "vendor",
  welcomed = false,
}
-- Settings that may be nil (no default value).
local OPTIONAL_SETTINGS = { "partner", "point", "finals" }

local DEFAULTS = {
  version = ns.DB_VERSION,
  debug = false, debugEcho = false, debugLog = {},
  point = { "CENTER", "CENTER", -320, 120 },
  history = {},          -- newest first, full detail
  old = {},              -- older runs, short form, newest first
  finals = {},           -- [dungeon key] = { id, name } final boss you pinned
  deleted = {},          -- [run uid] = when you deleted it (server time; true from older builds)
  clearedAt = 0,         -- /runbook clear yes: runs that ended before this are gone
  entries = {},          -- server times you entered a new instance
  nextId = 1,            -- run numbers shown in the history (never reused)
  savedAt = 0,           -- 0 = this account data was never saved (or didn't load)
}
for k, v in pairs(SETTINGS) do DEFAULTS[k] = v end

local function CopyDefaults(src, dst)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = CopyDefaults(v, {}) end
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end
ns.CopyDefaults = CopyDefaults

local RUN_DEFAULTS = {
  elapsed = 0, coin = 0, loot = 0, lootAH = 0, xp = 0, unpriced = 0,
  bosses = {}, wipes = {}, deaths = {}, drops = {}, notes = {}, members = {},
  partners = {}, pending = {},
}

-- A damaged file (or another addon's data under the same name) can hold any
-- value anywhere: everything that's compared, added or shown is checked.
local function Finite(v) return type(v) == "number" and v == v and v > -1e15 and v < 1e15 end
-- A partner total: five finite numbers (run time, coin, loot, loot at AH, XP).
local function FiveNumbers(t)
  if type(t) ~= "table" then return false end
  for i = 1, 5 do if not Finite(t[i]) then return false end end
  return true
end
ns.FiveNumbers = FiveNumbers
ns.Finite = Finite

local function NumOrNil(t, keys)
  for _, k in ipairs(keys) do if t[k] ~= nil and not Finite(t[k]) then t[k] = nil end end
end
local function StrOrNil(t, keys)
  for _, k in ipairs(keys) do if t[k] ~= nil and type(t[k]) ~= "string" then t[k] = nil end end
end
local RUN_NUMBERS = { "copyFrom",
  "startedAt", "serverStart", "serverEnd", "savedServer", "endedAt", "modified", "id", "lastIn",
  "leftAt", "leftServer", "deadAt", "visit", "mapID", "diff", "prevLeft", "pendingEntry", "keepAfterClear" }
local RUN_STRINGS = { "wing", "diffName", "kind", "char", "endReason" }
local ITEM_NUMBERS = { "t", "st", "v", "id", "q", "n" }
local ITEM_STRINGS = { "name", "link", "who", "key", "peer", "boss", "text", "wing" }

local FixItems
local function FixEntryBy(t, k)
  local e = t[k]
  if e == nil then return end
  if type(e) ~= "table" then t[k] = nil return end
  NumOrNil(e, { "at" })
  if e.kills ~= nil then
    if type(e.kills) ~= "table" then e.kills = nil else FixItems(e.kills) end
  end
end

FixItems = function(list)
  for i = #list, 1, -1 do
    local item = list[i]
    if type(item) ~= "table" then
      table.remove(list, i)
    else
      NumOrNil(item, ITEM_NUMBERS)
      StrOrNil(item, ITEM_STRINGS)
      FixEntryBy(item, "entryBy")
    end
  end
end

ns.FixItems = function(list) FixItems(list) end

-- Fills in anything a run saved by an older build (or a damaged file) lacks.
function ns.FixRun(run)
  for k, v in pairs(RUN_DEFAULTS) do
    if run[k] ~= nil and type(run[k]) ~= type(v) then run[k] = nil end
  end
  CopyDefaults(RUN_DEFAULTS, run)
  NumOrNil(run, RUN_NUMBERS)
  StrOrNil(run, RUN_STRINGS)
  if run.map ~= nil and type(run.map) ~= "string" and not Finite(run.map) then run.map = nil end
  -- A resume point needs every number a split uses, or it's no use.
  for _, k in ipairs({ "resumeSnap", "reopenSnap", "ghostSnap" }) do
    local snap = run[k]
    if snap ~= nil then
      if type(snap) ~= "table" then
        run[k] = nil
      else
        for _, f in ipairs({ "visit", "elapsed", "coin", "loot", "lootAH", "xp", "unpriced", "wall", "server" }) do
          if not Finite(snap[f]) then run[k] = nil break end
        end
      end
    end
  end
  if run.unbossed ~= nil and type(run.unbossed) ~= "table" then run.unbossed = nil end
  FixEntryBy(run, "entryBy")
  if type(run.entryBy) == "table" and run.entryBy.boss ~= nil then
    if type(run.entryBy.boss) ~= "table" then
      run.entryBy.boss = nil
    else
      NumOrNil(run.entryBy.boss, { "id" })
      StrOrNil(run.entryBy.boss, { "name" })
    end
  end
  if run.startTotals ~= nil then
    if type(run.startTotals) ~= "table" then
      run.startTotals = nil
    else
      for k, v in pairs(run.startTotals) do
        if type(k) ~= "string" or not FiveNumbers(v) then run.startTotals[k] = nil end
      end
    end
  end
  run.entryTimes = nil  -- (kept by older builds; never used)
  if run.copyKills ~= nil then
    if type(run.copyKills) ~= "table" then run.copyKills = nil else FixItems(run.copyKills) end
  end
  for i = #run.members, 1, -1 do if type(run.members[i]) ~= "string" then table.remove(run.members, i) end end
  for _, list in ipairs({ run.bosses, run.wipes, run.deaths, run.drops, run.notes }) do FixItems(list) end
  for _, k in ipairs({ "elapsed", "coin", "loot", "lootAH", "xp", "unpriced" }) do
    if not Finite(run[k]) or run[k] < 0 then run[k] = 0 end
  end
  if type(run.name) ~= "string" then run.name = "?" end
  if type(run.label) ~= "string" then run.label = run.name end
  -- Everything has a run time except notes added after the run ended.
  for _, list in ipairs({ run.bosses, run.wipes, run.deaths, run.drops }) do
    for _, item in ipairs(list) do
      if type(item.t) ~= "number" then item.t = 0 end
    end
  end
  for _, b in ipairs(run.bosses) do
    if type(b.name) ~= "string" then b.name = "?" end
  end
  for _, d in ipairs(run.drops) do
    if type(d.n) ~= "number" or d.n < 1 then d.n = 1 end
    if type(d.who) ~= "string" then d.who = "?" end
    if type(d.id) ~= "number" then d.id = 0 end
    if type(d.name) ~= "string" then d.name = "item:" .. d.id end
  end
  for _, d in ipairs(run.deaths) do
    if type(d.who) ~= "string" then d.who = "?" end
  end
  for _, n in ipairs(run.notes) do
    if type(n.text) ~= "string" then n.text = "" end
    if type(n.who) ~= "string" then n.who = "?" end
    if type(n.t) ~= "number" then n.t = nil end
  end
  if run.group ~= nil and type(run.group) ~= "table" then run.group = nil end
  for _, field in ipairs({ "partners", "group" }) do
  for name, p in pairs(run[field] or {}) do
    if type(p) ~= "table" or type(name) ~= "string" then
      run[field][name] = nil
    else
      for _, k in ipairs({ "elapsed", "coin", "loot", "lootAH", "xp" }) do
        if not Finite(p[k]) then p[k] = 0 end
      end
      if p.parts ~= nil and type(p.parts) ~= "table" then p.parts = nil end
      for key, part in pairs(p.parts or {}) do
        if type(key) ~= "string" or type(part) ~= "table" then
          p.parts[key] = nil
        else
          NumOrNil(part, { "at", "raw", "elapsed", "coin", "loot", "lootAH", "xp" })
          for _, f in ipairs({ "base", "rawv", "credit" }) do
            if part[f] ~= nil and not FiveNumbers(part[f]) then part[f] = nil end
          end
        end
      end
    end
  end
  end
  -- (The group view holds a raid's worth at most.)
  local n = 0
  for name in pairs(run.group or {}) do
    n = n + 1
    if n > 40 then run.group[name] = nil end
  end
  for k, p in pairs(run.pending) do
    if type(p) ~= "table" or not Finite(p.id) or not Finite(p.n) then
      run.pending[k] = nil
    else
      NumOrNil(p, { "tries", "v", "st", "q", "t", "at" })
      StrOrNil(p, { "who", "link", "name" })
      p.tries = p.tries or 0
    end
  end
  return run
end

-- A run's identity across characters and saved copies.
function ns.RunUID(run)
  return tostring(run.serverStart or run.startedAt or 0) .. ":" .. tostring(run.char or "") .. ":"
    .. tostring(run.name or "")
end

local function NumberList(list)
  local out, seen = {}, {}
  if type(list) == "table" then
    for _, v in ipairs(list) do
      if Finite(v) and not seen[v] then
        seen[v] = true
        out[#out + 1] = v
      end
    end
  end
  return out
end

-- A short-form run from a damaged file: make sure stats can read it.
local function FixLite(run)
  NumOrNil(run, RUN_NUMBERS)
  NumOrNil(run, { "pg", "pgAH" })
  StrOrNil(run, RUN_STRINGS)
  if type(run.label) ~= "string" then run.label = nil end
  if run.notes ~= nil and type(run.notes) ~= "table" then run.notes = nil end
  if run.notes then FixItems(run.notes) end
  if run.unbossed ~= nil and type(run.unbossed) ~= "table" then run.unbossed = nil end
  if type(run.bosses) ~= "table" then run.bosses = {} end
  for i = #run.bosses, 1, -1 do
    local b = run.bosses[i]
    if type(b) ~= "table" or type(b.t) ~= "number" then table.remove(run.bosses, i) end
  end
  for _, b in ipairs(run.bosses) do
    if type(b.name) ~= "string" then b.name = "?" end
    NumOrNil(b, { "id", "st" })
  end
  for _, k in ipairs({ "elapsed", "coin", "loot", "lootAH", "xp", "nd", "nw", "blues", "epics" }) do
    if not Finite(run[k]) or run[k] < 0 then run[k] = 0 end
  end
  if type(run.name) ~= "string" then run.name = "?" end
  run.lite = true
  return run
end

-- Gone for good: deleted, or ended before /runbook clear yes (a run that was
-- going at the time, and anything split from it, stays).
local function Gone(run, db)
  if db.deleted[ns.RunUID(run)] then return true end
  if run.keepAfterClear == db.clearedAt then return false end  -- going at the time of this clear
  -- (Saved after the clear: kept, even if it ended earlier - a run reopened
  -- and ended again, or one that ended when you left it.)
  return math.max(run.savedServer or 0, run.serverEnd or run.serverStart or 0) < db.clearedAt
end
ns.Gone = function(run) return Gone(run, ns.DB) end

-- Runs from both copies (account data and this character's backup), each once
-- (`seen` is shared, so a run can't be in the full and the short list both),
-- newest first.
-- newer: [uid] = when a short copy was changed; a full copy older than that is
-- left out (the short one is the latest word on that run).
local function MergeRuns(a, b, db, fix, seen, newer)
  local out, idx = {}, {}
  for _, list in ipairs({ a, b }) do
    if type(list) == "table" then
      for _, run in ipairs(list) do
        if type(run) == "table" then
          if fix then ns.FixRun(run) else FixLite(run) end
          local uid = ns.RunUID(run)
          local stale = newer and newer[uid] and (tonumber(run.modified) or 0) < newer[uid]
          if not seen[uid] and not stale and not Gone(run, db) then
            local at = idx[uid]
            if not at then
              out[#out + 1] = run
              idx[uid] = #out
            else
              -- The copy changed last wins; notes and kills taken back on either
              -- copy are kept.
              local keep, other = out[at], run
              if (tonumber(run.modified) or 0) > (tonumber(keep.modified) or 0) then keep, other = run, out[at] end
              if type(keep.notes) == "table" and type(other.notes) == "table" then
                for _, n in ipairs(other.notes) do
                  local have = false
                  for _, m in ipairs(keep.notes) do
                    if type(n) == "table" and type(m) == "table" and m.who == n.who and m.text == n.text then
                      have = true
                    end
                  end
                  if not have and type(n) == "table" then keep.notes[#keep.notes + 1] = n end
                end
              end
              if type(other.unbossed) == "table" then
                keep.unbossed = type(keep.unbossed) == "table" and keep.unbossed or {}
                for k in pairs(other.unbossed) do keep.unbossed[k] = true end
              end
              if type(keep.unbossed) == "table" and type(keep.bosses) == "table" then
                -- A kill taken back on the other copy stays taken back here.
                for i = #keep.bosses, 1, -1 do
                  local k = keep.bosses[i]
                  local gone = keep.unbossed
                  if type(k) == "table" and ((k.key and gone[k.key]) or (k.peer and gone[k.peer])) then
                    table.remove(keep.bosses, i)
                  end
                end
              end
              out[at] = keep
            end
          end
        end
      end
    end
  end
  for uid in pairs(idx) do seen[uid] = true end
  table.sort(out, function(x, y) return (x.startedAt or 0) > (y.startedAt or 0) end)
  return out
end

-- Keeps the DELETED_MAX most recent deletions (by when you deleted them;
-- older builds saved `true`, taken as the oldest). A deletion is kept while
-- any backup could still hold the run, so none is dropped for being old.
local function PruneDeleted(db)
  local keys = {}
  for uid in pairs(db.deleted) do keys[#keys + 1] = uid end
  if #keys <= ns.DELETED_MAX then return end
  local function When(uid) return tonumber(db.deleted[uid]) or 0 end
  table.sort(keys, function(x, y) return When(x) > When(y) end)
  for i = ns.DELETED_MAX + 1, #keys do db.deleted[keys[i]] = nil end
end

-- Account SavedVariables were reported (beta 1.60, unverified) to be written
-- but not read back. Each character keeps a backup of the history, cap
-- entries and settings, and both copies are merged on load, so nothing is lost
-- whichever one failed. (Deletions are remembered so a backup can't bring
-- runs back.)
function ns.LoadSavedData()
  -- Saved-data safety (Persist.lua): look at what the client loaded before anything fills it in.
  if ns.Persist then ns.Persist.CheckLoad(VulcanRunBookDB, VulcanRunBookCharDB) end
  local db = type(VulcanRunBookDB) == "table" and VulcanRunBookDB or {}
  VulcanRunBookDB = db
  VulcanRunBookCharDB = type(VulcanRunBookCharDB) == "table" and VulcanRunBookCharDB or {}
  local char = VulcanRunBookCharDB
  local mirror = type(char.mirror) == "table" and char.mirror or {}
  local accountLoaded = type(db.savedAt) == "number" and db.savedAt > 0
  -- When you last logged out (server time), for what happened while you were away.
  -- (This character's: the account copy is saved by every character.)
  ns.lastSaved = tonumber(mirror.savedAt) or 0
  char.endedCopy = nil  -- (older versions; now VulcanRunBookCharDB.copies)

  -- Settings: from the backup when the account data didn't load.
  if not accountLoaded and type(mirror.settings) == "table" then
    for k in pairs(SETTINGS) do
      if db[k] == nil and mirror.settings[k] ~= nil then db[k] = mirror.settings[k] end
    end
    for _, k in ipairs(OPTIONAL_SETTINGS) do
      if db[k] == nil and mirror.settings[k] ~= nil then db[k] = mirror.settings[k] end
    end
  end
  CopyDefaults(DEFAULTS, db)
  ns.DB = db
  db.version = ns.DB_VERSION
  for _, k in ipairs({ "clearedAt", "savedAt", "nextId", "cap", "capDay", "quality", "scale" }) do
    if not Finite(db[k]) then db[k] = DEFAULTS[k] end
  end
  if db.partner ~= nil and type(db.partner) ~= "string" then db.partner = nil end
  if db.partnerRealm ~= nil and type(db.partnerRealm) ~= "string" then db.partnerRealm = nil end
  if db.partnerTag ~= nil and (type(db.partnerTag) ~= "string" or not db.partner) then db.partnerTag = nil end
  if db.partnerHeard ~= nil and type(db.partnerHeard) ~= "table" then db.partnerHeard = nil end
  -- Your partner's characters: name -> realm (or true), 20 at most.
  if db.partnerChars ~= nil then
    if type(db.partnerChars) ~= "table" or db.partner == nil then
      db.partnerChars = nil
    else
      local n = 0
      for k, v in pairs(db.partnerChars) do
        if type(k) ~= "string" or k == "" or (v ~= true and (type(v) ~= "string" or v == "")) then
          db.partnerChars[k] = nil
        else
          n = n + 1
          if n > 20 and not ns.SameName(k, db.partner) then db.partnerChars[k] = nil end
        end
      end
    end
  end
  local pt = db.point
  if type(pt) ~= "table" or type(pt[1]) ~= "string" or type(pt[2]) ~= "string" or not Finite(pt[3])
      or not Finite(pt[4]) then
    db.point = { "CENTER", "CENTER", -320, 120 }
  end
  if db.scale < 0.5 or db.scale > 2 then db.scale = 1 end
  if db.quality ~= math.floor(db.quality) or db.quality < 0 or db.quality > 5 then db.quality = DEFAULTS.quality end
  for _, k in ipairs({ "cap", "capDay" }) do
    if db[k] ~= math.floor(db[k]) or db[k] < 0 or db[k] > 200 then db[k] = DEFAULTS[k] end
  end
  if db.priceSource ~= "vendor" and db.priceSource ~= "auction" then db.priceSource = "vendor" end
  for _, k in ipairs({ "autoShow", "locked", "sync", "quiet", "welcomed", "debug", "debugEcho" }) do
    if type(db[k]) ~= "boolean" then db[k] = DEFAULTS[k] end
  end
  if type(db.debugLog) ~= "table" then db.debugLog = {} end
  for i = #db.debugLog, 1, -1 do if type(db.debugLog[i]) ~= "string" then table.remove(db.debugLog, i) end end
  if type(db.finals) ~= "table" then db.finals = {} end
  for key, f in pairs(db.finals) do
    if type(key) ~= "string" or type(f) ~= "table" or not (Finite(f.id) or type(f.name) == "string")
        or (f.id ~= nil and not Finite(f.id)) or (f.name ~= nil and type(f.name) ~= "string") then
      db.finals[key] = nil
    end
  end

  if type(mirror.deleted) == "table" then
    for uid, v in pairs(mirror.deleted) do
      if v then db.deleted[uid] = math.max(tonumber(db.deleted[uid]) or 0, tonumber(v) or 0) end
    end
  end
  -- (A clear can't be later than now: a later one would hide every run.)
  local latest = ns.ServerTime() + 86400
  if db.clearedAt > latest then db.clearedAt = 0 end
  if Finite(mirror.clearedAt) and mirror.clearedAt > db.clearedAt and mirror.clearedAt <= latest then
    db.clearedAt = mirror.clearedAt
  end
  PruneDeleted(db)

  local before, beforeOld = 0, 0
  for _, r in ipairs(type(db.history) == "table" and db.history or {}) do
    if type(r) == "table" then before = before + 1 end
  end
  for _, r in ipairs(type(db.old) == "table" and db.old or {}) do
    if type(r) == "table" then beforeOld = beforeOld + 1 end
  end
  local seen = {}
  -- The run in progress is the real copy; any saved copy of it (a run you
  -- reopened, still in another character's backup) is left out.
  local cr = char.run
  if type(cr) == "table" and type(cr.serverStart) == "number" and cr.serverStart > 0 then
    seen[ns.RunUID(cr)] = true
  end
  local newer = {}
  for _, list in ipairs({ db.old, mirror.old }) do
    for _, r in ipairs(type(list) == "table" and list or {}) do
      if type(r) == "table" then
        local uid, m = ns.RunUID(r), tonumber(r.modified) or 0
        if m > (newer[uid] or 0) then newer[uid] = m end
      end
    end
  end
  local all = MergeRuns(db.history, mirror.history, db, true, seen, newer)
  local old = MergeRuns(db.old, mirror.old, db, false, seen)
  db.history, db.old = {}, {}
  for i, r in ipairs(all) do
    if i <= ns.HISTORY_MAX then
      r.pending = nil
      db.history[i] = r
    else
      db.old[#db.old + 1] = ns.Lite(r)
    end
  end
  for _, r in ipairs(old) do db.old[#db.old + 1] = r end
  table.sort(db.old, function(x, y) return (x.startedAt or 0) > (y.startedAt or 0) end)
  while #db.old > ns.OLD_MAX do table.remove(db.old) end
  -- Said once per character while the bug lasts (not at every login); again
  -- after a login where the account data did load.
  if accountLoaded then char.restoreNoticed = nil end
  if not accountLoaded and (#db.history > before or #db.old > beforeOld) and not char.restoreNoticed then
    ns.restoredFromBackup = { full = #db.history - before, short = #db.old - beforeOld }
    char.restoreNoticed = true
  end

  local entries = NumberList(db.entries)
  local have = {}
  for _, e in ipairs(entries) do have[e] = true end
  for _, t in ipairs(NumberList(mirror.entries)) do
    if not have[t] then entries[#entries + 1] = t end
  end
  db.entries = entries

  -- Resets are per character (each has its own copies of a dungeon).
  local resets, now = {}, ns.ServerTime()
  if type(char.resets) == "table" then
    for name, t in pairs(char.resets) do
      if type(name) == "string" and type(t) == "number" and now - t < 86400 then
        local k = ns.DungeonKey(name)
        if t > (resets[k] or 0) then resets[k] = t end
      end
    end
  end
  char.resets = resets
  db.resets = nil
  if Finite(mirror.nextId) and mirror.nextId > db.nextId then db.nextId = math.floor(mirror.nextId) end

  -- Every saved run has a number, oldest first; two runs numbered apart on two
  -- characters can clash after a merge, so a later clash gets a new one.
  -- (Short-form runs too, oldest of all first: they can be deleted by number.)
  local used, numbered = {}, {}
  for i = #db.old, 1, -1 do numbered[#numbered + 1] = db.old[i] end
  for i = #db.history, 1, -1 do numbered[#numbered + 1] = db.history[i] end
  for _, run in ipairs(numbered) do
    if type(run.id) ~= "number" or used[run.id] then run.id = nil end
    if run.id then
      used[run.id] = true
      if run.id >= db.nextId then db.nextId = run.id + 1 end
    end
  end
  for _, run in ipairs(numbered) do
    if not run.id then run.id = ns.NextId() end
  end

  ns.run = type(char.run) == "table" and ns.FixRun(char.run) or nil
  char.run = ns.run
  -- The run in progress is numbered when it's saved (a reopened run keeps its number).
  if ns.run and (type(ns.run.id) ~= "number" or used[ns.run.id]) then ns.run.id = nil end
  -- (A copy of the run you ended by hand, for /runbook start: checked like any run.)
  char.manualEnded = type(char.manualEnded) == "table" and ns.FixRun(char.manualEnded) or nil
  ns.ClearCache()
end

function ns.NextId()
  local id = ns.DB.nextId
  ns.DB.nextId = id + 1
  return id
end

-- Called on logout: stamp the account data and refresh this character's backup.
function ns.SaveBackup()
  if not ns.DB then return end
  local db = ns.DB
  db.savedAt = ns.ServerTime()
  local settings = {}
  for k in pairs(SETTINGS) do settings[k] = db[k] end
  for _, k in ipairs(OPTIONAL_SETTINGS) do settings[k] = db[k] end
  -- (All of it, short-form runs too: it's for when the account data doesn't
  -- load, and a part copy would lose the rest then.)
  VulcanRunBookCharDB.mirror = {
    savedAt = db.savedAt, history = db.history, old = db.old, entries = db.entries, settings = settings,
    nextId = db.nextId, deleted = db.deleted, clearedAt = db.clearedAt,
  }
end

---------------------------------------------------------------------------
-- Runs
---------------------------------------------------------------------------
-- inst = { map, mapID, name, label, wing, diff, diffName, kind } from ns.CurrentInstance()
function ns.NewRun(inst)
  local run = ns.FixRun({})
  run.map, run.mapID, run.name, run.label = inst.map, inst.mapID, inst.name, inst.label or inst.name
  run.wing, run.diff, run.diffName, run.kind = inst.wing, inst.diff, inst.diffName, inst.kind
  run.diffUnknown = inst.diffUnknown
  run.startedAt = time()
  run.serverStart = ns.ServerTime()
  run.char = ns.CharKey()
  -- Two runs of one dungeon started in the same second (a macro) would share
  -- an identity; nudge the newer one.
  local last = ns.lastRun
  while last and last.name == run.name and last.char == run.char and (last.serverStart or 0) >= run.serverStart do
    run.serverStart = last.serverStart + 1
  end
  return run
end

-- The dungeon a run belongs to for stats and best times. Wings (Scarlet
-- Monastery's four, say) share a map ID but are told apart by their wing.
function ns.RunKey(run)
  return tostring(run.mapID or run.name) .. ":" .. tostring(run.wing or "") .. ":" .. tostring(run.diff or 0)
end

function ns.FindRunById(id)
  for i, r in ipairs(ns.DB.history) do
    if r.id == id then return r, i end
  end
  return nil
end

-- A saved run by number, in full or (older than the last 200) in short form:
-- the run, its index and its list.
function ns.FindAnyRunById(id)
  local r, i = ns.FindRunById(id)
  if r then return r, i, ns.DB.history end
  for j, o in ipairs(ns.DB.old) do
    if o.id == id then return o, j, ns.DB.old end
  end
  return nil
end

-- "Run #12 is kept in short form..." for a short-form run, or nil.
function ns.ShortFormNote(id)
  local r, _, list = ns.FindAnyRunById(id)
  if r and list == ns.DB.old then
    return "Run #" .. id .. " is older than your last " .. ns.HISTORY_MAX .. " runs, so it's kept in short form "
      .. "(times and counts only): it can be deleted (/runbook delete " .. id .. "), not changed."
  end
  return nil
end

-- Is this run yours (this character's)? Runs from before names were saved count.
function ns.IsOwnRun(run)
  -- (Runs saved before realms were kept have the bare name.)
  return run.char == nil or run.char == ns.CharKey() or run.char == ns.PlayerName()
end

-- Your (this character's) most recent saved run.
function ns.LastOwnRun()
  if ns.lastRun and ns.IsOwnRun(ns.lastRun) then
    for _, r in ipairs(ns.DB.history) do if r == ns.lastRun then return r end end
  end
  for _, r in ipairs(ns.DB.history) do
    if ns.IsOwnRun(r) then return r end
  end
  return nil
end

-- Your gold for a run: coin + loot at the chosen price.
function ns.RunGold(run)
  local loot = ns.DB.priceSource == "auction" and (run.lootAH or run.loot) or run.loot
  return (run.coin or 0) + (loot or 0)
end

function ns.PartnerGold(p)
  local loot = ns.DB.priceSource == "auction" and (p.lootAH or p.loot) or p.loot
  return (p.coin or 0) + (loot or 0)
end

-- Your partner's gold in a run (a short-form run keeps the totals, at vendor
-- and at auction prices). auction: at auction prices (default: your setting).
function ns.PartnersGold(run, auction)
  if auction == nil then auction = ns.DB.priceSource == "auction" end
  if type(run.pg) == "number" then return auction and (tonumber(run.pgAH) or run.pg) or run.pg end
  local n = 0
  if type(run.partners) == "table" then
    for _, p in pairs(run.partners) do
      if type(p) == "table" then
        local loot = auction and (p.lootAH or p.loot) or p.loot
        n = n + (p.coin or 0) + (loot or 0)
      end
    end
  end
  return n
end

-- Per hour, or nil when there's too little time to say.
function ns.PerHour(amount, seconds)
  if not seconds or seconds < ns.MIN_RATE_SECONDS then return nil end
  return amount / seconds * 3600
end

-- Drops at or above quality minQ. Unknown quality never counts as notable.
function ns.NotableDrops(run, minQ)
  local out = {}
  for _, d in ipairs(run.drops or {}) do
    if (d.q or -1) >= (minQ or 0) then out[#out + 1] = d end
  end
  return out
end

-- Counts that work on full and short-form runs alike.
local function Count(run, list, field) return run[field] or (run[list] and #run[list]) or 0 end
-- (In a raid: you two's deaths, as names and drops are - not 40 people's.)
function ns.DeathCount(run)
  if run.nd or run.kind ~= "raid" or type(run.deaths) ~= "table" then return Count(run, "deaths", "nd") end
  local n = 0
  for _, d in ipairs(run.deaths) do if ns.IsRunDuo(run, d.who) then n = n + 1 end end
  return n
end
function ns.WipeCount(run) return Count(run, "wipes", "nw") end
-- Blue and epic drops; in a raid, only your two's (not 40 people's).
function ns.DropCounts(run)
  if run.blues then return run.blues, run.epics or 0 end
  local blues, epics = 0, 0
  for _, d in ipairs(run.drops or {}) do
    if run.kind ~= "raid" or ns.IsRunDuo(run, d.who) then
      if d.q == 3 then blues = blues + 1 elseif (d.q or 0) >= 4 then epics = epics + 1 end
    end
  end
  return blues, epics
end

-- The short form of a run kept once it's older than the last 200: enough for
-- stats and best times.
function ns.Lite(run)
  if run.lite then return run end
  local blues, epics = ns.DropCounts(run)
  local bosses = {}
  for i, b in ipairs(run.bosses) do
    bosses[i] = { id = b.id, name = b.name, t = b.t, manual = b.manual, anonymous = b.anonymous, untimed = b.untimed }
  end
  return {
    lite = true, id = run.id, name = run.name, label = run.label, mapID = run.mapID, wing = run.wing,
    diff = run.diff, diffName = run.diffName, kind = run.kind, char = run.char, startedAt = run.startedAt,
    serverStart = run.serverStart, serverEnd = run.serverEnd, keepAfterClear = run.keepAfterClear,
    savedServer = run.savedServer, modified = run.modified, unbossed = run.unbossed, late = ns.LateRun(run) or nil,
    elapsed = run.elapsed, coin = run.coin,
    loot = run.loot, lootAH = run.lootAH, xp = run.xp, nd = ns.DeathCount(run), nw = ns.WipeCount(run),
    pg = ns.PartnersGold(run, false), pgAH = ns.PartnersGold(run, true),
    blues = blues, epics = epics, bosses = bosses,
  }
end

function ns.Archive(run)
  if type(run.id) ~= "number" then run.id = ns.NextId() end
  run.savedServer = ns.ServerTime()
  run.modified = run.savedServer
  -- A reopened run may still have its earlier saved copy (from a backup): replace it.
  local uid = ns.RunUID(run)
  for i = #ns.DB.history, 1, -1 do
    if ns.DB.history[i] ~= run and ns.RunUID(ns.DB.history[i]) == uid then table.remove(ns.DB.history, i) end
  end
  -- Newest first, by when it started (an alt's run that ends at login is older).
  local at = 1
  while ns.DB.history[at] and (ns.DB.history[at].startedAt or 0) > (run.startedAt or 0) do at = at + 1 end
  table.insert(ns.DB.history, at, run)
  local short = false
  while #ns.DB.history > ns.HISTORY_MAX do
    local r = table.remove(ns.DB.history)
    short = short or r == run
    -- (Into the short-form list where it belongs by when it started - an alt's
    -- run from long ago can be older than some there.)
    local lite = ns.Lite(r)
    local j = 1
    while ns.DB.old[j] and (ns.DB.old[j].startedAt or 0) > (lite.startedAt or 0) do j = j + 1 end
    table.insert(ns.DB.old, j, lite)
  end
  while #ns.DB.old > ns.OLD_MAX do table.remove(ns.DB.old) end
  ns.ClearCache()
  -- (Whether this run itself went straight to short form - or, older than
  -- every run kept, past the cap and not kept at all.)
  if short then
    for _, r in ipairs(ns.DB.old) do if r.id == run.id then return "short" end end
    return "dropped"
  end
  return nil
end

-- Removes a run from the history for good (a backup can't bring it back).
function ns.DeleteRun(index, list)
  local run = table.remove(list or ns.DB.history, index)
  if run then
    ns.DB.deleted[ns.RunUID(run)] = ns.ServerTime()  -- (when: the newest are kept)
    PruneDeleted(ns.DB)
    local me = VulcanRunBookCharDB.manualEnded
    if type(me) == "table" and ns.RunUID(me) == ns.RunUID(run) then VulcanRunBookCharDB.manualEnded = nil end
  end
  ns.ClearCache()
  return run
end

function ns.ClearHistory()
  local n = #ns.DB.history + #ns.DB.old
  wipe(ns.DB.history)
  wipe(ns.DB.old)
  wipe(ns.DB.deleted)
  ns.DB.clearedAt = ns.ServerTime()
  if ns.run then ns.run.keepAfterClear = ns.DB.clearedAt end  -- the run going now isn't part of this clear
  VulcanRunBookCharDB.manualEnded = nil
  ns.lastRun = nil
  ns.ClearCache()
  return n
end

---------------------------------------------------------------------------
-- Bosses, clears and best times
--
-- The "final boss" of a dungeon, unless you pinned one with /runbook final, is
-- decided by a vote among your (nearly) full runs: each run that killed as
-- many bosses as your biggest run, or one fewer, votes for its last kill
-- (ties: the biggest run, then your latest). In a raid it takes two nights
-- ending on the same boss (a raid night often stops partway).
-- A run is a clear if it killed the final boss, and its clear time is when it
-- did, so skipping an optional boss still counts.
---------------------------------------------------------------------------
local function SameBoss(a, b)
  if a.id and b.id then return a.id == b.id end
  if a.anonymous or b.anonymous then
    return a.name ~= nil and b.name ~= nil and ns.Fold(a.name) == ns.Fold(b.name)
  end
  return ns.NameSimilar(a.name, b.name)
end
ns.SameBoss = SameBoss

-- A name you type for a boss, as you've written it before in this dungeon:
-- "VanCleef" becomes "Edwin VanCleef" if that's in your runs (the fuller
-- spelling wins), so stats and clears line up.
function ns.KnownBossName(key, name, run)
  if type(name) ~= "string" or name == "" then return name end
  -- (Written exactly so before: that, whatever else it's part of.)
  local function exact(list)
    for _, b in ipairs(list) do
      if type(b) == "table" and not b.anonymous and type(b.name) == "string" and ns.Fold(b.name) == ns.Fold(name) then
        return b.name
      end
    end
    -- (Or spelled the same but for spaces and punctuation: "Van Cleef".)
    for _, b in ipairs(list) do
      if type(b) == "table" and not b.anonymous and type(b.name) == "string" and ns.NameSimilar(b.name, name)
          and not ns.NameMatch(b.name, name) then
        return b.name
      end
    end
  end
  for _, r in ipairs(ns.RunsOf(key)) do local e = exact(r.bosses) if e then return e end end
  if run then local e = exact(run.bosses) if e then return e end end
  local matches = {}
  local function try(b)
    if type(b) == "table" and not b.anonymous and type(b.name) == "string" and ns.NameMatch(b.name, name) then
      matches[ns.Fold(b.name)] = b.name
    end
  end
  for _, r in ipairs(ns.RunsOf(key)) do for _, b in ipairs(r.bosses) do try(b) end end
  if run then for _, b in ipairs(run.bosses) do try(b) end end
  -- (Two different bosses it could be - "Barov" - and it stays as typed.)
  local best
  for _, n in pairs(matches) do
    if best and not ns.NameMatch(best, n) then return name end
    if not best or ns.Len(n) > ns.Len(best) then best = n end
  end
  if best and ns.Len(best) > ns.Len(name) then return best end
  return name
end

-- Every boss name in your runs of a dungeon, for a hint.
function ns.KnownBossNames(key, run)
  local seen, out = {}, {}
  local function add(b)
    if type(b) == "table" and not b.anonymous and type(b.name) == "string" and not seen[ns.Fold(b.name)] then
      seen[ns.Fold(b.name)] = true
      out[#out + 1] = b.name
    end
  end
  for _, r in ipairs(ns.RunsOf(key)) do for _, b in ipairs(r.bosses) do add(b) end end
  if run then for _, b in ipairs(run.bosses) do add(b) end end
  return out
end

local function BossKey(b)
  return b.id and ("i" .. b.id) or ("n" .. ns.Fold(tostring(b.name)))
end

-- Results are cached until a run is saved or the history changes; the live
-- window asks every second.
local cache, runIndex = {}, nil
function ns.ClearCache()
  wipe(cache)
  runIndex = nil
end

-- How many characters have saved runs (the history is shared by all of yours).
-- Characters with runs: by name and realm (a name saved before realms were
-- kept is the same character as that name on any realm). Also notes which
-- names more than one realm uses, for ns.CharLabel.
local function Characters()
  if not cache["*chars"] then
    local full, bare, realms = {}, {}, {}
    for _, list in ipairs({ ns.DB.history, ns.DB.old }) do
      for _, r in ipairs(list) do
        local c = type(r.char) == "string" and r.char or "?"
        local short = ns.ShortName(c) or c
        if c:find("-", 1, true) then
          if not full[c] then
            full[c] = true
            realms[short] = (realms[short] or 0) + 1
          end
        else
          bare[short] = true
        end
      end
    end
    local n = 0
    for _ in pairs(full) do n = n + 1 end
    for short in pairs(bare) do if not realms[short] then n = n + 1 end end
    cache["*chars"] = { n = n, realms = realms }
  end
  return cache["*chars"]
end

function ns.CharacterCount() return Characters().n end

-- A run's character as shown: the name, with the realm when two of your
-- characters share the name.
function ns.CharLabel(char)
  if type(char) ~= "string" then return "?" end
  local short = ns.ShortName(char) or char
  return (Characters().realms[short] or 0) > 1 and char or short
end

-- [key] = runs of that dungeon: the detailed history, then the older runs.
local function Index()
  if not runIndex then
    runIndex = {}
    for _, list in ipairs({ ns.DB.history, ns.DB.old }) do
      for _, r in ipairs(list) do
        local key = ns.RunKey(r)
        local t = runIndex[key]
        if not t then
          t = {}
          runIndex[key] = t
        end
        t[#t + 1] = r
      end
    end
  end
  return runIndex
end

local function RunsOf(key)
  return Index()[key] or {}
end
ns.RunsOf = RunsOf

local function Compute(key)
  local runs = RunsOf(key)
  local max, votes, raid = 0, {}, false
  local final
  for _, r in ipairs(runs) do
    if #r.bosses > max then max = #r.bosses end
    if r.kind == "raid" then raid = true end
  end
  -- Only (nearly) full runs vote: a farm route that stops early, however
  -- often, can't make its last boss the final one. One kill short still
  -- votes, so an optional boss skipped (or an extra one killed) doesn't matter.
  local minSize = math.max(1, max - 1)
  for i, r in ipairs(runs) do
    local last = r.bosses[#r.bosses]
    if last and #r.bosses >= minSize then
      -- The same boss can be a reported kill (by id) in one run and a marked
      -- one (by name) in another: one vote bucket.
      local v = votes[BossKey(last)]
      if not v then
        for _, o in pairs(votes) do
          -- (By name only when one of them has no id: two ids are two bosses.)
          if SameBoss(o.boss, last) or (not (o.boss.id and last.id) and o.boss.name and last.name
              and ns.Fold(o.boss.name) == ns.Fold(last.name)) then
            v = o
            break
          end
        end
      end
      if not v then
        v = { boss = last, n = 0, size = 0, newest = i }
      elseif last.id and last.name and not (v.boss.id and v.boss.name) then
        v.boss = last  -- the copy that has both
      end
      votes[BossKey(last)] = v
      v.n = v.n + 1
      if #r.bosses > v.size then v.size = #r.bosses end
    end
  end
  local pin = ns.DB.finals[key]
  if type(pin) == "table" and (pin.id or pin.name) then
    final = pin
  else
    local best
    for _, v in pairs(votes) do
      if (not raid or v.n >= ns.FINAL_VOTES) and (not best or v.n > best.n or (v.n == best.n
          and (v.size > best.size or (v.size == best.size and v.newest < best.newest)))) then
        best = v
      end
    end
    final = best and best.boss or nil
  end
  -- Bosses in a full clear: the most kills up to and including the final boss
  -- in any clear (a rare boss after it doesn't count; a run that skipped
  -- optional bosses doesn't lower it). 0 while there's no final boss yet.
  local total = 0
  if final then
    for _, r in ipairs(runs) do
      for i, b in ipairs(r.bosses) do
        if SameBoss(b, final) then
          if i > total then total = i end
          break
        end
      end
    end
  end
  -- A clear's time only counts when you were there for it (a kill your
  -- partner made while you were outside has your paused clock, not a real
  -- time) and the run began with the copy: not one that began where bosses
  -- had already died (back in after a break). (A route that skips bosses -
  -- a tribute run - is a clear like any other.)
  local clears, timed, clearSum, bestRun, bestT = 0, 0, 0, nil, nil
  if final then
    for _, r in ipairs(runs) do
      local away = ns.LateRun(r)
      for i, b in ipairs(r.bosses) do
        away = away or b.untimed == true
        if SameBoss(b, final) then
          clears = clears + 1
          if not away then
            timed = timed + 1
            clearSum = clearSum + b.t
            if not bestT or b.t < bestT then bestRun, bestT = r, b.t end
          end
          break
        end
      end
    end
  end
  return { max = max, total = total, final = final, best = bestRun, bestT = bestT, clears = clears,
    timed = timed, clearSum = clearSum, runs = runs }
end

local function Info(key)
  local c = cache[key]
  if not c then
    c = Compute(key)
    cache[key] = c
  end
  return c
end
ns.DungeonInfo = Info

-- Most bosses any saved run of this dungeon killed (0 if none).
function ns.MaxBosses(key) return Info(key).max end

-- Bosses in a full clear of this dungeon (see Compute), or 0 if unknown.
function ns.BossTotal(key) return Info(key).total end

function ns.FinalBoss(key) return Info(key).final end

-- When this run killed the final boss, or nil if it didn't.
-- (nil when a kill up to the final one was your partner's while you were outside.)
function ns.ClearTime(run, final)
  final = final or ns.FinalBoss(ns.RunKey(run))
  if not final then return nil end
  for _, b in ipairs(run.bosses) do
    if b.untimed then return nil end
    if SameBoss(b, final) then return b.t end
  end
  return nil
end

-- A run that began in a copy where bosses had already died (you came back
-- in after it ended): its clear time isn't a whole dungeon's.
function ns.LateRun(r)
  return r.late == true or (type(r.copyKills) == "table" and #r.copyKills > 0)
end

-- When this run's clear counts for best and average times (see Compute), or
-- nil.
function ns.TimedClear(run, final)
  final = final or ns.FinalBoss(ns.RunKey(run))
  if not final or ns.LateRun(run) then return nil end
  for _, b in ipairs(run.bosses) do
    if b.untimed then return nil end
    if SameBoss(b, final) then return b.t end
  end
  return nil
end

-- Your fastest clear of this dungeon (not counting `except`), and its time.
-- The final boss is always the one from all your runs.
function ns.BestRun(key, except)
  local i = Info(key)
  if not except or i.best ~= except then return i.best, i.bestT end
  local best, bestT
  for _, r in ipairs(i.runs) do
    if r ~= except then
      local t = ns.TimedClear(r, i.final)
      if t and (not bestT or t < bestT) then best, bestT = r, t end
    end
  end
  return best, bestT
end

-- The best run's time for this boss, if it killed it at the same point in the
-- run (same kill number); with a different boss order the times don't compare.
function ns.BestSplit(best, boss, index)
  if not best then return nil end
  local b = best.bosses[index]
  if b and SameBoss(b, boss) then return b.t end
  return nil
end

-- One row per dungeon (and difficulty), most-run first.
function ns.DungeonStats()
  local list = {}
  for key, runs in pairs(Index()) do
    local r1 = runs[1]
    local s = { key = key, name = r1.label or r1.name or "?", diff = r1.diff, diffName = r1.diffName, runs = #runs,
      elapsed = 0, gold = 0, xp = 0, xpElapsed = 0, deaths = 0, wipes = 0, blues = 0, epics = 0, last = 0 }
    for _, r in ipairs(runs) do
      s.elapsed = s.elapsed + (r.elapsed or 0)
      -- (Each run's gold as it's shown, to the silver, so one run's rate here
      -- matches its details and the live window.)
      s.gold = s.gold + ns.ShownMoney(ns.RunGold(r))
      s.duoGold = (s.duoGold or 0) + ns.ShownMoney(ns.RunGold(r)) + ns.ShownMoney(ns.PartnersGold(r))
      if (r.xp or 0) > 0 then
        s.xp = s.xp + r.xp
        s.xpElapsed = s.xpElapsed + (r.elapsed or 0)
      end
      s.deaths = s.deaths + ns.DeathCount(r)
      s.wipes = s.wipes + ns.WipeCount(r)
      local b, e = ns.DropCounts(r)
      s.blues, s.epics = s.blues + b, s.epics + e
      if (r.startedAt or 0) > s.last then s.last = r.startedAt end
    end
    local info = Info(key)
    s.maxBosses, s.final, s.best, s.clears = info.max, info.final, info.bestT, info.clears
    s.bestId = info.best and info.best.id  -- (its number, to look up or delete)
    s.pinned = ns.DB.finals[key] ~= nil
    s.avgClear = (info.timed or 0) > 0 and info.clearSum / info.timed or nil
    s.goldHr = ns.PerHour(s.gold, s.elapsed)
    s.duoGoldHr = ns.PerHour(s.duoGold or 0, s.elapsed)
    s.xpHr = ns.PerHour(s.xp, s.xpElapsed)
    list[#list + 1] = s
  end
  -- The same dungeon name at two difficulties gets its difficulty shown.
  local nameCount = {}
  for _, s in ipairs(list) do nameCount[s.name] = (nameCount[s.name] or 0) + 1 end
  for _, s in ipairs(list) do
    if nameCount[s.name] > 1 and s.diffName and s.diffName ~= "" and s.diff ~= 1 then
      s.name = s.name .. " (" .. s.diffName .. ")"
    end
  end
  table.sort(list, function(a, b)
    if a.runs ~= b.runs then return a.runs > b.runs end
    if a.name ~= b.name then return a.name < b.name end
    return a.key < b.key
  end)
  return list
end

---------------------------------------------------------------------------
-- Instance cap (unconfirmed for Forever: Classic allowed 5 new instances an hour)
---------------------------------------------------------------------------
function ns.PruneEntries()
  local now = ns.ServerTime()
  local list = ns.DB.entries
  for i = #list, 1, -1 do
    -- Far-future entries can only come from a broken clock; drop those too.
    if type(list[i]) ~= "number" or now - list[i] >= ns.CAP_DAY or list[i] > now + 86400 then
      table.remove(list, i)
    end
  end
end

-- Entries in the last hour, and seconds until you're under the cap again
-- (enough entries have aged out to enter one more), or until the oldest one
-- ages out when you're under it already (nil with no entries).
-- noPending: without a run whose wing is still being read.
-- window: seconds counted back (default the hour); cap: the limit for it.
function ns.CapStatus(noPending, window, cap)
  ns.PruneEntries()
  window = window or ns.CAP_WINDOW
  cap = cap or ns.DB.cap or 0
  local list, now = {}, ns.ServerTime()
  for _, t in ipairs(ns.DB.entries) do if now - t < window then list[#list + 1] = t end end
  -- (A run whose wing is still being read counts for now.)
  if not noPending and ns.run and type(ns.run.pendingEntry) == "number" then list[#list + 1] = ns.run.pendingEntry end
  table.sort(list)
  if #list == 0 then return 0, nil end
  local i = (cap > 0 and #list >= cap) and (#list - cap + 1) or 1
  return #list, math.max(0, list[i] + window - now)
end

-- The same for the daily limit.
function ns.DayStatus(noPending)
  return ns.CapStatus(noPending, ns.CAP_DAY, ns.DB.capDay or 0)
end

-- t: when you entered (server time); default now.
function ns.AddEntry(t)
  table.insert(ns.DB.entries, t or ns.ServerTime())
  ns.PruneEntries()
end
