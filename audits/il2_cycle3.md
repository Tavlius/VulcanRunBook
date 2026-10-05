# IL2 audit cycle 3 (fresh agent, recorded before fixes)
Scope: README, TOC, Bindings, all nine Lua files; il2 plan/cycles 1-2; harness, duo,
tests_il2_duo; run.sh green; fuzz_duo x3 40-70 at DELAY 0/1/2, 101-106 x600 at DELAY 1, 1-8 at
DELAY 3; fuzz/fuzz2 300-340; gold/drops/notes/copy 100-120; 60 seeds of random commands + views;
damaged-save matrix on cycle-2 fields; scenarios s1-s5. Not reached: real client, SM/DM wings,
Auctionator, font widths. Fuzz oracles don't check timed kills / best times.
Counts: critical 0, major 0, minor 4 (all confirmed).
1. minor Track.lua:379 (and :401) - the retried AddBoss after an inside split drops the kill
   time, so a partner kill from before your clock started is timed: false "New best clear".
2. minor History.lua:69-75, UI.lua:140-146 - history row and "Last:" line still floor gold.
3. minor History.lua:164-169 - coin under a silver kept exact while the total is rounded:
   "You: 3 silver (coin 51 copper, loot 2s 49c)".
4. minor Run.lua:525-528 (+174), Run.lua:633 - PartnerFoundReset (and the since-move in
   SplitAtResume) moves your own notes written outside into the new-copy run, which is thrown
   away if you don't go back in: note lost.

## Fixes (after the record above)
- 1: both retried AddBoss calls pass the kill time, so the "before your clock started" rule
  applies (untimed; not a best time).
- 2: history rows and the Last line use ShownMoney (whole gold rounded to nearest at 10g+).
- 3: with a total of a silver or more, coin is rounded to the silver too, so coin + loot = total.
- 4: MoveFrom's by-time move takes only others' things (partner kills, others' drops, deaths and
  notes); yours stay where you wrote them (PartnerFoundReset, SplitAtResume, MoveSince).
- Tests: 4 groups in tests_il2 (104 checks); 5 mutations; the adjacency test now has a partner
  kill (the old one only had your own things, which no longer move by time). run.sh green.
- il1 test 'his entry' gained a partner drop (own things no longer move by time, so it needed one to stay sensitive).
