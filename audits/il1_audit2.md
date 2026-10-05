# Improvement loop 1 — audit 2 (real client / hostile input), recorded before changes
A MED Saved runs only partly validated (startedAt, serverEnd, savedServer, id, members, drops.q/name/who/link, char.run.leftAt/lastIn): one bad field breaks history window / load. CONFIRMED.
B LOW-MED CHAT_MSG_ADDON channel unchecked; whisper from Mirel-OtherRealm runs X/R/P. CONFIRMED.
C LOW Partner boss names not cleaned (link escapes, length). CONFIRMED.
D LOW Drop message numbers: NaN/inf/fractional accepted. CONFIRMED.
E LOW English fallback "too many instances" matches LFG queue error. CONFIRMED.
F MED Classic cap is 5/hour AND 30/day, per realm; only hour tracked, realms pooled. DEPENDS.
G LOW Older SendAddonMessage returns boolean false on throttle -> dropped. DEPENDS.
H LOW Korean reset string grammar code |1;; may break pattern. DEPENDS.
I LOW Hidden-loot bag dip (stack split on cursor) counted as loot. CONFIRMED in mock.
J LOW Notes/boss names truncated after a long/Cyrillic header -> logs differ. INSPECTION.
K LOW /runbook check silent on party name / dead-state readability. INSPECTION.
L LOW Group change while outside = new copy in Classic, ignored. INSPECTION.
Questions: who receives reset msg; name match; which event carries too-many; party identity secrecy; cross-zone GetBestMapForUnit; raid lockout ID; own pet GUID copy field; saved size; VulcanRunBookDB collision; partner trust; error cap hides later errors; auto partner from one-off group; byte vs char cuts; EditBox limits; mixed locales; soulstone in fights.
