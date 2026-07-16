# Bezelbub

Bezelbub wraps your screenshots and screen recordings in realistic Apple device bezels — iPhone, iPad, Mac, and Apple TV — producing pixel-perfect device mockups as framed images and videos. It ships three ways:

- A **macOS and iOS app**: drop in a screenshot or video, Bezelbub auto-detects the matching device and composites the frame.
- A **headless `bezelbub` CLI** (`brew install cwooddgr/tap/bezelbub`): frame a screenshot in an iPhone bezel from the command line, add a device frame to a screen recording, or export a **transparent HEVC-with-alpha video** (plus a VP9/WebM copy for Chrome/Firefox) — designed for scripts, CI, and AI agents. [Jump to the CLI docs.](#headless-cli-bezelbub)
- A UI-free Swift package, **`BezelbubKit`**, for embedding the framing engine in your own tools.

[**Download the latest macOS release (DMG)**](https://github.com/cwooddgr/bezelbub/releases/latest)

## Features

- **Auto-detection** — Matches screenshots and videos to the correct device: iPhone and iPad by exact resolution, and Macs, iMac, and Apple TV by aspect ratio so captures taken at any scaled ("More Space") resolution still match and fill the bezel. Keeps your current device and color when you load another screenshot that fits the same device
- **Drag and drop** (macOS) — Drop a screenshot or screen recording onto the app window or dock icon
- **Paste** (macOS) — Paste a screenshot straight from the clipboard with ⌘V, or via Edit ▸ Paste
- **Photos & Share Extension** (iOS) — Import from Photos, or frame images directly from any app via the system share sheet
- **Video framing** — Export MOV/MP4 screen recordings with device bezels overlaid, audio preserved
- **Transparent video export** — Export a framed screen recording with a fully transparent background as HEVC-with-alpha (QuickTime `.mov`), for compositing device-framed video over any web page or presentation
- **Rotation** — Rotate videos to fix incorrect orientation (Option-click for counter-clockwise)
- **Device colors** — Choose from all available device color options
- **Export size controls** — Adjust Width, Height, or Scale (%) before saving, with per-mode size limits (images up to 16,384px, videos up to 7,680px)
- **Copy & Save** — Copy framed images to clipboard, save as PNG, or export framed videos as MOV/MP4
- **Landscape & Portrait** — Supports both orientations for iPhone and iPad

## Supported Devices

- **iPhone** — 14, 14 Plus, 14 Pro, 14 Pro Max, 15, 15 Plus, 15 Pro, 15 Pro Max, 16, 16 Plus, 16 Pro, 16 Pro Max, 17, 17 Pro, 17 Pro Max, Air
- **iPad** — iPad, iPad (A16), iPad Air 11"/13" M2, iPad Air 11"/13" M4, iPad mini, iPad mini (A17 Pro), iPad Pro 11"/13" M4, iPad Pro 11"/13" M5
- **Mac** — MacBook Air 13", MacBook Air 13"/15" M5, MacBook Pro 14", MacBook Pro 16", MacBook Pro 14"/16" M5, MacBook Neo, iMac 24" (matched by aspect ratio, so any scaled display resolution works)
- **Apple TV** — Apple TV 4K (1080p and 4K screenshots)

## Headless CLI (`bezelbub`)

`bezelbub` is a command-line tool that composites Apple device bezels onto screenshots and screen recordings — no GUI, no interactive prompts — so shell scripts, CI pipelines, and AI agents can generate device mockups. Every input is a flag with a sensible default, output is available as JSON, and errors go to stderr with distinct nonzero exit codes *and* concrete suggestions (valid ids, matching devices, nearest screen sizes), so a failed call tells the caller how to fix the next one.

Install via [Homebrew](https://brew.sh):

```sh
brew install cwooddgr/tap/bezelbub
```

### Quickstart

```sh
# Frame a screenshot — the device is auto-detected from its pixel size
bezelbub frame --input shot.png                 # → shot-framed.png

# Frame a screen recording (.mov/.mp4/.m4v) — audio preserved, MP4 out
bezelbub frame --input demo.mp4                 # → demo-framed.mp4

# Transparent video: HEVC-with-alpha in a QuickTime .mov
# (plays in Safari and Apple frameworks; background is fully transparent)
bezelbub frame --input demo.mp4 --background transparent   # → demo-framed.mov

# ...plus a VP9/WebM copy with alpha for Chrome/Firefox (needs ffmpeg on PATH)
bezelbub frame --input demo.mp4 --background transparent --webm
#   → demo-framed.mov + demo-framed.webm

# Discover valid device ids, colors, and screen sizes
bezelbub devices [--json]

# Which devices fit this screenshot or recording?
bezelbub devices --input shot.png               # or demo.mp4, or --dimensions 1206x2622

# Or specify everything explicitly
bezelbub frame --input shot.png --device iphone17pro \
               --color "Cosmic Orange" \
               --orientation landscape \
               --background "#1D1D1F" \
               --output-size 50% \
               --output framed.png --json
```

`frame` is the default subcommand, so `bezelbub --input shot.png` works too.

### Device auto-detection

Omit `--device` and the CLI detects the device from the input's pixel dimensions. iPhones and iPads match by exact screen resolution (±1px); display devices (Macs, iMac, Apple TV) match by aspect ratio, so screenshots taken at any scaled resolution still work and are rescaled to the bezel's screen. Detection succeeds when exactly one device matches; if several share the resolution, the error lists the candidates so you can re-run with `--device <id>`, and if none match, the nearest devices by aspect ratio are suggested. `bezelbub devices --input <path>` (or `--dimensions WxH`) answers "which devices fit this input" without framing anything.

### Transparent video and WebM (alpha-channel screen recordings)

`--background transparent` on a video input exports **HEVC with an alpha channel** in a QuickTime `.mov` instead of MP4 — a device-framed screen recording with a fully transparent background, ready to composite over anything. HEVC-with-alpha plays in Safari and Apple frameworks (AVFoundation, AppKit/UIKit) only; Chrome and Firefox don't decode it.

For those browsers, add `--webm` to also write a **VP9/WebM copy that keeps the alpha channel**. The CLI renders a temporary ProRes 4444 master and feeds *that* to `ffmpeg` (which must be on your PATH) — deliberately **not** the HEVC `.mov`, because ffmpeg builds older than 8.0 cannot decode HEVC's alpha layer and silently produce an opaque WebM. (ffmpeg 8+ decodes HEVC alpha correctly, but the ProRes bridge works on any build.) Serve both files, **with the `.mov` listed first**:

```html
<video autoplay loop muted playsinline>
  <source src="demo-framed.mov" type="video/quicktime" />
  <source src="demo-framed.webm" type="video/webm" />
</video>
```

The order matters: Safari can play VP9/WebM but **drops its alpha channel**, so a WebM-first listing renders the transparency as an opaque black background in Safari. Listed `.mov`-first, Safari takes the HEVC-alpha `.mov`, while Chrome and Firefox skip `video/quicktime` (which they can't play) and fall through to the WebM.

An explicit `--output` for a transparent export must end in `.mov`; the WebM lands beside it with a `.webm` extension.

### Flag reference

```
bezelbub frame --input <path> [options]
bezelbub devices [--input <path> | --dimensions WxH] [--json]
```

`frame` options:

| Flag | Meaning |
| --- | --- |
| `--input`, `-i` | Input screenshot (PNG/JPEG/HEIC) or video (`.mov`/`.mp4`/`.m4v`, routed by extension). Required. |
| `--device`, `-d` | Device id (see `bezelbub devices`). Omit to auto-detect from pixel size. |
| `--color`, `-c` | Color name or id, case-insensitive. Defaults to the device's default color. |
| `--orientation` | `portrait` \| `landscape` \| `auto` (default: infer from the input's aspect). |
| `--background` | Hex color (`#RRGGBB` / `#RRGGBBAA`) or `transparent`. Default: transparent for images, black for video. `transparent` on video switches to HEVC-with-alpha `.mov`. |
| `--output-size` | Scale preserving the bezel's aspect: a width (`1920`), exact `WxH` (must match the aspect), or a percentage (`50%`). Limits: 16–16,384 px images, 16–7,680 px video. |
| `--output`, `-o` | Output path. Default: `<input>-framed.png` / `.mp4` / `.mov` beside the input. |
| `--webm` | Also write a VP9/WebM copy with alpha (video + `--background transparent` only; needs ffmpeg on PATH). |
| `--json` | Machine-readable JSON result on stdout instead of a text summary. |

`devices` lists the full catalog (ids, display names, colors, orientations, screen sizes), or filters to the devices matching an `--input` file or bare `--dimensions`. Filtering always exits 0 — an empty `matches` array is the signal, with `nearest` (by aspect ratio) filled in when nothing matches.

### JSON output

`frame --json` emits one object:

```json
{
  "color" : "Cosmic Orange",
  "device" : "iphone17pro",
  "height" : 2760,
  "kind" : "image",
  "orientation" : "portrait",
  "output" : "/path/shot-framed.png",
  "width" : 1350
}
```

`kind` is `"image"` or `"video"`; video results add `"transparent": true|false` and, when `--webm` ran, the `"webm"` output path. `devices --json` emits an array of `{id, displayName, defaultColor, colors, landscapeOnly, hasPortraitBezel, screenWidth, screenHeight}`; with `--input`/`--dimensions` it emits `{width, height, matches, nearest}` using the same device objects (`nearest` is filled only when `matches` is empty).

### Exit codes

Stable and distinct, so scripts can branch on failure type instead of parsing stderr:

| Code | Meaning |
| --- | --- |
| 0 | Success |
| 1 | Invalid flag value (e.g. malformed `--background` or `--output-size`) |
| 2 | Unknown, ambiguous, or undetectable device (stderr lists candidates) |
| 3 | Unknown color (stderr lists the device's valid colors) |
| 4 | Input image or video unreadable |
| 5 | Compositing or video export failed |
| 6 | Output could not be written |
| 7 | `--webm` conversion failed (ffmpeg missing from PATH or errored) |
| 64 | Malformed arguments (standard `EX_USAGE`) |

### For AI agents

The CLI is designed for non-interactive, programmatic use — by LLM agents (Claude Code, MCP-style tool wrappers, CI bots) as much as by humans:

- **Nothing ever prompts.** Every input is a flag with a default; a call either completes or fails immediately.
- **`--json` on both subcommands** gives machine-readable results (shapes above).
- **Errors are self-correcting**: stderr messages include did-you-mean device/color ids, the devices matching the input's pixel size, and nearest sizes — enough for an agent to fix the next invocation without a human.
- **Exit codes 2–7 distinguish failure types** (table above), so an agent can branch without parsing text.
- **Clean pipes**: video-export progress is written to stderr only when it's a TTY, so captured output stays parseable.
- A typical agent flow: `bezelbub devices --input shot.png --json` to check the match, then `bezelbub frame --input shot.png --json` and read `output` from the result.

This repo also ships a ready-made **Claude Code skill** at [`skills/bezelbub-cli/`](skills/bezelbub-cli/SKILL.md) that teaches an agent the full workflow. To install it for all your projects, copy it into your user skills directory:

```sh
cp -R skills/bezelbub-cli ~/.claude/skills/
```

## Requirements

- macOS 14.0+ / iOS 17.0+
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Architecture

The device-framing engine lives in **`BezelbubKit`**, a UI-free Swift package (`BezelbubKit/`). It does the pure transformation — screenshot + device id + orientation → framed image — with no SwiftUI, app state, or GUI session, so it runs fully offscreen. Video framing lives in a sibling product, **`BezelbubVideoKit`** (AVFoundation-based), so still-image consumers like the Share Extension don't pull in the video pipeline. The macOS app, the iOS app, the Share Extension, and the `bezelbub` CLI are all thin clients of these packages; bezel/mask assets ship inside `BezelbubKit` and resolve via `Bundle.module`.

## Building

The apps are generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
open Bezelbub.xcodeproj
```

Schemes:
- **Bezelbub** — macOS app
- **Bezelbub-iOS** — iOS app and Share Extension

The engine and CLI build with SwiftPM:

```sh
cd BezelbubKit
swift build            # BezelbubKit library + bezelbub CLI
swift test             # engine round-trip tests
```

## License

Copyright 2026 DGR Labs, LLC. All rights reserved.
