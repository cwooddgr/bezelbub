# Bezelbub

macOS + iOS app that composites device bezels onto screenshots and screen recordings. Built with SwiftUI, targeting macOS 14+ and iOS 17+.

## Project Structure

- `Shared/` — Cross-platform code (compiled into all targets)
  - `AppState.swift` — Application state (uses `#if os()` for platform-specific bits)
  - `Models/` — Data models (`DeviceDefinition`, `DeviceCatalog`)
  - `Services/` — Core logic (`DeviceMatcher`, `FrameCompositor`, `VideoFrameCompositor`, `ScreenRegionDetector`)
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
- `Resources/Bezels/` — Device bezel images (shared across all targets)
- `Apple Product Bezels/` — Source bezel PNGs from Apple (gitignored, local reference only)
- `project.yml` — XcodeGen project definition

## Build

Project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.

```sh
xcodegen generate
open Bezelbub.xcodeproj
```

### Targets

- **Bezelbub** — macOS application
- **Bezelbub-iOS** — iOS application
- **BezelbubShareExtension** — iOS share extension (embedded in Bezelbub-iOS)

### Schemes

- **Bezelbub** — Builds/runs the macOS app
- **Bezelbub-iOS** — Builds/runs the iOS app + share extension

Bundle ID: `co.dgrlabs.bezelbub`
Team: `2CTUXD4C44`
