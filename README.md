# Bezelbub

Bezelbub puts your screenshots and screen recordings inside realistic Apple device bezels, so you get pixel-accurate device mockups for iPhone, iPad, Mac, and Apple TV as framed images and videos. You can use it three ways:

- As a **macOS and iOS app**. Drop in a screenshot or a video, and Bezelbub picks the matching device and frames it.
- As a **headless command-line tool**, `bezelbub` (`brew install cwooddgr/tap/bezelbub`). Frame a screenshot from a script, add a device frame to a screen recording, or export a transparent HEVC-with-alpha video with a VP9/WebM copy for Chrome and Firefox. We built it for shell scripts, CI, and AI agents. [Jump to the CLI docs.](#the-bezelbub-command-line-tool)
- As a Swift package with no UI, **`BezelbubKit`**, if you want the framing engine inside your own tool.

[**Get Bezelbub on the App Store**](https://apps.apple.com/app/id6759073631) for Mac, iPhone, and iPad.

## What you can do with it

- **Let it find the device.** Drop in a screenshot or video and you get the right bezel. We recognize iPhones and iPads by their exact resolution. For Macs, iMac, Studio Display, and Apple TV we recognize the capture size of each macOS display zoom setting, from "Larger Text" to "More Space", so you can take the capture at any zoom level. If we don't have a size on file, we fall back to matching by aspect ratio. When several models share a panel, you pick from all of them. Load another screenshot for the same device and your device and color choices stay put.
- **Drag and drop** on the Mac. Drop a screenshot or screen recording on the window or the Dock icon.
- **Paste** on the Mac. Copy a screenshot and press ⌘V, or use Edit ▸ Paste.
- **Photos and the share sheet** on iPhone and iPad. Import from Photos, or send an image to Bezelbub from any app's share sheet.
- **Frame videos.** Export MOV and MP4 screen recordings with the bezel on top, with the audio kept.
- **Export transparent video.** Save a framed recording with a fully transparent background as HEVC-with-alpha in a QuickTime `.mov`, ready to lay over any web page or presentation.
- **Fix rotation.** Rotate a video that came in sideways. Option-click to go the other way.
- **Pick the color.** Every color Apple ships for each device.
- **Set the export size.** Change the width, the height, or the scale before saving. Images go up to 16,384 px and videos up to 7,680 px.
- **Copy or save.** Copy a framed image to the clipboard, save it as PNG, or export a framed video as MOV or MP4.
- **Portrait or landscape** for iPhone and iPad.

## Devices

- **iPhone:** 14, 14 Plus, 14 Pro, 14 Pro Max, 15, 15 Plus, 15 Pro, 15 Pro Max, 16, 16 Plus, 16 Pro, 16 Pro Max, 17, 17 Pro, 17 Pro Max, Air, 18 Pro, 18 Pro Max
- **iPhone Duo:** three views, each its own device. Frame the inner display with the phone open (`iphoneduo`), the outer display with the phone closed (`iphoneduoouter`), or the outer display with the phone open and seen from the back (`iphoneduoouteropen`), in portrait or landscape
- **iPad:** iPad, iPad (A16), iPad Air 11"/13" M2, iPad Air 11"/13" M4, iPad mini, iPad mini (A17 Pro), iPad Pro 11"/13" M4, iPad Pro 11"/13" M5
- **Mac:** MacBook Air 13", MacBook Air 13"/15" M5, MacBook Pro 14", MacBook Pro 16", MacBook Pro 14"/16" M5, MacBook Neo, iMac 24", iMac 24" M4, Studio Display (2026). Any display zoom setting works. The Studio Display bezel covers the XDR too, because Apple ships identical art for both
- **Apple TV:** Apple TV 4K, from 1080p or 4K screenshots

## The `bezelbub` command-line tool

With `bezelbub` you can frame screenshots and screen recordings from a shell script, a CI pipeline, or an AI agent. There is no GUI and nothing ever prompts you. Every input is a flag with a sensible default, you can ask for JSON output, and when something goes wrong you get a distinct nonzero exit code plus a concrete suggestion on stderr (valid ids, matching devices, nearest screen sizes), so one failed call tells you how to fix the next one.

Install it with [Homebrew](https://brew.sh):

```sh
brew install cwooddgr/tap/bezelbub
```

### Quick start

```sh
# Frame a screenshot. We detect the device from its pixel size.
bezelbub frame --input shot.png                 # writes shot-framed.png

# Frame a screen recording (.mov/.mp4/.m4v). Audio is kept; you get an MP4.
bezelbub frame --input demo.mp4                 # writes demo-framed.mp4

# Transparent video: HEVC-with-alpha in a QuickTime .mov
# (plays in Safari and Apple frameworks; the background is fully transparent)
bezelbub frame --input demo.mp4 --background transparent   # writes demo-framed.mov

# Add a VP9/WebM copy with alpha for Chrome and Firefox (needs ffmpeg on PATH)
bezelbub frame --input demo.mp4 --background transparent --webm
#   writes demo-framed.mov and demo-framed.webm

# List device ids, colors, and screen sizes
bezelbub devices [--json]

# Which devices fit this screenshot or recording?
bezelbub devices --input shot.png               # or demo.mp4, or --dimensions 1206x2622

# Or spell everything out
bezelbub frame --input shot.png --device iphone17pro \
               --color "Cosmic Orange" \
               --orientation landscape \
               --background "#1D1D1F" \
               --output-size 50% \
               --output framed.png --json
```

`frame` is the default subcommand, so `bezelbub --input shot.png` works too.

### How device detection works

Leave out `--device` and we work out the device from the input's pixel dimensions. For iPhones and iPads that means an exact match on screen resolution, within a pixel. For Macs, iMac, Studio Display, and Apple TV it means an exact match on capture size: every macOS display zoom setting captures at a known pixel size per model, so a 3420×2214 screenshot can only have come from a 15" MacBook Air, whatever zoom it was taken at. Sizes we don't have on file, such as external monitors or downscaled recordings, fall back to aspect-ratio matching. When you frame a display capture, we scale it to fit the bezel's screen.

Detection succeeds when exactly one device matches. If several models share the size, the error lists them so you can run again with `--device <id>`. If nothing matches, we suggest the nearest devices by aspect ratio. To check before framing anything, run `bezelbub devices --input <path>` or `bezelbub devices --dimensions WxH`.

### Transparent video and WebM

Pass `--background transparent` with a video input and you get HEVC with an alpha channel in a QuickTime `.mov` instead of an MP4: a device-framed recording with a fully transparent background, ready to lay over anything. Safari and Apple's frameworks (AVFoundation, AppKit, UIKit) play HEVC-with-alpha. Chrome and Firefox don't decode it.

For those browsers, add `--webm` and you also get a VP9/WebM copy that keeps the alpha channel. To make it we render a temporary ProRes 4444 master and hand that to `ffmpeg`, which must be on your PATH. We deliberately don't hand ffmpeg the HEVC `.mov`: ffmpeg builds older than 8.0 can't decode HEVC's alpha layer and silently write an opaque WebM. Version 8 and later decode it fine, but the ProRes route works on any build. Serve both files, with the `.mov` first:

```html
<video autoplay loop muted playsinline>
  <source src="demo-framed.mov" type="video/quicktime" />
  <source src="demo-framed.webm" type="video/webm" />
</video>
```

The order matters. Safari can play VP9/WebM but drops its alpha channel, so if you list the WebM first, Safari shows your transparency as solid black. With the `.mov` first, Safari takes the HEVC-alpha file, while Chrome and Firefox skip `video/quicktime` and fall through to the WebM.

If you pass `--output` for a transparent export, the path must end in `.mov`. The WebM lands beside it with a `.webm` extension.

### Flags

```
bezelbub frame --input <path> [options]
bezelbub devices [--input <path> | --dimensions WxH] [--json]
```

Options for `frame`:

| Flag | What it does |
| --- | --- |
| `--input`, `-i` | The screenshot (PNG, JPEG, HEIC) or video (`.mov`, `.mp4`, `.m4v`, chosen by extension). Required. |
| `--device`, `-d` | A device id from `bezelbub devices`. Leave it out to detect from pixel size. |
| `--color`, `-c` | A color name or id, case-insensitive. Defaults to the device's default color. |
| `--orientation` | `portrait`, `landscape`, or `auto` (the default, taken from the input's shape). |
| `--background` | A hex color (`#RRGGBB` or `#RRGGBBAA`) or `transparent`. Defaults to transparent for images and black for video. `transparent` on a video switches the output to HEVC-with-alpha `.mov`. |
| `--output-size` | Scale the result, keeping the bezel's aspect: a width (`1920`), an exact `WxH` that matches the aspect, or a percentage (`50%`). Images go from 16 to 16,384 px, videos from 16 to 7,680 px. |
| `--output`, `-o` | Where to write the result. Defaults to `<input>-framed.png`, `.mp4`, or `.mov` beside the input. |
| `--webm` | Also write a VP9/WebM copy with alpha. Video with `--background transparent` only; needs ffmpeg on PATH. |
| `--json` | Print a JSON result on stdout instead of a text summary. |

`devices` lists the whole catalog (ids, display names, colors, orientations, screen sizes, and each display device's known capture sizes), or narrows it to the devices that fit an `--input` file or a bare `--dimensions` value. Filtering always exits 0. An empty `matches` array is the signal that nothing fits, and `nearest` (by aspect ratio) fills in when that happens.

### JSON output

`frame --json` prints one object:

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

`kind` is `"image"` or `"video"`. For video you also get `"transparent": true|false` and, when `--webm` ran, the `"webm"` output path. `devices --json` prints an array of `{id, displayName, defaultColor, colors, landscapeOnly, hasPortraitBezel, screenWidth, screenHeight, captureSizes}`. With `--input` or `--dimensions` it prints `{width, height, matches, nearest}` using the same device objects, and `nearest` is filled only when `matches` is empty.

### Exit codes

Each failure type has its own code, so a script can branch without parsing stderr:

| Code | Meaning |
| --- | --- |
| 0 | Success |
| 1 | A flag value we couldn't parse, such as a malformed `--background` or `--output-size` |
| 2 | Unknown, ambiguous, or undetectable device. stderr lists the candidates. |
| 3 | Unknown color. stderr lists the device's valid colors. |
| 4 | We couldn't read the input image or video |
| 5 | Compositing or video export failed |
| 6 | We couldn't write the output |
| 7 | The `--webm` conversion failed because ffmpeg is missing from PATH or returned an error |
| 64 | Malformed arguments (the standard `EX_USAGE`) |

### For AI agents

We built the CLI for non-interactive, programmatic use, by LLM agents (Claude Code, MCP tool wrappers, CI bots) as much as by people:

- **Nothing prompts.** Every input is a flag with a default, so a call either finishes or fails right away.
- **Both subcommands take `--json`** and return the shapes shown above.
- **Errors tell you how to fix them.** stderr includes did-you-mean device and color ids, the devices that fit the input's pixel size, and the nearest sizes, so an agent can correct the next call without a human.
- **Exit codes 2 through 7 name the failure type** (table above), so an agent can branch without reading text.
- **Pipes stay clean.** We only print video-export progress to stderr when it's a TTY, so captured output stays parseable.
- A typical agent flow: run `bezelbub devices --input shot.png --json` to check the match, then `bezelbub frame --input shot.png --json` and read `output` from the result.

This repo also includes a ready-made **Claude Code skill** at [`skills/bezelbub-cli/`](skills/bezelbub-cli/SKILL.md) that teaches an agent the whole workflow. To install it for all your projects, copy it into your user skills directory:

```sh
cp -R skills/bezelbub-cli ~/.claude/skills/
```

There is also an MCP server, [`@dgr_labs/bezelbub-mcp`](bezelbub-mcp/), that wraps the CLI as `frame_image`, `frame_video`, and `list_devices` tools.

## Requirements

- macOS 14 or later, iOS 17 or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## How it's put together

The framing engine lives in **`BezelbubKit`**, a Swift package with no UI (`BezelbubKit/`). It does one transformation, from a screenshot, a device id, and an orientation to a framed image, using Core Graphics only, so it runs fully offscreen with no SwiftUI, no app state, and no GUI session. Video framing lives in a sibling product, **`BezelbubVideoKit`**, built on AVFoundation, so still-image consumers like the Share Extension don't pull in the video pipeline. The macOS app, the iOS app, the Share Extension, and the `bezelbub` CLI are all thin clients of these packages. The bezel and mask assets ship inside `BezelbubKit` and resolve through `Bundle.module`.

## Building it

We generate the apps with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
open Bezelbub.xcodeproj
```

Schemes:
- **Bezelbub** builds the macOS app
- **Bezelbub-iOS** builds the iOS app and the Share Extension

The engine and CLI build with SwiftPM:

```sh
cd BezelbubKit
swift build            # BezelbubKit library and the bezelbub CLI
swift test             # engine round-trip tests
```

## License

Copyright 2026 DGR Labs, LLC. All rights reserved.
