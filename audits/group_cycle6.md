# Group feature audit cycle 6 (fresh agent, recorded before fixes)

**Scope.**
- Read in full:
  - audits/group_cycle1.md through group_cycle5.md;
  - RunBook/Sync.lua 1-1231 (the whole file; focus on UpdatePart 355-470, the S handler, ApplyStats and GroupStats 482-575, GroupKey 753-761, PartnerChars, IsPartnerChar, PartnerHere and ReconcilePartners 763-851, Wait, FriendHeard, TakeHeld and the TICK decision 853-938, PartnerChanged and SetPartner 940-973, BigGroup and the CHAT_MSG_ADDON gate 975-1114, and RUN_START and RUN_REOPEN 1163-1215);
  - RunBook/Group.lua 1-135;
  - tests/harness.lua.
- Read in part:
  - RunBook/Track.lua 36-160 (GroupUnits, SenderInGroup, SenderUnit, FriendInfo, PartnerInGroup) and 1053-1083 (IsDuo, IsRunDuo, KeepDrop);
  - RunBook/Commands.lua 140-215 (check), 298-306 (argument parsing) and 426-478 (group, partner);
  - RunBook/Data.lua 145-230 (FixRun: startTotals, partners and group, `p.realm`, the 40-player trim) and 390-418 (partner, partnerRealm, partnerTag, partnerChars);
  - RunBook/Util.lua 1-60 and 135-260 (plain, Call, MyRealm, ShortName, Fold, SameName, IsPlayerUnit);
  - RunBook/Run.lua 200-215 (WorthKeeping), 300-420 (copies: PartnerStarts, PartnerKeptCopy, RejoinCopy, TakeCopy), 600-760 (MoveSince, MoveParts, PartnerFoundReset, EndRun, RunSummary, SplitAtResume) and 1050-1150 (ManualEnd, ManualStart reopen, ManualNew);
  - RunBook/UI.lua 190-245; History.lua 100-125, 175-195 and 320-335; Export.lua 60-125;
  - README.md 1-30, 75-135 and 180-290;
  - tests/tests_group.lua 1-60, 335-365 and 1263-1382 (the cycle 5 groups).
- Ran:
  - tests_group.lua: 296 passed, 0 failed.
  - tests_group_duo.lua: 9 passed, 0 failed.
  - 7 repro scripts under /tmp/claude-0/grp_c6/ (r1-r7, with common.lua). Each prints "DEFECT CONFIRMED" next to a control or a stated truth. All run one client at a time.
  - A randomized fuzz, fuzz_identity.lua, with seeds 1-4: 600 trials of 30 steps.
    - The people: Mirel, Kelalt and Kelbox-Other (one BattleTag), Guildie (friends list), Pug, and Strange-Other. Senders are always Name-Realm, and nobody shares a name.
    - The steps: S messages; group changes; `partner X`, `partner X alt` and `partner off`; `end`; `start`; offline toggles; `/reload`; ticks.
    - Each person's gold moves in its own decimal band.
    - After each step it checks four things: no Lua errors; `run.partners` holds only characters that `IsPartnerChar(name, entry.realm)` accepts; nobody is both partner and group, or in the group view twice; and no other person's band shows up in a partner entry.
    - Result: 0 flagged. It reached about 4,300 steps with partner numbers and 10,500 with group numbers.
  - So with no name collisions, no hidden names and no damaged data, the cycle 5 identity model held under these flows. Every finding below needs one of those, or (finding 6) a narrow timing window.
- Checked and found sound (no finding):
  - Old saved Totals keys (`"~name@start"`, and `"Mirel@start"` for a partner on another realm) only sit out their 6 hours. A reopen or a new part finds the new keys once one message has arrived after the upgrade.
  - `moved` and `finals` are keyed by identity, so they carry across a promotion or demotion of the same player.
  - Held-message replays set `msgIdent`. S is never held, and the handlers for the held kinds don't use the identity.
  - The S handler's PartnerKeptCopy and RejoinCopy are only reached by the current partner.
  - startTotals at RUN_START and RUN_REOPEN cover both fields under one key.
  - The caps: 4 parts per player, 40 players, and at most 4 saved totals per player and 200 in all. Each message adds one total and removes one.
  - Non-partner messages other than S never reach a handler.
  - Version checks run on the two-person, TICK and follow paths.
  - A damaged `bigGroup`, `friendWait` or `friendsMany` is dropped or trimmed.
- Could not reach:
  - The real client. These points are unverified there:
    - the CHAT_MSG_ADDON sender format (the repros use Name-Realm, as the harness does);
    - whether names are hidden in Forever instances (finding 7 depends on it);
    - whether IsInGroup() is briefly false at login. If it is, the first TICK clears `bigGroup` and `friendsMany`, which would undo the cycle 5 reload fix. Not tested.
  - Two-client runs (duo.lua). All repros are single-client, with hand-built messages.
  - run.sh and the mutation suite (not run, per instructions).

**Counts.** critical 0 / major 1 / minor 6. All 7 are confirmed by a repro. Finding 7 is confirmed in the mock only (hidden names).

## Findings

1. **Major: your partner's same-named character on another realm (same BattleTag) is never followed. Following the addon's own chat line then loses all your partner's numbers at the next reconcile.**
   - Code:
     - Sync.lua:809: `PartnerHere` matches group units by short name only. Mirel's own alt "Mirel" (realm Other) counts as "your partner online", so the BattleTag follow at Sync.lua:1063 never runs.
     - Sync.lua:770-797: `partnerChars` is keyed by short name, so it can't hold Mirel-Realm and Mirel-Other both. `IsPartnerChar("Mirel", "Other")` stays false.
     - `run.partners` is keyed by short name too, so both characters' parts share one entry, whose `realm` is whichever sent last.
     - Sync.lua:835: when ReconcilePartners demotes an entry whose group key already exists, the partner entry is dropped, not merged.
   - Failure (a), automatic:
     - Mirel (your realm, Battle.net friend) logs out mid-run and comes back on his "Mirel" from realm Other.
     - His 30s goes to the group view, and his blue drop and his note are dropped. The only chat line is "Mirel-Other also runs RunBook; your sync partner is Mirel. (/runbook partner Mirel-Other to switch.)".
     - The control, an alt named Kelbox-Other, is followed: Together 40s, 1 drop, 1 note.
   - Failure (b), following that line with `/runbook partner Mirel-Other`:
     - The BattleTag matches, so it's the same person. `partnerRealm` becomes Other, while `partnerChars.Mirel` stays Realm.
     - The group view lists him twice: "All of you" 75s, 3 with RunBook, when the truth is 45s and 2.
     - After `/runbook end` and `/runbook start`, the 45s partner entry (both characters) is demoted onto the existing "Mirel-Other" key and thrown away. Together's partner share is 0, when the truth is 45s.
     - The control, the Kelbox-Other alt, keeps 45s.
   - Repro: r1_samename_alt_other_realm.lua.

2. **Minor: a message from a new partner while your run is ended rewrites the realm on the ended run's entry for the old partner, when the two share a short name. `/runbook start` then keeps the old partner's numbers in Together.**
   - Code: Sync.lua:548-549. ApplyStats sets `e.realm = realm` on every visited run's `partners[sender]` entry, whether or not UpdatePart accepted anything, and that entry can be another person's. This brings back cycle 5 #5 variant (c), which the identity change was meant to close, by another path.
   - Failure:
     - Partner Mirel (your realm) makes 40s. You `/runbook end`, then `/runbook partner Mirel-Other`, a different person.
     - Mirel-Other sends one message, and the ended run's Mirel entry now says realm Other.
     - At `/runbook start`, `IsPartnerChar("Mirel", "Other")` is true, so the old Mirel's 40s stays in Together: share 4400, when the control, with no message in the gap, gives 400.
     - The old Mirel's next message also opens a group entry, so he's counted twice.
   - Repro: r2_history_realm_overwritten.lua.

3. **Minor: a bare `/runbook partner Mirel`, typed while he isn't in your group, takes whoever named Mirel is heard first, from any realm. Re-typing the bare name after an auto-pick also forgets a realm that was known.**
   - The README (Duo sync) says "the bare name means the one from your realm", and its Quick start says to type the bare name.
   - Code:
     - Commands.lua:466 and 474: when the name isn't found in your group, `partnerRealm` is nil. For a re-type, `same` is true via IsPartnerChar with no realm, and the nil overwrites "Realm".
     - Sync.lua:793 and 1058-1059: with no realm, any realm passes the gate.
     - Sync.lua:1106-1108: the first sender's realm is then saved as your partner's for good.
   - Failure (a): you type `/runbook partner Mirel` before grouping. In a dungeon-finder group, the stranger Mirel-Other speaks first.
     - His 2g 50s is in Together, when the truth is 10s, and he can restart or end your run.
     - Your brother gets "Mirel-Realm also runs RunBook; your sync partner is Mirel".
     - This is saved.
   - Failure (b): Mirel was auto-paired, with realm Realm known. You re-type `/runbook partner Mirel` while he's offline. The same stranger then takes over (realm Other, Together 25000).
   - Repro: r3_bare_name_first_heard.lua.

4. **Minor: when your partner's realm is learned from their first message, their existing group-view entry isn't moved. The group view, the history's Group section and the CSV `group_*` columns count them twice until the next partner change or reopen, and a run that ends first keeps the error.**
   - Code:
     - Sync.lua:840-849: the promotion looks for `GroupKey(name, true → nil)` = "Mirel", not "Mirel-Other".
     - Sync.lua:1106-1109: the realm is learned without calling ReconcilePartners.
   - Failure:
     - Mirel-Other is in the group view at 20s. He drops group to relog, and you type `/runbook partner Mirel`. He rejoins and sends 30s.
     - Rows read "Mirel (partner) 30s" and "Mirel-Other 20s". "All of you" is 50s (truth 30s), with 3 with RunBook (truth 2).
     - It's still wrong 5 messages later.
   - Repro: r4_bare_name_unpromoted_group_entry.lua.

5. **Minor: a damaged `partnerChars` entry for your partner passes the load check, and the next reconcile moves your partner's own numbers out of Together.**
   - Code:
     - Data.lua:405-418 accepts any string, including "" or a realm that isn't `partnerRealm`.
     - PartnerChars (Sync.lua:773) never corrects an existing entry.
     - Sync.lua:793-794 then rejects the partner's own realm.
   - Failure: with `partnerChars = { Mirel = "" }` (or `"Other"` while `partnerRealm` is Realm), `/runbook end` then `/runbook start` moves Mirel's 20s to the group view.
     - Together's partner share is 0, while `IsDuo("Mirel")` is still true.
     - A damaged `partnerRealm = ""` does the same at the gate: the partner's messages go to the group view.
   - Repro: r5_corrupt_partnerchars_realm.lua.

6. **Minor: a split (MoveParts) builds the new run's entries without `entry.realm`. A partner change before the cross-realm partner's next message files them under the bare name, so they're counted twice.**
   - Code:
     - Run.lua:643: `{ parts = {} }` without the realm.
     - Sync.lua:827-833: after `partner off`, `chars` is empty, so the realm falls back to nil and the key is "Mirel".
   - This brings back cycle 4 #3 on the split path. It was flagged as cycle 5 #5 ("MoveParts doesn't carry it"). The cycle 5 fix carries realm only through messages.
   - Failure:
     - Partner Mirel-Other. Your log splits the run on a boss killed again, and you type `/runbook partner off` within his 30 seconds.
     - The group keys are "Mirel" and "Mirel-Other", with 3 with RunBook for 2.
     - With a same-realm Mirel in the group view, the old partner's entry is thrown away instead (Sync.lua:835).
   - Repro: r6_split_loses_realm.lua.

7. **Minor (hidden names only): two characters of one person side by side flip your partner after any boss fight longer than 40 seconds, and the main's drops and notes are then dropped as "stats only".**
   - Code:
     - Sync.lua:816-818: "online" means heard in the last 40 seconds.
     - Sync.lua:1063-1076: messages are held through boss fights, so after a 60-second fight, whichever character's queued message arrives first decides.
   - Failure:
     - Mirel and Kelbox (both known) are in an instance with hidden names. After a 60-second fight, Kelbox's message lands first, and "Mirel is on Kelbox now" is printed.
     - Mirel's blue and note right after are dropped (drops 0, notes 0).
     - It repeats with each long fight.
   - Repro: r7_hidden_names_long_fight_flip.lua (mock only).

## Fixes (after the audit was recorded)

1. **Your partner's characters are keyed by name and realm.** `db.partnerChars` is now keyed `GroupKey(name, realm)`. Two characters of one person with the same name on two realms are both known.
   - `PartnerHere` compares realms, so a same-name character elsewhere doesn't count as your partner being online, and the BattleTag follow runs (#1).
   - Your partner's own entry is always written as set, so a damaged one is put right (#5).
2. **Namesake entries stay apart.** A message never updates an entry under that name whose saved realm is another realm (it's someone else's). The realm is written only on entries a message actually updated (#2).
3. **Bare names.** A bare name typed for someone not in your group means your realm, or your partner's known realm if it's your partner. "Whoever is heard first" is left only for when the game gives no realm at all (#3). The README is updated.
4. **No separate step when the realm is learned.** The partner change's reconcile already moves their group entry. The realm-less case matches their entry by name, so the learn-realm step was removed as dead (#4).
5. **Load check.** `partnerChars` drops empty keys and empty realms (#5).
6. **Splits keep the realm.** A split's new entries keep `entry.realm` (#6).
7. **Hidden names, long fights.** With names hidden, "online with you" means heard from in the last 5 minutes, since messages wait during boss fights (#7).

**Tests:** tests_group.lua "Audit cycle 6" section, 7 groups.

**Mutations:** 15 new and 4 updated, all caught.
- Dropped as equivalent: realm written only when updated (the namesake guard covers it), the realm-learned reconcile (removed), and the "no realm means yours" fallback (removed as unreachable now that a bare name gets your realm).

All suites pass.
