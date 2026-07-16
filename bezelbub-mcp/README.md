# @dgrlabs/bezelbub-mcp

MCP (Model Context Protocol) server for [Bezelbub](https://dgrlabs.co): frame
screenshots and screen recordings in realistic Apple device bezels — iPhone,
iPad, MacBook, iMac, and Apple TV device mockups — straight from an AI
assistant. Supports transparent HEVC-with-alpha video export (with an optional
VP9/WebM copy for Chrome/Firefox).

The server is a thin stdio adapter over the `bezelbub` CLI: every tool shells
out to the CLI in `--json` mode, and the CLI's exit codes and suggestion-rich
stderr are surfaced as MCP tool errors.

> **macOS only.** The Bezelbub engine is a macOS-native binary (Core Graphics /
> AVFoundation), so this server runs only on a Mac. The npm package declares
> `"os": ["darwin"]` and will refuse to install elsewhere.

## Prerequisites

- macOS 14+
- Node.js 18+
- The `bezelbub` CLI:

```sh
brew install cwooddgr/tap/bezelbub
```

The server finds the CLI via the `BEZELBUB_CLI_PATH` environment variable if
set, otherwise on `PATH` (plus the standard Homebrew locations
`/opt/homebrew/bin` and `/usr/local/bin`, since GUI apps launch MCP servers
with a minimal `PATH`).

## Setup

### Claude Code

```sh
claude mcp add bezelbub -- npx -y @dgrlabs/bezelbub-mcp
```

### Claude Desktop

Open the config file (Claude menu › Settings… › Developer › Edit Config), which
lives at `~/Library/Application Support/Claude/claude_desktop_config.json`, and
add:

```json
{
  "mcpServers": {
    "bezelbub": {
      "command": "npx",
      "args": ["-y", "@dgrlabs/bezelbub-mcp"]
    }
  }
}
```

Then restart Claude Desktop.

### Desktop Extension (.mcpb)

The repo includes a `manifest.json` conforming to the
[MCPB](https://github.com/modelcontextprotocol/mcpb) spec. To build a
one-click-installable bundle:

```sh
npm ci && npm run build
npx @anthropic-ai/mcpb pack
```

## Tools

### `frame_image`

Frame a screenshot in a device bezel; writes a framed PNG.

| Parameter | Required | Description |
|---|---|---|
| `input_path` | yes | Absolute path to a PNG/JPEG/HEIC screenshot |
| `device` | no | Device id (e.g. `iphone17pro`); auto-detected from pixel size when omitted |
| `color` | no | Bezel color name (e.g. `Cosmic Orange`); device default when omitted |
| `orientation` | no | `portrait` \| `landscape` \| `auto` (default) |
| `background` | no | Hex color (`#FFFFFF`, `#RRGGBBAA`) or `transparent` (default) |
| `output_size` | no | Width (`1920`), exact size (`1920x988`), or percentage (`50%`) |
| `output_path` | no | Defaults to `<input>-framed.png` beside the input |

Returns JSON: `{kind: "image", device, color, orientation, output, width, height}`.

### `frame_video`

Frame a screen recording (`.mov`/`.mp4`/`.m4v`) in a device bezel; writes a
framed MP4 with audio preserved. `background: "transparent"` switches the
export to HEVC-with-alpha in a QuickTime `.mov` (plays in Safari and Apple
frameworks only); `webm: true` additionally writes a VP9/WebM copy for
Chrome/Firefox (requires `ffmpeg` on `PATH`).

Same parameters as `frame_image`, plus `webm` (boolean); `background` defaults
to black for video. Returns JSON:
`{kind: "video", transparent, output, webm?, device, color, orientation, width, height}`.

### `list_devices`

List the 38-device bezel catalog (ids, colors, screen pixel sizes), or — with
`input_path` or `dimensions` (`"1206x2622"`) — find which devices fit a given
screenshot, recording, or pixel size. Filtered results return
`{width, height, matches, nearest}`; an empty `matches` array means no exact
fit and `nearest` lists the closest devices by aspect ratio.

## Error handling

CLI failures come back as MCP tool errors carrying the CLI's stderr — which
already includes concrete fixes (valid device ids, a device's color list,
nearest screen sizes) — plus the documented meaning of the exit code (2 unknown
or ambiguous device, 3 unknown color, 4 unreadable input, 5 composite/export
failed, 6 write failed, 7 ffmpeg missing for `--webm`).

## Environment variables

| Variable | Purpose |
|---|---|
| `BEZELBUB_CLI_PATH` | Explicit path to the `bezelbub` binary (overrides `PATH` lookup) |
| `BEZELBUB_TIMEOUT_MS` | Per-call CLI timeout in milliseconds (default 600000; raise for long video exports) |

## Development

```sh
npm ci
npm run build      # tsc → dist/
npm test           # builds, then runs an end-to-end MCP-over-stdio test
                   # (requires the bezelbub CLI; generates its own test image)
```

## License

MIT © DGR Labs
