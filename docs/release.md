# Bezelbub releases

> **Author:** Claude Code (coder) · **Date:** 2026-09-26 · **Status:** moved verbatim from `CLAUDE.md` when it was slimmed (decided-by-user 2026-09-26); provenance stamps inside the text are the originals.

**App Store status:** 3.4.0 (macOS build 18 / iOS build 14) approved and live on both stores since 2026-09-12 (READY_FOR_SALE per the ASC API; Charlie confirmed). No submission pending. Update this line at every submission so the session-start status check stays accurate.

### Releasing

> **Author:** Claude Code (coder) · **Date:** 2026-09-11 · **Status:** proposed-by-agent (mechanics as run for 3.4.0; the App Store as the only macOS channel is assumed from 3.3.0 onward, not confirmed)

App Store builds go up headlessly: `xcodebuild archive` per scheme (`Bezelbub` for macOS, `Bezelbub-iOS` for iOS) with `-allowProvisioningUpdates`, then `xcodebuild -exportArchive -exportOptionsPlist build/ExportOptions-upload.plist` (method `app-store-connect`, destination `upload`, automatic signing; Xcode's logged-in ASC session does the auth). Then `Scripts/asc_prepare_version.py --version X --macos-build N --ios-build M --whats-new-file F` creates the App Store versions on both platforms, waits for build processing, attaches the builds, and sets the en-US What's New through the ASC API (Admin key via the marketroid venv); add `--submit` only on Charlie's say-so, since it creates and submits the review submission. Bump `MARKETING_VERSION` and each `CURRENT_PROJECT_VERSION` in `project.yml` first (macOS and iOS build numbers run independently), `xcodegen generate`, commit, tag `vX.Y.Z`. The CLI (`cli-vX.Y.Z` GitHub release + Homebrew tap formula) and the MCP server (npm + registry) are separate release rituals with their own version numbers. Build-number history: 3.4.0 shipped macOS 18 / iOS 14. `Scripts/build-dmg.sh` still works but no DMG has been cut since 3.2.1; the README links the App Store.

### Who submits to App Review

> **Author:** Claude Code (coder, written from an `sf` session) · **Date:** 2026-09-21 · **Status:** the permission is decided-by-user (Charlie's words, quoted; he asked that day for it to be recorded in every app we have submitted to the App Store); the mechanics note is proposed-by-agent.

Charlie, 2026-09-21, for all DGR Labs app projects (also in the workspace `CLAUDE.md` and as an `autoMode.allow` rule in `~/.claude/settings.json`): "Standing permission: in my app projects, the project's agent may submit a version to App Review through the App Store Connect API once I've told it in that session to submit that version. It never resubmits after a rejection without asking me."

Mechanics, as run for Flip Flap 1.2 that day and as `overflight/docs/release-sync.md` records them: check `/v1/apps/6759073631/reviewSubmissions` for an open submission, then `POST /v1/reviewSubmissions` (one per platform the version ships on; here `MAC_OS` and `IOS`), `POST /v1/reviewSubmissionItems` with the version, and `PATCH` the submission with `submitted: true`; expect `WAITING_FOR_REVIEW`. A new version does not inherit `promotionalText`, so copy it from the previous version before submitting. App Store Connect app id `6759073631`. `Scripts/asc_prepare_version.py --submit` (see "Releasing" above) makes these calls for this project. Read `../APP_STORE_REJECTIONS.md` first, and update this file's status line after submitting.

The shared release guide for all our apps (order of the work, each project's recipe, App Store Connect gotchas) is `../APP_STORE_RELEASE.md`, approved by Charlie 2026-09-21; read it when cutting a build, and add to it when a release teaches us something new.

