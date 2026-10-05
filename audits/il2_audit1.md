# Improvement loop 2 — audit 1 (design and test quality), recorded before changes
Scope: Track/Run/Sync, run.sh, duo harness, fuzz_duo, mutate_il1 in full; oracles of fuzz_copy,
fuzz2, fuzz_duo_late; README sync/limits; harness send/save mocks. Ran baseline run.sh, 18 own
mutations, ~150 duo seeds with a cross-log checker and random delays, r1-r3 repros. Not reached:
real client, Data merge, UI/History/Export/Commands, minimising delayed-delivery failures.

T1 MAJOR (tests) run.sh exits 0 when tests_round6-25 and tests_il1 fail: H.summary never exits
   non-zero; mutation scripts never check the unmutated suite is green. CONFIRMED.
T2 MOD fuzz_copy copyOf matches by boss name only: anon mode checks no kill (0/1481 matched).
D1 minor Sync TargetRun: late B/D message for the old run lands in the new run after /runbook
   new (Gilnid in both of Mirel's runs; a drop moves). CONFIRMED.
D2 minor PartnerFoundReset doesn't renumber unnamed kills ("Boss 3, Rhahk'Zor" vs "Boss 1"). CONFIRMED.
D3 minor MoveFrom -5 s slack takes a partner kill from before his /runbook new; untested.
D4 minor two /runbook new from both brothers within 60 s split the logs differently.
Untested guards (mutation, all green): FindRun endedBefore; redo clearing lastKill; MoveFrom
   slack; late-reset 120 s window; P prev-split adjacency; D ended grace; P once; partner's
   longer name on a known key; finals block. Six more caught only by a printed FAIL (T1).
Critiques/questions: logs share conclusions, not identity (copy token idea); no disagreement
   detection or repair; message delay never tested (0-5 s delays: 17/32 fail, oracle unclear);
   oracles only count; session-only state lost on /reload; AddBoss 300 lines/8 params; low
   fuzz density; complexity vs. value (leader decides / prompt instead of inferring); unknowns:
   message order and throttle, lockdown at ENCOUNTER_END, SavedVariables inf/NaN, /runbook end
   one-sided by design?; mutation proof one-sided.
