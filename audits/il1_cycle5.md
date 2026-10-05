# IL1 audit cycle 5 (fresh agent, recorded before fixes)

Scope: all addon files and README read in full; run.sh plus extra fuzz seeds (fuzz2 200-240,
fuzz_duo/fuzz_copy/fuzz_cap/fuzz_unread/fuzz_gold/fuzz_drops/fuzz_notes 20-40), a new
saved-file damage fuzzer (~2,100 cases), scenario scripts t1-t8. Not reached: real client
(partly unreadable encounter events), real two-client timing.

Counts: critical 0, major 0, minor 5 (all confirmed).

1. minor Track.lua:637-643 - ENCOUNTER_END naming an anonymous kill sets id/name directly,
   skipping NameKill/AfterNaming/FindBoss: a reset nobody saw isn't split; the "died here
   before" check doesn't run.
2. minor Track.lua:263-279 - partner names a kill in a second message; when the run already
   has that boss the code returns without the checks a named message gets: duplicate
   "Boss 2" (hand marks), or no PartnerFoundReset while outside.
3. minor Track.lua:231-244 - AfterNaming ignores theirManual and the 120 s check that the
   direct path uses; key-then-name hand mark adds a copy, direct name doesn't.
4. minor Track.lua:422-428 - named hand mark overwritten when the game reports a different
   boss within 10 s (Sneed then Sneed's Shredder -> Sneed lost).
5. minor Data.lua:419/482 - mirror.clearedAt / mirror.nextId not checked with Finite;
   1e300 empties the history permanently; inf nextId gives "#inf".

## Fixes (after the record above)
- 1, 2, 3: new NameOrRedo (Track.lua). An unnamed kill that gets a name already in the run,
  or one that died in this copy before the run, is taken out and recorded again with the full
  message (partner: tag, entry, kill time, hand flag), so it gets the same checks as a kill
  named from the start; it keeps its place and time when it stays in the same run. Used by
  ENCOUNTER_END and by the partner's naming message. The re-record never pairs with another
  recent kill.
- 4: the game's kill only takes over a hand mark within 10 s when the mark is unnamed or the
  names are similar. README sentence updated.
- 5: backup clearedAt must be finite and not later than now + 1 day (own clearedAt too);
  backup nextId must be finite.
- Tests: tests_il1.lua cycle 5 groups (180 checks); 10 new mutations in mutate_il1.py, all caught.
