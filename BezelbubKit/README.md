# BezelbubKit

A UI-free Swift package that composites Apple device bezels (iPhone, iPad, Mac, Apple TV) onto screenshots and screen recordings — the engine behind the [Bezelbub](../README.md) macOS/iOS apps and the headless `bezelbub` CLI. Everything runs fully offscreen (SSH, launchd, CI): no SwiftUI, no app state, no GUI session.

## Products

- **`BezelbubKit`** — still-image framing. `FrameCompositor` does the pure transform `(screenshot, device, orientation, styling) → framed CGImage` in Core Graphics; `DeviceMatcher` auto-detects the device from pixel dimensions; `DeviceCatalog`/`DeviceDefinition` describe every supported device, color, and screen region. Bezel and mask assets ship inside the package and resolve via `Bundle.module`.
- **`BezelbubVideoKit`** — video framing as a separate library product (AVFoundation/Core Image), so still-image consumers don't link the video pipeline. `VideoFrameCompositor` exports framed MP4 with audio preserved, or — with a `.transparent` background — HEVC-with-alpha in a QuickTime `.mov` for transparent screen-recording mockups.
- **`bezelbub`** — the command-line tool built on both libraries (`Sources/bezelbub/`), installable via Homebrew:

  ```sh
  brew install cwooddgr/tap/bezelbub
  ```

  It frames screenshots and videos non-interactively, auto-detects devices, emits `--json`, uses distinct exit codes, and can export transparent HEVC-with-alpha video plus a VP9/WebM copy for Chrome/Firefox. Full usage, flag reference, JSON shapes, and exit codes are documented in the [repository README](../README.md#headless-cli-bezelbub).

## Build and test

```sh
swift build                      # libraries + CLI
swift test                       # engine round-trip tests (image + video)
swift build --product bezelbub   # just the CLI
```

## Layout

- `Sources/BezelbubKit/` — image engine + `Resources/` (`Bezels/`, `Masks/`, `screen-regions.json`)
- `Sources/BezelbubVideoKit/` — video engine (`VideoFrameCompositor`, `BezelOverlayCompositor`)
- `Sources/bezelbub/` — CLI (swift-argument-parser)
- `Tests/BezelbubKitTests/` — round-trip tests
