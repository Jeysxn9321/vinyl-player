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
Apple Music cannot start playback from Lunara; Duo layout visually unverified.

## Install
GitHub Actions run "Build unsigned IPA" -> artifact `Vinyl-ipa` -> `Vinyl.ipa`. Download, then open in AltStore (My Apps -> + -> pick Vinyl.ipa). Free Apple ID: Apple Music/MusicKit capability may not provision; Spotify path does not need it.

## Rebuild toward the MD Vinyl look (in progress)
- Done (compiles in CI; iPhone and iPad portrait and the playlist sheet inspected in demo screenshots; tonearm rests on the grooves and its pivot is fully visible in the iPhone and Duo screenshots; demo playlists show blank covers because stub data has no images; real covers untested): portrait = full-width record with the real cover as its label, tonearm at the right edge, title/progress/controls bottom-left; vinyl colour presets in Settings; app icon (your artwork, cropped to 1024 px; CI bundles it, not yet seen on a device).
- Spotify playlist browser (`PlaylistsView`, `-browser -demo` shows stub data): lists up to 50 playlists via `GET /me/playlists` (Spotify's Feb 2026 changelog lists it and PUT /me/player/play as still available to dev-mode apps; context_uri body not documented there), search, tap plays via `PUT /me/player/play {context_uri}`. UNTESTED with a real account. Needs new scopes (`playlist-read-private/collaborative`): a login saved earlier lacks them, so the sheet shows "Reconnect Spotify". Spotify's Feb 2026 dev-mode changes limit playlist items to playlists you own, so tracks are not listed. The 3D cover stack, queue view, record patterns/effects, themes and label options from MD Vinyl are NOT built.
- Rotating the phone now resets the record's spin phase (portrait and wide are separate trees; the earlier 'single AnyLayout tree' note no longer applies). The Reconnect button re-runs sign-in on the existing provider, so a cancel keeps the old login.

## Update 2026-11-24 (queue, 3D playlists, Xcode 27.2, Duo)
- CI runs on the `xcode-27` runner image with Xcode 27.2 / SDK 27.2 (27.3 does not exist on the runner). An "iPhone Duo" simulator exists there; it has two displays (1 = main, 3 = second). The second display screenshot is all black (the app does not draw there). The main-display Duo screenshots show the portrait layout correctly. Real fold/hinge behaviour is untested.
- Queue view (`QueueView`, list button in the controls): read-only on purpose. Spotify has no "jump to queue item" call and playing by URI would drop the playlist context. Verified only with demo data; the real `/me/player/queue` call and its scope are untested.
- Playlist browser is now a 3D overlapping stack of covers (scroll transition). Verified only in demo screenshots (gradient fallback covers, no real artwork); the 3D tilt is barely visible in a still. Tapping to play a real playlist is untested.
- CI billing: macOS minutes are 10x; the free quota was exhausted. Screenshots workflow is manual-only, builds ignore doc-only pushes. Repo is now public; the first runs after that started and succeeded, but whether they were billed is not confirmed. A $0 Actions budget is still the user's step.
- Still untested with a real account/device: Spotify login, playlists, queue, playback, album art as label, icon, AltStore install.

## Update 2026-11-24 (Live Activity, patterns, effects, themes)
- Live Activity (`Shared/LunaraActivity.swift`, `Widgets/LunaraWidgets.swift`, `LiveActivityController`): lock-screen card plus Dynamic Island with title, artist, a timer-driven progress bar and a flat record glyph. It compiles in CI (the `LunaraWidgets` extension is embedded). NOT tested on a device. Limits: Lunara is suspended in the background, so the card cannot follow track changes while the phone is locked; it updates when you open the app, and goes stale at the track's end time. The progress bar is driven by a system timer, so it keeps moving without the app.
- Lock-screen "Now Playing": Spotify owns the system Now Playing controls, and Lunara plays no audio, so it cannot replace them (faking `MPNowPlayingInfoCenter` would not work). The Live Activity is the Lunara-styled replacement. Apple Music already shows system Now Playing through its own player.
- The extension has its own bundle ID (`com.example.vinyl.widgets`). With a free Apple ID in AltStore this uses a second App ID of the 10 per week; keep app extensions when AltStore asks.
- Record patterns (plain, splatter, marble, swirl), effects (light sheen, glow, scratches and dust) and background themes (artwork, midnight, ember, ocean, forest, mono) are in Settings. Seen only in demo screenshots from CI. These are my own design, since the original brief's exact list was not available.

## Update 2026-11-24 (labels, Apple Music playback, home-screen widget)
- **Label options** (Settings > Label): style Artwork / Solid / Title, size Small / Medium / Large. Verified in CI demo screenshots only.
- **Apple Music playback from Lunara**: new library browser (`AppleMusicLibraryView`, button in the controls) lists your library playlists and albums and plays them with `ApplicationMusicPlayer`. It compiles, but is **untested**: MusicKit does not run in the simulator, and the MusicKit capability may not provision on a free Apple ID. CI only shows demo rows.
- **Home-screen widget** (small + medium, "last played"): compiles and renders in a CI screenshot with demo data. It reads the last track from an App Group. The CI build is unsigned and carries **no entitlements** (`codesign` reports "not signed at all"), so whether AltStore's re-signing provides the App Group is **unverified**. If not, the widget shows a static record and "Play something". It does not follow live playback.
- Nothing from this round has run on a device.

## Update 2026-11-24 (vinyl artwork variants)
- **What exists** (`Vinyl/Artwork/`): MusicBrainz + Cover Art Archive provider, a matching/scoring engine, disk cache (14-day metadata, hashed images), per-album saved default, custom upload (centre-cropped square), a frosted-lavender selector sheet (button in the utility row, long-press the label), tap/horizontal-swipe on the label to cycle, 0.45 s crossfade. Settings > "Vinyl artwork" has an auto-lookup toggle and the Discogs proxy URL.
- **Live result (CI iOS simulator, 2026-11-24)**: a real lookup for Daft Punk - Random Access Memories ran from the app (`-artquery`), found the vinyl releases, auto-displayed a Columbia LP label scan tagged by the community database, and showed the populated selector. Not run on a physical device; only this one album seen.
- **Tested (unit)**: the pure logic (parsing, matching, classification, ranking, Codable) by unit tests against REAL recorded MusicBrainz/CAA responses for Daft Punk - Random Access Memories. Not tested: live network lookups from the app, the UI and gestures on a device, the crossfade, PhotosPicker upload, gesture conflicts with the record swipe.
- **Honesty rules in code**: an image is called "Tagged as a disc by the community database" only when the Cover Art Archive types it `Medium` alone, it is approved, and the release is a vinyl release whose title/artist match. Nothing is ever called "verified original". Medium + Front/Booklet/Tray images (product photos) are shown as unverified editions. No match -> streaming cover stays and the sheet says so. Failures are never cached as "no vinyl".
- **Discogs**: implemented against a proxy contract (`backend/discogs-proxy/`, a Cloudflare Worker) but NOT run live and no proxy is deployed. Needs a Discogs Consumer Key + Secret (discogs.com/settings/developers), stored as Worker secrets `DISCOGS_KEY`/`DISCOGS_SECRET` (never in the app); then paste the Worker URL in Settings > Vinyl artwork. Discogs images are always "unverified". I have NOT read the Discogs terms on caching images; read them before enabling.
- **Limits**: the player does not supply year/barcode/MBID, so matching uses title + artist (+ vinyl format) only; hence "Release match N%" is the release, not proof of the label. Under `-demo` no lookup runs. MusicBrainz asks for ~1 request/s and an identifying User-Agent (it names the app and the public repo URL, no personal data beyond the public repo).
