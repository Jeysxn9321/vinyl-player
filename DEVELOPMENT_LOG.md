# Development log
- 2026-11-23: Environment is Windows with no Xcode/swift toolchain and no video file found. Scaffolded XcodeGen project and Swift sources. No build possible.
- 2026-11-24: CI now compiles, builds the IPA and screenshots. Added pill, tinted vinyl, label title, auto-hiding controls (screenshot-verified on iPhone). Studied Atrium's Duo breakpoints (width/height based, no pixel sizes). Added Settings, Spotify token restore, LayoutMetrics, 4 unit tests (pass in CI). Skipped lock-screen and widgets with reasons in PROJECT_STATUS.md.

## Review round (Opus reviewer + advisor)
- Reviewer found 14 issues; fixed: Spotify HTTP status handling, token-error classification, auth session retention, overlapping polls, disconnect race, stale artwork, controls invisible at real launch, disc reset on rotation, empty PUT/POST body, local-file ids, double-connect guard.
- Advisor caught a regression I introduced (`p.disconnect()` in failure paths deleted the Keychain refresh token); removed.
- Viewed CI screenshots (iPhone portrait/hidden/landscape, iPad landscape): layout unchanged and correct. Duo `-frame` captures still unusable.
- Not fixed: see "Known open issues" in PROJECT_STATUS.md.

## Rebuild round 1 (MD Vinyl direction)
Portrait became a full-width record with the real cover as label; vinyl colour presets; Spotify playlist browser (new scopes, Reconnect flow); user-supplied app icon. Advisor review caught: reconnect wiping the login, a scope guard that could loop, tonearm landing on the label. All fixed; CI screenshots for the browser sheet added. Still unverified on a device or with a real Spotify account.

## Round 2 (queue, stack, Xcode 27.2)
Added QueueView and the 3D playlist stack; moved CI to xcode-27 / Xcode 27.2; fixed Duo screenshots (two displays); limited CI usage after the minutes ran out and made the repo public. Demo screenshots checked; nothing tested with a real Spotify account or device.

## Round 3 (Live Activity, customisation)
Added the Live Activity extension, record patterns, effects and themes. Compiles in CI; nothing seen on a device.

## 2026-11-24 (labels, Apple Music library, widget)
- Label style/size prefs in `VinylDisc`/`SpinningDisc`; portrait now only shows the title on the label for the "Title" style.
- `AppleMusicProvider.library()/play(_:)`, `AppleMusicLibraryView`, `PlayerModel.appleMusic`, `-ambrowser` CI flag.
- `Shared/WidgetData.swift` (`WidgetSnapshot` in App Group defaults, `RecordWidgetView`), `LunaraRecordWidget` in the bundle, snapshot written from `LiveActivityController.sync`, `-widget` CI flag.
- Entitlements files + `ALTAppGroups` in both Info.plists. IPA build now prints `codesign -d --entitlements`: result was "not signed at all" for app and appex.
