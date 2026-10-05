# Improvement loop 3 — audit 3 (sync protocol under load and hostility), recorded before changes
Scope: Sync.lua, README, harnesses, sync parts of Track/Run/Commands/Data/Util; 9 scripts with a
throttle model (burst 10, 1/s, 11 in fights): edge values, fast dungeon, 40-player raid farming,
reload with a full queue, leaving the group, end-of-run race, drop dedupe at 6 delays, hostility,
long names. Spec: /tmp/claude-0/il3_a3/protocol.md. Not reached: real throttle/result codes,
logout delivery, loading-screen delivery, two clients on one account, older builds, run.sh.
Load: fast dungeon queue <=1, current within 1 s; raid q0 60+60 drops: queue ~9, empty 9 s after.
D1 minor Sync:29/737-739/802-805 queue in memory only: /reload, logout or leaving the group loses
   queued drops/notes/kills/new/split for good (6 of 40 drops after a reload; 7 after leaving).
D2 minor Sync:546-547 (and :406) late drops for an ended run judged by arrival, not loot time:
   19 of 24 kept while the gold counts all 24.
D3 low Sync:675/705, Commands:415 a same-name player from another realm counts as the partner
   (coin summed, his /runbook new restarts your run).
D4 low Commands:423 non-ASCII first letter not capitalised; check looks up the partner by exact
   name ("none this session", no kills line).
D5 cosmetic Sync:573 partner boss names cut to 40 bytes, yours not (Cyrillic final boss name differs).
D6 low README Quick start: auto-pairing happens on any message in any two-person group (in or out
   of a dungeon), saved account-wide; a stranger can become the partner.
Critiques: no acks/sequence/resend; throttle model unverified; 11 vs throw in fights; loading-screen
delivery; IsInGroup false on loading screens wipes the queue?; partner stored account-wide by short
name; SenderInGroup trusts all when unreadable; ended grace by arrival; queue-full drops oldest
non-stats (could be X/P); stats can overtake kills; version notice only on protocol number;
oversized non-note messages dropped silently; no two-client throttle tests; auto-pairing permanent.
