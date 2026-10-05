# Proves each auto-pairing and group-view guard is tested: undo it, the named test must fail.
import shutil, subprocess, os, sys
IGNORE = shutil.ignore_patterns('tests', 'audits', 'ci', '.git', '.github', '.release', 'media-src')  # copy only the add-on
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..')
TMP = '/tmp/runbook_mutg'
muts = [
 ("Battle.net friend", "Track.lua", "      friend = true\n      local t = plain(info.battleTag)", "      local t = plain(info.battleTag)", "Battle.net friend in a raid"),
 ("not-a-friend account", "Track.lua", "plain(info.isFriend) ~= false", "true", "a known account that isn't a friend"),
 ("friends list by GUID", "Track.lua", "      friend = ok and plain(r) == true\n", "      friend = false\n", "friends list by GUID only"),
 ("friends list by name", "Track.lua", "        if not friend then friend = ok and type(plain(info)) == \"table\" end\n", "", "hidden GUIDs"),
 ("tag learned", "Sync.lua", "    if tag then db.partnerTag = tag end\n", "", "another BattleTag doesn't take"),
 ("tag kept at pairing", "Sync.lua", "    db.partnerTag = tag\n", "", "a Battle.net friend in a raid"),
 ("saved tag checked", "Data.lua", "  if db.partnerTag ~= nil and (type(db.partnerTag) ~= \"string\" or not db.partner) then db.partnerTag = nil end\n", "", "partner off clears"),
 ("group version checked", "Sync.lua", "  local current = ver <= PROTOCOL and ver >= OLDEST_ACCEPTED\n", "  local current = true\n", "bad group messages"),
 ("group only in the run now", "Sync.lua", "    if field == \"group\" and create and r ~= ns.run then create = false end\n", "", "never start a part in an older run"),
 ("group parts cap", "Sync.lua", "      if n >= GROUP_PARTS then return false end\n", "", "the group view has limits"),
 ("group players cap", "Sync.lua", "        if n >= GROUP_MAX then return false end\n", "", "the group view has limits"),
 ("totals per player", "Sync.lua", "  if mineN > 4 and myOldest then\n", "  if false then\n", "the group view has limits"),
 ("totals in all", "Sync.lua", "  elseif n > TOTALS_MAX and oldest then\n", "  elseif false then\n", "the group view has limits"),
 ("split moves group runs", "Run.lua", "  for _, field in ipairs({ \"partners\", \"group\" }) do\n    for name, entry in pairs(type(old[field])", "  for _, field in ipairs({ \"partners\" }) do\n    for name, entry in pairs(type(old[field])", "a split moves the group's"),
 ("reopen counts group from then", "Sync.lua", "  for _, field in ipairs({ \"partners\", \"group\" }) do\n    for name, entry in pairs(type(run[field])", "  for _, field in ipairs({ \"partners\" }) do\n    for name, entry in pairs(type(run[field])", "a reopened run counts"),
 ("saved group checked", "Data.lua", "  for _, field in ipairs({ \"partners\", \"group\" }) do\n  for name, p in pairs(run[field] or {}) do", "  for _, field in ipairs({ \"partners\" }) do\n  for name, p in pairs(run[field] or {}) do", "damaged saved group data"),
 ("saved group cap", "Data.lua", "    if n > 40 then run.group[name] = nil end\n", "", "damaged saved group data"),
 ("live group line", "UI.lua", "  if ns.HasGroupStats(run) then\n    local gold, xp, n = ns.GroupTotals(run)", "  if false then\n    local gold, xp, n = ns.GroupTotals(run)", "others' numbers are shown"),
 ("details group section", "History.lua", "  if ns.HasGroupStats(run) then\n    -- Everyone", "  if false then\n    -- Everyone", "details and CSV show them"),
 ("CSV group columns", "Export.lua", "    groupN, groupGold, groupXP,\n", "    \"\", \"\", \"\",\n", "details and CSV show them"),
 ("rows: RunBook first", "Group.lua", "    if a.log ~= b.log then return a.log end\n", "", "players with numbers come before"),
 ("rows: most gold first", "Group.lua", "    if a.gold ~= b.gold then return a.gold > b.gold end\n", "", "others' numbers are shown"),
 ("rows: deaths", "Group.lua", "    row.deaths = Count(run.deaths, short)\n", "    row.deaths = 0\n", "deaths and drops count"),
 ("rows: drops", "Group.lua", "    row.drops = Count(run.drops, short)\n", "    row.drops = 0\n", "deaths and drops count"),
 ("rows: short form", "Group.lua", "  if type(run) ~= \"table\" or run.lite then return rows end\n", "  if type(run) ~= \"table\" then return rows end\n", "a short-form run"),
 ("cross-realm friend by bare name", "Track.lua", "      if not realm or (type(mine) == \"string\" and realm:gsub(\"[%s%-]\", \"\") == mine:gsub(\"[%s%-]\", \"\")) then\n", "      if true then\n", "another realm with a friend's name"),
 ("friend wait", "Sync.lua", "  if not w or time() - w.first < FRIEND_WAIT then return end\n", "  if not w then return end\n", "a friend (friends list)"),
 ("rows: namesakes apart", "Group.lua", "    if member and seen[short] then return end\n", "    if seen[short] then return end\n", "namesake of your partner"),
 ("CSV exact copper", "Group.lua", "(exact and r.copper or r.gold)", "r.gold", "CSV gold to the copper"),
 ("check: hidden GUIDs", "Commands.lua", "      if type(g) ~= \"string\" or g == \"\" then hidden = true end\n", "", "hidden players' GUIDs"),
 ("raid friend note", "Sync.lua", "(size <= 5 or (ns.FriendInfo and ns.FriendInfo(sender)))", "size <= 5", "a friend heard after one was picked"),
 ("alt keeps the first", "Sync.lua", "      ns.SetPartner(name, realm, sender, true)", "      ns.SetPartner(name, realm, sender)", "another character keeps the first"),
 ("settled per group", "Sync.lua", "VulcanRunBookCharDB.friendsMany, VulcanRunBookCharDB.bigGroup = nil, nil", "VulcanRunBookCharDB.bigGroup = nil", "over a reload"),
 ("tag cleared", "Sync.lua", "    db.partnerTag = nil\n  end\n  PartnerChars()", "  end\n  PartnerChars()", "partner off clears"),
 ("several friends: none", "Sync.lua", "    if #here > 1 then\n      VulcanRunBookCharDB.friendsMany = true", "    if false then\n      VulcanRunBookCharDB.friendsMany = true", "several friends who run RunBook"),
 ("friend must still be here", "Sync.lua", "    if not ns.SenderInGroup or ns.SenderInGroup(f.sender) then here[#here + 1] = key end\n", "    here[#here + 1] = key\n", "several friends who run RunBook"),
 ("several friends: stays none", "Sync.lua", "  if FriendsMany() or not VulcanRunBookCharDB then return end\n", "  if not VulcanRunBookCharDB then return end\n", "several friends who run RunBook"),
 ("partner off: friends again", "Sync.lua", "  if VulcanRunBookCharDB then VulcanRunBookCharDB.friendWait, VulcanRunBookCharDB.friendsMany = nil, nil end\n", "  if VulcanRunBookCharDB then VulcanRunBookCharDB.friendWait = nil end\n", "several friends who run RunBook"),
 ("several friends kept", "Sync.lua", "      VulcanRunBookCharDB.friendsMany = true\n", "", "over a reload"),
 ("alt not while partner here", "Sync.lua", "current and not PartnerHere() and", "current and", "no flip-flop"),
 ("offline main doesn't block", "Sync.lua", "        if on ~= false then return true end\n", "        return true\n", "in the group, offline"),
 ("other version never picked", "Sync.lua", "    if (friend or two) and not current then\n      Notice(name, ver)\n      return\n    end\n", "", "another RunBook version is never picked"),
 ("two-person: version", "Sync.lua", "(friend or two) and not current", "friend and not current", "in a two-person group either"),
 ("only while in a group", "Sync.lua", "  if ns.DB.partner or not InGroup() then\n", "  if ns.DB.partner then\n", "just before you left the group"),
 ("reopen reconciles", "Sync.lua", "  ns.ReconcilePartners(run)\nend)", "end)", "end, a new partner, then start"),
 ("partner X: same person", "Commands.lua", "      ns.PartnerChanged(nil, same)\n", "      ns.PartnerChanged(nil, false)\n", "in the group, offline"),
 ("partner chars start over", "Sync.lua", "    db.partnerChars = {}\n", "", "in the group, offline"),
 ("partnersSeen pruned", "Sync.lua", "    if not ns.IsPartnerChar(who) then ns.partnersSeen[who] = nil end\n", "", "aren't 'you two's' any more"),
 ("IsDuo: partner chars", "Track.lua", " or (ns.IsPartnerChar ~= nil and ns.IsPartnerChar(who))", "", "in the group, offline"),
 ("held messages taken", "Sync.lua", "      local ok, err = pcall(handler, f.name, m.body)\n", "      local ok, err = true, nil\n", "sends during the wait"),
 ("held taken on any pairing", "Sync.lua", "  if waited then TakeHeld(waited) end\n", "", "however they become your partner"),
 ("held cap", "Sync.lua", "  if kind ~= \"S\" and #f.held < FRIEND_HELD then", "  if kind ~= \"S\" then", "sends during the wait"),
 ("held replay cap", "Sync.lua", "  for i = 1, math.min(#f.held, FRIEND_HELD) do", "  for i = 1, #f.held do", "however they become your partner"),
 ("wait saved", "Sync.lua", "    VulcanRunBookCharDB.friendWait = w\n", "", "however they become your partner"),
 ("wait checked on load", "Sync.lua", "    if VulcanRunBookCharDB then VulcanRunBookCharDB.friendWait = nil end\n    return nil", "    return nil", "however they become your partner"),
 ("same-name friends apart", "Sync.lua", "  local key = ns.GroupKey(name, realm)\n  local f = w.list[key] or { held = {} }", "  local key = name\n  local f = w.list[key] or { held = {} }", "two friends with one name"),
 ("wait from the future", "Sync.lua", "w.first > time() + 60", "false", "wait from the future"),
 ("two-person: asked fresh", "Sync.lua", "ns.FriendInfo(sender, two)", "ns.FriendInfo(sender)", "still picked in a two-person group"),
 ("two-person: its own note", "Sync.lua", "      local noted = two and (\"2:\" .. name) or name\n", "      local noted = name\n", "gets a note when it's down to two"),
 ("command: your realm's first", "Commands.lua", "          if not found or (not r and unitRealm) then name, found, unitRealm = n, true, r end\n", "          name, found, unitRealm = n, true, r\n", "two Mirels in the group"),
 ("command: alt", "Commands.lua", "      local same = isAlt or ns.IsPartnerChar(name, realm)", "      local same = ns.IsPartnerChar(name, realm)", "partner <name> alt"),
 ("command: same BattleTag", "Commands.lua", "        same = tag ~= nil and tag == db.partnerTag\n", "", "partner <name> alt"),
 ("hint: alt", "Sync.lua", "        local alt = not PartnerHere() and", "        local alt = false and", "partner <name> alt"),
 ("known char, partner gone: followed", "Sync.lua", "    if known or (tag and tag == db.partnerTag) then", "    if tag and tag == db.partnerTag then", "back on a known character, alone"),
 ("finder stranger not picked", "Sync.lua", "    if not two or (BigGroup()[key] and not friend) then", "    if not two then", "dungeon-finder group down to two"),
 ("finder stranger over a reload", "Sync.lua", "    if VulcanRunBookCharDB then VulcanRunBookCharDB.bigGroup = b end\n", "", "a /reload in a dungeon-finder group"),
 ("finder: forgotten out of a group", "Sync.lua", "VulcanRunBookCharDB.friendsMany, VulcanRunBookCharDB.bigGroup = nil, nil", "VulcanRunBookCharDB.friendsMany = nil", "a /reload in a dungeon-finder group"),
 ("two-person: a friend heard before", "Sync.lua", "(not two or BigGroup()[key]) and ns.FriendInfo and ns.FriendInfo(sender, two)", "not two and ns.FriendInfo and ns.FriendInfo(sender, two)", "still picked in a two-person group"),
 ("friends pair up", "Sync.lua", "    local friend = (not two or BigGroup()[key]) and ns.FriendInfo and ns.FriendInfo(sender, two)\n", "    local friend = false\n", "a friend (friends list)"),
 ("realm as the game spells it", "Commands.lua", "      realm = unitRealm or (found and ns.MyRealm()) or realm", "      realm = realm or unitRealm or (found and ns.MyRealm()) or nil", "lower case is the game's realm"),
 ("GroupKey realm case", "Sync.lua", "not ns.SameName(realm, (mine:gsub(\"[%s%-]\", \"\")))", "realm ~= mine:gsub(\"[%s%-]\", \"\")", "plays on while your run is ended"),
 ("alt followed", "Sync.lua", "    if known or (tag and tag == db.partnerTag) then", "    if known then", "same Battle.net account) is followed"),
 ("group key keeps the realm", "Sync.lua", "  if realm and type(mine) == \"string\" and not ns.SameName(realm, (mine:gsub(\"[%s%-]\", \"\"))) then\n    return name .. \"-\" .. realm\n  end\n", "", "another realm keeps their realm"),
 ("command: your realm when in group", "Commands.lua", "      realm = unitRealm or (found and ns.MyRealm()) or realm", "      realm = unitRealm or realm", "two Mirels in the group"),
 ("names hidden: heard lately", "Sync.lua", "    if ns.IsPartnerChar(who) and GetTime() - at < 300 then return true end\n", "", "names hidden: two characters"),
 ("names hidden: a long fight", "Sync.lua", "GetTime() - at < 300 then return true end", "GetTime() - at < 40 then return true end", "a long boss fight"),
 ("presence by realm", "Sync.lua", " and not (db.partnerRealm and r and not ns.SameName(r, db.partnerRealm))", "", "same name on another realm is followed"),
 ("partner chars by realm", "Sync.lua", "local function CharKey(name, realm) return ns.GroupKey(name, realm) end", "local function CharKey(name) return name end", "same name on another realm is followed"),
 ("partner char by realm", "Sync.lua", " and not (realm and type(r) == \"string\" and not ns.SameName(r, realm)) then\n      return true", "  then\n      return true", "two Mirels in the group"),
 ("partner chars cap", "Sync.lua", "    if n >= CHARS_MAX and other then db.partnerChars[other] = nil end\n", "", "at most 20 kept"),
 ("partner entry put right", "Sync.lua", "  if key then db.partnerChars[key] = db.partnerRealm or true end\n", "", "can't move your partner out"),
 ("saved chars: empty", "Data.lua", " or k == \"\" or (v ~= true and (type(v) ~= \"string\" or v == \"\"))", " or (v ~= true and type(v) ~= \"string\")", "can't move your partner out"),
 ("saved partner chars checked", "Data.lua", "        if type(k) ~= \"string\" or k == \"\" or (v ~= true and (type(v) ~= \"string\" or v == \"\")) then\n          db.partnerChars[k] = nil", "        if false then\n          db.partnerChars[k] = nil", "damaged saved partner characters"),
 ("saved partner chars cap", "Data.lua", "          if n > 20 and not ns.SameName(k, db.partner) then db.partnerChars[k] = nil end\n", "", "at most 20 kept"),
 ("known only once heard", "Sync.lua", " and PartnerHeard()[ns.GroupKey(name, realm)] == true", "", "never heard from isn't followed"),
 ("heard recorded", "Sync.lua", "  PartnerHeard()[key] = true\n", "", "online together"),
 ("switch-back line: realm", "Sync.lua", "      local was = ns.GroupKey(db.partner, db.partnerRealm)", "      local was = db.partner", "switch-back command keeps"),
 ("IsRunDuo: keyed entries", "Track.lua", "    if type(k) == \"string\" and ns.SameName(ns.ShortName(k), who) then return true end\n", "", "IsRunDuo"),
 ("partner's numbers move over", "Sync.lua", "        if have == nil then\n          run.partners[gk] = e", "        if false then\n          run.partners[gk] = e", "moves their numbers out"),
 ("reconcile demotes", "Sync.lua", "      run.partners[k] = nil\n    end\n  end\n  -- And your partner", "    end\n  end\n  -- And your partner", "changing partner mid-run"),
 ("reconcile into group", "Sync.lua", "      if run.group[k] == nil then run.group[k] = e end\n", "", "changing partner mid-run"),
 ("known char, partner here: stats", "Sync.lua", "      if kind == \"S\" then ns.GroupStats(key, body, \"partners\") end", "      if kind == \"S\" then ns.GroupStats(key, body) end", "online together"),
 ("bare name: your realm", "Commands.lua", "        realm = ns.PartnerCharRealm(name) or ns.MyRealm()\n", "", "bare name set before grouping"),
 ("one identity for a player", "Sync.lua", "  local state = sender\n  if final then", "  local state = \"~\" .. sender\n  if final then", "a reopened run counts"),
 ("reopen by key", "Sync.lua", "          local now = totals[name .. \"@\" .. key]", "          local now = totals[ns.ShortName(name) .. \"@\" .. key]", "plays on while your run is ended"),
 ("others to the group view", "Sync.lua", "    if kind == \"S\" and current then ns.GroupStats(key, body) end\n", "", "a stranger in a 5-player group"),
 ("partner entries by identity", "Sync.lua", "  ApplyStats(msgIdent or sender, target, start, dungeon, f, \"partners\")", "  ApplyStats(sender, target, start, dungeon, f, \"partners\")", "same-named characters on two realms"),
 ("switch back: the character's realm", "Commands.lua", "        realm = ns.PartnerCharRealm(name) or ns.MyRealm()", "        realm = ns.MyRealm()", "switch-back command keeps"),
 ("promotion: that very player", "Sync.lua", "  local function RealmOf(k) return k:match(\"%-(.+)$\") or ns.MyRealm() end", "  local function RealmOf(k) return k:match(\"%-(.+)$\") end", "namesake of your partner"),
]
suite = sys.argv[1] if len(sys.argv) > 1 else 'tests_group.lua'
ok = True
# The unmutated suite must be green first (a red baseline would 'catch' every mutation).
shutil.rmtree(TMP, ignore_errors=True); shutil.copytree(SRC, TMP, ignore=IGNORE)
base = subprocess.run(['lua5.1', suite], cwd=HERE, env=dict(os.environ, RL_DIR=TMP + '/'), capture_output=True, text=True)
if base.returncode != 0 or 'FAIL [' in base.stdout:
    print('BASELINE NOT GREEN'); print(base.stdout[-2000:]); sys.exit(1)
suite_text = open(os.path.join(HERE, suite)).read()
for name, f, a, b, group in muts:
    shutil.rmtree(TMP, ignore_errors=True); shutil.copytree(SRC, TMP, ignore=IGNORE)
    p = os.path.join(TMP, f); s = open(p).read()
    if group not in suite_text:
        if not any(group in open(os.path.join(HERE, f)).read() for f in ('tests_group.lua', 'tests_group_duo.lua')):
            print("NO TEST GROUP:", name); ok = False
        continue  # (checked by the other suite)
    if a not in s: print("MISSING SNIPPET:", name); ok = False; continue
    open(p, 'w').write(s.replace(a, b, 1))
    try:
        r = subprocess.run(['lua5.1', suite], cwd=HERE, env=dict(os.environ, RL_DIR=TMP + '/'), capture_output=True,
                           text=True, timeout=120)
        out = r.stdout + r.stderr
        red = any(('FAIL [' in l and group in l) for l in out.splitlines())
        # (A suite that crashes before the group runs caught it too: run.sh fails.)
        red = red or (r.returncode != 0 and ('FAIL [' not in out or 'stack traceback' in out))
    except subprocess.TimeoutExpired:
        red = True  # (it hangs: caught)
    print(("RED  " if red else "GREEN"), name)
    ok = ok and red
print("all mutations caught" if ok else "SOME MUTATION SURVIVED")
sys.exit(0 if ok else 1)
