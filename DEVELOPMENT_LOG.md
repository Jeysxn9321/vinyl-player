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

## 2026-11-24 (vinyl artwork variants)
- New `Vinyl/Artwork/*` (models, Matching, MusicBrainz/CAA provider with rate limiter + backoff, Discogs proxy provider, ArtworkStore, ArtworkCenter, ArtworkSelectorView), `VinylTests/ArtworkTests.swift` + 4 recorded fixtures, `backend/discogs-proxy/`.
- PlayerModel owns an `ArtworkCenter`; `discLabel` feeds both `SpinningDisc`s; label overlay gestures (tap/swipe/long-press); utility-row button; Settings section; `-artwork` CI flag + screenshot.
- Unit tests pass in CI; nothing run on a device; Discogs never run live.

## 2026-11-24 to 2026-11-25 (rebuilt from git history; nothing below was run on a device)
- 11-24: Browse playlists/albums/songs with direct playback (Spotify + Apple Music), shuffle/repeat, seekable progress, drag-the-tonearm to play/pause, record and tonearm redesigns (portrait and landscape), queue view with artwork and jump-to-row, Apple Music search through the iTunes Search API fallback.
- 11-24: Vinyl artwork variants from MusicBrainz / Cover Art Archive, selector, optional Discogs (personal token in the Keychain, or your own proxy; Discogs never run live). Widgets: collection widget with typed albums, shared container diagnostics (no App Group under AltStore). Both services can stay connected and be switched in Settings.
- 11-24: Artist discography, album page, LRCLIB lyrics, Apple Music style lyrics screen, full-screen cover and landscape two-column lyrics.
- 11-25: Live Activity vinyl card with tonearm, tinted bar and timer.
- 11-25 (batch 1): sleep timer (keeps the screen on while armed because the app is suspended when locked), AirPlay button (Apple Music only), "Play next" / "Add to queue" from song rows. Reordering the queue was skipped: no verified safe API path.
- 11-25 (batch 2): save to library / Liked Songs, add to playlist, lyrics romanisation (system) and translation (iOS 18 Translation framework). Spotify scopes extended, older logins must reconnect.
- 11-25 (batch 3): estimated A/B sides in the album page (split by track count; labelled as an estimate), LRC parser fixed for CRLF and repeated timestamps, offline unit tests for the parser, side split and ID helpers.
