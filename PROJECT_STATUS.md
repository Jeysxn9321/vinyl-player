# Project status

Written on Windows 11 with no Mac. GitHub Actions (macos-15) now **compiles the app, builds an unsigned IPA, and captures iPhone 16 Pro Max / iPad Pro 13" simulator screenshots** (`-demo` mode, sample data). Not yet verified: any real device, real Spotify/Apple Music accounts, audio, AltStore install. No iPhone Duo simulator exists; large-canvas layout is approximated with the iPad screenshots.

On a Mac: `brew install xcodegen && xcodegen && open Vinyl.xcodeproj`, add the MusicKit capability, set a team, build.

## Written (unverified)
- Shared model and provider protocol
- Apple Music provider (ApplicationMusicPlayer)
- Spotify provider (PKCE, Web API, 3 s polling; controls need Premium and an active device)
- Vinyl disc, tonearm, sleeve, spin driven by accumulated play time, controls, onboarding

## Not done
Widgets, Live Activity, custom lock-screen Now Playing (see below), real-device verification, AltStore install test.

## Notes
- Spotify clientID must be supplied from your own developer app.
- MusicKit cannot read the system Music app's playback, only this app's own queue.
- The Spotify Web API cannot be polled in the background.

## Video analysis (ref/sheet_1.png)
Landscape layout: square sleeve at left edge, record peeking out from behind its right edge (~18% hidden), tonearm pivoting top-right and swinging from near-vertical (rest) to angled over the record (playing). Background is a dark gradient tinted from the artwork; record label/colour follows the album (marbled cream, black with blue label). Only a small "Connecting to Spotify" pill at top; no visible controls. Source updated to match (since compiled in CI).

## Cloud build (no Mac)
`.github/workflows/build-ipa.yml` builds an unsigned IPA on a GitHub macOS runner; AltStore re-signs it on install. Needs the folder pushed to a GitHub repo. Risk: a free Apple ID may not be able to provision the MusicKit capability, so Apple Music may fail on-device; Spotify does not need it.

## Landscape / wide layout
`PlayerView` switches to side-by-side (record composition left, title/progress/controls right) when width > height. Verified only in CI simulator screenshots (iPad Pro 13" landscape looks correct; `-demo -landscape` launch args force rotation; simctl screenshots are saved in native orientation and need rotating). iPhone and iPad landscape were inspected in CI screenshots after rotation and look correct (single AnyLayout tree). This is not a real iPhone Duo layout.

## Latest visual features (CI screenshot checked, iPhone 16 Pro Max)
"Connecting to Spotify / Apple Music" pill, vinyl tinted from artwork average colour, track title on the record label, controls that fade out and return on tap (demo shows them unless `-hidden`). Pill, settings sheet and hidden-controls state were inspected in CI screenshots and render correctly. Real artwork tinting untested (demo uses a gradient).

## iPhone Duo (assumption, not measured)
No Duo simulator or official dimensions available. The Atrium web app (Jeysxn9321/Atrium) handles the Duo purely by available width/height breakpoints, not by device model: unfolded = coarse pointer, min-width 740px and min-height 540px; portrait unfolded = max-width 900px; outer screen held sideways = max-height 560px / 420px; it also reads `viewport.segments` for fold info. No pixel dimensions of the device are in that repo. Lunara's current `width > height` layout follows the same idea, but no Duo-specific breakpoints or fold avoidance are implemented yet.

## Added after the Duo review (CI-verified: compiles, 4 unit tests pass on a simulator)
- Settings sheet (gear button under the controls): disconnect, auto-hide controls, tint toggle. Sheet inspected in a CI screenshot.
- Spotify silent reconnect on launch from the Keychain refresh token; Apple Music re-requests authorization. Compiles, not tested with a real account.
- `LayoutMetrics`: portrait / wide / outer-screen-sideways (height <= 420 drops the progress row). Thresholds adapted from Atrium; real Duo point sizes unknown.
- Unit tests (`VinylTests`) run in the `Build unsigned IPA` workflow.

## Deliberately not built
- **Lock-screen Now Playing**: for Apple Music, `ApplicationMusicPlayer` already publishes system Now Playing. For Spotify, playback happens in the Spotify app, which owns the lock screen; Lunara has no audio session, so iOS would not show its info. Faking it would not work.
- **Widgets / Live Activity**: need an extension target (and normally an App Group); AltStore free accounts have a tight App ID limit, so this risks breaking the install. Left out until the user confirms they have a paid account or accepts the risk.
- Apple Music has no queue UI, so nothing plays until a queue is set; Spotify is the practical path for now.

## Opus review round (fixed in code; compiled in CI, NOT tested with a real account)
- Spotify: HTTP status is now checked (401/429/5xx/offline keep the last state instead of showing "Nothing playing"); only a 400/401 from the token endpoint forgets the saved login; auth session is retained and `start()` failure handled; polls no longer overlap; late responses after disconnect are dropped; PUT/POST send an empty body; local files get a title-based id.
- Connect/restore are guarded against double taps; disconnect also resets tint; stale artwork downloads are cancelled/ignored; items without artwork drop the previous cover.
- Controls are now visible on a real launch and auto-hide after 4 s (previously they were hidden until a tap, only `-demo` showed them); tapping a control keeps them visible.
- Portrait/wide use one layout tree so the disc no longer resets its spin on rotation.
- Apple Music pill now says playback from Lunara isn't built yet instead of "Start a song here".

## Known open issues (from review, not fixed)
- Token state in `SpotifyProvider` is not actor-isolated; concurrent refreshes are possible (Spotify's refresh-token rotation behaviour unverified).
- Offline launch shows onboarding with no retry/message even though a saved login exists.
- Tonearm frame is ~1.25x record height, may crowd the title in portrait; near-square windows (~600x590) may clip the controls row. Not seen on screen.
- Spotify progress advances in 3 s steps (no interpolation).
- Apple Music library artwork URLs (`musicKit://`) may not load via URLSession.
- A revoked Spotify token never returns the user to onboarding; the last track stays frozen (errors keep last state).
- A token response arriving after disconnect can still rewrite the Keychain.
- A post-tap poll is skipped if a timer poll is in flight, so a button can lag up to 3 s.
- Duo layouts: the `-frame` captures (740x540, 800x1000, 700x400) were unusable (simulator rotated the output, frame bled over white), so Duo is covered only by LayoutMetrics threshold unit tests. Tint-toggle live effect and real artwork tinting not seen.
- Everything on a real device, with real Spotify/Apple Music accounts, and through AltStore is unverified.
- Failed restore no longer clears the Keychain token (an earlier draft did; caught in advisor review).

## Unmet requirements (be explicit)
Widgets / Live Activity not built; custom lock-screen Now Playing not built; Apple Music cannot start playback from Lunara; Duo layout visually unverified.

## Install
GitHub Actions run "Build unsigned IPA" -> artifact `Vinyl-ipa` -> `Vinyl.ipa`. Download, then open in AltStore (My Apps -> + -> pick Vinyl.ipa). Free Apple ID: Apple Music/MusicKit capability may not provision; Spotify path does not need it.
