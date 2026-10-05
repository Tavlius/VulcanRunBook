# Group feature audit cycle 4 (fresh agent, recorded before fixes)

**Scope.**
- Read in full:
  - audits/group_cycle1.md, group_cycle2.md and group_cycle3.md;
  - RunBook/Sync.lua 1-120 and 184-1170 (RunFrom/SameRun/FindRun, UpdatePart, S/ApplyStats/GroupStats, the N/D/B/P/X/R handlers, GroupKey, PartnerChars, IsPartnerChar, PartnerHere, ReconcilePartners, Wait/FriendHeard/TakeHeld, the TICK decision, PartnerChanged/SetPartner, the CHAT_MSG_ADDON gate, RUN_START/RUN_REOPEN);
  - RunBook/Group.lua 1-135;
  - tests/harness.lua, and tests_group.lua 1-80 and 679-1044 (the cycle 2 and 3 groups).
- Read in part:
  - RunBook/Track.lua 30-175 (GroupUnits, SenderInGroup, SenderUnit, FriendInfo, PartnerInGroup) and 1040-1110 (IsDuo, IsRunDuo, KeepDrop, NoteDrop);
  - RunBook/Commands.lua 140-200 (check) and 405-470 (group, partner);
  - RunBook/Data.lua 150-240 (FixRun group/partners), 280-340 and 455-480 (copy merge, `modified`), 396-411 (partner, partnerTag, partnerChars);
  - RunBook/Run.lua 600-700 (MoveSince, MoveParts, PartnerFoundReset, EndRun);
  - RunBook/Util.lua 10-40, 140-160, 218-240 (plain, Call, PlayerName, ShortName, Touch, SameName, IsPlayerUnit);
  - RunBook/UI.lua 190-245; History.lua (the group and IsRunDuo lines); Export.lua (the group columns);
  - README.md 1-30, 75-140 and 180-230.
- Ran:
  - tests_group.lua: 236 passed, 0 failed.
  - tests_group_duo.lua: 9 passed, 0 failed.
  - 8 repro scripts under /tmp/claude-0/grp_c4/ (r1-r8, with common.lua).
  - A scratch fuzz, fuzz_partner_changes.lua: 300 trials of 25 random steps (S messages from Mirel, a cross-realm namesake Mirel-Other, Guildie and a pug; `partner X/off`; `end`; `start`; ticks).
    - It found no Lua errors.
    - It found no player in `run.partners` that IsPartnerChar rejects.
    - It flagged 22 group-view overcounts, all from findings 3 and 5 below.
- Could not reach:
  - The real client. These points are unverified there:
    - whether group GUIDs are hidden in Forever instances (finding 2's first variant and finding 6 depend on it);
    - the real sender format of CHAT_MSG_ADDON for same-realm players;
    - real message timing.
  - Two-client runs of these flows. All repros are single-client, with hand-built messages.
  - run.sh and the mutation suite (not run, per instructions).

**Counts.** critical 0 / major 2 / minor 7. All 9 are confirmed by a repro. Finding 2's hidden-GUID variant and finding 6 are confirmed in the mock only; each needs the follow or friend check to fail (hidden GUIDs, or a partner with no readable BattleTag). Finding 2's "friend added later" variant does not depend on that.

## Findings

1. **Major: after `/runbook end`, changing partner to someone who was in the group view, then `/runbook start`, puts everything the new partner made while your run was ended into your Together line.**
   - Code:
     - Sync.lua:1128: RUN_REOPEN first calls `ReconcilePartners`, which moves the group entry into `run.partners`.
     - Sync.lua:1135-1150: the rebase then looks the entry up under its new field's state (`totals["Mirel@start"]`). The totals during the gap were saved under the group state (`"~Mirel@start"`), so nothing is found and the part keeps its old base.
   - Failure:
     - Guildie is your partner. Mirel is in the group view with 9s. You `/runbook end`.
     - Mirel plays on to 5g. You type `/runbook partner Mirel`, then `/runbook start`.
     - Mirel's next message (5g 1s) makes Together 5g 1s. The README says "a run you reopened gets nothing your partner made while it was ended", so the truth is 10s.
     - The control (Mirel as partner throughout) gives 10s.
     - The same lookup misses for the demoted old partner, whose gap growth goes into the group view.
   - Repro: r2_reopen_promoted_counts_gap.lua (Together 50100, truth 1000).

2. **Major: a friend first heard in a bigger group, and not recognised as a friend there, is never paired in a two-person group for the rest of the session, and nothing is said.**
   - Code: Sync.lua:976-977, 992-993.
     - In a two-person group the friend check is skipped (`friend = not two and ...`).
     - `bigGroup[key]` alone blocks the pick. It was set when the friend check failed in the bigger group.
     - The pug note was already used up there (`otherNoticed`), so nothing is printed now.
   - The README promises a friend is paired "in a group of any size", and the two-person rule excludes only those who are "not a friend".
   - Failure, variant 1:
     - Mirel, a Battle.net friend, is heard in a dungeon-finder 5-man where GUIDs are hidden, so he isn't recognised as a friend.
     - The two of you then form a party and run Shadowfang Keep.
     - After 5 messages there is no partner and Together is 0. His 50s is in the group view, and no line mentions him.
   - Failure, variant 2 (no hidden GUIDs needed): you add a pug as a friend after the dungeon, then duo with him. He is still never paired. In a 3-player group he would be.
   - Repro: r3_biggroup_blocks_friend_duo.lua.

3. **Minor: a cross-realm partner who is demoted (another partner set, or `partner off`) is filed in the group view under the bare name, so their next message opens a second row. They are counted twice.**
   - Code:
     - Sync.lua:800-807: `chars` is read after PartnerChanged has reset `partnerChars`, so `chars[name]` is nil for the demoted player and the key is `GroupKey(name, nil)`.
     - Sync.lua:969 and 972: their later messages use `GroupKey(name, "Other")`.
   - This brings back cycle 2 #5 for partners from another realm.
   - Failure:
     - Rows read "Mirel-Other: 60s, Mirel: 50s". "All of you" is 1g 10s when the truth is 60s, and the player count is 3 instead of 2.
     - The live "Group (n with RunBook)" line, the Group tab and the CSV `group_*` columns all carry it.
     - The bare key can also collide with a same-realm player named Mirel. The demoted entry is then dropped, or two people share one row.
   - Repro: r1_crossrealm_partner_demote_double.lua.

4. **Minor: switching by hand to a namesake on another realm is treated as "the same person", so the old partner's numbers stay in Together and the new partner's are added to them.**
   - Code:
     - Commands.lua:445: `same = ns.IsPartnerChar(typed)` checks the short name only.
     - Sync.lua:766-769: IsPartnerChar ignores realms.
     - With `samePerson`, `partnerChars` keeps `Mirel=Realm` while `partnerRealm` becomes Other. The old BattleTag is kept too.
   - Failure:
     - Your partner is Mirel, from your realm, with 40s.
     - `/runbook partner Mirel-Other`, then Mirel-Other sends 9s.
     - Together is 49s (truth 9s), and the old Mirel still counts as "you two's" for deaths and drops.
     - A non-partner's numbers are in your Together line, which breaks the promise.
   - Repro: r7_namesake_switch_is_same_person.lua, part (b).

5. **Minor: `/runbook partner Mirel` with both your realm's Mirel and a Mirel-Other in the group picks Mirel-Other.**
   - Code: Commands.lua:456-461. The realm loop takes any unit named Mirel with a non-empty realm, and only a cross-realm unit returns one.
   - Failure: in a raid with both, typing your brother's name pairs you with the stranger. Mirel-Other's 7s goes into Together, and your brother's 40s goes to the group view.
   - Repro: r7_namesake_switch_is_same_person.lua, part (a). The fuzz traces with `p:Mirel` show this as well.

6. **Minor: when the automatic follow can't run, the addon's own hint ("/runbook partner Kelalt to switch") moves your partner's earlier numbers out of Together.**
   - Code:
     - Sync.lua:1029-1032: the hint is printed.
     - Commands.lua:445: a character not yet in `partnerChars` is "someone else". The list and the BattleTag are reset, and ReconcilePartners demotes Mirel.
     - The follow can fail with hidden GUIDs (no tag readable), or for a partner who is a friends-list friend only.
   - Failure: Together drops from 10s (Mirel) to 4s (Kelalt only). The true figure is 14s, since "their characters count as one partner". Mirel is no longer "you two's", and the saved BattleTag is lost, even though it was known.
   - Repro: r8_hint_switch_unknown_alt_demotes.lua.

7. **Minor: one of your partner's known characters that isn't the current one is put in the group view while the current one is online, so it counts twice and its new gold misses Together.**
   - Code: Sync.lua:1011-1034. Only the current partner name is accepted, and a known partner character takes the "another player" branch (`Others()`) whenever PartnerHere is true.
   - Failure:
     - Mirel's main disconnects, so his second account's Kelbox is followed. The main then reconnects, and both are online.
     - Rows read "Mirel: 16s, Mirel (partner): 10s, Kelbox (partner): 3s". "All of you" is 29s when the truth is 19s.
     - Together stays at 13s. The 6s Mirel made after the follow is missing, though the README says what each makes "stays in your Together line".
     - The same happens briefly when names are hidden and the main is back within 40 seconds of the alt's last message.
   - Repro: r6_known_char_back_double.lua.

8. **Minor: `partnerChars` has no cap at runtime, but the load check drops the whole table once it holds more than 10 characters.**
   - Code: Sync.lua:758-763 and 1020 add without limit. Data.lua:404-410 sets `ok = false` at n > 10 and clears the table.
   - Failure:
     - After following your partner onto an 11th character, a `/reload` forgets all of them. IsDuo for Mirel is now false.
     - At the next follow, ReconcilePartners moves 9s of the partner's own gold from Together to the group view (Together goes from 11s to 2s).
   - Repro: r5_partnerchars_cap_wipes.lua.

9. **Minor: a saved `friendWait` whose `first` is in the future passes the load check and never ends, so friend pairing is off for good on that character.**
   - Code: Sync.lua:837 checks only `type(first) == "number"`, and Sync.lua:884 returns before the partner and group checks. A future `first` comes from a damaged file or the PC clock being set back, and `math.huge` passes too.
   - Failure:
     - A lone friend in a 3-player group is never picked.
     - The wait also outlives every group: after 20 more groups it holds 21 friends and 1000 held messages, all saved, and nothing clears it.
   - Repro: r4_friendwait_future_first.lua.

## Checked and found sound (no finding)
- The cycle 3 fixes hold on the paths they cover:
  - ReconcilePartners on a mid-run change, partner off, and end-change-start, for same-realm players. Mid-run promotion keeps one continuous part, and mid-run demotion continues under the same key.
  - IsDuo after `partner off`; PartnerHere for an offline main.
  - Version checks in the two-person path and the TICK pick.
  - Waited-on friends keyed by realm.
  - Held messages taken by every route (two-person, by hand, reload), capped at 50, and dropped when nobody is picked.
- Non-partner messages other than S never reach a handler. RunFrom has no side effects. Group parts are created only on the run in progress, and history runs take no growth from group messages.
- MoveParts carries group parts on splits and partner-found resets. FixRun drops a damaged group table or parts, and players beyond 40.
- The totals caps stay bounded: each message adds at most one total and removes at most one.
- The copy merge's `modified` can be touched by a group message only within ENDED_GRACE or on a correction down, and both saved copies get it at the same logout.
- The fuzz found no errors from random partner changes, end/start and namesakes. Every `run.partners` key passes IsPartnerChar after each step (an invariant that is itself name-only; see finding 4).

## Fixes (after the audit was recorded)

1. **RUN_REOPEN order.** RUN_REOPEN now recounts each entry where its numbers were first, then calls ReconcilePartners. A partner moved in from the group view no longer brings what they made while the run was ended.
2. **Friends after a bigger group.** In a two-person group, someone first heard in a bigger group is asked about again, with a fresh lookup. A friend (even one added since) is picked at once. A stranger gets the "If that's your duo partner" line, with its own once-only note.
3. **Realm kept on the way out.** A partner moved to the group view keeps their realm. It comes from the realm saved on their entry (`e.realm`, set from their messages), or from the partner characters before the change. Their key is the same as their next message's, so they aren't counted twice.
4. **Same name, another realm.** `IsPartnerChar(name, realm)` checks the realm, so a same-name player on another realm is someone else.
5. **`/runbook partner <name>`** prefers your realm's player when two by that name are in the group. A realm in what you typed picks that realm's player. Your realm is saved as theirs, so the other one's first message isn't taken for your partner.
6. **The same person, by hand.**
   - `/runbook partner <name>` keeps your partner's characters when the new name has your partner's BattleTag.
   - `/runbook partner <name> alt` says it's them when no BattleTag can be read.
   - When your partner isn't here, the switch hint suggests `alt`.
7. **Two characters online at once.** Another known character of your partner's, online at the same time as the one you follow, sends numbers that count as your partner's. Only its stats are used.
8. **partnerChars cap.** At most 20 while playing (one makes room). The load check drops only bad or extra entries, never the whole list, and never your partner.
9. **friendWait.** A saved wait whose start is in the future (or not a number) is dropped.

**Tests:** tests_group.lua, "Audit cycle 4" section, 10 groups.

**Mutations:** 16 new, and 3 snippets updated. All caught. mutate_group.py now also counts a suite crash as caught, even when other groups failed first.

**README:** documents `alt` and Name-Realm.

All suites pass.
