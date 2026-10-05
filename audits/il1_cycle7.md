# IL1 audit cycle 7 (fresh agent, recorded before fixes)

Scope: README, Track, Sync, Run in full; Commands, Data, UI, History/Export boss parts, Util
name matching in part; cycle 5/6 tests and late fuzzers; run.sh; many extra seeds
(fuzz_duo_late 41-400, fuzz_duo 4-300, fuzz_copy_late 41-500, fuzz2_late 41-500, fuzz2
300-360); a new mixed-event two-client fuzzer (seeds 1-400); scenarios s1-s5. Not reached:
real client, raid-size groups, full History/Export/Commands pass, saved-file damage fuzz.

Counts: critical 0, major 0, minor 4 (all confirmed).

1. minor Sync.lua:709 / Run.lua:173-186, 660 - after a split leaves an old part too short to
   keep, its final stats are never sent; the partner's log keeps that part at full value and
   adds the new run too: partner gold counted twice (fuzz_duo_late 67 and 250 events).
2. minor Track.lua:473 + 704-711 - hidden start/kill and named end, two kills < 10 s apart:
   the second hidden kill is taken as the first's other event and its different end name is
   ignored (Sneed's Shredder then Sneed -> only Sneed's Shredder; same after a typed mark).
3. minor Track.lua:255-268 - partner's hand mark later named by his fight's end: his log
   makes it the game's kill and sends the name without !m, but your copy keeps byHand.
4. minor Run.lua:484-505 MoveSince - moved unnamed kills aren't renumbered ("Boss 2, Boss 3,
   Boss 1").
Test gap: run.sh never runs the late-naming mode of fuzz_duo_late / fuzz_copy_late.

## Fixes (after the record above)
- 1: RUN_END always sends the run's final stats (kept or not), so a part a split left empty
  tells the partner's log it ended with nothing. (Two-client test; fuzz_duo_late 67/250 pass.)
- 2: a hidden kill event is "the other event" of the last kill only if that kill came after
  the current fight began (ENCOUNTER_START records `at`). ENCOUNTER_END whose name differs
  from its kill (a hand mark, or a kill from before this fight) adds a second kill.
- 3: the partner's naming message without !m clears byHand on his earlier hand mark.
- 4: ns.RenumberUnnamed after MoveSince (both runs) and in SplitAtResume (both runs).
- run.sh: late-naming mode of fuzz_duo_late / fuzz_copy_late; seed 67; new two-client suite
  tests_il1_duo.lua. mutate_il1.py checks each mutation in the suite holding its group and
  fails if a group is in neither suite. tests_il1.lua 203 checks, all mutations caught.
- Extra sweep (fuzz_gold 1-30, fuzz_duo 4-20 x3, drops/notes 6-20, duo_late 60-120): 172 ok.

## IL1 status
Seven sequential audit cycles; no clean cycle. Majors: cycle 1 (1), cycle 2 (1), then none
in cycles 3-7 (4, 4, 5, 3, 4 minors). Stopped here as not converging (cap reached); every
finding was fixed, tested and mutation-proved. Moving to improvement loop 2.
