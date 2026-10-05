# IL1 audit cycle 6 (fresh agent, recorded before fixes)

Scope: README, Track.lua, Sync.lua, Run.lua, Commands.lua in full; Data.lua load/merge and
name matching; run.sh; extra seeds for fuzz2/fuzz_duo/fuzz_copy/fuzz_unread; new fuzz variants
with fights named only at their end (fuzz_duo_late, fuzz_copy_late, fuzz2_late); scenario
scripts s1-s6. Not reached: real client field hiding, real two-client timing, History/UI/Export
beyond boss events.

Counts: critical 0, major 0, minor 3 (all confirmed). All in the cycle 5 re-record.

1. minor (regression) Track.lua:271-283 - the re-record gets a new key and is sent under it;
   the partner keeps the old unnamed copy and adds the named one: a duplicate kill in the
   partner's log (fuzz_duo_late seeds 8, 14, 25, 27 of 1-40 one kill high).
2. minor Track.lua:676-682 - a hand mark named by ENCOUNTER_END stays "marked by hand" and is
   sent with !m (the readable path makes it the game's kill).
3. minor Track.lua:272 - your own unnamed kill named by your partner's message is re-recorded
   as the partner's kill (src=sync, "(from your partner)", wrong split time).

## Fixes (after the record above)
- 1: the re-record keeps the kill's tag (AddBoss takes it from `redoing`), so the named
  message goes out under the tag the unnamed one used; when the re-record merges into a kill
  you already have, the name is still sent under the old tag so your partner's copy merges too.
  Its time and place are now set inside AddBoss (before the message is sent).
- 2: ENCOUNTER_END naming a hand mark makes it the game's kill (as the readable path does).
- 3: NameOrRedo re-records your own kill as yours (hand mark stays a hand mark), with your
  partner's tag kept as its peer.
- The auditor's fuzz_duo_late, fuzz_copy_late and fuzz2_late adopted into tests/ and run.sh
  (120/120 duo-late runs ok over seeds 1-40, copy-late 1-40, fuzz2-late 1-60).
- tests_il1.lua: 194 checks; mutate_il1.py: 6 new or updated mutations, all caught.
