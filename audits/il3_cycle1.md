# IL3 audit cycle 1 (fresh agent, recorded before fixes)
Scope: README, il3_plan, Data/Sync/Commands/Util/Track/Run/History/Export in full, UI in part;
run.sh green; blocked-send fuzzers (8x3, and 10x3 with reloads while blocked) clean; probes p1-p5,
hostile saved data. Not reached: real sender/realm formats, logout delivery, real result codes.
Counts: critical 0, major 0, minor 4 (one hand-edit only).
1. minor Data.lua:508-519/588-595 - only full runs are renumbered at load: clashing numbers from a
   long failed-load stretch survive in short form; delete/note/unboss #N can hit the wrong run.
2. minor Data.lua:723-736/Run.lua:442-448 - a run older than everything, with the short-form list
   full, is cut by the cap at once but the end line says "kept in short form".
3. minor Sync.lua:547-548 - the 5 s grace still takes a partner drop looted after your run ended.
4. minor (hand edit) Data.lua:366 - PruneDeleted's sort indexes a non-string key: load error.

## Fixes (after the record above)
- 1: at load, short-form and full runs are numbered together (oldest first; a clash gets a new
  number), so every run has its own number.
- 2: Archive returns "short" or "dropped"; the end line says "isn't saved" for a run past the cap.
- 3: a drop with a loot time is judged by it (after your run ended: not added; before: up to
  2 minutes late); the 5 s grace is only for messages without one.
- 4: PruneDeleted's sort uses tostring.
- Tests: 4 groups (tests_il3 96 checks); 4 mutations; il2's "ended grace" mutation now targets
  the loot-time rule. run.sh green (now ~10 minutes).
