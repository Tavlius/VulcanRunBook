# IL1 audit cycle 4 (recorded before fixes)
1 minor Naming an unnamed kill (key then name; partner's press + your name; game naming a mark) skips the "died here before" (copy kill) check.
2 minor Saved partners table with a non-string key breaks the live window and details.
3 minor Short-form boss with a non-number id breaks stats.
4 minor Saved resumeSnap missing fields: a split resets the clock and errors; saved reopenSnap of the wrong type errors after /runbook start.
Also: fuzz_cap oracle didn't disable the 24-hour window (fixed in the fuzzer).
