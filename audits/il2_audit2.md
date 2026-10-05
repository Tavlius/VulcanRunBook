# Improvement loop 2 — audit 2 (real client, performance, resources), recorded before changes
Scope: all addon files, TOC, Bindings, harness/duo read; API/events/templates checked against
warcraft.wiki.gg, Blizzard UI source (Gethe/wow-ui-source), wowforeverguides; perf/size probe
(200 full + 2,000 short runs), raid probe, realm probe. Not reached: real client, GlobalStrings,
real EditBox/layout cache/chat restrictions, Forever's live interface number.

No defect that breaks the addon on 12.x found (templates, events, enums, secret wrapping, taint ok).
D1 MED SavedVariables size: 3.4 MB account file + 3.5 MB per-character backup (full mirror);
   ~110 ms parse + ~105 ms merge per login; short-form runs ~1 KB each; drops store full links.
D2 minor ProcessBags scans all bags on every bag change even with no run; SetMoneyWindow
   baseline twice per close (MERCHANT_CLOSED + PLAYER_INTERACTION_MANAGER_FRAME_HIDE).
D3 minor Sync.lua:34 retries only result codes 3/8/11; 5 (NotInGroup) and 9 (GeneralError)
   drop the message at once.
T1 MED mock has no GetNormalizedRealmName; run.char is "Tavlius" not "Tavlius-Realm"; the
   SenderInGroup realm compare is never exercised (probe: behaviour correct).
Risks: 88 KB CSV in one EditBox (no byte limit, HighlightText before Show/SetFocus); TOC 16001
   is the beta value; layout cache may override saved position (no SetDontSavePosition);
   CHAT_MSG_ADDON may become secret inside instances; /runbook report say needs a hardware event
   and multi-line sends; Bindings category="ADDONS" unverified; ERR_TOO_MANY_INSTANCES may not
   exist; plain() ignores secret tables, OutsideWorld not pcall-wrapped.
Mock looser than client: no-op frame methods, never-secret unit/map APIs, no throttle model,
   no hardware-event rule, UTC date, ticker ignores interval, no EditBox limits.
Questions: is the full backup still needed (beta bug confirmed?); per-boss detail past 200 runs;
   full links vs id+quality; check InChatMessagingLockdown before sending; stale alt backup
   resurrecting deleted runs past 500 deletions; SAY delivery; ENCOUNTER_* in 5-mans; paged
   export; why scan bags outside runs; realistic mock defaults.
