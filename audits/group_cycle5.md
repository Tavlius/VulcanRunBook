# Group feature audit cycle 5 (fresh agent, recorded before fixes)

**Scope.**
- Read in full:
  - audits/group_cycle1.md through group_cycle4.md;
  - RunBook/Sync.lua 1-1208 (the whole file, focus 355-573 UpdatePart/S/ApplyStats/GroupStats, 751-1093 GroupKey through the CHAT_MSG_ADDON handler, 1142-1192 RUN_START/RUN_REOPEN);
  - RunBook/Group.lua 1-135;
  - tests/harness.lua.
- Read in part:
  - RunBook/Track.lua 30-175 (GroupUnits, SenderInGroup, SenderUnit, FriendInfo, PartnerInGroup) and 1053-1083 (IsDuo, IsRunDuo, KeepDrop);
  - RunBook/Commands.lua 140-210 (check), 295-310 (argument parsing) and 426-477 (group, partner);
  - RunBook/Data.lua 185-232 (FixRun partners/group, `e.realm`) and 396-418 (partner, partnerTag, partnerChars);
  - RunBook/Util.lua 10-40 and 140-260 (plain, Call, MyRealm, ShortName, SameName, IsPlayerUnit);
  - RunBook/Run.lua 240-266 (Begin), 635-707 (MoveParts, PartnerFoundReset, EndRun), 748-800 (SplitAtResume) and 1054-1110 (ManualEnd, ManualStart reopen);
  - RunBook/UI.lua 195-240; History.lua 100-125 and 175-195; Export.lua (the group columns, 73-110);
  - README.md (the partner/group lines) and 180-230 (Duo sync);
  - tests/tests_group.lua 1-90 and 1040-1263 (the cycle 4 groups).
- Ran:
  - tests_group.lua: 277 passed, 0 failed.
  - tests_group_duo.lua: 9 passed, 0 failed.
  - 7 repro scripts under /tmp/claude-0/grp_c5/ (r1-r7, with common.lua). Each prints "DEFECT CONFIRMED" next to a control or a stated truth.
  - A scratch check of the `alt` parsing (s1_alt_parsing.lua). It found no defect:
    - Names ending in "alt" (Kelalt) are kept whole.
    - " alt", " ALT" and "   Alt" are stripped.
    - Without a partner, `alt` is ignored.
    - `/runbook partner alt` sets a character named "Alt", which is a valid name.
  - A randomized fuzz, fuzz_bands.lua, run with seeds 1-3 for 900 trials of 30 steps. The steps were:
    - S messages from Mirel, Kelalt (same BattleTag), Guildie and a namesake Mirel-Other;
    - `partner X/off/Kelalt alt`, `end`, `start`;
    - group changes, offline toggles, ticks and `/reload`.
  - Each person's gold moves in its own decimal band, so a leak into Together shows in the wrong band. Results:
    - No Lua errors.
    - 9 trials flagged. Trials 43 and 185 (seed 1) are finding 5. Trials 75 and 156 are not a reportable defect: partner-state totals are keyed by short name, so two different partners named Mirel with the same run start share "Mirel@start" (a base of a few copper here). That needs a namesake pair entering in the same second, so it is noted, not reported.
- Could not reach:
  - The real client. These points are unverified there:
    - the real CHAT_MSG_ADDON sender format;
    - whether group GUIDs and names are hidden in Forever instances (finding 2's hidden-GUID variant depends on it);
    - real timing of the roster at login.
  - Two-client runs (duo.lua, duo_common.lua). All repros are single-client, with hand-built messages.
  - run.sh and the mutation suite (not run, per instructions).

**Counts.** critical 0 / major 2 / minor 4. All 6 are confirmed by a repro. Finding 2's hidden-GUID variant is reasoned from the same line, not run separately. Its main repro (no BattleTag: paired by the two-person rule) needs no hidden values.

## Findings

1. **Major: changing partner right after `/runbook end`, then `/runbook start`, puts everything the new partner made while the run was ended into your Together line.** Sync.lua:1170-1191.
   - Code:
     - RUN_REOPEN recounts each entry from the totals of the field it sits in (Sync.lua:1174). For a group entry that's `"~Mirel@start"`.
     - Once Mirel is your partner, his messages save their totals as `"Mirel@start"` (Sync.lua:511-514), so `"~Mirel@start"` stops at the moment of the change.
     - The recount then adds almost nothing to the base, ReconcilePartners promotes the entry, and the whole gap counts.
     - Cycle 4's fix only holds when the partner sends nothing between the change and the start (its test changes partner just before `start`).
   - Failure:
     - Guildie is your partner and Mirel is in the group view with 9s. You `/runbook end`, then `/runbook partner Mirel` at once.
     - Mirel plays on for 10 minutes (to 5g 9s), then you `/runbook start`, and his next message is 5g 10s.
     - Together shows 5g 10s (51000 copper). The README promises "a run you reopened gets nothing your partner made while it was ended", so the truth is 10s.
     - The control (change just before `start`) gives 1000.
     - The mirror case: the demoted old partner's gap growth is looked up under `"Guildie@start"` (stale), so it lands in the group view too.
   - Repro: r1_reopen_partner_sends_after_change.lua.

2. **Major: a known character of your partner's, sending while your current partner character is NOT online, is held to "stats only" when no BattleTag can be read. Their drops, notes, kills, `/runbook new` and resets are dropped, and nothing is said.**
   - Code:
     - Sync.lua:1044-1051. `tag` is nil whenever no BattleTag is readable, not only when PartnerHere() is true. That happens with no `partnerTag` (paired by the two-person rule, friends-list friend), or with hidden GUIDs.
     - The branch `if not tag and ns.IsPartnerChar(name, realm)` then sends only S to `GroupStats(name, body, "partners")` and returns. It never checks that the current partner character is online, though the comment, and the README ("Another known character of theirs, online at the same time"), say so.
   - Failure, in the flow the addon itself suggests:
     - Mirel is paired by the two-person rule (no BattleTag).
     - He swaps to Kelalt; the hint says `alt`, and you type `/runbook partner Kelalt alt`.
     - The next day Mirel plays his main, without Kelalt online. His gold reaches Together, but his blue drop and his note are dropped: 0 drops and 0 notes, against 1 and 1 in the control with partner Mirel.
     - No chat line is printed, so you're never told to switch back.
     - His kills (`B`) and start-overs (`X`) take the same return, so a kill you missed or his `/runbook new` never reaches your log. The two logs then split runs differently.
     - It lasts until you type `/runbook partner Mirel` by hand, and it comes back each time he changes character.
   - Repro: r2_known_char_stuck_stats_only.lua.

3. **Minor: a `/reload` forgets who was first heard in a bigger group. A dungeon-finder stranger is then paired when the group thins to two, and their whole run moves into your Together line (cycle 3 #10 again).**
   - Code: Sync.lua:973 (`bigGroup` is a file local, unlike `friendsMany`/`friendWait`) and 1004/1019.
   - Failure:
     - A stranger who runs RunBook is heard in a 5-player group. You `/reload`, three players leave, and the stranger's next message pairs them ("Strange also runs RunBook…").
     - Together shows their 4g (40000 copper). The control without the reload: no partner, Together 0.
     - The pairing is saved (account-wide), so your friend Mirel is not auto-paired in later groups.
   - Repro: r3_reload_forgets_biggroup.lua.

4. **Minor: a partner character saved without a realm (`partnerChars[name] = true`) matches a player of that name on any realm for good. A stranger's gold goes into Together, and their deaths and drops count as "you two's".**
   - Code:
     - Sync.lua:777: a partner set by hand without a realm is saved as `true`. The README's Quick start says to type `/runbook partner Mirel` before grouping.
     - Sync.lua:787: `true` passes any realm.
     - Sync.lua:1086-1089: a realm is learned only for the current partner, so a character that's no longer current keeps `true`.
     - The known-character branch (Sync.lua:1046-1049) and IsDuo (Track.lua:1062, realm-less) then accept any namesake.
   - Failure:
     - `/runbook partner Mirel` before grouping. Mirel turns up on Kelalt, and you type `/runbook partner Kelalt alt`.
     - Next day, in a dungeon-finder group with Kelalt and a stranger Mirel-Other, the stranger's 2g 50s goes into `run.partners.Mirel`.
     - Together's partner share is 26000 copper (truth 1000), and `IsDuo("Mirel")` is true.
     - This breaks "nothing a non-partner sends can change your run".
   - Repro: r5_unknown_realm_char_namesake_leak.lua.

5. **Minor: entries in `run.partners` without a realm are filed by the wrong realm at `/runbook start` after `end`. This shows one player twice in the group view, and with a namesake it keeps a non-partner in Together.**
   - Code:
     - Sync.lua:500-504: `e.realm` is written only for the current partner's own S message while a run is going.
     - Sync.lua:1049: a known character's entry never gets one.
     - Sync.lua:829-841: an entry promoted from the group view (auto-pick, or by hand) has none until the partner's next S.
     - Run.lua:643: MoveParts doesn't carry it across a split either.
     - At RUN_REOPEN, Sync.lua:1191 calls ReconcilePartners without `oldChars`, so Sync.lua:823-825 falls back to the *new* partner's realm for that name, or to none.
     - Also at Sync.lua:839-840: when `run.partners[name]` already exists, the matching group entry is deleted, not kept.
   - Failure, variant (a): your partner Mirel-Other (another realm) was followed onto his alt Kelbox, so Kelbox is your partner and Mirel-Other is a known character. The next day both are online:
     - Mirel-Other's numbers go into `run.partners.Mirel` by the known-character route, with no realm.
     - You `end`, `partner Guildie`, `start`. The entry is filed as "Mirel", his next message opens "Mirel-Other", and the group view shows 1g 20s for 70s of real gold, with 4 players for 3 (r4).
   - Failure, variant (b): a cross-realm friend auto-picked at the 35-second decision. You `end` before their next message, change partner, then `start`. The group view shows them as two players, with 3 "with RunBook" for 2 (r7 b).
   - Failure, variant (c), with a namesake:
     - Friend Mirel (your realm) is auto-picked. You `end`, then set `/runbook partner Mirel-Other`, then `start`.
     - Mirel's 40s stays in Together as the new partner's, and Mirel-Other's own group entry is deleted.
     - Together's partner share is 4900 copper (truth ≤ 900) (r7 a).
   - Repros: r4_known_char_no_realm_reopen.lua (set up through a real follow) and r7_promoted_entry_no_realm_reopen.lua. Fuzz trials 43 and 185 (seed 1) hit variant (c) on their own.

6. **Minor: a realm typed in lower case (`/runbook partner mirel-other`, or your own realm as `mirel-realm`) is saved as typed, and the group view then counts that player twice after a partner change.**
   - Code:
     - Commands.lua:465 prefers the typed realm over the group unit's (`realm = realm or unitRealm or …`), so `partnerRealm = "other"`.
     - IsPartnerChar and the message check fold case, so sync itself works.
     - `ns.GroupKey` (Sync.lua:755) compares realms as raw strings. The entry demoted at a partner change is filed as "Mirel-other" (or "Mirel-realm"), and the player's next message uses "Mirel-Other" (or "Mirel").
     - The same mismatch hits the waited-friend lookup at Sync.lua:958, so a waited-on friend set this way loses what they sent meanwhile.
   - Failure: `partner mirel-other`, he makes 50s, then `partner Guildie`, and his next message is 60s.
     - Group keys are "Mirel-Other" and "Mirel-other". Group gold is 1g 10s (truth 60s), with 3 players with numbers (truth 2).
     - The same happens with your own realm typed in lower case.
     - The control (realm typed as shown) is correct.
   - Repro: r6_lowercase_realm_typed.lua.

## Checked and found sound (no finding)
- The cycle 4 fixes hold on the paths they test:
  - reopen when the partner changes just before `start`;
  - a cross-realm partner demoted mid-run (via `oldChars`);
  - a friend first heard in a bigger group is paired in a two-person group (fresh lookup), and a stranger gets the "2:" note once;
  - a future `friendWait` is dropped;
  - `partnerChars` is capped at 20 without wiping;
  - two characters side by side are both counted;
  - a bare name prefers your realm, and `Name-Realm` picks;
  - a namesake switch is someone else.
- `alt` parsing: see Scope.
- The two-person fresh lookup is one FriendInfo call per message, over a two-unit group: no cost issue.
- Non-partner messages other than S never reach a handler. Group parts are created only on the run in progress. The per-player caps (4 parts, 4 saved totals) and the 40-player cap held under the fuzz.
- Version: nobody on another version is picked (two-person, TICK, follow).
- Secret sender, prefix, text and group size return early.
- Missing friend APIs leave only the two-person rule.


## Fixes (after the audit was recorded)

**Structural change (fixes #1, #5 and the class behind them):** a player now has one identity, `ns.GroupKey(name, realm)`, for everything kept between messages: saved totals, final words and moved amounts. That holds whether their numbers are your partner's or in the group view.
- The gate passes it into the S handler (`msgIdent`/`msgRealm`; held messages set it too).
- Every partner or group entry keeps the realm of its messages (`entry.realm`).
- RUN_REOPEN recounts each entry by that identity. Moving an entry between partner and group view never loses or mixes its totals.
- A namesake from another realm has another identity, so it shares nothing with your partner. This replaces the "~name" prefix.
- The `oldChars` path from cycle 4 became dead and was removed.

Other fixes:

2. **Known character of your partner's.** Its stats count only while your partner's current character is online with you. Otherwise, a message from it follows your partner there (same person), so drops, notes and kills are taken.
3. **"First heard in a bigger group".** This is kept in `VulcanRunBookCharDB.bigGroup` (checked; at most 80 names), so it survives a `/reload`. It's forgotten once you're out of a group, like `friendsMany`.
4. **A partner character saved without a realm** counts as being on your realm. The exception is your partner whose realm isn't known yet: whoever is heard first, as before.
6. **`/runbook partner name-realm`.** The realm is the game's spelling when they're in your group. `GroupKey` compares realms case-insensitively.

**Tests:** tests_group.lua, "Audit cycle 5" section, 5 groups (plus a cross-realm reopen gap and a GroupKey check).

**Mutations:**
- 16 updated or added; all caught.
- 2 dropped as equivalent after the change: reconcile before or after the recount, and old characters' realms (removed).

All suites pass.
