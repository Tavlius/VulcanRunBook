#!/usr/bin/env python3
"""Mechanical mutant generator for the RunBook addon (Lua 5.1).

Operators (applied only to code outside string literals and comments):
  IFNEG   if/elseif COND then      -> if not (COND) then
  IFTRUE  if/elseif COND then      -> if true then
  IFFALSE if/elseif COND then      -> if false then
  ANDOR   one `and` <-> `or`
  REL     one of < <= > >= == ~=   -> boundary/negated neighbour
  NUM     one numeric literal n    -> n+1 / n-1 / n*2 / 0
  RETDEL  `return ...` -> removed (whole line, or the return inside a one-line if)
  ASSDEL  a one-line non-local assignment statement -> removed
Every mutant is syntax-checked with luac5.1 -p; invalid ones are discarded.
Writes mutants.json: [{id,file,line,func,op,orig,mut}]
"""
import json, os, random, re, subprocess, sys, tempfile

SRC = os.environ.get('SWEEP_SRC') or os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
FILES = ['Util.lua', 'Data.lua', 'Run.lua', 'Track.lua', 'Sync.lua', 'UI.lua', 'History.lua', 'Export.lua', 'Commands.lua']
WEIGHT = {'Run.lua': 95, 'Track.lua': 95, 'Sync.lua': 80, 'Data.lua': 80, 'Util.lua': 40,
          'Commands.lua': 40, 'History.lua': 30, 'UI.lua': 20, 'Export.lua': 20}
random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 3)


def code_mask(line):
    """True for each char that is code (not in a string literal or comment)."""
    mask = [True] * len(line)
    i, q = 0, None
    while i < len(line):
        ch = line[i]
        if q:
            mask[i] = False
            if ch == '\\':
                if i + 1 < len(line): mask[i + 1] = False
                i += 2; continue
            if ch == q: q = None
        else:
            if ch in '"\'':
                q = ch; mask[i] = False
            elif line.startswith('--', i):
                for j in range(i, len(line)): mask[j] = False
                break
        i += 1
    return mask


def code_spans(line, pattern):
    m = code_mask(line)
    out = []
    for mo in re.finditer(pattern, line):
        if all(m[k] for k in range(mo.start(), mo.end())):
            out.append(mo)
    return out


FUNC_RE = re.compile(r'^\s*(?:local\s+)?function\s+([\w.:]+)|^\s*(?:local\s+)?([\w.:\[\]"]+)\s*=\s*function\b')


def func_of(lines, idx):
    for j in range(idx, -1, -1):
        mo = FUNC_RE.match(lines[j])
        if mo:
            return (mo.group(1) or mo.group(2))
    return '<top>'


def gen_file(fname):
    lines = open(os.path.join(SRC, fname)).read().split('\n')
    muts = []
    for i, line in enumerate(lines):
        code = ''.join(c if ok else ' ' for c, ok in zip(line, code_mask(line)))
        if not code.strip():
            continue
        # if / elseif ... then on one line
        for mo in re.finditer(r'\b(if|elseif)\b(.*?)\bthen\b', code):
            s, e = mo.start(2), mo.end(2)
            cond = line[s:e]
            if not cond.strip(): continue
            for op, rep in (('IFNEG', ' not (' + cond.strip() + ') '), ('IFTRUE', ' true '), ('IFFALSE', ' false ')):
                muts.append((op, i, line[:s] + rep + line[e:]))
        for mo in code_spans(line, r'\band\b|\bor\b'):
            rep = 'or' if mo.group(0) == 'and' else 'and'
            muts.append(('ANDOR', i, line[:mo.start()] + rep + line[mo.end():]))
        for mo in code_spans(line, r'<=|>=|==|~=|(?<![<>=~-])<(?![=<])|(?<![-<>=~])>(?![=>])'):
            t = mo.group(0)
            reps = {'<': ['<='], '<=': ['<'], '>': ['>='], '>=': ['>'], '==': ['~='], '~=': ['==']}[t]
            for r in reps:
                muts.append(('REL', i, line[:mo.start()] + r + line[mo.end():]))
        for mo in code_spans(line, r'(?<![\w.])\d+(?:\.\d+)?(?![\w.])'):
            t = mo.group(0)
            v = float(t)
            cands = set()
            for nv in (v + 1, v - 1, v * 2, 0):
                if nv != v and nv >= 0:
                    cands.add(nv)
            for nv in cands:
                s = str(int(nv)) if nv == int(nv) else str(nv)
                muts.append(('NUM', i, line[:mo.start()] + s + line[mo.end():]))
        st = code.strip()
        if re.match(r'^return\b', st) and not re.search(r'\bfunction\b', st):
            muts.append(('RETDEL', i, ''))
        for mo in code_spans(line, r'\bthen\s+return\b[^\n]*?\bend\b'):
            # if X then return [vals] end  ->  if X then end
            muts.append(('RETDEL', i, line[:mo.start()] + 'then ' + line[mo.end() - 3:]))
        if (re.match(r'^[\w.\[\]"\':]+(\s*,\s*[\w.\[\]"\']+)*\s*=[^=]', st) and not st.startswith('local')
                and not re.search(r'\bfunction\b', st) and st.count('(') == st.count(')')
                and st.count('{') == st.count('}') and not st.endswith((',', '(', '{', 'and', 'or', '..'))):
            muts.append(('ASSDEL', i, ''))
    out = []
    for op, i, newline in muts:
        out.append({'file': fname, 'line': i + 1, 'func': func_of(lines, i), 'op': op,
                    'orig': lines[i].strip(), 'mut': newline.strip(), '_new': newline})
    return lines, out


def valid(lines, m):
    L = list(lines)
    L[m['line'] - 1] = m['_new']
    with tempfile.NamedTemporaryFile('w', suffix='.lua', delete=False) as f:
        f.write('\n'.join(L)); p = f.name
    ok = subprocess.run(['luac5.1', '-p', p], capture_output=True).returncode == 0
    os.unlink(p)
    return ok


def main():
    total = int(sys.argv[2]) if len(sys.argv) > 2 else 600
    wsum = sum(WEIGHT.values())
    allm, space = [], {}
    for f in FILES:
        lines, ms = gen_file(f)
        space[f] = len(ms)
        # spread across functions: round-robin sample by function, one op per line first
        quota = max(10, round(total * WEIGHT[f] / wsum))
        byfunc = {}
        for m in ms:
            byfunc.setdefault(m['func'], []).append(m)
        for v in byfunc.values(): random.shuffle(v)
        picked, seenline = [], set()
        funcs = list(byfunc)
        random.shuffle(funcs)
        while len(picked) < quota and any(byfunc.values()):
            for fn in funcs:
                if not byfunc[fn] or len(picked) >= quota: continue
                m = byfunc[fn].pop()
                if not valid(lines, m): continue
                picked.append(m)
        allm.extend(picked)
    for k, m in enumerate(allm):
        m['id'] = k
    json.dump(allm, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mutants.json'), 'w'), indent=1)
    print('space per file (pre-validity):', space, 'sum', sum(space.values()))
    print('sampled', len(allm))
    from collections import Counter
    print(Counter(m['file'] for m in allm))
    print(Counter(m['op'] for m in allm))


if __name__ == '__main__':
    main()
