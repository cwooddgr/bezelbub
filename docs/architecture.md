# Bezelbub architecture

> **Author:** Claude Code (coder) · **Date:** 2026-09-26 · **Status:** moved verbatim from `CLAUDE.md` when it was slimmed (decided-by-user 2026-09-26); provenance stamps inside the text are the originals.

The device-framing engine lives in a UI-free Swift package (`BezelbubKit`) so it can run headless. The SwiftUI apps, the share extension, and the `bezelbub` CLI are all thin clients of that package — see [Architecture](#architecture-shared-engine--thin-adapters).

## Project Structure

- `BezelbubKit/` — **UI-free engine** as a local SwiftPM package (the single source of truth for framing logic and bezel assets)
  - `Sources/BezelbubKit/` — `FrameCompositor` (the pure screenshot→framed-image transform, Core Graphics), `DeviceMatcher`, `DeviceDefinition`/`DeviceCatalog`, `ScreenRegionDetector`. No SwiftUI, no app state, no AVFoundation.
  - `Sources/BezelbubKit/Resources/` — `Bezels/`, `Masks/`, `screen-regions.json`, served to every consumer via `Bundle.module`
  - `Sources/BezelbubVideoKit/` — video framing as a **separate library product** (`VideoFrameCompositor`, `BezelOverlayCompositor`, `BezelOverlayInstruction`; AVFoundation/CoreImage) so still-image consumers like the share extension don't link the video pipeline
  - `Sources/bezelbub/` — the `bezelbub` CLI (swift-argument-parser); `frame` and `devices` subcommands
  - `Tests/BezelbubKitTests/` — engine round-trip tests (image + video)
- `Shared/` — Cross-platform **app** code (compiled into the app targets; imports `BezelbubKit` + `BezelbubVideoKit`)
  - `AppState.swift` — Application state (uses `#if os()` for platform-specific bits; the share extension compiles it with `-DSHARE_EXTENSION`, which guards out the video/`BezelbubVideoKit` parts)
  - `Models/` — App-layer models (`ExportSizeModel`)
- `macOS/` — macOS-specific code
  - `BezelbubApp.swift` — macOS app entry point
  - `Views/` — macOS SwiftUI views (`ContentView`, `ExportSizeAccessoryView`)
  - `Info.plist`, `Bezelbub.entitlements`, `Assets.xcassets`
- `iOS/` — iOS-specific code
  - `BezelbubApp.swift` — iOS app entry point
  - `Views/` — iOS SwiftUI views (`ContentView` with PhotosPicker, share sheet)
  - `Info.plist`, `Bezelbub-iOS.entitlements`, `Assets.xcassets`
- `BezelbubShareExtension/` — iOS Share Extension
  - `ShareViewController.swift` — Receives images from share sheet, frames them, copies to clipboard
  - `Info.plist`, `BezelbubShareExtension.entitlements`
- `Apple Product Bezels/` — Source bezel PNGs from Apple (gitignored, local reference only)
- `project.yml` — XcodeGen project definition

## Architecture: shared engine + thin adapters

The pure transformation `(screenshot, device id, orientation, styling) → framed image` lives in **`BezelbubKit`** and has no dependency on SwiftUI, app state, AVFoundation, or a GUI session — it's Core Graphics bitmap work, so it runs fully offscreen (SSH, launchd, CI). Bezel/mask assets ship inside the package and resolve via `Bundle.module`, so there's one copy regardless of consumer.

Video framing (`(video, device id, orientation, styling) → framed MP4`, audio preserved) lives in the sibling product **`BezelbubVideoKit`** in the same package. It's AVFoundation/CoreImage work: macOS composites via `AVVideoCompositionCoreAnimationTool`, iOS via a custom `AVVideoCompositing` (CALayer alpha doesn't composite correctly on iOS). A `.transparent` background (`VideoBackground` enum) exports HEVC-with-alpha as `.mov` instead of MP4 and routes through the custom compositor on **both** platforms — the CALayer path's alpha behavior is unverified, while the Core Image compositor is deterministic about alpha.

Clients:
- The **macOS / iOS apps** depend on both library products; the **share extension** depends only on `BezelbubKit` (declared in `project.yml` under each target's `dependencies:`). `AppState` and the views are adapters over the engine.
- The **`bezelbub` CLI** (`Sources/bezelbub/`) depends on `BezelbubKit` + `BezelbubVideoKit` + swift-argument-parser. swift-argument-parser is a dependency of the CLI target only — it is **not** linked into the apps (verified: absent from the archived app binary), though it does appear in the package's resolved graph.

The **MCP server** (`bezelbub-mcp/`, npm `@dgr_labs/bezelbub-mcp`, registry `io.github.cwooddgr/bezelbub-mcp`) wraps the CLI over a process boundary: tools `frame_image`, `frame_video`, `list_devices`; it resolves the binary via `BEZELBUB_CLI_PATH`, then PATH, then Homebrew. Its version is read from `package.json` at runtime (a 0.2.0 shipped announcing itself as 0.1.0 when it was a source constant). Publishing needs Charlie: `npm publish --access public` prompts for his OTP, and `mcp-publisher login github` is a browser device flow. Directory listings (2026-09-11): the official registry and Smithery (`charlie-wood/bezelbub-mcp`, published with `npm run bundle:smithery` then `npx @smithery/cli mcp publish`, login is a browser step); Glama skipped (decided-by-user 2026-09-11: its indexing checks run in Docker on Linux, so a macOS-only server would never be searchable); PulseMCP is paused and ingests the official registry when it resumes. `bezelbub-mcp/REGISTRY_SUBMISSIONS.md` has the details. Tool argument schemas are a compatibility surface: an MCP client fetches the tool list once per session and calls against that cached copy for the session's life, so a session opened before an update keeps sending the old argument shapes and a server that reshaped a field rejects every call until the client reconnects (reported by a user on Threads after 0.2.x, though 0.1.0 through 0.2.1 changed only descriptions). When changing a tool's inputs: add optional fields rather than retyping existing ones, or accept both shapes for a release; bump the version as breaking and tell users in the release notes to restart their client; and make the validation error name the version and say to reconnect. Since MCP 0.3.0 the server also checks the npm registry on demand, in the background of a tool call and at most once per six hours, never on a timer and never at startup, where npx has just fetched the latest build anyway (decided-by-user 2026-09-13, Charlie called the timer "mucho overkill"; `src/update-check.ts`, opt-out `BEZELBUB_NO_UPDATE_CHECK=1`, test-only override `BEZELBUB_UPDATE_CHECK_URL`) and, when a newer version exists, appends a "reconnect the server" text block to every tool result, because the text of results is the only channel that reaches a stale session (the old process can't serve new definitions, so `tools/list_changed` alone wouldn't help). Release notes for the MCP server should still carry a "restart your client after updating" line.

### Regenerating bezel assets

`Scripts/generate-screen-regions.swift` flood-fills the bezel PNGs to (re)generate `Masks/` and `screen-regions.json`. It reads/writes under `BezelbubKit/Sources/BezelbubKit/Resources/`.

The flood fill seeds from the image center; when that pixel is opaque (the iPhone Duo "open, outer display" view, where the center is the hinge) it falls back to the largest enclosed fully-transparent region. `ScreenRegionDetector` mirrors the same seed logic for its runtime fallback. Apple ships that Duo view once, as a wide canvas with a portrait screen: that file is our `-p` bezel, and the `-l` bezel is the same art rotated 90° counter-clockwise (`sips --rotate -90`) so the display sits on top.


### Targets

- **Bezelbub** — macOS application
- **Bezelbub-iOS** — iOS application
- **BezelbubShareExtension** — iOS share extension (embedded in Bezelbub-iOS)
- **bezelbub** — headless CLI (SwiftPM executable in `BezelbubKit/`, not part of the Xcode project)

### Schemes

- **Bezelbub** — Builds/runs the macOS app
- **Bezelbub-iOS** — Builds/runs the iOS app + share extension

Bundle ID: `co.dgrlabs.bezelbub`
Team: `2CTUXD4C44`
