# Bezelbub

macOS + iOS app that composites device bezels onto screenshots and screen recordings. Built with SwiftUI, targeting macOS 14+ and iOS 17+.

The device-framing engine lives in a UI-free Swift package (`BezelbubKit`) so it can run headless. The SwiftUI apps, the share extension, and the `bezelbub` CLI are all thin clients of that package — see [Architecture](#architecture-shared-engine--thin-adapters).

## Project Structure

- `BezelbubKit/` — **UI-free engine** as a local SwiftPM package (the single source of truth for framing logic and bezel assets)
  - `Sources/BezelbubKit/` — `FrameCompositor` (the pure screenshot→framed-image transform, Core Graphics), `DeviceMatcher`, `DeviceDefinition`/`DeviceCatalog`, `ScreenRegionDetector`. No SwiftUI, no app state.
  - `Sources/BezelbubKit/Resources/` — `Bezels/`, `Masks/`, `screen-regions.json`, served to every consumer via `Bundle.module`
  - `Sources/bezelbub/` — the `bezelbub` CLI (swift-argument-parser); `frame` and `devices` subcommands
  - `Tests/BezelbubKitTests/` — engine round-trip tests
- `Shared/` — Cross-platform **app** code (compiled into the app targets; imports `BezelbubKit`)
  - `AppState.swift` — Application state (uses `#if os()` for platform-specific bits)
  - `Models/` — App-layer models (`ExportSizeModel`)
  - `Services/` — App-layer services (`VideoFrameCompositor`, `BezelOverlayCompositor`, `BezelOverlayInstruction`)
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

Clients:
- The **macOS / iOS apps** and **share extension** depend on the `BezelbubKit` library product (declared in `project.yml` under `packages:`). `AppState` and the views are adapters over the engine.
- The **`bezelbub` CLI** (`Sources/bezelbub/`) depends on `BezelbubKit` + swift-argument-parser. swift-argument-parser is a dependency of the CLI target only — it is **not** linked into the apps (verified: absent from the archived app binary), though it does appear in the package's resolved graph.

A future MCP server is meant to wrap the CLI (a clean process boundary) or link `BezelbubKit` directly.

## Build

The apps are generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`:

```sh
xcodegen generate
open Bezelbub.xcodeproj
```

The engine + CLI build with SwiftPM:

```sh
cd BezelbubKit
swift build            # library + CLI
swift test             # engine round-trip tests
swift build --product bezelbub   # just the CLI
```

### CLI usage

```sh
bezelbub devices [--json]
bezelbub frame --input <path> --device <id> [--color <name>] \
               [--orientation portrait|landscape|auto] [--background <hex>] \
               [--output <path>] [--json]
```

Agent-friendly: every input is a flag with a default, `--json` gives machine-readable output, errors go to stderr with distinct nonzero exit codes (2 unknown device, 3 unknown color, 4 unreadable input, 5 composite failed, 6 write failed; argument-parsing errors use ArgumentParser's EX_USAGE 64).

### Regenerating bezel assets

`Scripts/generate-screen-regions.swift` flood-fills the bezel PNGs to (re)generate `Masks/` and `screen-regions.json`. It reads/writes under `BezelbubKit/Sources/BezelbubKit/Resources/`.

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
