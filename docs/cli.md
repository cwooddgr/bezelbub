# Bezelbub CLI

> **Author:** Claude Code (coder) · **Date:** 2026-09-26 · **Status:** moved verbatim from `CLAUDE.md` when it was slimmed (decided-by-user 2026-09-26); provenance stamps inside the text are the originals.

### CLI usage

```sh
bezelbub devices [--input <path> | --dimensions WxH] [--json]
bezelbub frame --input <path> [--device <id>] [--color <name>] \
               [--orientation portrait|landscape|auto] \
               [--background <hex>|transparent] [--webm] \
               [--output-size <width|WxH|N%>] [--output <path>] [--json]
```

`frame` is the default subcommand (`bezelbub --input shot.png` works). Image inputs (PNG/JPEG/HEIC) write a framed PNG; video inputs (`.mov`/`.mp4`/`.m4v`, routed by extension) write a framed MP4 with audio preserved — `--background` defaults to black there (images default to transparent). `--background transparent` on a video exports HEVC-with-alpha in a QuickTime `.mov` instead (default output `<input>-framed.mov`; an explicit `--output` must end in `.mov`). Transparent video plays in Safari/Apple frameworks only; `--webm` additionally writes a VP9/WebM copy for Chrome/Firefox by rendering a ProRes 4444 master and converting it with ffmpeg (found on PATH; the master is temporary). ffmpeg gets ProRes, never the HEVC `.mov` — ffmpeg builds before 8.0 can't decode HEVC's alpha layer and silently produce an opaque WebM (8+ decodes it correctly — verified empirically on 8.1.2 — but the ProRes bridge works on any build). `--device` is optional: omitted, it's auto-detected from the input's pixel size (iPhone/iPad by screen size; Macs and displays by the exact capture size of each macOS display-zoom preset, tabulated per panel in `DeviceCatalog.MacCaptures`, with aspect-ratio matching as the fallback); ambiguous or unmatched sizes fail with candidate/nearest-device lists. `--output-size` scales the output preserving the bezel's aspect (a width, an exact `WxH`, or a percentage; limits mirror the app: 16–16384 px image, 16–7680 px video). `devices --input/--dimensions` answers "which devices fit this input" directly (JSON shape: `{width, height, matches, nearest}`).

Agent-friendly: every input is a flag with a default, `--json` gives machine-readable output (`kind` says image or video; video adds `transparent` and, with `--webm`, the `webm` path), errors go to stderr with concrete suggestions (did-you-mean ids via `DeviceCatalog.suggestDevices/suggestColors`, dimension matches) and distinct nonzero exit codes (2 unknown/ambiguous/undetectable device, 3 unknown color, 4 unreadable input, 5 composite/export failed, 6 write failed, 7 ffmpeg missing or errored for `--webm`; argument-parsing errors use ArgumentParser's EX_USAGE 64). Exit codes are documented in `bezelbub --help`. Video export progress goes to stderr only when it's a TTY, so piped/agent callers see clean output.

