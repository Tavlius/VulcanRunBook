# RunBook: audit report

**Status: it works and every test passes, but the audits never converged.**
The stopping rule is two clean audits in a row. That never happened:

- **The audit rounds:** stopped after 25 rounds.
- **The improvement loops:** stopped after 7 cycles in each of 3 loops.
- **The auto-pairing and group-view feature:** stopped after 7 cycles.

Each time, I followed the "stop and escalate" rule instead of continuing. Findings shrank a lot over time. In the last 21 audit cycles there were 2 majors in total. Most findings now sit in rare duo edge cases, but they never reached zero.

**Recommendation:** more simulated audits will keep finding smaller edge cases. The most useful next step is a real session on Forever with `/runbook check`. See "Not reached" below.

## Phase 1: audit rounds 1-25

Three fresh reviewers looked at each round:

- **State and data:** wrong numbers, lost runs, errors.
- **Real client:** the API and the Midnight secret-value rules.
- **Player's view:** the windows, chat lines, commands and README.

| Rounds | Major | Minor | Where |
|---|---|---|---|
| 1-5 | (counts not kept) | | core tracking, UI, sync basics |
| 6-12 | 33 | ~103 | partner gold/XP, splits, wings, saved-data merge |
| 13-18 | 4 | ~48 | names, notes, marks, display widths |
| 19-25 | 6 | 39 | resets neither log saw, the partner split message |

## Phase 2: three improvement loops

Each loop ran in this order:

1. Three fresh audits.
2. A list of critiques and questions.
3. A plan.
4. The changes.
5. Tests.
6. Up to 7 audit cycles, one at a time, each by a new agent.

Every finding was written down before it was fixed. Every fix got a test. Each fix was then undone once to confirm its test fails (a mutation check).

| Loop | Critiques | Main changes | Findings per cycle (1-7) | Clean cycles |
|---|---|---|---|---|
| IL1 | 48 | sync trust rules, daily cap, boss-name snapping, saved-data checks | 6 (1 major), 5 (1 major), 4, 4, 5, 3, 4 | 0 |
| IL2 | 40+ | suites now fail the build, delayed-message test harness, kill counts in sync | 3, 3 (+2 borderline), 4, 4, 3, 2, 2 | 0 |
| IL3 | 35+ | mutation sweep, short-form runs deletable, sync queue survives logout, characters per realm | 4, 1, 1, 2, 3, 1, 6 (1 major) | 0 |

**IL3 cycle 7's major:**

- **The bug:** a raid week split over two nights made night 2 look like a new "best clear".
- **The fix:** a run that times out is now remembered. A raid stays known until the weekly reset.
- **Caveat:** these fixes are tested, but no fresh audit has looked at them.

**Why it doesn't converge:** most findings since round 19 are in one area. That area is working out a dungeon reset that neither log saw. The clues are things like a boss dying twice, a partner's run starting over, or a ghost return. Each rule that covers one case opens a narrower one. The rest of the addon has had only minor findings for many cycles: timing, cap, drops, gold, history, export and UI.

## Phase 3: auto-pairing and the group view

Added on request:

- **(A) Auto-pairing.** A friend who runs RunBook becomes your partner in any group, and your partner is followed onto their other characters.
- **(D) Group view.** A read-only Group view shows everyone in your group or raid.

The build was followed by 7 audit cycles, one at a time, each by a new agent. Records: `audits/group_cycle1-7.md`.

| Cycle | Major | Minor | Main area |
|---|---|---|---|
| 1 | 3 | 3 | cross-realm namesakes, several friends in a raid |
| 2 | 4 | 3 | the 35-second friend wait, mid-run partner changes |
| 3 | 3 | 7 | end/start around a partner change, alts |
| 4 | 2 | 7 | reopen recounts, namesakes, switch commands |
| 5 | 2 | 4 | identity of a player across partner/group (fixed by one key per player) |
| 6 | 1 | 6 | same-name characters on two realms |
| 7 | 1 | 4 | partner entries keyed by short name (fixed by keying them per player) |

**What held:**
- After cycle 1, no audit found a player who was never your partner reaching your gold, Together, stats or best times.
- The leaks found later all came through partner changes: a former partner's or a namesake's numbers staying in Together.
- Each cycle's fuzz found no Lua errors.

**Why it doesn't converge:** auto-pairing guesses who a player is from names, realms, BattleTags and timing. Each rule for one case opens a rarer one, the same pattern as the reset detection in Phase 2. Two structural changes cut a whole class each:
- one key per player for everything kept between messages (cycle 5);
- your partner's entries named by that key (cycle 7).

The last change has not had a fresh audit.

## Test coverage

- **Suites:** 35 suites, 2,297 checks (the group feature: 333 checks in `tests_group.lua`, plus a two-client suite). `tests/run.sh` runs them all, plus a syntax check and lint, in about 12 minutes.
  - Any failure fails the run. That was proven by planting a real defect.
- **Fuzzers:** 12 randomized fuzzers.
  - One client: lifecycle, cap, unreadable data.
  - Two clients, including delayed messages: kills, gold, drops, notes, copies.
- **Mutation checks:** 315 targeted mutations, across the round 25, IL1, IL2, IL3 and group scripts (99 of them for the group feature). Each one undoes a fix, and all are caught.
  - The scripts first confirm the unmutated suite is green.
- **Mutation sweep** (`tests/sweep/`, 600 random mutants, run twice):
  - 39% survived, then 36.5% after IL3's tests.
  - History.lua is still ~78%, mostly wording and layout of saved-run views. UI is ~46%.
  - So about a third of small random code changes still go unnoticed. That measures the limit of the tests, and it's stated here so the 2,297 checks aren't taken as complete. (The sweep wasn't re-run on the group feature.)

## Not reached (needs the real Forever client)

- Whether boss kill events fire in 5-player dungeons. If not, mark kills by hand.
- Whether loot messages are hidden inside dungeons.
- Whether addon messages are blocked or throw errors during boss fights. Also: delivery during loading screens, and throttling.
- The instance-cap error text, and whether a saved raid counts toward the cap.
- `C_DateAndTime.GetSecondsUntilWeeklyReset` on Forever. It's used for raid lockouts; without it, the 2-hour window applies.
- Whether a dungeon can be reset while a corpse is inside. This decides which return a split uses.
- Scarlet Monastery wing map IDs, real font widths, and a real spreadsheet opening the CSV.
- The friends APIs on Forever: `C_BattleNet.GetAccountInfoByGUID`, `C_FriendList.IsFriend`/`GetFriendInfo`, and whether group members' GUIDs and names are hidden inside instances. `/runbook check` shows "readable", "by name only" or "not available".
- The sender format of addon messages ("Name-Realm"), which the per-player keys rely on.

## Known limits (also in the README)

- A reset neither log sees is found only when a named boss dies twice. Until then, one run holds two copies. `/runbook new` fixes it by hand.
- With hand marks only, your partner's log can miss a reset nobody saw.
- `unboss` takes back a mistaken split's cap entry, but the two runs stay separate.
- **Group view.**
  - It shows gold and XP only for players who run RunBook with sync on.
  - Deaths and drops come from your own log, by short name.
  - Short-form runs don't keep it.
- **Auto-pairing.**
  - With several friends who run RunBook in one group, none is picked.
  - With players hidden inside, Battle.net friends can't be read, and a relog onto a known alt counts only gold and XP for up to 5 minutes.

## Where the records are

- `audits/`: every audit, written before its fixes.
  - `il1_*`, `il2_*`, `il3_*`, `group_cycle*`, `round25.md`.
  - The plans are `il*_plan.md`.
- `tests/`: the suites, fuzzers, mutation scripts and the sweep tool.
