# Group feature audit cycle 3 (fresh agent, recorded before fixes)

**Scope.**
- Read in full:
  - audits/group_cycle1.md and group_cycle2.md;
  - RunBook/Sync.lua 1-1066 (focus: UpdatePart 358-468, S/ApplyStats/GroupStats 483-566, FriendHeard/TICK 744-791, GroupKey/PartnerChanged/SetPartner 793-847, CHAT_MSG_ADDON gate 853-954, RUN_START/RUN_REOPEN 1003-1050);
  - RunBook/Group.lua 1-135.
- Read in part:
  - RunBook/Track.lua 1-200 (GroupUnits, SenderInGroup, SenderUnit, FriendInfo, PartnerInGroup) and 1040-1100 (IsDuo, IsRunDuo, KeepDrop);
  - RunBook/Commands.lua 140-200 (check) and 410-470 (group, partner);
  - RunBook/Data.lua 190-232 (FixRun group/partners), 380-420 (partnerTag) and 630-700 (PartnerGold, PartnersGold, DeathCount, DropCounts);
  - RunBook/Run.lua 200-225 (WorthKeeping), 600-740 (MoveSince, MoveParts, PartnerFoundReset, RunSummary) and 1054-1105 (ManualEnd/ManualStart reopen);
  - RunBook/UI.lua 190-245; RunBook/History.lua 160-215 and 430-460; RunBook/Export.lua 60-130;
  - RunBook/Util.lua (plain, Call, PlayerName, ShortName, SameName, IsPlayerUnit);
  - README.md 10-30, 78-100, 120-135 and 178-240;
  - tests/tests_group.lua 1-200, 640-end and its case list.
- Also read in full: tests/harness.lua, duo.lua, duo_common.lua and tests_group_duo.lua.
- Ran:
  - tests_group.lua: 185 passed, 0 failed.
  - tests_group_duo.lua: 9 passed, 0 failed.
  - 11 repro scripts and 1 scratch fuzz under /tmp/claude-0/grp_c3/. The fuzz sent 400 random and malformed D/N/B/P/X/R/Z messages and S messages from a 39-player raid during a friend wait, with corrupt `friendsMany` values ("yes", 1, a table, true, false) and an empty saved `partnerTag`. It found no errors, your own coin was untouched, and the group view stayed at 40 players or fewer.
- Could not reach:
  - The real client. These points are unverified there:
    - that a logged-out party member stays in the group as offline, as in live WoW (finding 2 assumes it);
    - whether names are hidden (secret) in Forever instances (finding 9 depends on it);
    - the LFG GetNumGroupMembers category;
    - real message timing.
  - run.sh and the mutation suite (not run, per instructions).
  - Two-client runs of these flows. All repros are single-client, with hand-built messages.

**Counts.** critical 0 / major 3 / minor 7. All 10 confirmed by a repro. Number 9 is confirmed in the mock only and depends on hidden names.

## Findings

1. **Major: `/runbook end`, then a partner change, then `/runbook start` reopens the run with the old partner still in your Together line, and counts them twice in the group view.**
   - Code:
     - Sync.lua:814-822: `ns.PartnerChanged` only demotes and promotes in `ns.run`, which is nil between end and start.
     - Run.lua:1074-1102: ManualStart reopens the ended run as it was.
     - Sync.lua:1024-1050: RUN_REOPEN rebases group parts from the "~name" totals, but the old partner's totals were saved under the partner key.
   - Failure:
     - Guildie is your partner and makes 50s. You `/runbook end`, `/runbook partner Mirel`, then `/runbook start`.
     - The reopened run keeps `partners.Guildie = 5000`, so Together shows "Guildie: 50 silver, Mirel: 9 silver, Together: 59 silver" while your partner is Mirel.
     - Guildie's next message opens a new group part that counts his whole run (6000, with no base). The group rows then read "Guildie: 6000, Guildie (partner): 5000", and GroupTotals is 11900 when the truth is 6900.
     - This also breaks the README line "neither does `/runbook start` after `end`".
     - `partner off` between end and start does the same: a Together line with no partner.
   - Repro: r1_reopen_after_partner_change.lua.

2. **Major: following your partner onto another character fails in the usual relog flow, and the chat line's fix drops the main's numbers from Together.**
   - Code:
     - Track.lua:148-155: `ns.PartnerInGroup` counts the partner's character as "in your group" even when it's offline (no UnitIsConnected check).
     - Sync.lua:917: the follow is skipped whenever PartnerInGroup is true.
   - Failure:
     - Mirel logs out of his main mid-run. The main stays in the party, offline. You invite his alt Kelalt (same BattleTag).
     - Kelalt's messages go to the group view ("group: Kelalt=800"), with the line "Kelalt also runs RunBook; your sync partner is Mirel. (/runbook partner Kelalt to switch.)".
     - Typing that command demotes Mirel's numbers to the group view (Commands.lua passes `old`, see #4). Together drops from 18s to 8s, with no word.
     - The documented follow ("unless your partner's character is in your group too") never happens while the offline main is listed.
   - Repro: r2_offline_main_blocks_follow.lua.

3. **Major: after your partner is followed onto an alt mid-run, a partner change or `partner off` demotes only the alt. The first character's numbers stay in Together.**
   - Code:
     - Sync.lua:843-846: `SetPartner(..., keepOld)` leaves `partners.Mirel` in place.
     - Sync.lua:815-822: a later `PartnerChanged(nil, old)` moves only `old.name` (Kelalt).
   - Failure:
     - You followed Mirel onto Kelalt, so the run's partners are Mirel=1000 and Kelalt=300.
     - `/runbook partner Guildie` leaves partners Guildie=2000 and Mirel=1000 (Together share 3000, of which 1000 is a non-partner's).
     - `/runbook partner off` then leaves "Mirel: 10 silver / Together: 10 silver" on the live window with no partner set. That gold is also saved into the run, the CSV partner columns and the duo stats.
   - Repro: r10_followed_alt_then_change.lua.

4. **Minor: switching by hand between two characters of the same BattleTag, as the addon's own lines suggest, demotes the other character's numbers.**
   - Code: Commands.lua:443-469 always passes `old`. The follow line itself says "(/runbook partner Mirel to switch back.)" (Sync.lua:922-923).
   - Failure: after the automatic follow, Together is 13s (Mirel 10s + Kelalt 3s). Typing the suggested `/runbook partner Mirel` moves Kelalt's 3s to the group view, so Together is 10s. It's the same person, and the automatic switch keeps both.
   - Repro: r3_switch_back_hint_demotes.lua (and #2).

5. **Minor: a friend's drops, notes and kills held during the 35-second wait are discarded on three paths.** The README promises "what they sent meanwhile … is taken then".
   - Code: Sync.lua:812 (`PartnerChanged` sets `friendWait = nil` without replaying) and Sync.lua:750 (a file local).
   - The three paths:
     - The pug leaves, so the group is now two people, and the friend's next message pairs at once (Sync.lua:908).
     - You type `/runbook partner Mirel` during the wait.
     - A `/reload` during the wait.
   - Failure: each repro ends with partner=Mirel, but drops 0 and notes 0. The blue and the note sent in the first seconds are gone for good.
   - Repros: r4_wait_then_two_person_drops_held.lua (first two paths), r4b_reload_during_wait.lua.

6. **Minor: after `partner off` mid-run, the old partner's gold moves to the group view, but their deaths and drops still count as "you two's".**
   - Code: Track.lua:1057-1063. With no partner set, `IsDuo` falls back to `ns.partnersSeen`, which still holds the old partner. That feeds IsRunDuo in DeathCount and DropCounts (Data.lua:676, 685), the raid drop filter in the live window (UI.lua:233) and KeepDrop.
   - Failure: in Molten Core after `partner off`, Guildie is only in the group view, yet his death shows on the live window ("1 death (Guildie)"). His epic is listed under the raid's "you two" drops, and DeathCount and DropCounts count both. Those counts go into the saved run's stats.
   - Repro: r7_partner_off_still_duo.lua.

7. **Minor: a friend on another RunBook version is picked in a two-person group, though the README says "never picked".**
   - Code: Sync.lua:893-910. In a two-person group the friend check is skipped, so `SetPartner` runs before the version check at Sync.lua:943.
   - Failure:
     - Two back-to-back lines: "Guildie also runs RunBook, so you'll see each other's gold…" then "Guildie runs an older RunBook, so sync is off".
     - The pairing is saved. In the next group (with current-version friend Mirel and two pugs), Mirel is never auto-picked, and his gold goes only to the group view.
   - Repro: r5_oldversion_two_person.lua.

8. **Minor: two friends with the same name on different realms count as one friend.** One is picked instead of "several", and the other one's held messages are replayed as your partner's.
   - Code: Sync.lua:755-758 (`friendWait.list` is keyed by short name; `f.sender` and `f.realm` are overwritten) and Sync.lua:769-776.
   - Failure: friends Mirel (your realm) and Mirel-Other are in a raid. The partner becomes Mirel of realm Other, yet the note sent by Mirel of your realm ("note from Mirel of Realm") is written into your run as your partner's note. A non-partner changed your run.
   - Repro: r6_two_friends_same_name.lua.

9. **Minor (mock only; depends on hidden names): with names hidden in an instance, cycle 1 #6 comes back.** Two characters of one BattleTag side by side flip your partner on every message.
   - Code:
     - Track.lua:148-155: PartnerInGroup reads names via UnitShortName and returns false when they're secret.
     - Sync.lua:917-919: the follow check then uses the 5-minute FriendInfo cache. In a raid, that cache was filled with both tags by the note check at Sync.lua:930.
   - Failure: in the raid, the partner sequence is Kelbox,Mirel,Kelbox,Mirel,Kelbox,Mirel, with 6 "is on … now" lines.
   - Repro: r8_secret_names_flipflop.lua.

10. **Minor: when a dungeon-finder group thins out, the last other player (a stranger who runs RunBook) is paired mid-run, and their whole run moves from the group view into your Together line.**
    - Code: Sync.lua:908 (two-person rule) and PartnerChanged's promotion at Sync.lua:828-837.
    - Failure:
      - "Strange: 4g 1s / Together: 4g 1s" appears for gold made before the pairing.
      - The pairing is saved, so in the next group friend Mirel stays in the group view and is never auto-picked.
      - The README says "first RunBook user you're in a two-person group with (from their first message)". It doesn't cover a group that shrinks to two, or the stranger's earlier numbers counting.
    - Repro: r9_lfg_tail_stranger.lua.

## Checked and found sound (no finding)
- The cycle 1 and cycle 2 fixes hold:
  - A cross-realm namesake isn't a friend.
  - The "~name" state is kept apart.
  - Pairing needs a group.
  - A version mismatch blocks a pick in groups of 3 or more.
  - The raid note goes to late friends.
  - Demotion on a mid-run change keeps one row per player.
  - `friendsMany` survives a reload and is cleared on leaving the group.
  - Held messages are capped at 50 and dropped when nobody is picked.
- A corrupt `friendsMany` (string, number or table) is treated as false and causes no errors. A saved `partnerTag` without a partner, or not a string, is dropped.
- Non-partner messages other than S never reach a handler. Group parts are created only on the run in progress. History runs take no growth from group messages. Under the fuzz, the per-player part and totals caps held, and nothing reached your coin.
- Held-message replay runs each message under `pcall`. Messages for ended runs go through the handlers' existing loot-time and ENDED_GRACE checks.

## Fixes (after the audit was recorded)

The partner is now handled as a person, not a single name.

1. **Your partner's characters** are saved as `db.partnerChars` (name -> realm). Following the same BattleTag onto another character adds it. Setting someone else by hand, or `partner off`, starts the list over. Switching back by hand to one of your partner's own characters keeps the list (#4).
2. **`ns.ReconcilePartners(run)`** keeps only your partner's characters in a run's partner numbers. Anyone else's go to the group view, and your partner's numbers in the group view come back. It runs on every partner change (for the run in progress) and on RUN_REOPEN. That covers end, change, start (#1) and an alt then a change (#3).
3. **`IsDuo`** counts all your partner's characters. A partner change drops the others from `partnersSeen`, so after `partner off` their deaths and drops aren't "you two's" (#6).
4. **Alt-follow guard (`PartnerHere`):** your partner's character must be in your group and connected (#2). When the group's names can't be read, the guard asks whether they were heard from in the last 40 seconds (#9).
5. **The friend wait** is saved in `VulcanRunBookCharDB.friendWait` and checked on load, so it survives a `/reload`. Whatever way the waited-on friend becomes your partner (two-person rule, set by hand, or picked), what they sent meanwhile is taken, at most 50 (#5).
6. **Version check:** nobody on another version is picked, in a two-person group too (#7).
7. **Waited-on friends** are keyed by name and realm, so two friends with one name are two friends (#8).
8. **Not picked when down to two:** someone heard in a bigger group who isn't a friend isn't picked when it's down to two (#10).

**Data:** `partnerChars` is checked on load (string keys, `true` or realm-string values, at most 10).

**Tests:** tests_group.lua "Audit cycle 3", 10 groups.

**Mutations:** the pairing set was rewritten for the new code, 29 entries. All mutations are caught.
- Equivalent, so not mutated: the held-entry type check in `Wait()`. The replay is `pcall`'d and ignores unknown kinds.

All suites pass.
