# Improvement loop 1 — audit 1 (design / angle c), recorded before changes
D1 MAJOR P split applied while receiver outside splits at an old-copy resume point (P has no guard that B path has).
D2 MAJOR Partner's run start (after /runbook end in same copy) is taken as a new-copy start: copy-1 kills/gold move into copy-2 run; false "partner's log saw the reset".
D3 MED Split only at last resume point (ghost return) leaves new-copy coin/death/wipe in old run.
D4 MED Fuzzers check totals only; no per-copy invariant (fuzz_copy fails 9/60, 1 = D2, 8 = documented limit).
D5 LOW Partner numbers not checked finite/bounded (1e308/inf).
D6 LOW PROTOCOL never bumped though message set changed.
D7 LOW /runbook check shows nothing about reset messages.
D8 LOW Partner last-heard not shown; drift invisible.
Critiques 1-18 (see agent report): run boundaries stand in for copy boundaries; v vs st clocks; single resumeSnap; irreversible moves; message order load-bearing; partner-gold delta machinery; many time windows; no resend for N/D/B/P/X/R; no cross-log comparison; overconfident chat lines; account-wide history vs per-char copies; boss events may not exist in Forever 5-mans; unknowns: does Forever send reset msg to party; per-copy id; regroup new copies; reset msg name vs GetInstanceInfo name; does X pay for itself; WorthKeeping silently drops data.
Ranked improvements: quick fix D1/D2; per-dungeon copy timeline shared over sync; keep all resume points; per-copy fuzz invariant; event-sourced redesign (long term); drift display; finite numbers; protocol bump; reset parsing in check; hedged chat lines.
