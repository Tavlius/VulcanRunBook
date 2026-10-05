# IL2 audit cycle 2 (fresh agent, recorded before fixes)
Scope: README, TOC, Bindings, all nine Lua files in full; il2 plan/cycle1; harness/duo/fuzz_duo;
run.sh green; fuzz2 100-160, fuzz_duo 40-70 x3, gold/drops/notes 40-80; damaged-save fuzzers
(400 seeds + junk matrix); scenarios s1-s4; fixed the delay harness in a scratch copy. Not
reached: real client (delivery across loading screens, throttle, hidden names), SM/DM wings.
Counts: critical 0, major 0, minor 3 (all confirmed); 2 borderline.
1. minor History.lua:166-183, Run.lua:589-594 vs UI.lua:41-43 - details and end-of-run line
   floor gold, live window rounds; details' Together doesn't add up (2g 57s + 1g 10s = 3g 68s).
2. minor Sync.lua:460 / Commands.lua:170-177 - /runbook check compares with a kill count from a
   final (ended) or hours-old stats message: false "they differ".
3. minor Run.lua:970 ipairs(VulcanRunBookCharDB.copies or {}) - a non-table (hand edit) makes
   /runbook start throw.
Borderline: (a) his split message then his kill message arriving just after you come back
in: the split starts your run at your re-entry, then the kill (died before that) is dropped
by Sync.lua:563 - in neither run; (b) anon kill + /reload within ~2 s: duplicate.
Harness: DELAY counted only in D.tick seconds (2 s became 15-30 s across loading screens) and
held messages went to the client object a reload replaces; with both fixed, DELAY=1 passes all
36 seeds; DELAY=2-3 failures are mostly borderline (a) plus oracle assumptions.

## Fixes (after the record above)
- 1: ns.ShownMoney/ShownMoneyText (Util) used by the live window, run details and the
  end-of-run line: one rounding everywhere; details' Together is the sum of shown shares; the
  coin/loot breakdown only when both are there.
- 2: stats remember whether the run ended; /runbook check says "has no run here going" for an
  ended run, and "can differ" (no fix advice) for numbers over 90 s old or a run that began at
  another time.
- 3: the /runbook start path uses Copies() (validated).
- Borderline (a): a run split at your re-entry by your partner's message records when the copy
  began for them (copyFrom); messages from then on belong to it (ns.CopyBegan). Partner kills
  from before your clock started are untimed.
- Borderline (b): pairing is kept on the kill (b.matched) and a kill's age falls back to its
  server time, so a /reload doesn't unpair or double kills.
- Harness: adopted the auditor's delay fix (delay counts loading screens; held messages go to
  the current client by name). run.sh runs fuzz_duo with DELAY=1 (all ops) and DELAY=2
  (without end/start/new, whose instant-effect oracle doesn't hold with delay).
  Sweep: DELAY=1 36/36, DELAY=2 without slash 36/36 (was 6 anon failures from reloads).
- Tests: tests_il2 93 checks, tests_il2_duo 13; 13 new mutations, all caught. run.sh green.
