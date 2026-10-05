# Improvement loop 3 — audit 1 (test adequacy by systematic mutation), recorded before changes
Scope: 600 sampled mutants (of 10,019 sites; 8 operators) over all nine files, each against all 31
tests*.lua suites; fuzzers (114 runs) for 27 survivors + a control; ~40 hand probes. Not reached:
multi-line conditions, arithmetic/pattern/field-name mutations, 94% of sites, real client,
harness fidelity. Tools/results: /tmp/claude-0/il3_a1/.
Score: 365 killed, 235 survived (39%): 68 equivalent, 129 real untested (32 probe-confirmed),
26 layout/wording, 12 dead. History 75% survival, UI 50%, Data 42%. Fuzzers caught 4 of 27.
Top untested behaviours: (1) Track:520 own repeat kill's SyncSplit; (2) Run:289 CopyKillsOf
ignoring copyKills (second /runbook end); (3) Sync:124 SyncNoteRoom; (4) Sync:578 partner boss id;
(5) Data:656 Lite; (6) Run:663 wing split for new-wing partner items; (7) Data:701 manualEnded
cleared on any delete; (8) Run:1032 end-then-new hold; (9) History:32 Wrap; (10) History:97 end
text; (11) Export:85/79 partner gold/minutes; (12) Data:618/UI:49 5-minute rate guard;
(13) UI:51 XP/hr; (14) Run:183-184 WorthKeeping; (15) Track:793 death guard; (16) Track:109 roster
members; (17) Data:79 partner totals; (18) CharacterCount; (19) Commands:61 channel case;
(20) Commands:434 end reply; (21) History:76/247 zero counts; (22) Track:1121 late item data;
(23) Sync:69 queued stats replaced.
Defects: D1 minor - partner kill timed at arrival not kill time (Track:561-562; sent kill time only
used for the before-run check): a held message gives a late split/clear time. D2 cleanup - run.entryTimes
written and repaired but never read. D3 cleanup - RunsOf `except` unused.
Critiques: saved-run views not compared with exact text; fuzzers check agreement, not lost info;
time windows untested at boundaries; damaged-field fuzzing absent for several fields; old code
has no regression mutation protection; tests_round2 slow; coverage never measured; fuzz seeds
not coverage-driven; "can't happen" guards; harness event order unvalidated.
