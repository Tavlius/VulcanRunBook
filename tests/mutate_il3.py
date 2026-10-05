# Proves each improvement-loop-3 guard is tested: undo it, the named test must fail.
import shutil, subprocess, os, sys
IGNORE = shutil.ignore_patterns('tests', 'audits', 'ci', '.git', '.github', '.release', 'media-src')  # copy only the add-on
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..')
TMP = '/tmp/runbook_mut3'
muts = [
 ("short form: delete finds it", "Data.lua", "  for j, o in ipairs(ns.DB.old) do", "  for j, o in ipairs({}) do", "short-form run can be deleted"),
 ("short form: says why", "Data.lua", "  if r and list == ns.DB.old then", "  if false then", "short-form run can be deleted"),
 ("best run's number", "History.lua", "(s.bestId and (\" (#\" .. s.bestId .. \")\") or \"\")", "\"\"", "best run's number"),
 ("restore notice again", "Data.lua", "  if accountLoaded then char.restoreNoticed = nil end", "", "each time"),
 ("restore counts short form", "Run.lua", "restored.short > 0 and", "false and", "each time"),
 ("archive in order", "Data.lua", "    while ns.DB.old[j] and (ns.DB.old[j].startedAt or 0) > (lite.startedAt or 0) do j = j + 1 end", "", "in order, and says so"),
 ("archive says so", "Run.lua", "      .. (short == \"short\" and", "      .. (false and", "in order, and says so"),
 ("characters by realm", "Data.lua", "        if c:find(\"-\", 1, true) then", "        if false then", "two realms"),
 ("realm in the label", "Data.lua", "  return (Characters().realms[short] or 0) > 1 and char or short", "  return short", "two realms"),
 ("short-form AH partner gold", "Data.lua", " pgAH = ns.PartnersGold(run, true),", "", "price setting"),
 ("deletions by when", "Data.lua", "  table.sort(keys, function(x, y) return When(x) > When(y) end)", "  table.sort(keys, function(x, y) return tostring(x) > tostring(y) end)", "deletions are kept"),
 ("deletion time saved", "Data.lua", "    ns.DB.deleted[ns.RunUID(run)] = ns.ServerTime()  -- (when: the newest are kept)", "    ns.DB.deleted[ns.RunUID(run)] = 1", "deletions are kept"),
 ("queue saved at logout", "Sync.lua", "    VulcanRunBookCharDB.syncQueue = #keep > 0 and keep or nil", "    VulcanRunBookCharDB.syncQueue = nil", "after a /reload"),
 ("saved queue too old", "Sync.lua", "          and type(q.at) == \"number\" and time() - q.at <= HOLD_SECONDS then", "          then", "after a /reload"),
 ("queue held out of group", "Sync.lua", "      if time() - (queue[i].at or 0) > HOLD_SECONDS then table.remove(queue, i) end", "      table.remove(queue, i)", "short break"),
 ("late drop by loot time", "Sync.lua", "  elseif run.ended and f[4] and run.serverEnd then", "  elseif false then", "looted before your run ended"),
 ("partner realm", "Sync.lua", "      or (realm and type(db.partnerRealm) == \"string\" and not ns.SameName(realm, db.partnerRealm)) then", "      then", "another realm"),
 ("check by name", "Commands.lua", "    for who, v in pairs(ns.partnerKills) do if ns.SameName(who, ns.DB.partner) then k = v end end", "    k = ns.partnerKills[ns.DB.partner]", "whatever the case"),
 ("heard by name", "Commands.lua", "  for who, at in pairs(ns.partnersSeen) do if ns.SameName(who, ns.DB.partner) then heard = at end end", "  heard = ns.partnersSeen[ns.DB.partner]", "whatever the case"),
 ("kill timed when it died", "Track.lua", "    boss.t = math.max(0, boss.t - math.max(0, ns.ServerTime() - theirKillAt))", "", "timed when it died"),
 ("stats replaced in the queue", "Sync.lua", "        q.msg = msg\n", "", "replaces the waiting one"),
 ("sweep #62 ns.DeleteRun IFTRUE", "Data.lua", "    if type(me) == \"table\" and ns.RunUID(me) == ns.RunUID(run) then VulcanRunBookCharDB.manualEnded = nil end", "    if true then VulcanRunBookCharDB.manualEnded = nil end", "deleting another run"),
 ("sweep #65 ns.PerHour RETDEL", "Data.lua", "  if not seconds or seconds < ns.MIN_RATE_SECONDS then return nil end", "  if not seconds or seconds < ns.MIN_RATE_SECONDS then end", "rates only after 5 minutes"),
 ("sweep #100 ns.Lite IFTRUE", "Data.lua", "  if run.lite then return run end", "  if true then return run end", "short form has no notes"),
 ("sweep #151 WorthKeeping ANDOR", "Run.lua", "  if run.elapsed >= ns.MIN_KEEP_SECONDS or #run.bosses > 0 or #run.drops > 0 or #run.deaths > 0", "  if run.elapsed >= ns.MIN_KEEP_SECONDS or #run.bosses > 0 and #run.drops > 0 or #run.deaths > 0", "only a note, or only a copper"),
 ("sweep #200 WorthKeeping NUM", "Run.lua", "      or #run.wipes > 0 or #run.notes > 0 or run.coin > 0 or run.xp > 0 or run.loot > 0 or run.unpriced > 0", "      or #run.wipes > 0 or #run.notes > 0 or run.coin > 1 or run.xp > 0 or run.loot > 0 or run.unpriced > 0", "only a note, or only a copper"),
 ("sweep #249 WorthKeeping ANDOR", "Run.lua", "      or #run.wipes > 0 or #run.notes > 0 or run.coin > 0 or run.xp > 0 or run.loot > 0 or run.unpriced > 0", "      or #run.wipes > 0 and #run.notes > 0 or run.coin > 0 or run.xp > 0 or run.loot > 0 or run.unpriced > 0", "only a note, or only a copper"),
 ("sweep #160 ns.ManualNew ASSDEL", "Run.lua", "  VulcanRunBookCharDB.suppress, VulcanRunBookCharDB.manualEnded = nil, nil", "", "end then /runbook new"),
 ("sweep #196 CopyKillsOf REL", "Run.lua", "  for _, k in ipairs(type(run.copyKills) == \"table\" and run.copyKills or {}) do out[#out + 1] = k end", "  for _, k in ipairs(type(run.copyKills) ~= \"table\" and run.copyKills or {}) do out[#out + 1] = k end", "second /runbook end"),
 ("sweep #303 ns.SnapshotMembers IFNEG", "Track.lua", "  if ns.InRun() then ns.SnapshotMembers() end", "  if not (ns.InRun()) then ns.SnapshotMembers() end", "joins mid-run"),
 ("sweep #355 ns.SnapshotMembers IFFALSE", "Track.lua", "  if ns.InRun() then ns.SnapshotMembers() end", "  if false then ns.SnapshotMembers() end", "joins mid-run"),
 ("sweep #352 ns.AddBoss IFFALSE", "Track.lua", "    if ns.SyncSplit then ns.SyncSplit(run, nil, ck.st) end", "    if false then ns.SyncSplit(run, nil, ck.st) end", "tells your partner to split"),
 ("sweep #357 AddDeath ANDOR", "Track.lua", "  if ns.DB and ns.InRun() then AddDeath(ns.PlayerName() or \"You\") end", "  if ns.DB or ns.InRun() then AddDeath(ns.PlayerName() or \"You\") end", "dying outside"),
 ("sweep #426 ns.SyncNoteRoom NUM", "Sync.lua", "  return 255 - #Header(\"N\", run) - 3", "  return 0 - #Header(\"N\", run) - 3", "aren't cut short"),
 ("sweep #432 HANDLERS.B ANDOR", "Sync.lua", "  local b = ns.AddBoss(id > 0 and id or nil, name ~= \"\" and name or nil, \"sync\", key, entry or start,", "  local b = ns.AddBoss(id > 0 and id and nil, name ~= \"\" and name or nil, \"sync\", key, entry or start,", "keeps its boss id"),
 ("sweep #471 AddStats ANDOR", "UI.lua", "  if g and gold > 0 then rates[#rates + 1] = ns.Money(Shown(g)) .. \"/hr\" end", "  if g or gold > 0 then rates[#rates + 1] = ns.Money(Shown(g)) .. \"/hr\" end", "rates only after 5 minutes"),
 ("sweep #485 AddStats IFFALSE", "UI.lua", "  if x and xp > 0 then rates[#rates + 1] = ns.Short(x) .. \" XP/hr\" end", "  if false then rates[#rates + 1] = ns.Short(x) .. \" XP/hr\" end", "rates only after 5 minutes"),
 ("sweep #495 EndText IFFALSE", "History.lua", "  if not run.ended then return \"in progress\" end", "  if false then return \"in progress\" end", "details say how"),
 ("sweep #513 EndText IFTRUE", "History.lua", "  if run.endReason == \"timeout\" and run.kind == \"raid\" then return \"ended: away 2+ hours\" end", "  if true then return \"ended: away 2+ hours\" end", "details say how"),
 ("sweep #511 ns.RunRowText IFTRUE", "History.lua", "  if blues > 0 then parts[#parts + 1] = \"|cff0070dd\" .. ns.Plural(blues, \"blue\") .. \"|r\" end", "  if true then parts[#parts + 1] = \"|cff0070dd\" .. ns.Plural(blues, \"blue\") .. \"|r\" end", "no zero counts"),
 ("sweep #515 ns.DungeonLines IFNEG", "History.lua", "    if s.wipes > 0 then more[#more + 1] = ns.Plural(s.wipes, \"wipe\") end", "    if not (s.wipes > 0) then more[#more + 1] = ns.Plural(s.wipes, \"wipe\") end", "no zero counts"),
 ("sweep #524 Wrap ASSDEL", "History.lua", "      line = indent .. word", "", "long notes"),
 ("sweep #528 Minutes NUM", "Export.lua", "local function Minutes(sec) return sec and string.format(\"%.1f\", sec / 60) or \"\" end", "local function Minutes(sec) return sec and string.format(\"%.1f\", sec / 120) or \"\" end", "CSV has"),
 ("sweep #542 Minutes NUM", "Export.lua", "local function Minutes(sec) return sec and string.format(\"%.1f\", sec / 60) or \"\" end", "local function Minutes(sec) return sec and string.format(\"%.1f\", sec / 61) or \"\" end", "CSV has"),
 ("sweep #549 Minutes NUM", "Export.lua", "local function Minutes(sec) return sec and string.format(\"%.1f\", sec / 60) or \"\" end", "local function Minutes(sec) return sec and string.format(\"%.1f\", sec / 59) or \"\" end", "CSV has"),
 ("sweep #547 ns.CSVRow ASSDEL", "Export.lua", "    partnerGold = partnerGold + ns.PartnerGold(p)", "", "CSV has"),
 ("sweep #564 Handle IFNEG", "Commands.lua", "    if not ns.ManualEnd() then ns.Print(\"No run in progress.\") end", "    if not (not ns.ManualEnd()) then ns.Print(\"No run in progress.\") end", "says the run ended"),
 ("sweep #597 Report ASSDEL", "Commands.lua", "  channel = channel:lower()", "", "any case"),
 ("short form numbered too", "Data.lua", "  for i = #db.old, 1, -1 do numbered[#numbered + 1] = db.old[i] end", "", "numbered apart"),
 ("dropped run said", "Run.lua", "        or short == \"dropped\" and", "        or false and", "too old to keep"),
 ("loot time decides", "Sync.lua", "    if f[4] > run.serverEnd + 1 or time() - (run.endedAt or 0) > 120 then return end", "    if time() - (run.endedAt or 0) > 120 then return end", "looted after your run ended isn't"),
 ("no best for a dropped run", "Run.lua", "        and short ~= \"dropped\" then  -- (a run not kept isn't a best)", "        then", "too old to keep"),
 ("clear asks for all characters", "Commands.lua", "    elseif arg == \"yes\" and ns.CharacterCount() > 1 and not (clearAskedAt and GetTime() - clearAskedAt <= 15) then", "    elseif false then", "clear yes asks again"),
 ("history rate rounded", "History.lua", "out[#out + 1] = ns.Money(ns.ShownMoney(g)) .. \"/hr\" end", "out[#out + 1] = ns.Money(g) .. \"/hr\" end", "history rates round"),
 ("details rate from shown gold", "History.lua", "Rates(mine, run.xp or 0, run.elapsed))", "Rates(ns.RunGold(run), run.xp or 0, run.elapsed))", "same live, in the details"),
 ("stats gold as shown", "Data.lua", "      s.gold = s.gold + ns.ShownMoney(ns.RunGold(r))", "      s.gold = s.gold + ns.RunGold(r)", "same live, in the details"),
 ("bare clear arms the confirm", "Commands.lua", "      if many then clearAskedAt = GetTime() end", "", "clear then clear yes"),
 ("first-visit ghost return", "Run.lua", "    if wasGhost then\n", "    if wasGhost and run.resumeSnap then\n", "while you ran back keeps its time"),
 ("ghost return split point", "Run.lua", "      run.ghostSnap = Snap(run)\n", "", "dead outside is found"),
 ("own repeat kill after a ghost return", "Track.lua", "    local at = ns.SplitPointFor(run, have.st)\n", "    local at = nil\n", "dead outside is found"),
 ("late reset after a ghost return", "Run.lua", "    elseif ns.LastReturn(run) and ns.ServerTime() - ns.LastReturn(run).server <= 120", "    elseif run.resumeSnap and ns.ServerTime() - run.resumeSnap.server <= 120", "late reset message after your ghost return"),
 ("his repeat kill after a ghost return", "Track.lua", "    local at = again and ns.SplitPointFor(run, known.st) or nil\n", "    local at = again and run.resumeSnap and known.st < run.resumeSnap.server and run.resumeSnap or nil\n", "his repeat kill or split after your ghost return"),
 ("his split after a ghost return", "Sync.lua", "  if after then snap = ns.SplitPointFor(run, after) else snap = ns.LastReturn(run) end\n", "  snap = run.resumeSnap\n", "his repeat kill or split after your ghost return"),
 ("raid saved to the weekly reset", "Run.lua", "      local saved = type(c.expires) == \"number\" and ns.ServerTime() < c.expires\n", "      local saved = false\n", "a raid week over two nights"),
 ("weekly reset time read", "Run.lua", "    if type(s) == \"number\" and s > 0 and s <= 8 * 86400 then expires = ns.ServerTime() + s end\n", "", "a raid week over two nights"),
 ("timed-out run remembered", "Run.lua", "  if (reason == \"manual\" or reason == \"new dungeon\" or reason == \"timeout\")\n", "  if (reason == \"manual\" or reason == \"new dungeon\")\n", "a raid week over two nights"),
 ("timed-out run remembered (duo)", "Run.lua", "  if (reason == \"manual\" or reason == \"new dungeon\" or reason == \"timeout\")\n", "  if (reason == \"manual\" or reason == \"new dungeon\")\n", "away 30+ minutes"),
 ("partner kept the copy", "Sync.lua", "    if c then ns.RejoinCopy(now, c, sender) end\n", "", "away 30+ minutes"),
 ("rejoin takes back the cap entry", "Run.lua", "      if type(list[i]) == \"number\" and math.abs(list[i] - (run.serverStart or 0)) <= 5 then\n", "      if false then\n", "away 30+ minutes"),
 ("copy kept for the partner", "Run.lua", "      if not keep then table.remove(list, i) end\n", "      table.remove(list, i)\n", "away 30+ minutes"),
 ("only his run in that copy", "Run.lua", "c.partners[sender .. \"@\" .. tostring(start)]", "next(c.partners)", "he left too"),
 ("unboss of a split mark", "Track.lua", "    run.entryBy = { boss = { id = id, name = name }, at = run.counted and run.serverStart or nil }\n", "", "unboss of a mark that split"),
 ("CSV minus guard", "Export.lua", "(v:find(\"^%-\") and not v:find(\"^%-%d+%.?%d*$\"))", "v:find(\"^%-[^%d]\")", "a cell starting with '-'"),
 ("visits kept in a split", "Run.lua", "      item.v = math.max(1, (item.v or 1) - visit + 1)  -- (its visit, counted in the new run)\n", "      item.v = 1\n", "the run splits again there"),
 ("later return carried", "Run.lua", "      new[k] = r\n", "", "the run splits again there"),
 ("visit count carried", "Run.lua", "  new.visit = math.max(1, (old.visit or 1) - (s.visit or 1) + 1)\n", "", "the run splits again there"),
 ("his copy kill while outside", "Track.lua", "      elseif ns.LastReturn(run) and (ns.inside or theirEntry > ck.st) then\n", "      elseif ns.inside and ns.LastReturn(run) then\n", "while you're outside splits your run"),
]
suite = sys.argv[1] if len(sys.argv) > 1 else 'tests_il3.lua'
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
        if not any(group in open(os.path.join(HERE, f)).read() for f in ('tests_il3.lua', 'tests_il3_duo.lua')):
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
        red = red or (r.returncode != 0 and 'FAIL [' not in out)
    except subprocess.TimeoutExpired:
        red = True  # (it hangs: caught)
    print(("RED  " if red else "GREEN"), name)
    ok = ok and red
print("all mutations caught" if ok else "SOME MUTATION SURVIVED")
sys.exit(0 if ok else 1)
