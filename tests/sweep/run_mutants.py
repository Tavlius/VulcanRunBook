#!/usr/bin/env python3
"""Runs every mutant in mutants.json against all tests*.lua suites (fail fast).
Results appended to results.jsonl (resumable)."""
import json, os, shutil, subprocess, sys, time
IGNORE = shutil.ignore_patterns('tests', 'audits', 'ci', '.git', '.github', '.release', 'media-src')  # copy only the add-on
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
TESTS = os.path.join(HERE, '..')
ORIG = os.environ.get('SWEEP_SRC') or os.path.join(HERE, '..', '..')
WORK = '/tmp/runbook_sweep_work'
# fast suites first; tests_round2 (8 s) last
SUITES = sorted([f for f in os.listdir(TESTS) if f.startswith('tests') and f.endswith('.lua')],
                key=lambda f: (f == 'tests_round2.lua', f))
SUITE_TIMEOUT = 60


def run_one(m):
    d = os.path.join(WORK, 'm%d' % m['id'])
    shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(ORIG, d, ignore=IGNORE)
    p = os.path.join(d, m['file'])
    L = open(p).read().split('\n')
    L[m['line'] - 1] = m['_new']
    open(p, 'w').write('\n'.join(L))
    env = dict(os.environ, RL_DIR=d + '/')
    res = {'id': m['id'], 'status': 'survived', 'killer': None, 'detail': ''}
    t0 = time.time()
    for s in SUITES:
        try:
            r = subprocess.run(['lua5.1', s], cwd=TESTS, env=env, capture_output=True, text=True,
                               timeout=SUITE_TIMEOUT)
        except subprocess.TimeoutExpired:
            res.update(status='timeout', killer=s)
            break
        if r.returncode != 0:
            out = (r.stdout + r.stderr)
            fails = [l for l in out.split('\n') if 'FAIL' in l or 'error' in l.lower()]
            res.update(status='killed', killer=s, detail=(fails[0] if fails else out[-200:])[:200])
            break
    res['secs'] = round(time.time() - t0, 1)
    shutil.rmtree(d, ignore_errors=True)
    return res


def main():
    muts = json.load(open(os.path.join(HERE, sys.argv[1] if len(sys.argv) > 1 else 'mutants.json')))
    outp = os.path.join(HERE, sys.argv[2] if len(sys.argv) > 2 else 'results.jsonl')
    done = set()
    if os.path.exists(outp):
        for l in open(outp):
            done.add(json.loads(l)['id'])
    todo = [m for m in muts if m['id'] not in done]
    os.makedirs(WORK, exist_ok=True)
    with ProcessPoolExecutor(max_workers=int(os.environ.get('J', '2'))) as ex, open(outp, 'a') as f:
        for i, r in enumerate(ex.map(run_one, todo)):
            f.write(json.dumps(r) + '\n'); f.flush()
            if i % 20 == 0:
                print(i, len(todo), r, flush=True)


if __name__ == '__main__':
    main()
