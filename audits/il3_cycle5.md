# IL3 audit cycle 5 (fresh agent, recorded before fixes)
Scope: README, TOC, Bindings, AUDIT_REPORT, il3 plan/cycles 1-4; Commands/Data/Run/Sync/History/UI/
Util/Export in full, Track 1-1427 (500-960 closest); run.sh green; fuzz 400-440, fuzz2 400-425,
fuzz_duo 60-68 x3, cap/gold/drops/notes 30-40; a hostile slash-command fuzzer (6 x 3,000); probes
p1-p5. Not reached: real client (delivery during loading screens and at logout, throttle, the
account-load bug, font widths, instance/guild chat errors); duo harness under DELAY not used.
Counts: critical 0, major 0, minor 3 (all confirmed).
1. minor UI.lua:42-49 vs History.lua:80-83/170 - the live window rates the rounded gold, the
   history rates the exact gold: 2g 46s/hr live vs 2g 47s/hr in the details (cycle 4 fix incomplete).
2. minor Commands.lua:541-544/528-532 - with 2+ characters, bare `clear` says "Type /runbook clear
   yes to confirm", which then asks again: three commands.
3. minor Track.lua:572-574 + Run.lua:766-775 - a first-visit ghost return makes a resume point, so a
   partner kill during your ghost run, handled after you zone in, is untimed (README: running back
   counts).

## Fixes (after the record above)
- 1: history details' rates use the shown (rounded) gold, as the live window does; the Dungeons
  tab sums each run's shown gold, so one run's rate matches everywhere.
- 2: with more than one character, bare `clear` arms the 15-second confirmation and says
  "clear yes within 15 seconds".
- 3: every ghost return keeps the split point (none on a first visit), so a partner kill while you
  ran back keeps its time.
- Tests: 3 groups (tests_il3 112 checks), 4 mutations; il1's ghost mutation updated. run.sh green.
