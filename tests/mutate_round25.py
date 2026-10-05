import shutil, subprocess, os, sys
IGNORE = shutil.ignore_patterns('tests', 'audits', 'ci', '.git', '.github', '.release', 'media-src')  # copy only the add-on
SRC=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
HERE = os.path.dirname(os.path.abspath(__file__))
TMP = '/tmp/runbook_mut25'
muts = [
 ("PartnerFoundReset moves items", "Run.lua",
  "    if theirStart then MoveFrom(old[k], moved[k], math.huge, math.huge, theirStart) end",
  "    if false then end",
  "he finds the reset while you're outside"),
 ("late move from P", "Sync.lua",
  "    local n = ns.MoveSince(prev, run, start)",
  "    local n = 0",
  "he was in the new copy before you"),
 ("never-entered run not kept", "Run.lua",
  "  if run.entryOnEntry then return false end\n",
  "",
  "a run for his new copy that you never go into"),
 ("ghost carried", "Run.lua",
  "  if ghost then run.leftAt, run.leftServer, run.ghost = leftAt, leftServer, ghost end",
  "",
  "still running back"),
 ("map ID filled at save", "Run.lua",
  "        if not run.mapID then run.mapID, run.map = r.mapID, r.map end",
  "",
  "map ID was never readable"),
 ("newer short copy wins", "Data.lua",
  "          local stale = newer and newer[uid] and (tonumber(run.modified) or 0) < newer[uid]",
  "          local stale = false",
  "newer short copy wins"),
 ("note spacing", "History.lua",
  "      for _, l in ipairs(Wrap(n.who .. \": \" .. n.text, 90, \"      \", head)) do add(l) end",
  "      for _, l in ipairs(Wrap(head .. n.who .. \": \" .. n.text, 90, \"      \")) do add(l) end",
  "note lines keep their spacing"),
]
suite = sys.argv[1]
ok = True
# The unmutated suite must be green first (a red baseline would 'catch' every mutation).
shutil.rmtree(TMP, ignore_errors=True); shutil.copytree(SRC, TMP, ignore=IGNORE)
base = subprocess.run(['lua5.1', suite], cwd=HERE, env=dict(os.environ, RL_DIR=TMP + '/'), capture_output=True, text=True)
if base.returncode != 0 or 'FAIL [' in base.stdout:
    print('BASELINE NOT GREEN'); print(base.stdout[-2000:]); sys.exit(1)
for name, f, a, b, group in muts:
    d = '/tmp/runbook_mut25'
    shutil.rmtree(d, ignore_errors=True); shutil.copytree(SRC, d, ignore=IGNORE)
    p = os.path.join(d, f); s = open(p).read()
    if a not in s: print("MISSING SNIPPET:", name); ok=False; continue
    open(p,'w').write(s.replace(a, b, 1))
    try:
        r = subprocess.run(['lua5.1', suite], cwd=HERE, env=dict(os.environ, RL_DIR=d + '/'), capture_output=True,
                           text=True, timeout=120)
        out = r.stdout + r.stderr
        red = any(('FAIL [' in l and group in l) for l in out.splitlines())
    except subprocess.TimeoutExpired:
        red = True  # (it hangs: caught)
    print(("RED  " if red else "GREEN"), name)
    ok = ok and red
print("all mutations caught" if ok else "SOME MUTATION SURVIVED")
