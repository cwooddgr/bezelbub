# Bezelbub

macOS app that composites device bezels onto screenshots. Built with SwiftUI, targeting macOS 14+.

## Project Structure

- `Bezelbub/` — App source code
  - `BezelbubApp.swift` — App entry point
  - `AppState.swift` — Application state
  - `Models/` — Data models (e.g. `DeviceDefinition`)
  - `Services/` — Core logic (`DeviceMatcher`, `FrameCompositor`, `ScreenRegionDetector`)
  - `Views/` — SwiftUI views (`ContentView`)
- `Resources/Bezels/` — Device bezel images
- `project.yml` — XcodeGen project definition

## Build

Project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.

```sh
xcodegen generate
open Bezelbub.xcodeproj
```

Bundle ID: `co.dgrlabs.framer`
Team: `4W2V3Q3VA4`
