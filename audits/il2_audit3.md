# Improvement loop 2 — audit 3 (players' experience), recorded before changes
Scope: README, Commands, Export in full; UI/History views; Track death/money/XP; Sync pairing
and send; Run login/summary; ran an evening (two clients), ~110 odd commands, level-60 and
40-player raid, AFK and next-day login, best-clear, money. Not reached: real client, real
delays, SM/DM wings, Auctionator, alts, 200/2,000-run limits, key bindings.

P1 MAJOR a split-off 2-boss leftover (35 min away, then 2 bosses) becomes "New best clear 6:05"
   and anchors best/avg/splits from then on (also after end+back in, a late-found reset, or
   joining a group in progress).
P2 minor README: "pairs you up in your first two-person group (you'll get a message)" - the
   message only comes once you enter a dungeon (stats sent only while a run exists).
P3 minor live window: You 2s + Mirel 3s = Together 6s (floored parts, exact total); rates in copper.
P4 minor one blue drop -> 29g/hr at 5 min; raid BoP epics at vendor value inflate gold/hr.
P5 minor bare /runbook sync and /runbook auto toggle instead of showing; README silent.
P6 minor partner rate drifts while both are paused (UI adds up to 30 s "since" to paused partner).
P7 minor raid detail "Group: 40 players, with Tavlius, Mirel" lists the viewer; README says only
   your two deaths are shown in the history, detail shows "+77 deaths of other players".
P8 minor report party/raid while solo sends anyway; help lists "instance", README doesn't.
P9 minor lowercase typed boss name ("rhahk'zor") sticks and becomes the final-boss name.
P10 minor noise: "0.0 deaths/run", "You: 0c (coin 0c, loot 0c)", cap line always shown, 14-line check.
Critiques/questions: AFK inside counts on the clock; next-day login inside keeps the run (does
   Forever eject from a reset copy?); hunter pet deaths untracked; /runbook delete has no
   confirm; gold is gross not net; best ignores route/skips; README long for phone; raid live
   window ~21 lines; CSV formula injection from notes; partner drops not links in reports;
   30-min timeout vs selling breaks; auto-pairing permanent (first 2-person group wins).
