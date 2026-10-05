# IL2 audit cycle 5 (fresh agent, recorded before fixes)
Scope: README, TOC, Bindings, all nine Lua files; il2 plan/cycles 1-4, il1 notes; harness, duo,
fuzz_duo, tests_il2 cycle-4 groups; run.sh green; scenarios s1-s4; a command/message fuzzer
(100 seeds x 300 steps, views each step); a fuzz_duo variant reviving outside (30+30+40 seeds).
Not reached: real client (delivery during loading screens, throttle, revives/resets in Forever),
SM/DM wings, Auctionator, font widths, one shared clock for two clients.
Counts: critical 0, major 0, minor 3 (all confirmed).
1. minor Track.lua:572-575 + Run.lua:755-761 - leaving dead sets run.ghost; coming back in is
   treated as a ghost run back (no new resume point) even after a graveyard revive or past the
   10-minute limit, so `back` is the earlier return: his kill while you were out is timed ->
   false new best. (Opposite case: a ghost-run kill can come out untimed.)
2. minor same root cause via ThisVisit/duplicate check - after a graveyard revive, a reset
   neither log saw is never found (repeat kills dropped as "the same kill again").
3. minor Run.lua:458-459 - /runbook end on a run you never entered says "too short to save".

## Fixes (after the record above)
- 1, 2: outside, a run's ghost flag clears when you're alive again (revived at the graveyard,
  not zoning) or the ghost run passes GHOST_MAX; coming back in is then a return like any
  other (new resume point: kills meanwhile untimed, a repeat kill shows the reset).
- 3: /runbook end on a never-entered run: "you never went in, so it isn't saved".
- Tests: 3 groups (tests_il2 126 checks); 3 mutations. run.sh green.
