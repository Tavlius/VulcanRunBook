# IL3 audit cycle 4 (fresh agent, recorded before fixes)
Scope: README, il3 plan/cycles, UI/History/Export/Commands/Data/Util/Bindings/TOC in full, Run
nearly all, Sync 1-300 and 450-845, Track output/unboss/marks/notes/drops; run.sh green; a solo
first evening and a duo evening; duo hand-marking; ~80 hostile command inputs; instance cap
scenarios; deaths-line fuzz (3,000 cases). Not reached: real rendering (pixel widths, copy box),
logout delivery, throttle, INSTANCE_CHAT/SAY, ENCOUNTER_END in Forever; Sync 300-450 and Track's
death/wipe/bag code skimmed.
Counts: critical 0, major 0, minor 2 (confirmed).
1. minor README:124-125 vs Commands.lua:527-531 - `/runbook clear yes` (what the README table and
   help tell you to type) wipes every character's runs with no warning; only bare `clear` warns.
2. minor History.lua:80-86/186/243-245 - history and Dungeons tab rates floor the copper; the live
   window rounds: the same run shows 3g 17s/hr live and 3g 16s/hr in the history.

## Fixes (after the record above)
- 1: `clear yes` with more than one character asks once more (15 s), naming how many characters;
  the reply says it cleared all of them; README says it asks again.
- 2: history details and the Dungeons tab round rates with ns.ShownMoney, as the live window does.
- Tests: 2 groups (tests_il3 104 checks), 2 mutations; tests_round2 types clear yes twice for two
  characters. run.sh green.
