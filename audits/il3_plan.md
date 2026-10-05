# Improvement loop 3 — critiques consolidated (step 2) and plan (step 3)

## Critiques and questions (from il3_audit1-3; 35+ raised, the main ones)
1. 39% of 600 sampled mutants survive the suites; History 75%, UI 50%; 32 player-visible
   behaviours have no test. Coverage was never measured before.
2. The fuzzers check that totals agree; they can't see information lost on both sides (a dropped
   boss id, a cut note, a split message never sent).
3. Time windows and constants have no boundary tests.
4. Older code (rounds 1-20) has no regression mutation protection; only recent guards do.
5. A partner kill gets its time from arrival, not from when it died.
6. A short-form run (past the newest 200) can't be deleted, yet can hold the best time.
7. A failed account load at the caps loses 1,500 short-form runs (backup keeps 500) and the
   notice understates it; a second failure is silent.
8. An alt's months-old run in progress goes straight to short form, out of order, unreachable.
9. Same name on two realms counts as one character (and as the partner in sync).
10. Short-form partner gold is frozen at the price setting of the time.
11. Deletions are pruned by run start: a deleted old run can return from a stale backup.
12. The sync queue lives only in memory: /reload, logout or leaving the group loses it.
13. Late drops for an ended run are judged by arrival time, not loot time.
14. Partner boss names are capped at 40 bytes, yours aren't (non-English clients).
15. README: auto-pairing happens on any message in any two-person group, saved account-wide.
16. Dead code: run.entryTimes (written, never read); RunsOf's `except`.
17. Unanswerable here: real throttle and result codes; whether logout sends are delivered;
    delivery during loading screens; whether IsInGroup is false on loading screens; DB_VERSION
    rollback behaviour of an older build; Forever's rename/transfer folder behaviour; whether the
    account-load bug still exists.
18. Design: no acks or resend; the stats message could carry drop/note counts for detection.
19. The 2,000 cap is shared by every dungeon: farming one pushes out a raid's history.

## Plan
Tests
 T1 Tests for the player-visible untested behaviours from audit 1 (the probe-confirmed ones).
 T2 tests/mutation_sweep.py (audit 1's generator and runner, kept as a tool; not in run.sh - an
    hour per 600 mutants), with its last result recorded.
Data
 D1 /runbook delete finds short-form runs too; note/unboss on one say why they can't.
 D2 The backup keeps every short-form run again (a partial backup loses runs in the very failure
    it exists for); the restore notice counts both kinds; it shows on every failed load.
 D3 A run archived straight into short form is inserted in order and the end line says so.
 D4 CharacterCount by name and realm; rows/details show the realm when two share a name.
 D5 Short-form runs keep partner gold at both prices.
 D6 Deletions are kept while the run could still be in a backup (newer than the oldest kept run).
Sync
 S1 The queue is saved at logout and restored at login (10 minutes), and kept for 10 minutes while
    not in a group instead of being wiped.
 S2 A drop for an ended run is taken when it was looted before the run ended (2 minutes).
 S3 A partner set with a realm (or auto-paired from a sender with a realm) only matches that realm.
 S4 /runbook check finds the partner's data by name, any case.
 S5 Partner boss names capped at 100 bytes (what fits a message), as long as yours.
 S6 A partner kill's time is when it died (from the message), not when it arrived.
README
 R1 Auto-pairing wording; the backup's size; short form can be deleted but not changed.
Cleanup
 C1 Remove run.entryTimes and RunsOf's `except`.
Not doing (recorded): acks/resend (S1 covers the commonest losses); per-dungeon minimum in the
2,000 cap; rollback handling (no older build exists to test against).

## Implemented (steps 4-5)
Data: D1 ns.FindAnyRunById (delete reaches short form; note/unboss explain via ns.ShortFormNote;
the Dungeons tab shows the best run's number); D2 full backup again, the notice counts both kinds
and repeats after a good load; D3 Archive inserts short-form runs in order and returns whether the
run itself went there (the end line says so); D4 Characters() by name and realm, ns.CharLabel;
D5 Lite keeps pg and pgAH; D6 PruneDeleted drops a deletion only once the short-form list is full
and the run is older than its oldest (cap 5,000).
Sync: S1 queue saved at PLAYER_LOGOUT and restored at READY (10 minutes), kept out of a group for
10 minutes; S2 ended-run drops by loot time (2 minutes); S3 db.partnerRealm (set by /runbook
partner Name-Realm, from the group, or the first message heard), a same-name player elsewhere is
"another player"; S4 check finds the partner by SameName; S5 partner boss names to 100 bytes;
S6 a partner kill's t from its kill time.
README: partner setup first in Quick start; pairing rule; queue over /reload; full backup;
short-form delete. Cleanup: run.entryTimes and RunsOf's except removed.
Harness: UnitName returns name, realm for another realm (as the real API).
Tests: tests_il3.lua (88 checks: the IL3 changes plus 27 behaviours from the sweep's
probe-confirmed survivors); mutate_il3.py (47 mutations incl. the 27 sweep mutants, all caught);
mutation scripts count a suite crash before the group as caught. tests/sweep/ keeps the sweep
tool (gen.py, run_mutants.py, report.py, README).

## Re-run of the mutation sweep after the changes (tests/sweep, seed 3, 600 mutants)
A fresh sample (the code changed, so not the same sites): 381 killed, 219 survived (36.5%,
was 39%). History.lua still 78% (wording and layout of saved-run views), UI 46%, Export 38%,
Data/Run 36%, Sync 33%, Track 32%, Util 29%, Commands 27%. The 27 targeted behaviours are now
pinned (mutate_il3.py); the broad rate barely moved - most survivors are wording/layout,
equivalent changes, or constants. Recorded as the measured test adequacy, not as fixed.
