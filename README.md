# Bezelbub
A macOS app that wraps your screenshots and screen recordings in realistic Apple device bezels. Drop in a screenshot or video, and Bezelbub automatically detects the matching device and composites it into a pixel-perfect framed image or video.

[**Download the latest release (DMG)**](https://github.com/cwooddgr/bezelbub/releases/latest)

## Features

- **Auto-detection** — Matches screenshots and videos to the correct device by resolution
- **Drag and drop** — Drop a screenshot or screen recording onto the app window or dock icon
- **Video framing** — Export MOV/MP4 screen recordings with device bezels overlaid, audio preserved
- **Rotation** — Rotate videos to fix incorrect orientation (Option-click for counter-clockwise)
- **Device colors** — Choose from all available device color options
- **Copy & Save** — Copy framed images to clipboard, save as PNG, or export framed videos as MOV
- **Landscape & Portrait** — Supports both orientations for iPhone and iPad
- **Apple TV** — Supports 1080p (1920×1080) and 4K (3840×2160) screenshots

## Supported Devices

- **iPhone** — 14, 14 Plus, 14 Pro, 14 Pro Max, 15, 15 Plus, 15 Pro, 15 Pro Max, 16, 16 Plus, 16 Pro, 16 Pro Max, 17, 17 Pro, 17 Pro Max, Air
- **iPad** — iPad, iPad Air 11" M2, iPad Air 13" M2, iPad mini, iPad Pro 11" M4, iPad Pro 13" M4
- **Apple TV** — Apple TV 4K (1080p and 4K screenshots)

## Requirements

- macOS 14.0+
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Building

```sh
xcodegen generate
open Bezelbub.xcodeproj
```

## License

Copyright 2026 DGR Labs, LLC. All rights reserved.
