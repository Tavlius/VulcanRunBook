# Round 25 audit findings (recorded before fixes)

Auditors: state/data (A), real-client (B), user-facing (C). B: no defects.

1. MAJOR (A1) Partner's kills/drops in the new copy stay in your old run when a reset is
   found later (PartnerFoundReset moves only numbers; SplitAtResume moves by visit, and
   synced items while you were outside carry the old visit).
2. MAJOR (C1) A run created for a partner's reset or /runbook new (entryOnEntry, never
   entered) is saved as a 0:00 run with their kills, drops and gold; counts in stats,
   clears and the final-boss vote.
3. minor (A2) Partner's /runbook new while you run back as a ghost loses the ghost state
   in the new paused run.
4. minor (A3) A run whose map ID or difficulty stayed unreadable the whole run is filed
   under its own stats row.
5. minor (A4) A stale full copy in an alt's backup beats a newer short-form copy on merge
   (unboss/notes lost); Lite() drops unbossed.
6. minor (C2) Note lines in run details lose the double space after the time.
