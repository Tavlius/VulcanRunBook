# IL3 audit cycle 3 (fresh agent, recorded before fixes)
Scope: README, TOC, AUDIT_REPORT tail, il3 plan/audits/cycles 1-2, il2_cycle7, all nine Lua files;
run.sh green; fuzz_duo 20-34 x3, fuzz 200-260, fuzz2 SMALLCAP 200-260, fuzz_copy 10-22 x3,
fuzz_duo_late 30-35 x4; a fuzz variant deleting short-form runs (30 seeds), a hostile message
fuzzer (40 seeds), reload-while-blocked probe; gold/drops/notes at DELAY 2/4 (known limit only).
Not reached: real client (logout delivery, throttle, loading screens, save/load), account-load bug,
rollback, font widths.
Counts: critical 0, major 0, minor 1 (confirmed, low likelihood).
1. minor Run.lua:438-456 - a run Archive "dropped" (past the cap) still prints "New best clear".

## Fixes (after the record above)
- 1: Finish skips "New best clear" when Archive dropped the run. Test (the too-old group now has a
  fast clear and checks no new-best line) and mutation. run.sh green.
