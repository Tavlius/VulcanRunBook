# Proves each improvement-loop-1 guard is tested: undo it, the named test must fail.
import shutil, subprocess, os, sys
IGNORE = shutil.ignore_patterns('tests', 'audits', 'ci', '.git', '.github', '.release', 'media-src')  # copy only the add-on
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..')
TMP = '/tmp/runbook_mut'
muts = [
 ("P outside: no split", "Sync.lua", "if snap and once and ns.inside and", "if snap and once and", "split message while you're outside"),
 ("kill-time rule", "Track.lua", "and diedAt > known.st + 120", "and true", "late message for the same kill"),
 ("entry, not run start", "Sync.lua", 'ns.AddBoss(id > 0 and id or nil, name ~= "" and name or nil, "sync", key, entry or start,',
   'ns.AddBoss(id > 0 and id or nil, name ~= "" and name or nil, "sync", key, start,', "(his entry is)"),
 ("ghost keeps split point", "Run.lua", "    if wasGhost then\n", "    if false then\n", "ghost run back"),
 ("copy kills own", "Track.lua", "local ck = not have and named and not sync and ns.inside and CopyKill(run, boss)",
   "local ck = false", "died in this copy in an earlier run"),
 ("P from partner-found reset", "Track.lua", "if ns.SyncSplit then ns.SyncSplit(ns.run, theirEntry, known.st) end  -- (their log may not know)", "", "a reset his log can't see"),
 ("finite numbers", "Sync.lua", "x ~= x or x < -1 or x > 2e9 or x ~= math.floor(x)", "false", "only finite whole numbers"),
 ("group channel", "Sync.lua", "if type(channel) == \"string\" and not GROUP_CHANNELS[channel] then return end", "", "only from your group"),
 ("sender in group", "Sync.lua", "if ns.SenderInGroup and not ns.SenderInGroup(sender) then return end", "", "only from your group"),
 ("boss name cleaned", "Sync.lua", "name = ns.Truncate(ns.CleanText(name or \"\"), 100)", "name = name or \"\"", "boss name is cleaned"),
 ("note room", "Track.lua", "if not who and ns.SyncNoteRoom then", "if false then", "note fits one message"),
 ("false retried", "Sync.lua", "elseif (not ok or result == false or RETRY_A_WHILE[result])", "elseif (not ok or RETRY_A_WHILE[result])", "'not now' is retried"),
 ("version notice", "Sync.lua", "local OLDEST_ACCEPTED = 3", "local OLDEST_ACCEPTED = 2", "both get the notice"),
 ("saved-data validation", "Data.lua", "  NumOrNil(run, RUN_NUMBERS)\n  StrOrNil(run, RUN_STRINGS)\n  if run.map", "  if run.map", "damaged saved run"),
 ("LFG string", "Util.lua", 'msg:lower():find("entered too many instances", 1, true)', 'msg:lower():find("too many instances", 1, true)', "dungeon finder"),
 ("Korean particle", "Util.lua", 'if p ~= "" and #name > #p and name:sub(-#p) == p then', 'if false then', "Korean"),
 ("dungeon key", "Run.lua", "if run and ns.DungeonKey(run.name) == key then", "if run and run.name == name then", "naming 'The Deadmines'"),
 ("bag dip", "Track.lua", "if d and now - d.at <= BAG_DIP_SECONDS then was = math.max(was, d.n) end", "", "dips and comes back"),
 ("daily cap", "UI.lua", "if capDay <= 0 or day < capDay - 5 then return nil end", "do return nil end", "the daily cap"),
 ("over-cap hint", "Run.lua", "if cap > 0 and count > cap and not overCapHinted then", "if false then", "past the cap"),
 ("known boss name", "Commands.lua", "if name then name = ns.KnownBossName(ns.RunKey(ns.run), name, ns.run) end", "", "matches how you wrote it"),
 ("ambiguous name", "Data.lua", "if best and not ns.NameMatch(best, n) then return name end", "", "ambiguous name"),
 ("new asks", "Commands.lua", 'if big and arg ~= "yes" and', 'if false and', "asks first"),
 ("char on rows", "History.lua", "if ns.CharacterCount() > 1 then", "if false then", "whose run"),
 ("raid deaths", "Data.lua", 'if run.nd or run.kind ~= "raid" or type(run.deaths) ~= "table" then', 'if true then', "raid deaths"),
 ("byHand label", "History.lua", "((b.manual or b.byHand) and", "((b.manual) and", "labelled"),
 ("together gold", "Run.lua", 'if theirs > 0 then parts[#parts + 1] = "together "', 'if false then parts[#parts + 1] = "together "', "together gold"),
 ("check lines", "Commands.lua", 'P(string.format("Resets: %d reset messages', 'P(string.format("(%d) %d', "/runbook check"),
 ("strict word boundaries", "Util.lua", 'before:match("[%s,]")) and (j == #fb or after:match("[%s,]"))', 'before:match("[%s%-\',]")) and (j == #fb or after:match("[%s%-\',]"))', "Sneed and Sneed's Shredder"),
 ("pairing by similar name", "Track.lua", "      if other and named and similar then", "      if other and named then", "seconds apart"),
 ("wing copy kills", "Run.lua", "if sameCopy then new.copyKills = kills end", "", "Scarlet Monastery wing after a reset"),
 ("trust fallback", "Track.lua", 'n ~= UNKNOWN and not ns.IsPlayerUnit(unit) then', 'n ~= UNKNOWN then', "can't be read"),
 ("settings validation", "Data.lua", "if db.scale < 0.5 or db.scale > 2 then db.scale = 1 end", "", "damaged settings"),
 ("day full is not free", "Run.lua", "or (capDay > 0 and day >= capDay) then", "then", "the day is full"),
 ("similar names in stats", "Data.lua", "  return ns.NameSimilar(a.name, b.name)\nend\nns.SameBoss", "  return ns.NameMatch(a.name, b.name)\nend\nns.SameBoss", "Van Cleef"),
 ("unboss undoes entry", "Track.lua", "if t == e.at then table.remove(ns.DB.entries, i) break end", "", "takes back the instance"),
 ("NaN entries", "Data.lua", "      if Finite(v) and not seen[v] then", "      if type(v) == \"number\" and not seen[v] then", "NaN in saved entries"),
 ("entry tied to its boss", "Track.lua", "if type(e) == \"table\" and type(e.boss) == \"table\" and ns.SameBoss(e.boss, b) then", "if type(e) == \"table\" then", "goes with that kill only"),
 ("similar name for recent kill", "Track.lua", "and last.src ~= \"sync\" and ns.NameSimilar(name, last.name) then", "and last.src ~= \"sync\" then", "typed right after a reported kill"),
 ("parts validated", "Data.lua", 'NumOrNil(part, { "at", "raw", "elapsed", "coin", "loot", "lootAH", "xp" })', "", "partner parts"),
 ("stale login inside", "Run.lua", "if time() - last > Timeout(run) and run.leftAt then", "if time() - last > Timeout(run) then", "logged out inside for 40 minutes"),
 ("copy kill on naming", "Track.lua", "  if name then b.name, b.anonymous = name, nil end\n  AfterNaming(b)", "  if name then b.name, b.anonymous = name, nil end", "the key, then the name"),
 ("partner keys", "Data.lua", 'if type(p) ~= "table" or type(name) ~= "string" then', 'if type(p) ~= "table" then', "damaged partner keys"),
 ("snapshot fields", "Data.lua", "          if not Finite(snap[f]) then run[k] = nil break end", "", "damaged partner keys"),
 ("lite boss ids", "Data.lua", '    NumOrNil(b, { "id", "st" })\n  end\n  for _, k in ipairs({ "elapsed", "coin", "loot", "lootAH", "xp", "nd"', '  end\n  for _, k in ipairs({ "elapsed", "coin", "loot", "lootAH", "xp", "nd"', "damaged partner keys"),
 ("group change hint", "Run.lua", "if grouped ~= run.leftGrouped then run.groupChanged = true end", "", "group changed"),
 ("redo on a known name", "Track.lua", "  if not ((other and other ~= b) or CopyKill(run, boss)) then", "  if true then", "usual checks"),
 ("end event redo", "Track.lua", "          NameOrRedo(k, id, name)\n        elseif", "          k.id, k.name, k.anonymous = id or k.id, name, nil\n        elseif", "end event"),
 ("key path redo", "Track.lua", "          return NameOrRedo(b, id, name, source, key, theirEntry, theirManual, theirKillAt)", "          NameKill(b, id, name) return b", "second message"),
 ("no pairing while redoing", "Track.lua", "      local other = not redoing and Unpaired(run, manual)", "      local other = Unpaired(run, manual)", "doesn't pair"),
 ("named mark vs other boss", "Track.lua", "      and (last.anonymous or not name or ns.NameSimilar(name, last.name)) then", "      then", "two kills"),
 ("mirror clear time", "Data.lua", "mirror.clearedAt > db.clearedAt and mirror.clearedAt <= latest then", "mirror.clearedAt > db.clearedAt then", "damaged backup"),
 ("own clear time", "Data.lua", "  if db.clearedAt > latest then db.clearedAt = 0 end", "", "damaged backup"),
 ("mirror next id", "Data.lua", "  if Finite(mirror.nextId) and mirror.nextId > db.nextId", "  if type(mirror.nextId) == \"number\" and mirror.nextId > db.nextId", "damaged backup"),
 ("redo keeps time", "Track.lua", "    boss.t, boss.st, boss.v, boss.out, boss.untimed = redo.t, redo.st, redo.v, redo.out, redo.untimed", "", "stays yours"),
 ("redo keeps place", "Track.lua", "    table.insert(run.bosses, redo.at, boss)  -- (and its place)", "    run.bosses[#run.bosses + 1] = boss", "doesn't pair"),
 ("redo keeps tag", "Track.lua", "    if redoing and redoing.key then", "    if false then", "keeps its tag"),
 ("merged name sent", "Track.lua", "  if mine and b.key and not (new and added.key == b.key) and ns.SyncBoss then", "  if false then", "keeps its tag"),
 ("end names a mark", "Track.lua", "          if k.manual then k.manual, k.src, k.byHand = nil, nil, nil end", "", "fight's end names"),
 ("own stays own", "Track.lua", "  if mine then\n    ok, added, same, why = pcall(ns.AddBoss, id, name, b.manual and \"manual\" or nil)", "  if false then\n    ok, added, same, why = pcall(ns.AddBoss, id, name, b.manual and \"manual\" or nil)", "stays yours"),
 ("hidden kill after a fight began", "Track.lua", "    if since <= 10 and not (enc and enc.at and lastKill.at < enc.at) then return nil, last end", "    if since <= 10 then return nil, last end", "two hidden kills"),
 ("end names another boss", "Track.lua", "          ns.AddBoss(id, name)\n        end\n      else", "        end\n      else", "two hidden kills"),
 ("his mark the game named", "Track.lua", "          if b.src == \"sync\" and b.byHand and not theirManual then b.byHand = nil end", "", "isn't shown as by hand"),
 ("final stats of a dropped run", "Sync.lua", 'ns.Listen("RUN_END", function(run) ns.SyncStats(run) end)', 'ns.Listen("RUN_END", function(run, kept) if kept then ns.SyncStats(run) end end)', "counted once"),
 ("renumber after a move", "Run.lua", "    ns.RenumberUnnamed(to)  -- (what", "    -- (what", "numbered in order"),
]
suite = sys.argv[1] if len(sys.argv) > 1 else 'tests_il1.lua'
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
        if not any(group in open(os.path.join(HERE, f)).read() for f in ('tests_il1.lua', 'tests_il1_duo.lua')):
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
