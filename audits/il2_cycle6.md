# IL2 audit cycle 6 (fresh agent, recorded before fixes)
Scope: README, TOC, Bindings, all nine Lua files (focus Run/Track), Sync, Data, il2 notes,
harnesses, cycle-5 tests; run.sh green; fuzz/fuzz2 500-560; fuzz_duo DELAY 1 200-215 x3; a new
clock/ghost/timeout fuzzer (200 seeds x 300 steps, exact run time) - no defects; scenarios.
Not reached: real-client rez/loading timing; whether Forever revives a ghost entering another SM
wing; SM/DM wings, Auctionator, font widths in game; one shared clock for two clients.
Counts: critical 0, major 0, minor 2 (both confirmed).
1. minor Run.lua:756-761/765-767/636-686 - a ghost return into another Scarlet Monastery wing
   splits at the last resume point, not at this entry: the old wing's later kills and clock go
   to the new wing's run ("Armory [Doan] 6:20").
2. minor Commands.lua:332 / Track.lua:632 - /runbook unboss acts on a never-entered run (removes
   your partner's real kill there) instead of your last run (RunOrLast missed here).

## Fixes (after the record above)
- 1: a ghost return into a multi-wing dungeon keeps where this entry began (session only); if
  the wing check finds another wing, the run splits there instead of at the last return.
- 2: /runbook unboss without a number uses ns.RunOrLast().
- Tests: 2 groups (tests_il2 133 checks); 3 mutations. run.sh green.
