---
name: bezelbub-cli
description: Frame screenshots and screen recordings in realistic Apple device bezels (iPhone, iPad, Mac, Apple TV) using the bezelbub CLI. Use when the user wants a screenshot or screen recording wrapped in a device frame / device mockup — e.g. "put this in an iPhone bezel", "make a device mockup of this recording", "export this demo video with a transparent background".
---

# bezelbub CLI

`bezelbub` composites Apple device bezels onto screenshots (PNG/JPEG/HEIC → framed PNG) and screen recordings (`.mov`/`.mp4`/`.m4v` → framed MP4, audio preserved). It is fully non-interactive: every input is a flag, nothing prompts, `--json` gives machine-readable output, and failures use distinct exit codes with self-correcting stderr messages.

## 0. Check the binary

```sh
bezelbub --version
```

If missing: `brew install cwooddgr/tap/bezelbub`. If Homebrew is unavailable, it also builds from the Bezelbub repo with `cd BezelbubKit && swift build --product bezelbub`.

## 1. Core commands

```sh
bezelbub devices --json                     # full catalog: ids, colors, screen sizes
bezelbub devices --input shot.png --json    # which devices fit this input?
bezelbub devices --dimensions 1206x2622 --json   # same, without a file

bezelbub frame --input shot.png --json      # frame it (device auto-detected)
bezelbub frame --input demo.mp4 --json      # frame a recording → MP4
```

`frame` is the default subcommand (`bezelbub --input shot.png` works). Always pass `--json` when calling programmatically.

`frame` flags: `--input/-i` (required), `--device/-d` (omit to auto-detect from pixel size), `--color/-c` (case-insensitive name or id; defaults to the device default), `--orientation portrait|landscape|auto`, `--background <hex>|transparent` (default: transparent for images, black for video), `--output-size <width|WxH|N%>` (aspect-preserving; 16–16384 px images, 16–7680 px video), `--output/-o` (default `<input>-framed.png|.mp4|.mov` beside the input), `--webm`, `--json`.

## 2. Device selection

- Omit `--device` first — auto-detection from pixel size usually works.
- If the size matches several devices, the command exits 2 and stderr lists candidate ids; re-run with `--device <id>` (ask the user which device if it matters, or pick the newest listed).
- If nothing matches, stderr suggests the nearest devices by aspect ratio. Prefer resizing/recapturing the input at a native screen size; forcing `--device` on a mismatched size composites at native pixel size and looks wrong.
- To check before framing: `bezelbub devices --input <path> --json` → `{width, height, matches, nearest}`. That query always exits 0; an empty `matches` array is the "no fit" signal.

## 3. Interpreting results

`frame --json` prints one object to stdout:

```json
{"kind": "image|video", "device": "...", "color": "...", "orientation": "portrait|landscape",
 "output": "/abs/path", "width": 1350, "height": 2760}
```

Video results add `"transparent": true|false` and, when `--webm` ran, a `"webm"` path. Report the `output` (and `webm`) paths to the user.

Exit codes — branch on these, not stderr text:

| Code | Meaning | Recovery |
| --- | --- | --- |
| 0 | success | read JSON from stdout |
| 1 | invalid flag value (bad `--background`/`--output-size`) | fix the value per stderr |
| 2 | unknown/ambiguous/undetectable device | stderr lists candidate ids; re-run with `--device` |
| 3 | unknown color | stderr lists the device's valid colors |
| 4 | input unreadable | check path/format (PNG/JPEG/HEIC or .mov/.mp4/.m4v) |
| 5 | compositing or video export failed | usually not caller-fixable; surface the error |
| 6 | output could not be written | check destination path/permissions |
| 7 | ffmpeg missing or failed (`--webm`) | `brew install ffmpeg`, or drop `--webm` |
| 64 | malformed arguments (EX_USAGE) | fix flags (e.g. `--webm` without `--background transparent`) |

Video progress goes to stderr only on a TTY, so captured stdout is clean JSON.

## 4. Recipes

```sh
# Screenshot → framed PNG, auto-detected device
bezelbub frame --input shot.png --json

# Specific device, color, background, size
bezelbub frame --input shot.png --device iphone17pro --color "Cosmic Orange" \
               --background "#1D1D1F" --output-size 50% --json

# Screen recording → framed MP4 (audio preserved, black background)
bezelbub frame --input demo.mp4 --json

# Transparent video: HEVC-with-alpha QuickTime .mov
# (plays in Safari/Apple frameworks ONLY — warn the user about that)
bezelbub frame --input demo.mp4 --background transparent --json

# Transparent + a VP9/WebM copy with alpha for Chrome/Firefox (needs ffmpeg)
bezelbub frame --input demo.mp4 --background transparent --webm --json
```

Transparent-video rules: output container is `.mov` (an explicit `--output` must end in `.mov`, else exit 64). `--webm` requires a video input *and* `--background transparent`. For web embedding, offer both files with the `.mov` `<source>` listed **first** and the `.webm` second — Safari can play WebM but drops its alpha channel (opaque black background), so it must pick the HEVC `.mov`, while Chrome/Firefox skip `video/quicktime` and fall through to the WebM. Prefer `--webm` over converting the HEVC `.mov` with ffmpeg yourself: ffmpeg builds older than 8.0 can't decode HEVC's alpha and silently produce an opaque WebM (no error — verify output transparency if you must convert directly, which is safe only on ffmpeg 8+). `--webm` avoids the issue on any ffmpeg build by rendering a ProRes 4444 master internally.
