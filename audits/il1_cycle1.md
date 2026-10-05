# IL1 audit cycle 1 (recorded before fixes)
1 MAJOR NameMatch merges distinct bosses ("Sneed" / "Sneed's Shredder", Barovs): drops kills, false splits, canonicalises wrong, final pins wrong.
2 minor Hourly cap line hidden once within 5 of daily cap.
3 minor SM wing return (SplitAtResume wing) drops remembered copy kills.
4 minor SenderInGroup: own unit makes names "readable", so trust fallback never runs; partner messages dropped if party names secret.
5 minor README "Ended a run by mistake -> /runbook start" false after leaving.
6 minor Settings not validated on load (point, scale, quality, priceSource, finals).
Also: fuzz2 "run lost across relog" for never-entered (entryOnEntry) runs: oracle disagrees with the round-25 keep rule.
