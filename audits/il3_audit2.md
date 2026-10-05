# Improvement loop 3 — audit 2 (data lifecycle over months), recorded before changes
Scope: Data.lua in full; history parts of Commands/Run/History; README; 12 scripts (2,300 runs over
3 dungeons, sizes/timings, short-form delete/note/unboss, price change, same name two realms, >500
deletions, failed account load at caps and twice, alt's months-old run, old-format data, rename,
numbering after a failed load). Not reached: real client writer/load/rename, older build rollback,
partner parts growth, raid-sized runs, copy box limits; run.sh not run. Scripts: /tmp/claude-0/il3_a2/.
D1 MED Commands:223/251/328 FindRunById searches history only: a short-form run can't be deleted,
   noted or unbossed but still sets the best time.
D2 MED Data:541-546/462-469, Run:1141 one failed account load at the caps loses 1,500 short-form
   runs for good (backup holds 500); notice says "200 runs were restored"; restoreNoticed never reset.
D3 minor Data:665-670 an alt's months-old run in progress is archived straight to short form at
   db.old[1] (order broken), #251, unreachable ("No run to add a note to yet.").
D4 minor Data:810 CharacterCount uses ShortName: same name on two realms counts as one.
D5 minor Data:654 Lite freezes partner gold (pg) at the price setting of the time.
D6 low Data:337-343 PruneDeleted keeps the 500 newest by run start: a deleted old run can return
   from a stale alt backup after 500+ later deletions.
D7 minor Data:491-503 after a failed account load the alt's stale nextId numbers runs that get
   renumbered at the next normal login.
Critiques: shared 2,000 cap lets a farmed dungeon push out a raid's history/best; DB_VERSION never
read, no migrations, rollback unknown; history ordered by PC clock; permanent account-load bug would
split alts; rename/transfer loses the run in progress; runs without char count as everyone's; notes
vanish silently in short form, export covers only 200; short-form runs invisible yet set bests;
sizes (1.32 MB account, 0.46 MB/char at caps with simple runs; raid deaths unmeasured); timings fine.
