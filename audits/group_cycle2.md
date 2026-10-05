# Group feature audit cycle 2 (fresh agent, recorded before fixes)

**Scope.** Read in full: audits/group_cycle1.md; RunBook/Sync.lua 1-1028 (focus: FRIEND_WAIT/FriendHeard/TICK 31-62, UpdatePart 388-487, ApplyStats/GroupStats 497-585, GroupKey/PartnerChanged/SetPartner 778-815, CHAT_MSG_ADDON gate 817-917, RUN_START/RUN_REOPEN 965-1012); RunBook/Track.lua 1-175 (GroupUnits, SenderInGroup, SenderUnit, FriendInfo, PartnerInGroup); RunBook/Group.lua 1-135; RunBook/Run.lua 495-520 (Finish clears startTotals), 600-690 (MoveSince, MoveParts, PartnerFoundReset), 740-800 (SplitAtResume), 1080-1105 (reopen); RunBook/Data.lua 140-235 (FixRun group/partners/startTotals), 395-405 (partnerTag), 633-645, 694-735 (Lite); RunBook/Commands.lua 140-200 (check), 420-470 (group, partner); RunBook/UI.lua 195-240; RunBook/History.lua 180-195, 325-335, 451-460; RunBook/Export.lua 60-125; RunBook/Util.lua 143-160, 220-240; README.md 1-30, 80-140, 180-262; tests/harness.lua (whole), duo.lua, duo_common.lua, tests_group.lua 1-120. Ran: tests_group.lua (147 passed, 0 failed), tests_group_duo.lua (9 passed, 0 failed), 7 repro scripts and 2 scratch checks under /tmp/claude-0/grp_c2/ (a 39-player hostile flood of random starts/values/finals: caps held at 4 parts/player and 4 totals/player, no errors, your run untouched; CSV header and row have the same field count). Could not reach: the real client (real CHAT_MSG_ADDON sender format, whether group GUIDs/names are secret in Forever instances, whether GetAccountInfoByGUID fills `isFriend`, what GetNumGroupMembers says while you're between groups); run.sh and the mutation suite (not run, per instructions); render cost of the History window on a 40-player message stream.

**Counts.** critical 0 / major 4 / minor 3. All 7 confirmed by a repro.

## Findings

1. **Major: a friend running an older or newer RunBook is paired at once in any group, skipping the 35-second wait and the several-friends rule.** Sync.lua:848-871. When `friend` is true but `current` is false (protocol ≠ 3), neither the friend branch (849) nor the non-friend branch (856) is taken, so control falls through to the old two-person line `ns.SetPartner(name, realm, sender)` (871). Sync is then off between you anyway (version notice), so the pairing does nothing useful and only blocks the real partner.
   - Failure: a 5-player group with your guildmate (friends list, an outdated RunBook) and Mirel (Battle.net friend, up to date). The guildmate's first message makes him your partner right away ("Guildie also runs RunBook…" followed by "Guildie runs an older RunBook, so sync is off"). Mirel's numbers go to the group view, with "your sync partner is Guildie". In a raid, the Mirel line isn't printed (size > 5). The pairing is saved, so it persists across sessions.
   - Repro: r1_oldversion_friend_instant.lua (partner=Guildie after one ver-2 message; Mirel's 9s goes to the group view).

2. **Major: a friend heard just before you leave the group becomes your partner after you've left.** Sync.lua:50 counts a friend as "still in your group" through `ns.SenderInGroup(f.sender)`. Track.lua:63-81 returns `not readable`, which is true when the group has no readable others, and that includes having no group at all. Secret names in an instance trip the same check.
   - Failure: a dungeon-finder group with a guildmate on your friends list. The group breaks up (or you leave) within 35 seconds of his first message. When the window closes you're alone, and he's made your partner anyway ("Guildie (a friend of yours) also runs RunBook"). This is saved. Later, you and Mirel in a 3-player group: Mirel only reaches the group view, with "your sync partner is Guildie".
   - Repro: r2_left_group_still_paired.lua (SenderInGroup is true while solo; partner=Guildie).

3. **Major: in a raid, a friend whose first message arrives after the 35-second window is dropped with no word; the cycle 1 #3 failure still happens.** Sync.lua:43-61 decides on the friends heard in the first 35 seconds. A client sends only while it has a run, so a raid member who zones in later (summoned, still flying in) is heard too late. After the pick, their messages take the "another player" branch (Sync.lua:887-898), whose note prints only when `size <= 5`.
   - Failure: Molten Core with your guildmate (friends list) and Mirel (Battle.net). The guildmate is inside first; Mirel arrives 50 seconds later. The guildmate is paired and announced, and the guildmate's `/runbook new` will restart your raid run. Mirel's gold goes only to the group view, and nothing is printed about him.
   - Repro: r3_raid_late_friend_silent.lua (partner=Guildie, "Mirel's 8g went to: group view", and only the guildmate's pairing line printed).

4. **Major: after you correct a wrong auto-pick mid-run with `/runbook partner <name>` (the fix the pairing line itself suggests), the wrongly picked friend's gold stays in your Together line, your saved run, and your together stats.** Sync.lua:789-810 (`ns.PartnerChanged`) moves the new partner's group entry into `run.partners`, but leaves the old partner's entry there. UI.lua:198-219, History.lua:180-186, Export.lua `partner_gold_copper` and `ns.PartnersGold` all sum every entry in `run.partners`. A non-partner's numbers then sit in your totals, which breaks the promise.
   - Failure: continuing #3, you type `/runbook partner Mirel`. `run.partners` becomes `Guildie=5000 Mirel=900`, so Together shows 59s, of which 50s is the guildmate's. `/runbook end` saves both entries into history.
   - Repro: r5_fix_wrong_pick_leaves_old_partner.lua.

5. **Minor: a former partner who stays in your group is counted twice in the group view.** After a partner change (`/runbook partner off`, or switching as in #4), the old partner's frozen entry stays in `run.partners`. Their next S message (Sync.lua:888, `Others()`) creates a new `run.group` entry. It has no "~name" start totals, so when their run began with yours it counts from their run's start. GroupRows (Group.lua:41-52) lists both entries, and GroupTotals adds both together. The result feeds the live-window "Group (n with RunBook)" line, the Group tab, the run details and the CSV `group_*` columns, with no warning.
   - Failure (partner off): rows "Mirel: 15 silver" and "Mirel (partner): 10 silver", "3 with RunBook" (2 in truth), and "All of you: 25 silver" (15s in truth).
   - Failure (#4 flow): "Guildie: 70 silver" plus "Guildie (partner): 50 silver", giving "All of you: 1g 29s" when the truth is 79s.
   - Repros: r4_partner_off_double_count.lua, r5_fix_wrong_pick_leaves_old_partner.lua.

6. **Minor: "none is picked until `/runbook partner off`" doesn't survive a `/reload`.** `friendsMany` (Sync.lua:36) and `friendWait` are file locals. After a reload, the first friend heard in the next 35 seconds is picked, even with several friends still in the raid (for example, one is on a loading screen). The README (Duo sync) promises otherwise.
   - Repro: r3b_reload_forgets_several.lua (partner=nil before the reload, then partner=Guildie after it; Mirel is still in the raid).

7. **Minor: a friend's drops, notes, kills and `/runbook new` sent during the 35-second wait are thrown away and never recovered.** While the friend isn't yet your partner, only S messages are kept (Sync.lua:843-852, `Others()`). D/N/B/X are dropped, and none is resent. Where the client hides other players' loot lines, sync is the only source of their drops. The README's Quick start ("you pair up on your own … about half a minute after you're both in a run") doesn't say the first half minute is lost.
   - Failure: you, Mirel (friends list) and a pug. Mirel loots a blue 20 seconds in and writes a note. After pairing, your run has neither the blue nor that note; a later note does arrive.
   - Repro: r6_window_drops_lost.lua (drops "none", notes only "second note").

## Checked and found sound (no finding)
- Cycle 1 fixes hold:
  - A cross-realm namesake of a friend isn't a friend: FriendInfo uses the bare name only on your realm.
  - The "~name" state keeps a group namesake away from your partner's moved/finals/totals.
  - GroupKey carries the realm.
  - The CSV group gold is to the copper.
  - Alt-follow pauses while your partner's own character is in the group.
  - The check line reports hidden GUIDs.
- Non-partner messages other than S never reach a handler. Group parts are created only on the run in progress. History runs take no growth after they end. Nothing in the non-partner path calls RejoinCopy or partnerKills, or writes your run's own fields.
- Caps under a hostile 39-player flood: at most 4 parts per player and 4 saved totals per player. Malformed, negative and out-of-range numbers are rejected. With only 39 others, the 200-total cap can't push out your partner's current entry.
- RUN_REOPEN rebases group parts under "~". MoveParts carries group parts on a split or a partner-found reset. Finish clears startTotals. FixRun drops a damaged group table or parts, and players beyond 40.
- A damaged `partnerTag`, or one saved without a partner, is dropped on load.
- The two-person rule, the friend wait being cleared by any partner change, and the friend leaving the group (with names readable) all behave as documented.
- WorthKeeping, stats and best times read only `partners` and your own fields. Lite runs carry no group data, and export covers only full runs.

## Fixes (after the audit was recorded)

1. **A friend on another version** gets the version notice and is never picked. It no longer falls through to the two-person rule.
2. **Pairing needs a group:** the decision is made only while you're in a group (`InGroup()`). A broken group picks nobody.
3. **Notes in raids:** a friend heard after one was picked gets the "your sync partner is X" line, in raids too. Strangers still get at most the one raid note.
4. **Changing partner mid-run:** the old partner's entry in your run moves to the group view (`ns.PartnerChanged(sender, old)`). It's no longer in Together, the partner CSV columns or the duo stats. This applies to `/runbook partner X`, `partner off` and an automatic pick. Following your partner onto another character keeps the first character's numbers (`SetPartner(..., keepOld)`).
5. **No double counting:** the demoted entry keeps its parts, so the former partner's later messages continue it.
6. **Several friends:** this is saved in `VulcanRunBookCharDB.friendsMany`, so it survives a `/reload`. It's cleared when you leave the group (and by a partner change).
7. **Held messages:** a friend's non-stats messages during the wait (at most 50) are handled once they're picked, and dropped if they aren't.

**README:** the Duo sync section says all of the above.

**Tests** (tests_group.lua, "Audit cycle 2"): another version; leaving the group; a raid note; a mid-run change; partner off; an alt mid-run; several friends over a reload, and leaving the group; held messages and the cap of 50.

**Mutations:** 12 new, and all mutations are caught. All suites pass.
