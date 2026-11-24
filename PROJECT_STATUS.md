# Project status

Written on Windows 11 with no Mac. GitHub Actions (macos-15) now **compiles the app, builds an unsigned IPA, and captures iPhone 16 Pro Max / iPad Pro 13" simulator screenshots** (`-demo` mode, sample data). Not yet verified: any real device, real Spotify/Apple Music accounts, audio, AltStore install. No iPhone Duo simulator exists; large-canvas layout is approximated with the iPad screenshots.

On a Mac: `brew install xcodegen && xcodegen && open Vinyl.xcodeproj`, add the MusicKit capability, set a team, build.

## Written (unverified)
- Shared model and provider protocol
- Apple Music provider (ApplicationMusicPlayer)
- Spotify provider (PKCE, Web API, 3 s polling; controls need Premium and an active device)
- Vinyl disc, tonearm, sleeve, spin driven by accumulated play time, controls, onboarding

## Not done
Settings, Now Playing / lock screen, widgets, Live Activity, ambient colour extraction, Duo-specific layout (only width/height responsive), token reload on launch, visual QA, tests, IPA / AltStore.

## Notes
- Spotify clientID must be supplied from your own developer app.
- MusicKit cannot read the system Music app's playback, only this app's own queue.
- The Spotify Web API cannot be polled in the background.

## Video analysis (ref/sheet_1.png)
Landscape layout: square sleeve at left edge, record peeking out from behind its right edge (~18% hidden), tonearm pivoting top-right and swinging from near-vertical (rest) to angled over the record (playing). Background is a dark gradient tinted from the artwork; record label/colour follows the album (marbled cream, black with blue label). Only a small "Connecting to Spotify" pill at top; no visible controls. Source updated to match; still uncompiled.

## Cloud build (no Mac)
`.github/workflows/build-ipa.yml` builds an unsigned IPA on a GitHub macOS runner; AltStore re-signs it on install. Needs the folder pushed to a GitHub repo. Risk: a free Apple ID may not be able to provision the MusicKit capability, so Apple Music may fail on-device; Spotify does not need it.

## Landscape / wide layout
`PlayerView` switches to side-by-side (record composition left, title/progress/controls right) when width > height. Verified only in CI simulator screenshots (iPad Pro 13" landscape looks correct; `-demo -landscape` launch args force rotation; simctl screenshots are saved in native orientation and need rotating). iPhone landscape not inspected after rotation. This is not a real iPhone Duo layout.

## Latest visual features (CI screenshot checked, iPhone 16 Pro Max)
"Connecting to Spotify / Apple Music" pill, vinyl tinted from artwork average colour, track title on the record label, controls that fade out and return on tap (demo shows them unless `-hidden`). Pill and hidden-controls state not yet inspected in a screenshot. Real artwork tinting untested (demo uses a gradient).

## iPhone Duo (assumption, not measured)
No Duo simulator or official dimensions available. The Atrium web app (Jeysxn9321/Atrium) handles the Duo purely by available width/height breakpoints, not by device model: unfolded = coarse pointer, min-width 740px and min-height 540px; portrait unfolded = max-width 900px; outer screen held sideways = max-height 560px / 420px; it also reads `viewport.segments` for fold info. No pixel dimensions of the device are in that repo. Lunara's current `width > height` layout follows the same idea, but no Duo-specific breakpoints or fold avoidance are implemented yet.
