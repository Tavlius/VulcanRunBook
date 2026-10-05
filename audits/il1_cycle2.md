# IL1 audit cycle 2 (recorded before fixes)
1 MAJOR Infinite loop: PartnerFoundReset moves the known kill (st within 5 s before their entry), recursive AddBoss re-triggers forever. fuzz2 seed 118 hangs.
2 minor "Slot free again" printed while the daily cap is full; daily freeing never announced.
3 minor Typed names differing only in spaces/punctuation ("Van Cleef") count as different bosses across runs.
4 minor /runbook unboss doesn't undo the cap entry a mistaken mark added (copy-kill new copy); split flag missing on copy-kill split path.
5 minor Saved data: NaN in entries crashes load; pending item fields unchecked.
