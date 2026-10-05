# IL2 audit cycle 1 (fresh agent, recorded before fixes)
Scope: README, TOC, Bindings, all nine Lua files in full; il2 plan/audits; run.sh (green);
extra seeds fuzz/fuzz2 20-60, fuzz_duo x3 10-30, drops/gold 10-30, notes 11-30, copy x3 10-25,
unread 10-25; ~30 commands with odd input; scenarios t1-t4. Not reached: real client, timed
two-client delivery (clock drift), SM/DM wings in-game, Auctionator, font widths.
Counts: critical 0, major 0, minor 3 (all confirmed).
1. minor Export.lua:138-147 /runbook report says "new best" for a partial clear (uses ClearTime).
2. minor Data.lua:923/982, History.lua:110 half rule excludes route runs (DM tribute, Baron,
   Emperor) once one fuller clear exists; details say "part of the dungeon" for a full route.
3. minor UI.lua:41-44/206-224 "Together" doesn't add up when a share is under 1 silver
   (50c + 3s -> "Together: 3 silver").

## Fixes (after the record above)
- 1: ReportLines says "new best" only for a TimedClear.
- 2: the half rule is removed (routes like tribute runs are clears like any other); a run you
  joined part way counts too - README says to delete it if it would spoil the best. The
  details text now names the one reason left ("began after bosses here were down").
- 3: Together is the sum of the shown shares, shown exactly ("3s 50c", "1g 50c").
- Tests: groups "a route that skips bosses...", "a report doesn't call...", gold-with-copper
  checks; mutations updated (half-rule ones removed, 3 added). run.sh green.
