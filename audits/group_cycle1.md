# Group feature audit cycle 1 (fresh agent, recorded before fixes)

**Scope.** Read in full: RunBook/Group.lua (1-129); RunBook/Sync.lua (1-970, with focus on UpdatePart 354-463, ApplyStats/GroupStats 497-561, PartnerChanged/SetPartner/CHAT_MSG_ADDON gate 738-858, RUN_START/RUN_REOPEN 920-955); RunBook/Track.lua 30-170 (GroupUnits, SenderInGroup, SenderUnit, FriendInfo, PartnerInGroup) and 1044-1064 (IsDuo/IsRunDuo); RunBook/Run.lua 200-225, 305-410, 600-800 (WorthKeeping, copies, MoveSince, MoveParts, PartnerFoundReset, RunSummary, SplitAtResume); RunBook/Data.lua 150-230 (FixRun group/partners), 380-420 (partnerTag validation), 625-720 (PartnerGold, Lite); RunBook/Commands.lua 140-190 (check), 410-455 (group, partner); RunBook/UI.lua 195-240; RunBook/History.lua 165-200, 320-335, 440-460; RunBook/Export.lua 66-124; README.md sections on Quick start, live window, Group tab, Duo sync, First-time check; tests/harness.lua (whole), duo.lua, duo_common.lua, tests_group.lua (case list + first 140 lines, 284-311), tests_group_duo.lua. Ran: tests_group.lua (115 passed, 0 failed), tests_group_duo.lua (9 passed, 0 failed), and 7 repro scripts under /tmp/claude-0/grp_c1/. Could not reach: the real client (whether UnitGUID of group members is secret in Forever instances, whether GetAccountInfoByGUID returns data for non-friends, real CHAT_MSG_ADDON sender format); run.sh and the mutation suite (not run, per instructions); timing/perf of a 40-player flood (not measurable in the mock).

**Counts.** critical 0 / major 3 / minor 3. All 6 confirmed by a repro.

## Findings

1. **Major: a stranger from another realm who has a friend's name is auto-paired as your partner.** Track.lua:127-131 (`ns.FriendInfo`) falls back to `C_FriendList.GetFriendInfo(ns.ShortName(sender))`. For a cross-realm sender "Mirel-Other", this looks up your same-realm friend "Mirel", so the stranger counts as a friend. Sync.lua:800-816 then makes them your partner. The README promises that "someone with the same name on another realm isn't taken for them".
   - Failure: your friend Mirel (your realm) isn't online. A dungeon-finder pug has Mirel-Other in it. His first message makes him your partner, with the line "(a friend of yours)". His gold goes into your Together line (the repro shows "Together: 2g 50s"). His /runbook new, resets and kills now reach your run. `partnerRealm=Other` is also saved, so your real friend Mirel is then treated as "another player".
   - Test gap: the mock's `IsFriend(guid)` also matches the short name (harness.lua, `c.friends[(n:match("^[^%-]+"))]`), which hides this bug. The real IsFriend matches the GUID exactly.
   - Repro: r1_crossrealm_friend_namesake.lua.

2. **Major: a non-partner's numbers leak into your partner's when they share a short name.** Your partner is cross-realm (Mirel-Other). A stranger named Mirel from your own realm is in the group. The stranger's group key is the bare "Mirel" (Sync.lua:793), and your partner's handler key is also "Mirel" (Sync.lua:857, `handler(name, body)`). The two paths share state:
   - (a) Sync.lua:752-756 (`ns.PartnerChanged`): `ns.SameName(key, name)` matches the stranger's group entry, so setting the partner mid-run (`/runbook partner Mirel-Other`) moves the stranger's numbers into `run.partners.Mirel`. Repro: the stranger's 4g plus the partner's 10s show as "Mirel: 4g 10s / Together: 4g 10s".
   - (b) With no partner change at all: `moved[sender]`, `finals[sender]` and `partnerTotals["Mirel@start"]` (Sync.lua:342-352, 423-433, 500-503) are keyed the same for both players. The stranger sends 90g, then a lower final (their log split their run). That puts 90g in `moved["Mirel"]`, and the partner's next new run is credited with it (Sync.lua:395-406). Repro: "Mirel: 90g / Together: 90g", where the partner's real share from now is 0.
   - Side effect: GroupRows (Group.lua:26) dedups the stranger's row away under the partner's, yet the live window still prints "Group (2 with RunBook): 90g".
   - This breaks the promise "nothing a non-partner sends can change your run".
   - Repros: r2_namesake_move_on_partner_set.lua, r2b_namesake_moved_leak.lua.

3. **Major: in a raid with several friends who run RunBook, the first message wins, and your real duo partner is dropped without a word.** Sync.lua:798-818 pairs with whichever friend's message arrives first. After that, Mirel's messages take the "other player" branch (Sync.lua:827-837), and its note is only printed when `size <= 5`. The pairing line names only the guildmate. Nothing in a raid says Mirel was skipped.
   - Failure: a raid with your guildmate (on your friends list) and Mirel (Battle.net friend). The guildmate's client sends first, so the guildmate becomes your partner and Mirel's 5g goes to the group view. The guildmate's later `/runbook new` (X message) then ends your raid run ("your run restarted by the guildmate: true", endReason=new). Each of you can also end up with a different, one-sided pairing.
   - Repro: r3_raid_first_friend_wins.lua.

4. **Minor: `/runbook check` says "Battle.net readable" when Battle.net pairing can't work.** Commands.lua:166-172 only tests whether the API functions exist. FriendInfo (Track.lua:110-112) needs a readable GUID from the group unit, and with hidden (secret) GUIDs it never calls GetAccountInfoByGUID. In that case a Battle.net-only friend is never paired, and their BattleTag is never learned, so the alt-following doesn't work either. Meanwhile, check prints "Friends: Battle.net readable, friends list readable", and the README tells the player to rely on that line. Repro: r4_check_claims_bnet_readable.lua (partner=nil).

5. **Minor: the CSV `group_gold_copper` column is rounded to the silver, unlike every other `*_copper` column.** Export.lua:100 uses GroupTotals → GroupRows, which uses `ns.ShownMoney` (Group.lua:35, 47). Repro: three players with 1s 49c each give `group_gold_copper = 300`, while the exact sum is 447. A spreadsheet summing coin + loot + partner_gold won't match the group column, and nothing says why. Repro: r5_csv_group_gold_rounded.lua.

6. **Minor: two characters on one BattleTag in the same group flip your partner on every message.** Sync.lua:823-830: when Mirel plays two characters at once (two game licenses on one Battle.net account, which Blizzard allows) and both are in your group, every message from the non-partner character switches the partner. Each switch prints "Mirel is on Kelbox now…" (5 lines in 6 messages) and re-runs PartnerChanged. Repro: r6_same_tag_two_chars_flipflop.lua (partner sequence Mirel,Kelbox,Mirel,Kelbox,Mirel,Kelbox).

## Checked and found sound (no finding)
- Non-partner messages other than S (D/N/B/P/X/R) are dropped. Group parts are created only on the run in progress.
- Caps hold: 40 players, 4 parts per player, and 4 saved totals per sender. Each message adds at most one total and removes at most one.
- Malformed and hostile numbers are rejected by `Numbers` (range, NaN, non-integer, negative).
- Lite runs drop the group data. RunSummary, WorthKeeping, DeathCount, DropCounts, stats and best times read only `partners` and your own fields.
- RUN_REOPEN rebases the group parts. MoveParts moves the group parts on a split. FixRun drops a non-table group, damaged parts, and players past 40.
- A damaged `partnerTag`, or one saved without a partner, is dropped on load. `/runbook partner off` clears the tag.
- Secret sender, prefix, text, GUID and group size are handled without errors.

## Fixes (after the audit was recorded)

1. **Friends list by name:** the bare name is used only when the sender is on your realm. A full "Name-Realm" lookup still works. The mocks now match exactly, like the real GUID lookups.
2. **Namesakes:**
   - The group view's state between messages (totals, final words, moved amounts) is kept under "~name", apart from your partner's.
   - `ns.GroupKey` names a player with their realm when it isn't yours.
   - Setting a partner moves only that very player's group entry, using their realm (or yours, when theirs isn't known).
   - The group rows never merge two keyed players; a name from the member list is only added when nobody by that name is listed.
3. **Several friends:** a friend is picked 35 seconds after the first one is heard, and only if they're the only friend still in your group who runs RunBook. With several, none is picked, and you're told the names. That holds until `/runbook partner off`.
4. **`/runbook check`:** when the group's GUIDs are hidden, it says "Battle.net not readable here (hidden players), friends list by name only".
5. **CSV:** `group_gold_copper` is to the copper (`ns.GroupTotals(run, true)`).
6. **Alt-follow:** not while your partner's own character is in your group.

**Tests** (in tests_group.lua, after "Audit cycle 1"):

- A cross-realm namesake of a friend.
- A friend on another realm, found by full name.
- Your partner's namesake from your realm.
- A namesake's final word never reaching your partner.
- Several friends, a friend who left, and partner off.
- Two characters of one Battle.net account side by side.
- The check line, and CSV copper.
- Group members' numbers from before your run.
- The existing friend tests now wait out the 35 seconds.

**Mutations:** mutate_group.py has 45 mutations, all caught. All suites pass.
