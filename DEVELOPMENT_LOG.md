# Development log
- 2026-11-23: Environment is Windows with no Xcode/swift toolchain and no video file found. Scaffolded XcodeGen project and Swift sources. No build possible.
- 2026-11-24: CI now compiles, builds the IPA and screenshots. Added pill, tinted vinyl, label title, auto-hiding controls (screenshot-verified on iPhone). Studied Atrium's Duo breakpoints (width/height based, no pixel sizes). Added Settings, Spotify token restore, LayoutMetrics, 4 unit tests (pass in CI). Skipped lock-screen and widgets with reasons in PROJECT_STATUS.md.

## Review round (Opus reviewer + advisor)
- Reviewer found 14 issues; fixed: Spotify HTTP status handling, token-error classification, auth session retention, overlapping polls, disconnect race, stale artwork, controls invisible at real launch, disc reset on rotation, empty PUT/POST body, local-file ids, double-connect guard.
- Advisor caught a regression I introduced (`p.disconnect()` in failure paths deleted the Keychain refresh token); removed.
- Viewed CI screenshots (iPhone portrait/hidden/landscape, iPad landscape): layout unchanged and correct. Duo `-frame` captures still unusable.
- Not fixed: see "Known open issues" in PROJECT_STATUS.md.
