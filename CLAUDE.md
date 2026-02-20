# Bezelbub

macOS app that composites device bezels onto screenshots and screen recordings. Built with SwiftUI, targeting macOS 14+.

## Project Structure

- `Bezelbub/` — App source code
  - `BezelbubApp.swift` — App entry point
  - `AppState.swift` — Application state
  - `Models/` — Data models (`DeviceDefinition`, `DeviceMatcher`)
  - `Services/` — Core logic (`FrameCompositor`, `VideoFrameCompositor`, `ScreenRegionDetector`)
  - `Views/` — SwiftUI views (`ContentView`)
- `Resources/Bezels/` — Device bezel images
- `Apple Product Bezels/` — Source bezel PNGs from Apple (gitignored, local reference only)
- `project.yml` — XcodeGen project definition

## Build

Project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.

```sh
xcodegen generate
open Bezelbub.xcodeproj
```

Bundle ID: `co.dgrlabs.framer`
Team: `4W2V3Q3VA4`
