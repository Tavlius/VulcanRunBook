# IL3 audit cycle 2 (fresh agent, recorded before fixes)
Scope: README, il3 plan/cycle 1, AUDIT_REPORT; Data/Sync/Commands/History/Export/UI in full, Run
150-1210, Track 25-680 and 930-1427, Util 40-240 (rest skimmed); run.sh green; probes p1-p5; damaged
saved data (700 seeds); fuzz_duo/gold/notes/drops 6 seeds at DELAY 0 and 3, fuzz_drops 8 more at
DELAY 2 and 5 (failures only the known delayed-check limit). Not reached: real sender/realm formats,
real result codes, logout delivery; messages while the partner is disconnected (no-acks decision).
Counts: critical 0, major 0, minor 1 (confirmed).
1. minor Data.lua:348-362 + merge 464-477 - PruneDeleted forgets a deletion once the short-form list
   is full and the run is older than its oldest; a later short-form delete makes room, and an alt's
   older backup brings the deleted run (a deleted best time) back.
Checked, no defect: renumbering at load (normal reloads keep numbers), number commands, partner drops
for ended runs, hostile saved data.

## Fixes (after the record above)
- 1: a deletion stores when it was made (older builds' `true` counts as oldest); deletions are
  never dropped for the run being old - only past DELETED_MAX (5,000), the least recent first;
  merges keep the later time. The auditor's scenario now keeps run #1 deleted.
- Tests: the deletion group rewritten (full list + old run's deletion kept; past the cap the least
  recent deletion goes, recent ones stay); mutations updated. run.sh green.
