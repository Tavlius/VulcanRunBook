# Improvement loop 1 — critiques consolidated (step 2) and plan (step 3)
Critiques/questions: 48 raised across audits 1-3 (see il1_audit1-3.md). Open questions that can't be answered
without the client (become /runbook check items): who receives the reset message; whether its name matches
GetInstanceInfo; which event carries "too many instances"; party name/dead-state readability; cross-zone
GetBestMapForUnit; boss events in 5-mans; EditBox limits; font widths; raid lockout IDs; pet GUID copy field.

Plan (implement all):
Sync/reconciliation
 P1 P handler: never split while outside; inside, split only if your resume is at/after their split - 60 (D1).
 P2 Runs record whether they began in a fresh copy (`fresh`); B carries it (tag flag "f"); a partner's run start is
    taken as a new-copy start only when fresh (D2). Message text hedged.
 P3 Ghost returns don't move the split point (D3).
 P4 PROTOCOL 2 (D6); flags on the kill tag ("!mf").
 P5 Partner numbers and drops: finite non-negative integers only (D5, D).
 P6 Addon messages accepted only on PARTY/RAID/INSTANCE_CHAT from a current group member (B).
 P7 Partner boss names cleaned + 40 bytes (C); notes limited so header+note fits 255 for both logs (J).
 P8 Boolean false from SendAddonMessage retried (G).
Robustness
 R1 Saved-data validation of all compared/formatted fields; history rows rendered one at a time (A).
 R2 "too many instances": localized strings only, no loose English fallback (E).
 R3 Korean grammar codes tolerated in reset pattern (H).
 R4 Bag dips that come back within seconds aren't loot (I).
Cap
 C1 Daily cap (30/day default) tracked and shown; entries per realm (F).
 C2 Over-cap hint when the game let you in past the cap (audit3 #4).
Player-facing
 U1 Hand-typed boss names snap to a known name for this dungeon; SameBoss accepts name-part matches (#2);
    /runbook final lists known names on a miss.
 U2 /runbook new on a run with kills or 2+ min asks to repeat within 15 s (#3).
 U3 Character shown on history rows when more than one character has runs; clear/delete say "all characters" (#1).
 U4 Raid deaths: counts are you two's (row, summary, stats, live), details list all (#5).
 U5 byHand flag for every hand mark (yours or partner's) shown in details (#6).
 U6 Short-form runs keep notes (#7).
 U7 Together gold on the run-end line and gold/hr in the Dungeons tab (#9).
 U8 Raid details: group shown as a count, not 40 names (#11).
 U9 /runbook check: last reset message seen and whether it matched; party names/dead readable; cap errors seen (D7, K).
 U10 Hint when your group changed while you were outside (L).
 U11 Live/checks: partner last heard shown in /runbook check (D8).
README
 D1 Quick start first; "Fixing mistakes" table; quality wording; alts sharing; daily cap; details later; shorter.
Tests
 T1 fuzz_copy (per-copy invariant) in run.sh with seen resets only (D4).
 T2 tests_il1.lua for every change; mutation script proving each guard fails when removed.
