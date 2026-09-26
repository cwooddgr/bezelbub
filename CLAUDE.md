# Bezelbub

macOS + iOS app that composites device bezels onto screenshots and screen recordings. Built with SwiftUI, targeting macOS 14+ and iOS 17+. Tier 1, live on the Mac and iOS App Stores. Also ships the headless `bezelbub` CLI (GitHub release + Homebrew tap) and an MCP server (`bezelbub-mcp/`, npm `@dgr_labs/bezelbub-mcp`). Bundle ID `co.dgrlabs.bezelbub`, team `2CTUXD4C44`, ASC app id `6759073631`.

**Status: 3.4.0 (macOS build 18 / iOS build 14) live on both stores since 2026-09-12; no submission pending.** Replace this line at each submission and outcome so the session-start status check stays accurate; history goes in `docs/release.md`.

## Docs map

| Topic | File |
|---|---|
| Project structure, engine/adapters architecture, MCP server detail, bezel-asset regeneration | `docs/architecture.md` |
| CLI flags, output rules, exit codes | `docs/cli.md` |
| Archive/export/upload recipe, submitting to App Review, status history | `docs/release.md` |
| MCP registry and directory listings | `bezelbub-mcp/REGISTRY_SUBMISSIONS.md` |
| App Store listing copy | `APP_STORE_METADATA.md` |
| Design plans | `docs/plans/` |

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

MCP server (from `bezelbub-mcp/`): `npm test`. Bezel masks and `screen-regions.json`: `Scripts/generate-screen-regions.swift` (details in `docs/architecture.md`).

Targets: **Bezelbub** (macOS), **Bezelbub-iOS** (iOS), **BezelbubShareExtension** (embedded in Bezelbub-iOS), and **bezelbub** (SwiftPM CLI in `BezelbubKit/`, not in the Xcode project). Schemes: **Bezelbub** (macOS app), **Bezelbub-iOS** (iOS app + share extension).

## Architecture in brief

- `BezelbubKit/` is the UI-free engine (Core Graphics, runs offscreen; bezel/mask assets via `Bundle.module`). `BezelbubVideoKit` is a separate library product for video (AVFoundation/CoreImage) so the share extension doesn't link it.
- The apps (`Shared/`, `macOS/`, `iOS/`), the share extension, and the CLI are thin clients of that package. The MCP server wraps the CLI over a process boundary (`frame_image`, `frame_video`, `list_devices`).
- `Apple Product Bezels/` is gitignored source art, local reference only.

## Rules that have bitten us

- swift-argument-parser is a CLI-only dependency; it must not end up linked into the apps.
- A transparent video background goes through the custom Core Image compositor on both platforms (CALayer alpha is unverified; on iOS it doesn't composite correctly at all).
- `--webm` hands ffmpeg a ProRes 4444 master, never the HEVC `.mov`: ffmpeg before 8.0 silently drops HEVC alpha.
- The MCP server reads its version from `package.json` at runtime (a 0.2.0 once shipped announcing itself as 0.1.0).
- MCP tool argument schemas are a compatibility surface: clients cache the tool list per session. Add optional fields rather than retyping, bump as breaking, and tell users to restart their client in release notes.
- Asset flood fill falls back to the largest enclosed transparent region when the center is opaque (iPhone Duo); the Duo `-l` bezel is the `-p` art rotated 90° counter-clockwise.

## Settled: don't propose changing (decided-by-user)

Glama listing skipped: its checks run on Linux, so a macOS-only server would never be searchable (2026-09-11). The MCP update check runs on demand during a tool call, at most every six hours, never on a timer or at startup (2026-09-13; `bezelbub-mcp/src/update-check.ts`). Rationale in `docs/architecture.md`.

## Releases

- **Who submits**: the workspace `CLAUDE.md` standing permission (decided-by-user 2026-09-21); never resubmit after a rejection without asking. Mechanics and the ASC calls in `docs/release.md`.
- Before any submission, read `../APP_STORE_REJECTIONS.md` and `../APP_STORE_RELEASE.md`.
- Bump `MARKETING_VERSION` and each `CURRENT_PROJECT_VERSION` in `project.yml` (macOS and iOS build numbers run independently), `xcodegen generate`, commit, tag `vX.Y.Z`; then archive/export per scheme and run `Scripts/asc_prepare_version.py` (`--submit` only on Charlie's say-so). Full recipe in `docs/release.md`.
- The CLI (`cli-vX.Y.Z` release + Homebrew tap) and the MCP server (npm + registry) are separate releases with their own versions. Publishing the MCP server needs Charlie (npm OTP, browser device flow for `mcp-publisher login github`).
