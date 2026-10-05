# IL2 audit cycle 4 (fresh agent, recorded before fixes)
Scope: README, TOC, Bindings, all nine Lua files; il2 plan/cycles 1-3; AUDIT_REPORT; harness,
duo, fuzz_duo; run.sh green (1,727 checks); fuzz2 400-440; fuzz_duo DELAY 1 80-95 x3, DELAY 2 no
slash 100-125 x3; a timed-kill fuzz variant (178 runs); scenarios s1-s8. Not reached: real
client (delivery during loading screens, throttle, hidden names), SM/DM wings, Auctionator,
font widths, timing finer than the per-client clocks.
Counts: critical 0, major 0, minor 4 (all confirmed; #4 hand-edit only).
1. minor Track.lua:567-572 - "while you were outside" decided by when the message arrives,
   not the kill time: his kill while you were out, arriving after you're back in, is timed ->
   false new best (timed-kill fuzz: 25/60 fail at DELAY 2, none at 0/1).
2. minor Track.lua:1392, Run.lua:174/561, Export.lua:132 - after a partner-found reset while
   you're outside, /runbook note goes on the empty never-entered run (lost if you don't go in);
   /runbook report reports that run ("0:00, 1 boss, in progress").
3. minor Track.lua:1027/1165 - the partner's own quality setting filters which drops he sends;
   README says the setting covers "your and your partner's drops".
4. minor (hand edit) UI.lua:134, Run.lua:950 -> Data.lua:287 - VulcanRunBookCharDB.manualEnded fields
   used before validation: Lua error at login.

## Fixes (after the record above)
- 1: a partner kill is "while you were outside" (untimed) when its kill time is before you last
  came back in (resumeSnap.server, or the run start), whenever the message arrives.
- 2: ns.RunOrLast(): your own notes and /runbook report go to your last run while the run going
  is one you haven't gone into (made for your partner's new copy).
- 3: greens and up are sent to your partner even when your own setting doesn't keep them;
  README quality row says so.
- 4: VulcanRunBookCharDB.manualEnded goes through ns.FixRun at load.
- fuzz_duo adopts the auditor's timed-kill oracle (no kill timed for a log whose player wasn't
  there; no kill time past the run time): 180/180 at DELAY 0/1/2 (2 without end/start/new).
- Tests: 4 groups (tests_il2 117 checks); 5 mutations. run.sh green.
