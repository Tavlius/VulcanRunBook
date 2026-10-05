# IL2 audit cycle 7 (fresh agent, recorded before fixes)
Scope: README, TOC, audit notes, all nine Lua files; harness/duo, cycle-5/6 tests; run.sh green;
fuzz2 600-650; fuzz_duo DELAY 1 300-312 x3; scenarios s1-s4; new fuzzers: one-client SM wings
(200 x 400, clean), two-client SM with ghosts/revives/resets/wings (~300 seeds at DELAY 0-2: only
finding 1), hostile messages (80 x 400 + views + save/reload, clean). Commands by reading only.
Not reached: real client (addon messages vs PLAYER_ENTERING_WORLD order, ghost revive into another
wing, SM map IDs, throttle), one shared clock, run-time oracle for wing fuzzers.
Counts: critical 0, major 0, minor 2 (both confirmed; #2 hand edit only).
1. minor Sync.lua TargetRun + Run.lua wing check/SplitAtResume - your partner's kill/drop/note
   from the wing you just left, arriving in the seconds before your wing check, is recorded in
   this visit and moved to the new wing's run (Cathedral loses Whitemane and her drop).
2. minor (hand edit) Run.lua:309-325 TakeCopy hands saved copy kills to run.copyKills unchecked:
   a numeric name -> Lua error on every kill until the next login.

## Fixes (after the record above)
- 1: partner kills, drops and notes keep the wing their message names (item.wing); a wing split
  doesn't move others' things from another wing.
- 2: TakeCopy runs the saved copy kills through ns.FixItems.
- Tests: duo group (SM Cathedral -> Library with his kill, drop and note), damaged copy kill;
  5 mutations. run.sh green.

## IL2 status
Seven sequential audit cycles after the improvement step; no clean cycle. All findings minor
(3, 3+2 borderline, 4, 4, 3, 2, 2). Stopped at the same cap as IL1: not converging; every
finding fixed, tested and mutation-proved. Moving to improvement loop 3.
