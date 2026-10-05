# IL3 audit cycle 6 (fresh agent, recorded before fixes)
Scope: README, TOC, il3 plan/cycles 1-5; Run, History, Export, Sync, Track 150-1428, Data 1-760 +
stats/cap, Commands 1-560, UI 1-240, Util 1-310 in full; run.sh green; fuzz_duo 101-106 x3, fuzz2
501-508, fuzz_copy 1-6 with unseen resets; probes p1-p3. Not reached: real client (delivery during
loading screens, logout, throttle; whether Forever allows a reset with a corpse inside), font widths.
Counts: critical 0, major 0, minor 1 (confirmed; partly a regression from cycle 5).
1. minor Run.lua:767-773 (+ Run:936, Track:181-184/529-530/372, Sync:610) - a ghost return never
   makes a split point; on a first visit there is none at all. A reset while you were dead outside is
   never found after you zone in: the repeat kill is dropped as "the same kill again" (also with an
   earlier alive trip, if the kill came after it); a partner's late reset message doesn't split.

## Fixes (after the audit was recorded)

1. A ghost return now makes its own split point (`run.ghostSnap`, set when you zone back in dead; cleared by a return alive, a new snapshot and Finish).
   - `ns.SplitPointFor(run, st)` picks the last alive return after the first death, else the ghost return after it.
   - `ns.LastReturn(run)` picks the later of the two, for late reset messages.
   - Used in: your own repeat kill (Track), his repeat kill (Track), his P split (Sync), late R message (Run). Saved snapshot validation includes `ghostSnap` (Data).
2. Tests (tests_il3.lua, "Audit cycle 6"): first visit and after an earlier trip; a ghost return into the same copy does not split; his late R message after a ghost return splits on the message alone; his B repeat kill and his P split after a ghost return.
3. Mutations (mutate_il3.py): 5 new entries, all caught (ghostSnap set, own ghostAt, late-reset LastReturn, his ghostAt, P handler ghostSnap).
   - Not mutated: `run.ghostSnap = nil` in Snapshot. Removing it is an equivalent mutant: every reader prefers the later alive return (`resumeSnap` is checked first, and kills in the current visit come after both). Kept as housekeeping.
