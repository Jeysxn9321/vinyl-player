# Development log
- 2026-11-23: Environment is Windows with no Xcode/swift toolchain and no video file found. Scaffolded XcodeGen project and Swift sources. No build possible.
- 2026-11-24: CI now compiles, builds the IPA and screenshots. Added pill, tinted vinyl, label title, auto-hiding controls (screenshot-verified on iPhone). Studied Atrium's Duo breakpoints (width/height based, no pixel sizes). Added Settings, Spotify token restore, LayoutMetrics, 4 unit tests (pass in CI). Skipped lock-screen and widgets with reasons in PROJECT_STATUS.md.
