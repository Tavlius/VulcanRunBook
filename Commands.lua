-- RunBook: slash commands (/runbook, /rlog), key bindings, the addon compartment
-- button, and the /runbook check diagnostics.
local _, ns = ...
local plain = ns.plain

BINDING_HEADER_VULCANRUNBOOK = "Vulcan RunBook"
BINDING_NAME_VULCANRUNBOOK_TOGGLE = "Show/hide the live window"
BINDING_NAME_VULCANRUNBOOK_HISTORY = "Open run history"
BINDING_NAME_VULCANRUNBOOK_BOSS = "Mark a boss kill (if the game doesn't report it)"

function VulcanRunBook_ToggleLive() ns.ToggleLive() end
function VulcanRunBook_ToggleHistory() ns.ToggleHistory() end
function VulcanRunBook_OnAddonCompartmentClick() ns.ToggleHistory() end
function VulcanRunBook_MarkBoss() ns.MarkBoss() end

local Y = "|cffffd100"
-- No bare "|" in these: in WoW text "|r", "|a" and the like are escape codes.
local HELP = {
  Y .. "/runbook|r (or " .. Y .. "show|r/" .. Y .. "hide|r) the live window   " .. Y .. "history|r your runs   " .. Y
    .. "stats|r per dungeon   " .. Y .. "group|r everyone in your group",
  Y .. "note <text>|r note on this run (or your last); " .. Y .. "note #12 <text>|r on run #12",
  Y .. "boss [name]|r mark a boss kill by hand (there's a key binding too)   " .. Y .. "unboss|r take one back",
  Y .. "final <boss>|r set a dungeon's final boss (" .. Y .. "final auto|r to undo)",
  Y .. "end|r finish this run   " .. Y .. "start|r reopen it   " .. Y .. "new|r start over here (new instance)",
  Y .. "report [group/party/raid/instance/guild/say/w Name]|r share the run   " .. Y .. "export|r CSV",
  Y .. "partner <name> [alt]/off|r who you sync with   " .. Y .. "sync|r on/off   " .. Y
    .. "quiet|r on/off: fewer chat lines",
  Y .. "cap [n/off]|r instance cap   " .. Y .. "quality 0-5|r lowest drop quality listed for you two",
  Y .. "delete <run #>|r remove a run   " .. Y .. "clear yes|r remove all   " .. Y .. "price vendor/ah|r",
  Y .. "auto|r  " .. Y .. "lock|r/" .. Y .. "unlock|r  " .. Y .. "scale 0.5-2|r  " .. Y .. "resetpos|r  " .. Y
    .. "check|r  " .. Y .. "debug on/off/echo/clear|r  " .. Y .. "export debug|r",
}

-- Help added by optional modules (Persist.lua).
for _, line in ipairs(ns.extraHelp or {}) do HELP[#HELP + 1] = line end

local QUALITY_NAMES = { [0] = "poor (grey)", "common (white)", "uncommon (green)", "rare (blue)", "epic (purple)",
  "legendary (orange)" }

local function OnOff(v) return v and "on" or "off" end

-- "on"/"off" sets it; nothing flips it. Returns the new value, or nil (and
-- says how) for anything else.
local function Toggle(current, arg, cmd)
  if arg == "" then return not current end
  if arg == "on" then return true end
  if arg == "off" then return false end
  ns.Print("Usage: /runbook " .. cmd .. " on or off.")
  return nil
end

-- Chat is locked during boss fights; sending then is silently blocked.
local function ChatLocked()
  return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and ns.Call(C_ChatInfo.InChatMessagingLockdown) == true
end

local CHANNELS = {
  party = "PARTY", p = "PARTY", raid = "RAID", ra = "RAID", instance = "INSTANCE_CHAT", i = "INSTANCE_CHAT",
  guild = "GUILD", g = "GUILD", say = "SAY", s = "SAY", w = "WHISPER", whisper = "WHISPER", t = "WHISPER",
}

local function Report(args)
  local channel, target = (args or ""):match("^(%S*)%s*(.-)%s*$")
  channel = channel:lower()
  local chatType = CHANNELS[channel]
  if channel == "group" then
    if not (IsInGroup and IsInGroup()) then
      ns.Print("You're not in a group.")
      return
    end
    chatType = ns.GroupChannel()
  elseif channel ~= "" and not chatType then
    ns.Print("Unknown channel \"" .. channel .. "\". Use group, party, raid, instance, guild, say or w Name.")
    return
  elseif chatType == "PARTY" and not (IsInGroup and IsInGroup()) then
    ns.Print("You're not in a party.")
    return
  elseif chatType == "RAID" and not (IsInRaid and IsInRaid()) then
    ns.Print("You're not in a raid.")
    return
  end
  local lines = ns.ReportLines(nil, chatType == "RAID" or (IsInRaid and IsInRaid()))
  if not lines then
    ns.Print("No run to report yet.")
    return
  end
  if not chatType then
    for _, l in ipairs(lines) do print(l) end
    return
  end
  if chatType == "WHISPER" and target == "" then
    ns.Print("Who to whisper? /runbook report w Name")
    return
  end
  if ChatLocked() then
    ns.Print("Chat is locked right now (a boss fight, or the instance). Try again after it, or outside.")
    return
  end
  for _, l in ipairs(lines) do
    local ok = pcall(ns.SendChat, l, chatType, nil, chatType == "WHISPER" and target or nil)
    if not ok then
      ns.Print("That message couldn't be sent.")
      return
    end
  end
end

local newAskedAt  -- /runbook new asked to confirm (GetTime())

local function Check()
  local P = ns.Print
  local version, build, _, iface = "?", "?", nil, "?"
  if GetBuildInfo then version, build, _, iface = GetBuildInfo() end
  P(string.format("check (version %s) - client %s (%s), interface %s", ns.VERSION, tostring(plain(version)),
    tostring(plain(build)), tostring(plain(iface))))
  local inst, state = ns.CurrentInstance()
  if inst then
    -- (In words: "wing nil" would read like a problem in a dungeon without wings.)
    local wing = inst.wing and ("wing: " .. (inst.label:match(" %- (.+)$") or inst.wing))
      or (inst.multiWing and "wing: unreadable" or "no wings")
    local diff = inst.diffUnknown and "difficulty: unreadable"
      or ("difficulty: " .. (inst.diffName or tostring(inst.diff)))
    P(string.format("Instance: %s (map %s), %s, %s, %s", inst.label, tostring(inst.map), wing, diff,
      inst.kind == "raid" and "raid" or "dungeon"))
    if not inst.mapID then P("  Map ID unreadable: using the dungeon name instead.") end
    if inst.multiWing and not inst.wing then
      if inst.name == "Dire Maul" or inst.mapID == 429 then
        P("  Dire Maul: wings aren't told apart (by design). Type /runbook new when you switch wings.")
      else
        P("  Wing unreadable: this dungeon's wings won't be told apart.")
      end
    end
  elseif state == "unknown" then
    P("Instance: in one, but it can't be read right now.")
  else
    P("Instance: not in a dungeon or raid.")
  end
  if ns.run then
    P(string.format("Run in progress: %s, %s, %s", ns.run.label, ns.Clock(ns.run.elapsed),
      ns.inside and "inside" or "outside"))
  end
  local seen = ns.eventsSeen
  P(string.format("Boss events this session: %d encounter start, %d encounter end, %d boss kill",
    seen.ENCOUNTER_START or 0, seen.ENCOUNTER_END or 0, seen.BOSS_KILL or 0))
  P(string.format("Loot: %d loot lines read, %d hidden by the client, %d bag pickups seen", ns.stats.lootRead,
    ns.stats.lootSecret, ns.stats.bagLoot))
  local st = ns.stats
  P(string.format("Resets: %d reset messages seen this session, %d matched a run of yours%s", st.resetsSeen,
    st.resetsMatched, st.lastReset and (' (last: "' .. st.lastReset .. '")') or ""))
  if st.resetsSeen > 0 and st.resetsMatched == 0 then
    P("  |cffff5050None matched:|r the reset message names dungeons differently. Use /runbook new after a reset.")
  end
  local members, names, deads = ns.GroupReadability()
  if members > 1 then
    P(string.format("Group: %d members, names readable for %d, alive/dead readable for %d", members, names, deads))
  end
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    P("Chat lockdown right now: " .. (ChatLocked() and "|cffff5050yes|r" or "no"))
  end
  P("Feign Death check (others): " .. (UnitIsFeignDeath and "available" or "|cffff5050missing|r (a hunter "
    .. "partner's feign may count as a death)"))
  local partners = {}
  for name in pairs(ns.heardFrom) do partners[#partners + 1] = name end
  table.sort(partners)
  P(string.format("Sync: %s, partner %s, prefix %s, channel %s, %d queued, heard from: %s", OnOff(ns.DB.sync),
    ns.DB.partner or "not set yet", ns.SyncRegistered() and "registered" or "|cffff5050not registered|r",
    ns.GroupChannel(), ns.SyncQueueSize(), #partners > 0 and table.concat(partners, ", ") or "nobody yet"))
  -- Whether the game lets an addon see your friends (for picking a partner).
  local bnet = C_BattleNet and C_BattleNet.GetAccountInfoByGUID and true or false
  local list = C_FriendList and (C_FriendList.IsFriend or C_FriendList.GetFriendInfo) and true or false
  local groupN = 0
  if ns.run and type(ns.run.group) == "table" then for _ in pairs(ns.run.group) do groupN = groupN + 1 end end
  -- (Battle.net friends and the friends list by GUID need the group's GUIDs.)
  local hidden = false
  for _, unit in ipairs(ns.GroupUnits()) do
    if not ns.IsPlayerUnit(unit) and UnitGUID then
      local g = plain(ns.Call(UnitGUID, unit))
      if type(g) ~= "string" or g == "" then hidden = true end
      break
    end
  end
  P(string.format("  Friends: Battle.net %s, friends list %s%s; group view: %s this run",
    (bnet and hidden) and "|cffff5050not readable here (hidden players)|r" or (bnet and "readable" or
    "|cffff5050not available|r"), list and (hidden and "by name only" or "readable") or "|cffff5050not available|r",
    ns.DB.partnerTag and ", partner's BattleTag known" or "", ns.Plural(groupN, "other player")))
  local heard
  for who, at in pairs(ns.partnersSeen) do if ns.SameName(who, ns.DB.partner) then heard = at end end
  if ns.DB.partner then
    P("  Last message from " .. ns.DB.partner .. ": " .. (heard and (ns.Clock(GetTime() - heard) .. " ago")
      or "none this session"))
    -- Whether the two logs agree on this run's kills (as of their last numbers).
    local k
    for who, v in pairs(ns.partnerKills) do if ns.SameName(who, ns.DB.partner) then k = v end end
    local run = ns.run
    if run and k and k.d == run.name then
      local mine, who = #run.bosses, ns.DB.partner
      if k.final then
        P("  Kills this run: yours " .. mine .. "; " .. who .. " has no run here going")
      elseif GetTime() - k.at > 90 or math.abs(k.start - (run.serverStart or 0)) > 120 then
        -- (Old numbers, or their run began at another time - before you came, or
        -- after a start-over of one of you: the counts can differ.)
        P(string.format("  Kills this run: yours %d, %s's log %d (their run %s, so they can differ)", mine, who, k.n,
          GetTime() - k.at > 90 and ("as of " .. ns.Clock(GetTime() - k.at) .. " ago") or "began at another time"))
      else
        P(string.format("  Kills this run: yours %d, %s's log %d%s", mine, who, k.n,
          k.n == mine and "" or ("  |cffff5050(they differ: a kill only one of you has - /runbook boss or "
          .. "/runbook unboss on the side that's wrong)|r")))
      end
    end
  end
  local count, wait = ns.CapStatus()
  local capped = (ns.DB.cap or 0) > 0 and count >= ns.DB.cap
  P(string.format("Instance cap: %s, %s this hour%s", (ns.DB.cap or 0) > 0 and tostring(ns.DB.cap) or "off",
    ns.Plural(count, "entry", "entries"), wait and ((capped and ", under the cap again in " or ", oldest frees up in ")
    .. ns.Clock(wait)) or ""))
  local day = ns.DayStatus()
  P(string.format("Daily cap: %s, %s in the last 24 hours. Cap errors from the game seen: %d",
    (ns.DB.capDay or 0) > 0 and tostring(ns.DB.capDay) or "off", ns.Plural(day, "entry", "entries"),
    ns.stats.capErrors or 0))
  P(string.format("Saved runs: %d%s. Prices: %s%s", #ns.DB.history,
    ns.restoredFromBackup and " (restored from this character's backup)" or "", ns.DB.priceSource,
    ns.DB.priceSource == "auction" and (ns.HasAuctionator() and " (Auctionator found)"
      or " (|cffff5050Auctionator not found|r, using vendor)") or ""))
  if ns.Persist then P(ns.Persist.CheckLine()) end
end

function ns.HasAuctionator()
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  return (api and api.GetAuctionPriceByItemID) and true or false
end

-- "12" or "#12" -> 12
local function RunNumber(text)
  return tonumber((text or ""):match("^#?(%d+)$"))
end

local deleteAsked  -- { id, at }: /runbook delete asked to confirm
local clearAskedAt  -- GetTime(): /runbook clear yes asked to confirm (more than one character)

local function Delete(arg)
  local yes
  arg, yes = arg:gsub("%s+yes$", "")
  local id = RunNumber(arg)
  if not id then
    ns.Print("Usage: /runbook delete <run #> (the numbers are in /runbook history)")
    return
  end
  local run, i, list = ns.FindAnyRunById(id)
  if not run then
    ns.Print("No saved run #" .. id .. ". The numbers are in /runbook history.")
    return
  end
  -- (A typo deletes the wrong run for good: it's asked twice, like clear.)
  local asked = deleteAsked and deleteAsked.id == id and GetTime() - deleteAsked.at <= 15
  if yes == 0 and not asked then
    deleteAsked = { id = id, at = GetTime() }
    ns.Print(string.format("This deletes run #%d (%s, %s, %s, %s) for good. Type /runbook delete %d again within "
      .. "15 seconds to do it.", id, run.label or run.name or "?", ns.When(run.startedAt), ns.Clock(run.elapsed or 0),
      ns.Plural(#(run.bosses or {}), "boss", "bosses"), id))
    return
  end
  deleteAsked = nil
  ns.DeleteRun(i, list)
  if ns.lastRun == run then ns.lastRun = nil end
  ns.Print(string.format("Deleted run #%d (%s, %s).", id, run.label or run.name or "?", ns.When(run.startedAt)))
  ns.Fire("HISTORY_CHANGED")
end

local function Note(rest)
  local target, text
  -- "#12 text" or "#12" ("#1st pull" is a note that starts with #).
  local idText, after = rest:match("^#(%d+)%s+(.*)$")
  if not idText then idText = rest:match("^#(%d+)$") after = idText and "" end
  if idText then
    local id = tonumber(idText)
    target = (ns.run and ns.run.id == id) and ns.run or ns.FindRunById(id)
    if not target then
      ns.Print(ns.ShortFormNote(id) or ("No run #" .. idText .. "."))
      return
    end
    text = after
  else
    text = rest
  end
  if text == "" then
    ns.Print("Usage: /runbook note <text>  (or note #12 <text> for run #12)")
    return
  end
  local run, cut, note = ns.AddNote(text, nil, target)
  if not run then
    ns.Print("No run to add a note to yet.")
    return
  end
  if not note then
    ns.Print("That note is already there.")
    return
  end
  ns.Print("Note added to " .. (run == ns.run and "this run" or ("run #" .. tostring(run.id) .. " (" .. run.label
    .. ")")) .. (cut and " (cut short to fit)" or "") .. ".")
  if ns.SyncNote then ns.SyncNote(run, note.text) end
  ns.Fire("HISTORY_CHANGED")
end

local function Handle(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  local arg = rest:lower()   -- keyword arguments; notes and names keep their case
  local db = ns.DB
  -- Commands added by optional modules (Persist.lua).
  if ns.extraCommands and ns.extraCommands[cmd] then return ns.extraCommands[cmd](rest) end

  if cmd == "" or cmd == "toggle" then
    ns.ToggleLive()
  elseif cmd == "show" or cmd == "hide" then
    ns.manualShown = cmd == "show"
    ns.UpdateVisibility()
  elseif cmd == "history" or cmd == "h" or cmd == "runs" then
    ns.ShowHistory("runs")
  elseif cmd == "stats" or cmd == "dungeons" then
    ns.ShowHistory("dungeons")
  elseif cmd == "note" then
    Note(rest)
  elseif cmd == "boss" then
    if not ns.InRun() then
      ns.Print("Only inside a dungeon run.")
    else
      local name = rest ~= "" and ns.Truncate(ns.CleanText(rest), 40) or nil
      if name then name = ns.KnownBossName(ns.RunKey(ns.run), name, ns.run) end  -- (your earlier spelling)
      if name and name == name:lower() and name:find("%l") then
        -- (A new name typed all in lowercase: capitalised, as it'll show in your stats.)
        name = (name:gsub("^%l", string.upper):gsub(" %l", string.upper))
      end
      local added, same, why = ns.AddBoss(nil, name, "manual")
      if not added and same and same.src == "sync" then
        ns.Print(same.name .. " was already marked by your partner.")
      elseif not added and same and (why == "recent" or (not name)) then
        ns.Print(same.name .. " was just recorded." .. (same.anonymous
          and " To name it, type /runbook boss <name> within 10 seconds." or ""))
        if same.anonymous then ns.TouchKill(same) end
      elseif not added and why == "visit" then
        -- (Killed since you last came in: no reset in between.)
        ns.Print((same and same.name or "That boss") .. " is already in this run.")
      elseif not added then
        ns.Print((same and same.name or "That boss") .. " is already in this run. If the dungeon was reset, "
          .. "type /runbook new.")
      end
    end
  elseif cmd == "unboss" then
    local id = tonumber(rest:match("^#?(%d+)$") or "")
    if rest ~= "" and not id then
      ns.Print("Usage: /runbook unboss, or /runbook unboss #12 for run #12.")
      return
    end
    if id and not ((ns.run and ns.run.id == id) or ns.FindRunById(id)) then
      ns.Print(ns.ShortFormNote(id) or ("No run #" .. id .. "."))
      return
    end
    local b, run = ns.RemoveLastBoss(id)
    if b then
      local shared = run == ns.run and db.sync and db.partner and ns.PartnerInGroup()
      ns.Print("Removed " .. b.name .. " from " .. (run == ns.run and "this run" or ("run #" .. tostring(run.id)))
        .. "." .. (shared and (" Your partner's log keeps it; " .. db.partner .. " can /runbook unboss too.") or ""))
      if b.undidCopy then
        ns.Print("It had counted this run as a new instance; that's taken back too.")
      end
      if b.split then
        ns.Print("It had started this as a new run (a boss killed again); the earlier part stays a separate run.")
      end
    else
      ns.Print("No boss kill to take back" .. (ns.run and not id and " in this run (/runbook unboss #12 for run #12)"
        or "") .. ".")
    end
  elseif cmd == "final" then
    local run = ns.run or ns.LastOwnRun()
    if not run then
      ns.Print("Run a dungeon first.")
    elseif arg == "" then
      local f = ns.FinalBoss(ns.RunKey(run))
      local wait = run.kind == "raid" and "it takes two raid nights ending on the same boss"
        or "it's set from your first finished run with a boss kill"
      ns.Print("Final boss for " .. run.label .. ": " .. (f and f.name or ("none yet (" .. wait .. ")"))
        .. (ns.DB.finals[ns.RunKey(run)] and " (set by you; /runbook final auto to undo)" or "") .. ".")
    elseif arg == "auto" then
      ns.DB.finals[ns.RunKey(run)] = nil
      ns.ClearCache()
      ns.Print("Final boss for " .. run.label .. " is worked out from your runs again.")
      ns.Fire("HISTORY_CHANGED")
    else
      -- Pick a boss you've killed there, by name (case doesn't matter).
      -- (The exact name first; a part of one only if it's the only boss it fits.)
      local found
      local exactName = ns.KnownBossName(ns.RunKey(run), rest, ns.run == run and run or nil)
      for _, r in ipairs(ns.RunsOf(ns.RunKey(run))) do
        for _, b in ipairs(r.bosses) do
          if b.name and not b.anonymous and ns.Fold(b.name) == ns.Fold(exactName) then found = b end
        end
      end
      for _, b in ipairs((ns.run == run) and run.bosses or {}) do
        if b.name and not b.anonymous and ns.Fold(b.name) == ns.Fold(exactName) then found = b end
      end
      local key, label = ns.RunKey(run), run.label
      if not found then
        -- Not there: another dungeon of yours that has it (one only).
        local keys, n = {}, 0
        for _, r in ipairs(ns.DB.history) do
          for _, b in ipairs(r.bosses) do
            if b.name and ns.Fold(b.name) == ns.Fold(rest) and ns.IsOwnRun(r) then
              local k = ns.RunKey(r)
              if not keys[k] then
                keys[k] = { boss = b, label = r.label or r.name }
                n = n + 1
              end
            end
          end
        end
        if n == 1 then
          for k, v in pairs(keys) do key, label, found = k, v.label, v.boss end
        end
      end
      if not found then
        local known = ns.KnownBossNames(ns.RunKey(run), ns.run == run and run or nil)
        ns.Print("No kill of \"" .. rest .. "\" in your " .. run.label .. " runs."
          .. (#known > 0 and (" Bosses there: " .. table.concat(known, ", ") .. ".") or ""))
      else
        ns.DB.finals[key] = { id = found.id, name = found.name }
        ns.ClearCache()
        ns.Print("Final boss for " .. label .. " is now " .. found.name .. ".")
        ns.Fire("HISTORY_CHANGED")
      end
    end
  elseif cmd == "group" then
    -- Everyone in your group or raid (gold and XP from those who run RunBook).
    ns.ShowHistory("group")
  elseif cmd == "partner" then
    if arg == "" then
      ns.Print("Sync partner: " .. (db.partner or "not set (the first RunBook user you're in a two-person "
        .. "group with, or a friend of yours in any group)") .. "."
        .. (db.partner and db.partnerTag and " Their other characters on the same Battle.net account are "
          .. "followed." or ""))
    elseif arg == "off" or arg == "none" then
      db.partner, db.partnerRealm = nil, nil
      ns.PartnerChanged()
      ns.Print("Sync partner cleared: the next RunBook user you're in a two-person group with, or a friend of "
        .. "yours in any group, becomes your partner.")
    else
      -- The name as your group shows it, if they're in it; else as typed.
      -- With two in the group by that name, the one from your realm (unless
      -- you typed the realm).
      -- "alt": the same person as your partner, on another character.
      local isAlt = false
      if rest:lower():match("%s+alt$") then
        rest, isAlt = rest:gsub("%s+[Aa][Ll][Tt]$", ""), db.partner ~= nil
      end
      local typed = ns.ShortName(rest) or rest
      local realm = rest:match("%-(.+)$")
      realm = realm and realm:gsub("[%s%-]", "") or nil
      local name, found, unitRealm = typed, false, nil
      for _, unit in ipairs(ns.GroupUnits()) do
        local n, r = UnitName(unit)
        n, r = ns.ShortName(plain(n)), plain(r)
        r = (type(r) == "string" and r ~= "") and r:gsub("[%s%-]", "") or nil
        if n and ns.SameName(n, typed) and not ns.IsPlayerUnit(unit)
            and (not realm or ns.SameName(r or "", realm) or (not r and ns.SameName(realm, ns.MyRealm() or ""))) then
          if not found or (not r and unitRealm) then name, found, unitRealm = n, true, r end
        end
      end
      if not found and typed:sub(1, 1):match("%l") then
        name = typed:sub(1, 1):upper() .. typed:sub(2)  -- names start with a capital
      end
      -- (As the game spells it, when they're in your group. A bare name not in
      -- your group: your partner's realm if it's them, else yours.)
      if not found and not realm then
        realm = ns.PartnerCharRealm(name) or ns.MyRealm()
      end
      realm = unitRealm or (found and ns.MyRealm()) or realm
      -- The same person: one of your partner's characters, or (for one the
      -- addon told you to switch to) one with your partner's BattleTag.
      local same = isAlt or ns.IsPartnerChar(name, realm)
      if not same and found and db.partnerTag and ns.FriendInfo then
        local _, tag = ns.FriendInfo(name .. "-" .. (realm or ns.MyRealm() or ""))
        same = tag ~= nil and tag == db.partnerTag
      end
      db.partner, db.partnerRealm = name, realm
      ns.PartnerChanged(nil, same)
      ns.Print("Sync partner set to " .. db.partner .. "." .. (found and "" or " (Not in your group right now: "
        .. "check the spelling, and the capital letter if the name starts with a special one.)"))
    end
  elseif cmd == "quiet" then
    local v = Toggle(db.quiet, arg, cmd)
    if v == nil then return end
    db.quiet = v
    ns.Print("Quiet mode " .. OnOff(db.quiet) .. (db.quiet and ": no chat line per boss kill or run start." or "."))
  elseif cmd == "end" or cmd == "stop" then
    if not ns.ManualEnd() then ns.Print("No run in progress.") end
  elseif cmd == "new" then
    -- A run with kills (or a few minutes in) ends for good, and your partner's
    -- starts over too: typed by mistake, that can't be undone, so it's asked twice.
    local run = ns.run
    local big = run and ns.inside and (#run.bosses > 0 or run.elapsed >= 120)
    if big and arg ~= "yes" and not (newAskedAt and GetTime() - newAskedAt <= 15) then
      newAskedAt = GetTime()
      ns.Print(string.format("This ends %s (%s, %s) and starts a new run - for your partner too. Type /runbook new "
        .. "again within 15 seconds to do it.", run.label, ns.Clock(run.elapsed), ns.Plural(#run.bosses, "boss",
        "bosses")))
    else
      newAskedAt = nil
      if not ns.ManualNew() then ns.Print("Only inside a dungeon.") end
    end
  elseif cmd == "start" or cmd == "resume" then
    local ok, why = ns.ManualStart()
    if why == "outside" then ns.Print("Only inside a dungeon.")
    elseif why == "running" then ns.Print("A run is already going (" .. ns.run.label .. ").")
    elseif not ok then ns.Print("Couldn't start a run here.")
    elseif why == "started" and db.quiet then ns.Print(ns.run.label .. " started.") end  -- (quiet hides it otherwise)
  elseif cmd == "report" then
    Report(rest)
  elseif cmd == "export" then
    ns.ShowCopy(arg == "debug" and "RunBook diagnostics" or "RunBook CSV", ns.ExportLines(arg))
  elseif cmd == "cap" and arg:match("^day") then
    local v = arg:match("^day%s*(.*)$")
    local n = tonumber(v)
    if v == "off" or n == 0 then
      db.capDay = 0
      ns.Print("Daily instance cap tracking off.")
    elseif n and n >= 1 and n <= 200 and n == math.floor(n) then
      db.capDay = n
      ns.Print("Daily instance cap set to " .. n .. " per day.")
    else
      local day = ns.DayStatus()
      ns.Print(string.format("%s in the last 24 hours (daily cap %s). Usage: /runbook cap day 1-200 or off",
        ns.Plural(day, "instance", "instances"), (db.capDay or 0) > 0 and tostring(db.capDay) or "off"))
    end
  elseif cmd == "cap" then
    local n = tonumber(arg)
    if arg == "off" or n == 0 then
      db.cap = 0
      ns.Print("Instance cap tracking off.")
    elseif n and n >= 1 and n <= 30 and n == math.floor(n) then
      db.cap = math.floor(n)
      ns.Print("Instance cap set to " .. db.cap .. " per hour.")
    elseif arg == "" then
      local line = ns.CapLine()
      if ns.DayCapLine() then ns.Print(ns.DayCapLine()) end
      ns.Print(line or "Instance cap tracking is off (/runbook cap 5 turns it on).")
    else
      ns.Print("Usage: /runbook cap 1-30 or /runbook cap off")
    end
  elseif cmd == "quality" then
    local q = tonumber(arg)
    if q and q >= 0 and q <= 5 and q == math.floor(q) then
      db.quality = math.floor(q)
      ns.Print("Drop list keeps your and your partner's " .. QUALITY_NAMES[db.quality]
        .. " and better (other players': " .. QUALITY_NAMES[math.max(db.quality, 3)]
        .. " and better). Applies to new drops.")
    else
      ns.Print("Usage: /runbook quality 0-5 (now " .. db.quality .. ": " .. QUALITY_NAMES[db.quality] .. ")")
    end
  elseif cmd == "price" then
    if arg == "ah" or arg == "auction" then
      db.priceSource = "auction"
      ns.Print("Loot valued at AH prices"
        .. (ns.HasAuctionator() and "." or " (needs Auctionator; vendor until then)."))
    elseif arg == "vendor" then
      db.priceSource = "vendor"
      ns.Print("Loot valued at vendor prices.")
    else
      ns.Print("Usage: /runbook price vendor or /runbook price ah (now " .. db.priceSource .. ")")
    end
    ns.Fire("HISTORY_CHANGED")
  elseif cmd == "delete" then
    Delete(arg)
  elseif cmd == "clear" then
    local n = #db.history + #db.old
    if n == 0 then
      ns.Print("No saved runs.")
    elseif arg == "yes" and ns.CharacterCount() > 1 and not (clearAskedAt and GetTime() - clearAskedAt <= 15) then
      -- (Every character's runs: asked once more, even typed straight away.)
      clearAskedAt = GetTime()
      ns.Print("This deletes all " .. n .. " saved runs and their stats, for all " .. ns.CharacterCount()
        .. " of your characters. Type /runbook clear yes again within 15 seconds to do it.")
    elseif arg == "yes" then
      clearAskedAt = nil
      local chars = ns.CharacterCount()
      ns.ClearHistory()
      ns.lastRun = nil
      ns.Print("Deleted " .. ns.Plural(n, "saved run") .. (chars > 1 and (", for all " .. chars .. " characters") or "")
        .. ".")
      ns.Fire("HISTORY_CHANGED")
    else
      -- (With more than one character, this was the warning: clear yes within
      -- 15 seconds does it.)
      local many = ns.CharacterCount() > 1
      if many then clearAskedAt = GetTime() end
      ns.Print("This deletes " .. (n == 1 and "your 1 saved run and its stats"
        or ("all " .. n .. " saved runs and their stats")) .. (many and ", for all your characters" or "")
        .. ". Type /runbook clear yes " .. (many and "within 15 seconds " or "") .. "to confirm.")
    end
  elseif (cmd == "auto" or cmd == "sync") and arg == "" then
    -- (Just the word: what it's set to, not a switch.)
    local on = (cmd == "auto") and db.autoShow or db.sync
    ns.Print((cmd == "auto" and "Live window shows itself in dungeons: " or "Duo sync: ") .. OnOff(on)
      .. ". /runbook " .. cmd .. " " .. (on and "off" or "on") .. " to change it.")
  elseif cmd == "auto" then
    local v = Toggle(db.autoShow, arg, cmd)
    if v == nil then return end
    db.autoShow = v
    ns.Print("Live window shows itself in dungeons: " .. OnOff(db.autoShow))
    ns.manualShown = nil
    ns.UpdateVisibility()
  elseif cmd == "sync" then
    local v = Toggle(db.sync, arg, cmd)
    if v == nil then return end
    db.sync = v
    ns.Print("Duo sync: " .. OnOff(db.sync))
  elseif cmd == "lock" or cmd == "unlock" then
    db.locked = cmd == "lock"
    ns.Print("Live window " .. (db.locked and "locked." or "unlocked."))
  elseif cmd == "scale" then
    local s = tonumber(arg)
    if s and s >= 0.5 and s <= 2 then
      db.scale = s
      ns.ApplyPosition()
      ns.Print("Live window scale " .. s .. ".")
    else
      ns.Print("Usage: /runbook scale 0.5-2")
    end
  elseif cmd == "resetpos" then
    db.point = { "CENTER", "CENTER", -320, 120 }
    ns.ApplyPosition()
    ns.Print("Live window moved back to its starting spot.")
  elseif cmd == "check" then
    Check()
  elseif cmd == "debug" then
    if arg == "on" or arg == "off" then
      db.debug = arg == "on"
      if arg == "off" then db.debugEcho = false end
    elseif arg == "echo" then
      db.debug, db.debugEcho = true, not db.debugEcho
    elseif arg == "clear" then
      wipe(db.debugLog)
    elseif arg ~= "" then
      ns.Print("Usage: /runbook debug on, off, echo or clear")
      return
    end
    ns.Print(string.format("Debug log %s (echo %s, %s). /runbook export debug copies it.",
      OnOff(db.debug), OnOff(db.debugEcho), ns.Plural(#db.debugLog, "entry", "entries")))
  else
    if cmd ~= "help" and cmd ~= "?" then ns.Print("Unknown command \"" .. cmd .. "\".") end
    for _, l in ipairs(HELP) do print(l) end
  end
end
ns.HandleCommand = Handle

SLASH_VULCANRUNBOOK1 = "/runbook"
-- The names from before the Vulcan rename keep working.
SLASH_VULCANRUNBOOK2 = "/runlog"
SLASH_VULCANRUNBOOK3 = "/rlog"
SlashCmdList.VULCANRUNBOOK = function(msg)
  if not ns.DB then return end
  local ok, err = pcall(Handle, plain(msg) or "")
  if not ok then ns.ReportError("command", err) end
end

ns.Listen("LOGIN", function()
  if not ns.DB.welcomed then
    ns.DB.welcomed = true
    ns.Print("loaded. It starts on its own when you enter a dungeon. /runbook help for commands.")
  end
end)
