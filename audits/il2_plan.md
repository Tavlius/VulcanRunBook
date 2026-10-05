# Improvement loop 2 — critiques consolidated (step 2) and plan (step 3)

## Critiques and questions (from il2_audit1-3; 40+ raised, the main ones)
1. run.sh passed while 20 suites failed: the green status was never proven (T1). [fixed first]
2. Mutation proof one-sided: never checked the unmutated suite is green.
3. Nine guards can be deleted with every test green; six more caught only by a printed FAIL.
4. fuzz_copy's per-copy check sees no kill in anon mode (matches by name).
5. Two-client fuzzers deliver messages instantly; real messages wait out boss fights.
6. Two-client oracles only count kills/gold; nothing checks the logs agree on names/runs.
7. Nothing notices when the two logs disagree, and nothing can repair it.
8. Late partner messages (kill, drop) after /runbook new land in the new run (D1).
9. A split-off leftover run (2 of 6 bosses) becomes the "best clear" (P1, major).
10. Backup doubles SavedVariables (3.5 MB per character); is it still needed?
11. Bag scan on every bag change even with no run.
12. Send results 5 and 9 drop messages at once.
13. Mock has no realm names; realm compare never exercised.
14. Money shown floored per part but totalled exactly ("2s + 3s = 6s").
15. Partner rate drifts while both are paused.
16. Bare /runbook sync and /runbook auto silently flip settings.
17. /runbook report party/raid while solo sends anyway.
18. Lowercase typed boss names stick and become the final-boss name.
19. /runbook delete deletes at once (a typo deletes the wrong run); clear asks first.
20. CSV cells from notes starting with = become spreadsheet formulas.
21. README: pairing message timing wrong; raid deaths wording; "instance" channel missing;
    too long for a phone.
22. Hunter pet deaths untracked; gold is gross not net; AFK inside counts on the clock.
23. Unanswerable here: does Forever fire ENCOUNTER_* in 5-mans; is CHAT_MSG_ADDON secret inside
    instances; message order/throttle; is the beta saved-data bug fixed; SAY needs a hardware
    event; does the game eject you from a reset copy at login; TOC number at launch.
24. Design: the logs share conclusions, not identity (copy token); AddBoss 300 lines.

## Plan
Tests
 T1 H.summary exits 1 on failure; mutation scripts check a green baseline. (done; proven)
 T2 fuzz_copy matches kills to copies by tag/true copy, not name.
 T3 Tests for each guard that survived deletion (or remove the guard if it does nothing).
 T4 Mock: GetNormalizedRealmName; realm-suffixed names in a test.
 T5 Delay mode in the duo harness (in-order, random delay); a fuzz mode using it; investigate.
 T6 Cross-log invariant in fuzz_duo: same kill count and names per matching run pair where
    no commands were used.
Sync
 S1 B/D messages whose kill/loot time is before your run began go to the run of yours that
    was going then (D: noted there; B: dropped, not misplaced).
 S2 RenumberUnnamed in PartnerFoundReset.
 S3 MoveFrom -5 s slack: test or remove.
 S4 Retry results 5 and 9 (bounded like the rest).
 S5 Kill count in the stats message; /runbook check shows "his log: N kills, yours: M" for the
    run in progress (disagreement visible). Protocol 3.
Data
 R1 Backup without the 2,000 short-form runs (keeps the 200 full ones); measured size.
 R2 Bag scans only while a run is going.
 R3 Export: highlight after show/focus.
Player
 U1 Best/average clear times and "New best" only from runs with at least (most kills - 1)
    kills; README says so.
 U2 README pairing wording.
 U3 Money: parts rounded the same way as the total; rates in the same short format.
 U4 Bare sync/auto show the state and how to change it.
 U5 Partner rate doesn't drift while their run is paused.
 U6 Raid detail: "Group: 40 players" (you two named only if you're not alone); README raid wording.
 U7 report party/raid checks you're in one; README lists instance.
 U8 Typed all-lowercase boss names are capitalised.
 U9 /runbook delete asks to repeat within 15 s (or "delete 12 yes").
 U10 CSV cells starting with = + - @ are prefixed with '.
 U11 Noise: no "0.0 deaths/run", no "You: 0c" line on empty runs.
 U12 README: Limits add hunter pet deaths, gross gold, AFK; a short "What you'll see" lead.
Not doing (recorded): copy-token redesign (too large a change late; S5 makes divergence
visible instead); gold net of repairs (API can't attribute costs); AFK detection; pet deaths.

## Implemented (steps 4-5)
Tests: T1 (H.summary exits 1; baseline-green check; proven with a real mutation), T2 (fuzz_copy
places unnamed kills by time; fails if it places under 80%), T3 (tests for every guard audit 1
could delete: late-reset window, P adjacency, P once, fuller name on a known key, finals block,
ended grace, FindRun endedBefore, retry guard via a fake reset; the redundant redo clearing and
the MoveFrom -5 s slack were removed instead - the slack was audit 1's D3), T4 (mock realm by
default; realm tests use it), T5 (DELAY option in duo.lua - see below).
Sync: S1 (partner kill/drop from before your run began: dropped, or the drop goes to the run of
yours going then), S2, S4 (5 and 9 retried 10 min), S5 (protocol 3: kill count in stats;
/runbook check compares). PartnerFoundReset's `after` bound removed (callers guarantee it).
Data: R1 (backup keeps 500 short-form runs), R2 (no bag scans outside a run), R3.
Player: U1 (best/avg only from whole-dungeon clears; details say "not a best time"), U2-U11,
README updated (U12 in part: limits added; no new lead section - Quick start already leads).
New suites tests_il2.lua (79 checks) and tests_il2_duo.lua (8); mutate_il2.py (37 mutations,
all caught). run.sh green.

Not done, recorded:
- T5 finding: with a 2 s in-order delay, fuzz_duo fails often (anon mode most). The two-client
  harness can't tell defects from artifacts: each client's clock jumps on its own loading
  screens, so with any delay the pairing windows (20 s on GetTime) and server-time rules see
  gaps that can't happen for real. Settling it needs a two-client harness with one shared clock
  (both advance on either's loading screen). Recorded as the main unreached area.
- T6 cross-log run invariant: by-design differences after /runbook end (one-sided) make it
  noisy; S5's check line covers the player-facing side.
- Copy-token redesign; net gold; AFK; pet deaths (README limits).
