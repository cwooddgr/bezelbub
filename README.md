# Bezelbub
A macOS and iOS app that wraps your screenshots and screen recordings in realistic Apple device bezels. Drop in a screenshot or video, and Bezelbub automatically detects the matching device and composites it into a pixel-perfect framed image or video.

[**Download the latest macOS release (DMG)**](https://github.com/cwooddgr/bezelbub/releases/latest)

## Features

- **Auto-detection** — Matches screenshots and videos to the correct device by resolution
- **Drag and drop** (macOS) — Drop a screenshot or screen recording onto the app window or dock icon
- **Photos & Share Extension** (iOS) — Import from Photos, or frame images directly from any app via the system share sheet
- **Video framing** — Export MOV/MP4 screen recordings with device bezels overlaid, audio preserved
- **Rotation** — Rotate videos to fix incorrect orientation (Option-click for counter-clockwise)
- **Device colors** — Choose from all available device color options
- **Export size controls** — Adjust Width, Height, or Scale (%) before saving, with per-mode size limits (images up to 16,384px, videos up to 7,680px)
- **Copy & Save** — Copy framed images to clipboard, save as PNG, or export framed videos as MOV/MP4
- **Landscape & Portrait** — Supports both orientations for iPhone and iPad

## Supported Devices

- **iPhone** — 14, 14 Plus, 14 Pro, 14 Pro Max, 15, 15 Plus, 15 Pro, 15 Pro Max, 16, 16 Plus, 16 Pro, 16 Pro Max, 17, 17 Pro, 17 Pro Max, Air
- **iPad** — iPad, iPad (A16), iPad Air 11"/13" M2, iPad Air 11"/13" M4, iPad mini, iPad mini (A17 Pro), iPad Pro 11"/13" M4, iPad Pro 11"/13" M5
- **Mac** — MacBook Air 13", MacBook Air 13"/15" M5, MacBook Pro 14", MacBook Pro 16", MacBook Pro 14"/16" M5, MacBook Neo, iMac 24"
- **Apple TV** — Apple TV 4K (1080p and 4K screenshots)

## Requirements

- macOS 14.0+ / iOS 17.0+
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Building

```sh
xcodegen generate
open Bezelbub.xcodeproj
```

Schemes:
- **Bezelbub** — macOS app
- **Bezelbub-iOS** — iOS app and Share Extension

## License

Copyright 2026 DGR Labs, LLC. All rights reserved.
