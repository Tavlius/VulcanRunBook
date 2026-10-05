#!/usr/bin/env python3
import json, os, collections, sys
HERE = os.path.dirname(os.path.abspath(__file__))
muts = {m['id']: m for m in json.load(open(os.path.join(HERE, 'mutants.json')))}
res = [json.loads(l) for l in open(os.path.join(HERE, 'results.jsonl'))]
st = collections.Counter(r['status'] for r in res)
print('total', len(res), dict(st))
byf = collections.defaultdict(collections.Counter)
byfn = collections.defaultdict(collections.Counter)
byop = collections.defaultdict(collections.Counter)
killer = collections.Counter()
for r in res:
    m = muts[r['id']]
    byf[m['file']][r['status']] += 1
    byfn[(m['file'], m['func'])][r['status']] += 1
    byop[m['op']][r['status']] += 1
    if r['status'] == 'killed': killer[r['killer']] += 1
out = []
out.append('## per file')
for f, c in sorted(byf.items()):
    n = sum(c.values()); out.append('%-13s n=%3d killed=%3d survived=%3d timeout=%d  survival=%.0f%%' % (
        f, n, c['killed'], c['survived'], c['timeout'], 100 * c['survived'] / n))
out.append('## per operator')
for f, c in sorted(byop.items()):
    n = sum(c.values()); out.append('%-8s n=%3d survived=%3d (%.0f%%)' % (f, n, c['survived'], 100 * c['survived'] / n))
out.append('## per function (n>=3 or any survivor), sorted by survivors')
for (f, fn), c in sorted(byfn.items(), key=lambda kv: (-kv[1]['survived'], kv[0])):
    n = sum(c.values())
    if c['survived'] or n >= 3:
        out.append('%-13s %-32s n=%2d survived=%2d' % (f, fn, n, c['survived']))
out.append('## first killer suite')
for k, v in killer.most_common(): out.append('%-22s %d' % (k, v))
out.append('## survivors')
for r in res:
    if r['status'] != 'killed':
        m = muts[r['id']]
        out.append('#%d %s %s:%d [%s] %s\n    - %s\n    + %s' % (r['id'], r['status'], m['file'], m['line'], m['func'],
                                                          m['op'], m['orig'], m['mut']))
open(os.path.join(HERE, 'summary.txt'), 'w').write('\n'.join(out) + '\n')
print('\n'.join(out[:60]))
