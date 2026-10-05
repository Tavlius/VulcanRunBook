# Proves each improvement-loop-2 guard is tested: undo it, the named test must fail.
import shutil, subprocess, os, sys
IGNORE = shutil.ignore_patterns('tests', 'audits', 'ci', '.git', '.github', '.release', 'media-src')  # copy only the add-on
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..')
TMP = '/tmp/runbook_mut2'
muts = [
 ("late run not timed", "Data.lua", "      local away = ns.LateRun(r)", "      local away = false", "after a break"),
 ("late run: TimedClear", "Data.lua", "  if not final or ns.LateRun(run) then return nil end", "  if not final then return nil end", "after a break"),
 ("late kept in short form", "Data.lua", " late = ns.LateRun(run) or nil,", "", "after a break"),
 ("new best only for timed", "Run.lua", "    local clear = ns.TimedClear(run)", "    local clear = ns.ClearTime(run)", "after a break"),
 ("report: only a timed clear is a new best", "Export.lua", "    if prevT and clear < prevT and ns.TimedClear(run) then", "    if prevT and clear < prevT then", "report doesn't call"),
 ("retry 5 and 9", "Sync.lua", "local RETRY_A_WHILE = { [5] = true, [9] = true }", "local RETRY_A_WHILE = {}", "5 and 9"),
 ("kill from before your run", "Sync.lua", "  if at and ns.CopyBegan(run) and at < ns.CopyBegan(run) - 1 then return end", "", "before your run began"),
 ("drop from before your run", "Sync.lua", "  elseif run == ns.run and f[4] and ns.CopyBegan(run) and f[4] < ns.CopyBegan(run) - 1 then", "  elseif false then", "before your run began"),
 ("earlier drop routed", "Sync.lua", "  local earlier = run == ns.run and EarlierRun(run, f[4])", "  local earlier = false", "before your run began"),
 ("earlier: only before the start", "Sync.lua", "  if not (run and t and ns.CopyBegan(run) and t < ns.CopyBegan(run) - 1) then return nil end", "  if not (run and t and ns.CopyBegan(run)) then return nil end", "before your run began"),
 ("no endless retry", "Track.lua", "    local again = not retried and known and sync", "    local again = known and sync", "can't loop"),
 ("ended before theirs began", "Sync.lua", "local endedBefore = r.serverEnd and start > r.serverEnd + 5", "local endedBefore = false", "ended before theirs began"),
 ("no bag scans outside", "Track.lua", "  if not ns.InRun() then bagCounts = nil return end", "", "no bag scans"),
 ("gold adds up", "Util.lua", "  if copper >= 100 then return math.floor(copper / 100 + 0.5) * 100 end", "", "adds up"),
 ("copper in a gold total", "Util.lua", "(v % 100 ~= 0 and (\" \" .. (v % 100) .. (colored and \"|cffeda55fc|r\" or \"c\")) or \"\")", "\"\"", "adds up"),
 ("exact under a gold", "Util.lua", "  if v >= 100 and v % 100 ~= 0 then return ns.Money(v, colored) end", "", "adds up"),
 ("details to the silver", "History.lua", "  local mine, coin = ns.ShownMoney(ns.RunGold(run)), ns.ShownMoney(run.coin or 0)", "  local mine, coin = ns.RunGold(run), run.coin or 0", "as the live window does"),
 ("end line to the silver", "Run.lua", "  local gold = ns.ShownMoney(ns.RunGold(run))", "  local gold = ns.RunGold(run)", "as the live window does"),
 ("check: ended run", "Commands.lua", "      if k.final then", "      if false then", "ended or old run"),
 ("check: old numbers", "Commands.lua", "      elseif GetTime() - k.at > 90 or", "      elseif", "ended or old run"),
 ("copies list checked", "Run.lua", "  -- it, so not a new instance.\n  for _, c in ipairs(Copies()) do", "  -- it, so not a new instance.\n  for _, c in ipairs(VulcanRunBookCharDB.copies or {}) do", "damaged list of copies"),
 ("copy began earlier", "Sync.lua", "  return math.min(run.serverStart, tonumber(run.copyFrom) or math.huge)", "  return run.serverStart", "after his split message"),
 ("split run's copy start", "Run.lua", "  if since and since < s.server then new.copyFrom = since end", "", "after his split message"),
 ("pre-entry kill untimed", "Track.lua", "  if sync and theirKillAt and back and theirKillAt < back - 1 then", "  if false then", "after his split message"),
 ("pairing kept on the kill", "Track.lua", "    if age and age <= ns.SYNC_MATCH_SECONDS and not paired[b] and not b.matched", "    if age and age <= ns.SYNC_MATCH_SECONDS and not paired[b]", "reload just after"),
 ("pairing age after reload", "Track.lua", "      or (type(b.st) == \"number\" and ns.ServerTime() - b.st) or nil", "      or nil", "reload just after"),
 ("retried keeps the kill time", "Track.lua", "        return ns.AddBoss(id, name, source, key, nil, nil, theirKillAt, true)", "        return ns.AddBoss(id, name, source, key, nil, nil, nil, true)", "inside split, has no time"),
 ("rows rounded", "History.lua", "  local gold = ns.ShownMoney(ns.RunGold(run))  -- (rounded as everywhere else)", "  local gold = ns.RunGold(run)", "Last line round gold"),
 ("last line rounded", "UI.lua", "      local gold = ns.ShownMoney(ns.RunGold(last))  -- (rounded as everywhere else)", "      local gold = ns.RunGold(last)", "Last line round gold"),
 ("coin in the total's unit", "History.lua", "  if mine >= 100 then coin = math.floor((run.coin or 0) / 100 + 0.5) * 100 end", "", "coin and loot split"),
 ("only theirs by time", "Run.lua", "item.st >= since and Theirs(item))\n", "item.st >= since)\n", "note you write outside"),
 ("out by kill time", "Track.lua", "  local back = run.resumeSnap and run.resumeSnap.server or run.serverStart", "  local back = run.serverStart", "even if it arrives after"),
 ("note to your last run", "Track.lua", "  run = run or ns.RunOrLast()", "  run = run or ns.run or ns.LastOwnRun()", "for your last run"),
 ("report on your last run", "Export.lua", "  run = run or ns.RunOrLast()", "  run = run or ns.run or ns.LastOwnRun()", "for your last run"),
 ("greens sent anyway", "Track.lua", "    if type(q) == \"number\" and q >= 2 then ns.SyncDrop(run,", "    if false then ns.SyncDrop(run,", "greens go to your partner"),
 ("manualEnded checked", "Data.lua", "  char.manualEnded = type(char.manualEnded) == \"table\" and ns.FixRun(char.manualEnded) or nil", "  if type(char.manualEnded) ~= \"table\" then char.manualEnded = nil end", "copy of the run you ended"),
 ("revived outside", "Run.lua", "      and ((not IsDead() and not ns.Zoning()) or time() - (run.leftAt or 0) > ns.GHOST_MAX) then", "      and (time() - (run.leftAt or 0) > ns.GHOST_MAX) then", "revived at the graveyard"),
 ("ghost past the limit", "Run.lua", "      and ((not IsDead() and not ns.Zoning()) or time() - (run.leftAt or 0) > ns.GHOST_MAX) then", "      and ((not IsDead() and not ns.Zoning())) then", "long ghost run"),
 ("never went in text", "Run.lua", "    ns.Print(run.label .. (run.entryOnEntry and", "    ns.Print(run.label .. (false and", "never went into says why"),
 ("ghost wing split at entry", "Run.lua", "  if entry and entry.run == run then run.resumeSnap = entry.snap end", "", "ghost into another wing"),
 ("ghost entry kept", "Run.lua", "      ghostEntry = inst.multiWing and { run = run, snap = Snap(run) } or nil", "      ghostEntry = nil", "ghost into another wing"),
 ("unboss not the unentered run", "Track.lua", "    run = ns.RunOrLast()  -- (not a run you haven't gone into yet)", "    run = ns.run or ns.LastOwnRun()", "unboss on a run you haven't"),
 ("wing split keeps others' wing items", "Run.lua", "    if move and wing and type(item.wing) == \"string\" and item.wing ~= wing then move = false end", "", "wing you just left"),
 ("kill tagged with its wing", "Sync.lua", "  if b and b.src == \"sync\" and wing then b.wing = wing end", "", "wing you just left"),
 ("drop tagged with its wing", "Sync.lua", "  if d and isNew and wing then d.wing = wing end", "", "wing you just left"),
 ("note tagged with its wing", "Sync.lua", "    if note and wing then note.wing = wing end", "", "wing you just left"),
 ("copy kills checked", "Run.lua", "          ns.FixItems(c.kills)  -- (checked like a saved run's)", "", "damaged kill in the saved copies"),
 ("no drift outside", "UI.lua", "local since = (ns.inside and heard > 0)", "local since = (heard > 0)", "drift"),
 ("not with yourself", "History.lua", "if ns.IsRunDuo(run, m) and m ~= me then", "if ns.IsRunDuo(run, m) then", "with yourself"),
 ("report party check", "Commands.lua", 'elseif chatType == "PARTY" and not (IsInGroup and IsInGroup()) then', "elseif false then", "report to party"),
 ("report raid check", "Commands.lua", 'elseif chatType == "RAID" and not (IsInRaid and IsInRaid()) then', "elseif false then", "report to party"),
 ("lowercase capitalised", "Commands.lua", 'if name and name == name:lower() and name:find("%l") then', "if false then", "lowercase"),
 ("delete asks", "Commands.lua", "  if yes == 0 and not asked then", "  if false then", "delete asks first"),
 ("delete ask expires", "Commands.lua", "deleteAsked.id == id and GetTime() - deleteAsked.at <= 15", "deleteAsked.id == id", "delete asks first"),
 ("csv formulas", "Export.lua", "  if v:find(\"^[=+@\\t\\r]\") or (v:find(\"^%-\") and not v:find(\"^%-%d+%.?%d*$\")) then v = \"'\" .. v end", "", "formulas"),
 ("you: nothing", "History.lua", "  if mine == 0 and (run.xp or 0) == 0 then", "  if false then", "zero noise"),
 ("no deaths", "History.lua", 'more[#more + 1] = s.deaths > 0 and string.format("%.1f deaths/run", s.deaths / s.runs) or "no deaths"', 'more[#more + 1] = string.format("%.1f deaths/run", s.deaths / s.runs)', "zero noise"),
 ("bare shows", "Commands.lua", '  elseif (cmd == "auto" or cmd == "sync") and arg == "" then', '  elseif false then', "bare sync and auto"),
 ("late reset window", "Run.lua", "    elseif ns.LastReturn(run) and ns.ServerTime() - ns.LastReturn(run).server <= 120", "    elseif ns.LastReturn(run)", "long after you came back in"),
 ("P adjacency", "Sync.lua", "      and math.abs((prev.serverEnd or 0) - (run.serverStart or 0)) <= 5 and ns.MoveSince then", "      and ns.MoveSince then", "older split run"),
 ("P once", "Sync.lua", "  if after then snap = ns.SplitPointFor(run, after) else snap = ns.LastReturn(run) end", "  snap = ns.LastReturn(run)", "a kill you saw this visit"),
 ("fuller name on a known key", "Track.lua", "        if name and not b.anonymous and Longer(name, b.name) then\n          b.name = name  -- their fuller name for the same kill", "        if false then\n          b.name = name  -- their fuller name for the same kill", "fuller name"),
 ("finals block", "Sync.lua", "      if type(at) ~= \"table\" and run.serverStart and start < run.serverStart and fin and fin.from ~= start", "      if false and fin", "split his earlier run"),
 ("ended grace", "Sync.lua", "    if f[4] > run.serverEnd + 1 or time() - (run.endedAt or 0) > 120 then return end", "    if time() - (run.endedAt or 0) > 120 then return end", "few seconds after it ended"),
 ("renumber new in PFR", "Run.lua", "  ns.RenumberUnnamed(run)\n  -- Their numbers from the new copy", "  -- Their numbers from the new copy", "numbered in order"),
 ("kill count sent", "Sync.lua", "run.ended and 1 or 0, #run.bosses))", "run.ended and 1 or 0, 0))", "agree on kills"),
 ("kill count shown", "Commands.lua", "    if run and k and k.d == run.name then", "    if false then", "agree on kills"),
]
suite = sys.argv[1] if len(sys.argv) > 1 else 'tests_il2.lua'
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
        if not any(group in open(os.path.join(HERE, f)).read() for f in ('tests_il2.lua', 'tests_il2_duo.lua')):
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
