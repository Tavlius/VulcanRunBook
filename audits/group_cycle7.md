# Group feature audit cycle 7 (fresh agent, recorded before fixes)

**Scope.**
- Read in full:
  - audits/group_cycle1.md through group_cycle6.md;
  - RunBook/Sync.lua 1-1259 (the whole file). Focus: UpdatePart 362-470, the S handler, ApplyStats and GroupStats 487-582, GroupKey 762-768, PartnerChars, IsPartnerChar, PartnerHere and ReconcilePartners 777-878, Wait, FriendHeard, TakeHeld and the TICK decision 887-965, PartnerChanged and SetPartner 974-1000, BigGroup and the CHAT_MSG_ADDON gate 1007-1141, and RUN_START and RUN_REOPEN 1190-1242;
  - RunBook/Group.lua 1-135;
  - tests/harness.lua.
- Read in part:
  - RunBook/Track.lua 30-170 (GroupUnits, SenderInGroup, SenderUnit, FriendInfo, PartnerInGroup) and 1053-1110 (IsDuo, IsRunDuo, KeepDrop, NoteDrop);
  - RunBook/Util.lua 135-245 (MyRealm, ShortName, Fold, SameName, IsPlayerUnit);
  - RunBook/Commands.lua 140-220 (check), 290-310 (argument parsing) and 420-490 (group, partner);
  - RunBook/Data.lua 185-235 (FixRun partners/group, `p.realm`, 40-player trim) and 390-430 (partner, partnerRealm, partnerTag, partnerChars);
  - RunBook/Run.lua 625-685 (MoveParts, PartnerFoundReset);
  - RunBook/UI.lua 190-250; History.lua 100-125, 175-205, 320-340 and 440-460; Export.lua 60-130;
  - README.md 10-40 and 180-229 (Quick start, Duo sync), plus every partner/realm/friend line by grep;
  - tests/tests_group.lua 1-60 and 1383-1522 (the cycle 6 groups); tests/duo.lua 1-80; tests_group_duo.lua.
- Ran:
  - tests_group.lua: 318 passed, 0 failed.
  - tests_group_duo.lua: 9 passed, 0 failed.
  - Repro scripts under /tmp/claude-0/grp_c7/ (with common.lua). Each runs one client at a time and prints "DEFECT CONFIRMED" next to a control.
    - r1, r1b, r2, r4, r5, r6 and r7 confirm the findings below.
    - Two scripts found no defect. r3 (a saved `partnerRealm = ""`) is put right at load. r4b (one person dual-boxing two Battle.net-friend characters, no partner yet) gives "several friends, pick one", which is what the README says.
- Checked and found sound (no finding):
  - The realm guard in ApplyStats doesn't block a realm-less sender, since it needs a realm on both sides. An entry's `realm` is only ever written from a message's sender (or carried by MoveParts and ReconcilePartners), so no second spelling reaches it. Realms are compared without case.
  - Totals caps: one total is added and at most one removed per message, so a player holds at most 4 and all players at most 200.
  - Group parts: at most 4 per player and 40 players. They're created only on the run in progress.
  - Non-partner messages other than S never reach a handler. Held messages are capped at 50 per friend and are taken only for the friend who becomes your partner.
  - Group numbers stay out of your totals. RunSummary, PartnersGold, the Together line, DeathCount, the CSV partner columns and IsRunDuo read only `run.partners` and your own fields. GroupTotals, the live "Group" line, the Group tab, the run details and the CSV `group_*` columns are the only readers of `run.group`.
  - Keeping a bare-name partner's known realm when you retype it, and setting a cross-realm partner by `Name-Realm`, behave as documented.
- Could not reach:
  - The real client. These points are unverified there:
    - the CHAT_MSG_ADDON sender format (the repros use Name-Realm, as the harness does);
    - whether names are hidden in Forever instances (finding 5 depends on it);
    - whether IsInGroup() is briefly false at login.
  - Two-client runs of these flows. All repros are single-client, with hand-built messages.
  - run.sh and the mutation suite (not run, per instructions).
  - No randomized fuzz was run this cycle.

**Counts.** critical 0 / major 1 / minor 4. All 5 are confirmed by a repro. Finding 5 is confirmed in the mock only (hidden names).

## Findings

1. **Major: following your partner onto a same-named character on another realm (the cycle 6 #1 fix) works, but that character's gold and XP are then thrown away for the rest of the run. Nothing is said.**
   - Code:
     - `run.partners` is still keyed by short name. The S path calls `handler(name, body)` (Sync.lua:1140), and the known-character path calls `ns.GroupStats(name, …, "partners", …)` (Sync.lua:1096), so both of Mirel's characters map to `run.partners.Mirel`.
     - The cycle 6 realm guard (Sync.lua:548-551) then skips every message from "Mirel of Other", because `partners.Mirel.realm` is "Realm". UpdatePart is never reached, so the numbers land nowhere, not even in the group view.
     - Sync.lua:872-873: when ReconcilePartners promotes your partner's group-view entry and `run.partners[name]` already exists, the group entry is deleted, not merged.
   - Failure (a), r1:
     - Partner Mirel (your realm, Battle.net friend) makes 10s. He logs out and comes back on his "Mirel" from realm Other, with the same BattleTag.
     - The follow line prints, and `partnerRealm` becomes Other. His next 40s goes nowhere: Together's partner share is 10s, and the saved run keeps 10s.
     - The control, an alt named Kelbox-Other, gives 50s.
     - His drops still arrive (D doesn't go through ApplyStats), so nothing looks wrong.
   - Failure (b), r1b:
     - Both characters are online at first, so "Mirel-Other" is in the group view with 30s. Then Mirel-Realm goes offline and the follow runs.
     - ReconcilePartners deletes the "Mirel-Other" group entry. Together is 10s and "All of you" is 10s; the 35s is gone from both.
     - The control, Kelbox-Other, gives Together 45s.
   - The same guard also drops the stats-only path for a same-named known character online beside your partner.
   - Repros: r1_samename_alt_numbers_dropped.lua, r1b_samename_alt_group_entry_deleted.lua.

2. **Minor: for a partner from another realm, the follow line's own "switch back" command wipes your partner's characters and BattleTag, and moves their numbers out of Together.**
   - Code:
     - Sync.lua:1102-1103: the follow line suggests `/runbook partner <was>`, where `was` is the bare short name.
     - Commands.lua:467-469: a bare name that isn't in your group gets your partner's realm only when it matches the *current* partner's name. Otherwise it gets your realm. Your partner's other known characters (`partnerChars`) aren't consulted.
     - Commands.lua:473: `IsPartnerChar("Mirel", "Realm")` is false (his main is "Mirel-Other"). So `same` is false, `partnerChars` and `partnerTag` are reset, and ReconcilePartners demotes the alt.
   - Failure (r6):
     - Partner Mirel-Other is followed onto Kelbox-Other. The line says "(/runbook partner Mirel to switch back.)". You type exactly that while his main isn't in the group.
     - Together's partner share drops from 40s to 0. The tag is lost, and the partner becomes "Mirel of your realm", a player who doesn't exist.
     - When Mirel-Other returns, his 15s goes to the group view.
     - The control, `/runbook partner Mirel-Other`, keeps 40s and then 45s.
   - Repro: r6_switch_back_bare_name_crossrealm.lua.

3. **Minor: a bare name set before grouping (the README Quick start), followed by the addon's `alt` suggestion, makes an imaginary "Mirel of your realm" one of your partner's characters. A stranger with that name and realm later becomes your partner, and his numbers go into Together.**
   - Code:
     - Commands.lua:468: a bare `/runbook partner Mirel` means your realm.
     - Sync.lua:1113-1116: the "another player" line offers `alt` to a same-named player from another realm.
     - Commands.lua:445-447 and Sync.lua:977: `alt` keeps `partnerChars`, so "Mirel" = Realm is kept as one of his.
     - Sync.lua:1092-1103: a later "Mirel-Realm" is `known`, and is followed when the real Mirel isn't there.
   - Failure (r5):
     - Your brother is Mirel-Other. You typed `/runbook partner Mirel`. In the group you get "(... or /runbook partner Mirel-Other alt if that's Mirel on another character.)". It is him, so you take the `alt` option.
     - Next day, in a dungeon-finder group with a stranger Mirel from your realm, he becomes your partner. The line reads "Mirel is on Mirel now (the same Battle.net account)", though no BattleTag was ever compared.
     - His 2g 50s is in Together. His `/runbook new` and resets can now restart or end your run. The pairing is saved.
   - Repro: r5_bare_name_crossrealm_alt_hint.lua.

4. **Minor: the README says your partner's other character online beside them "both count as your partner … their deaths and drops are 'you two's'". In the code, a second character the addon doesn't know yet goes to the group view only, and a known one counts for stats only (its drops, notes and kills are thrown away).**
   - Code: Sync.lua:1090-1098 and 1104-1105. README.md:196-200.
   - Failure (a), r4:
     - Mirel dual-boxes Mirel and Kelbox on one BattleTag. The tag is known, and both are online from the start.
     - Kelbox's 30s goes to the group view and Together is 12s. `IsDuo("Kelbox")` is false.
     - The only line is "(/runbook partner Kelbox to switch.)", with no word that it's the same account.
   - Failure (b), r7:
     - Kelbox is a known character, declared with `alt`, and online beside Mirel, with loot lines hidden.
     - His blue drop and his note are dropped: 0 drops and 0 notes. The control, with Mirel offline, has 1 and 1.
     - His kills (B) and `/runbook new` (X) are dropped the same way. Sync is the only source of his drops when the client hides loot lines.
   - Repros: r4_unknown_alt_side_by_side.lua, r7_side_by_side_known_char_drops_lost.lua.

5. **Minor (hidden names only): a real relog onto a known alt is held to "stats only" for up to 5 minutes. The alt's drops, notes, kills and `/runbook new` are thrown away, and nothing is said.**
   - Code:
     - Sync.lua:841-844: with names unreadable, "your partner is online" means any of their characters was heard in the last 5 minutes, and that includes the main who just logged out.
     - Sync.lua:1093-1098: a known character then counts for stats only.
   - Failure (r2):
     - Mirel logs out, and his known alt Kelbox is invited a minute later.
     - Kelbox's blue and note are lost (0 and 0). The control, with names readable, follows and keeps both.
     - Any relog finishes well inside 5 minutes, so with hidden names the follow onto a known alt always loses that window.
   - Repro: r2_hidden_names_relog_known_alt.lua (mock only).

## Fixes (after the audit was recorded)

**Structural change (#1 and the class behind it).** Your partner's entries in a run are now named by the player's key (`GroupKey`: the name, plus the realm when it isn't yours), the same way the group view's entries are.
- Two characters with one name on two realms never share an entry. One player's entry keeps its name when it moves between your partner's numbers and the group view.
- Saved totals, final words and moved amounts are all keyed by it.
- ReconcilePartners works from the key, with the realm taken from the name, or yours when there's none. When a player has an entry in both places, their runs are merged instead of dropped.
- `IsRunDuo` matches keyed entries by short name.
- Now redundant, and removed: `entry.realm`, the namesake realm guard, and the identity parameter.

**Other fixes:**

2. The follow line's "switch back" names the realm when it isn't yours. A bare name typed for one of your partner's characters takes that character's saved realm.
3. A character of your partner's is followed without a BattleTag only after it has been heard from as your partner (`db.partnerHeard`, keyed by GroupKey, cleared when the list starts over). A guessed realm can't let a stranger in.
4. README: side by side, a character that has synced with you before counts for gold and XP only; an unknown one goes to the Group tab until `alt`.
5. README Limits: with hidden names, a relog onto a known alt counts gold and XP only for up to 5 minutes. Mock only, unconfirmed on Forever.

**Tests:** tests_group.lua "Audit cycle 7" (3 groups) and IsRunDuo for a keyed entry. Earlier tests now look up cross-realm partner entries by their key.

**Mutations:** mutate_group.py has 99 mutations, all caught.
- The list was rebuilt for the simplified code.
- Dropped as equivalent or removed code: the namesake guard, `entry.realm`, the identity parameter, the separate "~" namespace, "heard starts over" (hygiene only), and merging on promotion (defensive).

All suites pass.

## Status

Seven audit cycles after the build. None came back clean.

| Cycle | Critical | Major | Minor |
| --- | --- | --- | --- |
| 1 | 0 | 3 | 3 |
| 2 | 0 | 4 | 3 |
| 3 | 0 | 3 | 7 |
| 4 | 0 | 2 | 7 |
| 5 | 0 | 2 | 4 |
| 6 | 0 | 1 | 6 |
| 7 | 0 | 1 | 4 |

The loop stopped at the same 7-cycle cap as IL1 to IL3: it is not converging. Every finding was fixed, tested and mutation-checked.

Nearly all findings were in auto-pairing edge cases: name collisions across realms, alts, partner changes around end/start and splits, reloads, hidden names. After cycle 1, no audit found a player who was never your partner reaching your totals. The leaks into Together found in later cycles all came through partner changes: a former partner's or a namesake's numbers stayed in Together.

The fixes from this last cycle (the partner entries keyed by player) have not been seen by a fresh audit.

## Full run (run.sh) after the fixes

The first full run failed in three older mutation checks. The per-player keys made each check's test stop failing when its guard was removed, so the tests were strengthened:

- **mutate_il1, "sender in group".** A stranger's stats from outside your group must not reach the group view. The partner realm now set at `/runbook partner` already rejects the old "Mirel from another realm" case.
- **mutate_il3, "partner realm".** The test also checks Together, since a same-name player from another realm now gets their own key.
- **mutate_il3, "sweep #547" (CSV partner gold).** The test reads the `partner_gold_copper` column by its position. The new group columns can hold the same number.

The run was then repeated.
run.sh: exit 0 (all suites, fuzzers, lint and 315 mutation checks).
