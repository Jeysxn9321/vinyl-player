# Project status

Written on Windows 11. There is no Xcode, Mac, simulator or reference video here, so **nothing has been compiled, run or tested.** All source is unverified.

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
