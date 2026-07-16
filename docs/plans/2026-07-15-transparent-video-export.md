# Transparent Video Export — Design Spec

> **Author:** Claude Code (planner)
> **Date:** 2026-07-15
> **Status:** proposed-by-agent — feature requested by Charlie (spec across macOS + iOS + CLI, decided-by-user); all design choices below are proposals pending review.

## Goal

Let users export framed **videos** with a transparent background, the way framed images
already default to transparency. Output is **HEVC with alpha in a QuickTime `.mov`**
container — the only alpha video format AVFoundation can encode.

## Format facts (verified against Apple docs, 2026-07-15)

- `AVAssetExportPresetHEVCHighestQualityWithAlpha` — iOS 13+/macOS 10.15+ (our floors:
  iOS 17/macOS 14). Encodes HEVC video + AAC audio; audio tracks carry through as today.
- Apple's sample code pairs the preset with `outputFileType = .mov`.
- Playback: Safari + Apple frameworks (AVPlayer/AVPlayerLayer) honor the alpha; Chrome,
  Firefox, and Edge do **not**. The cross-browser story is a WebM/VP9 conversion via
  ffmpeg (AVFoundation cannot encode VP9/WebM) — we document it, we don't bundle it.

## Engine — `BezelbubVideoKit`

New background representation on `VideoFrameCompositor.export`:

```swift
public enum VideoBackground: Sendable {
    case color(CGColor)      // current behavior → H.264/HEVC .mp4
    case transparent         // HEVC-with-alpha .mov
}
```

Replace the `backgroundColor: CGColor` parameter with `background: VideoBackground`
(all three callers — macOS app, iOS app, CLI — update in the same commit; no
deprecation shim needed for a local package).

When `.transparent`:

1. Preset: `AVAssetExportPresetHEVCHighestQualityWithAlpha`, `outputFileType = .mov`
   (caller-supplied `exportPreset` override is ignored in transparent mode).
2. Guard availability with `AVAssetExportSession(asset:presetName:)` failing →
   new `VideoExportError.alphaExportUnsupported` with a clear message, rather than the
   generic `exportSessionFailed`.
3. **Compositor path: use `BezelOverlayCompositor` on both platforms.** The macOS
   CALayer/`animationTool` path has unverified alpha semantics (it was already too
   flaky for iOS); the custom compositor is plain CoreImage + BGRA buffers and is
   deterministic about alpha — background becomes `CIImage(color: .clear)`.
   Opaque macOS exports keep the existing CALayer path (zero regression risk).
   - Requires un-gating `BezelOverlayCompositor`/`BezelOverlayInstruction` from
     `#if os(iOS)` in `VideoFrameCompositor.swift` (the files themselves are
     platform-neutral).
4. Verify (test, below) that `ciContext.render` into the output buffer preserves
   alpha end-to-end. This is the one real engineering risk in the feature.

## Apps — UI

*(UI control choice: toggle proposed by agent, pending Charlie's confirmation on look/feel.)*

- `AppState`: add `var videoBackgroundTransparent: Bool = false` alongside
  `videoBackgroundColor`. Preview passes `nil` background to the still-image preview
  compositor when set, so the existing transparent-image checkerboard appears.
- **macOS** (`ContentView.swift:157` area): a `Toggle("Transparent")` next to the
  existing `ColorPicker("Background")`; the color picker is `.disabled()` and dimmed
  while on. Caption under the control:
  *"Exports HEVC with alpha (.mov). Plays in Safari and Apple apps; convert to WebM
  for other browsers."*
- **macOS save panel** (`exportVideo()` in `ContentView.swift:314`):
  `allowedContentTypes = [.quickTimeMovie]` and `-framed.mov` filename when
  transparent; unchanged (`.mpeg4Movie` / `-framed.mp4`) otherwise.
- **iOS** (background controls near `ContentView.swift:330`): same toggle + caption in
  the background sheet. `performVideoExport` writes the temp file with a `.mov`
  extension when transparent; the share sheet's `FileRepresentation(contentType: .movie)`
  already covers QuickTime.

## CLI — `bezelbub frame`

- `--background transparent` becomes valid for video (today video rejects/flattens
  alpha). Images already treat missing `--background` as transparent, so the keyword is
  accepted there too as a no-op synonym.
- Transparent video: default output becomes `<input>-framed.mov`. An explicit
  `--output` with a non-`.mov` extension is a usage error (exit 64) with a message
  saying HEVC-with-alpha requires a QuickTime container — deterministic beats
  silently writing a mislabeled file.
- `--json` gains `"transparent": true|false` for video results.
- **`--webm` flag** (only valid with `--background transparent`; usage error otherwise):
  after the `.mov` export, shell out to ffmpeg —
  `ffmpeg -i <out>.mov -c:v libvpx-vp9 -pix_fmt yuva420p <out>.webm` —
  and report both files (`--json` lists both outputs). ffmpeg is discovered on PATH;
  if absent, fail with a distinct exit code (7, `ffmpeg not found`) and a
  `brew install ffmpeg` hint — deterministic for agent callers, never a silent skip.
  A nonzero ffmpeg exit also maps to exit 7 with ffmpeg's stderr passed through.
- Without `--webm`, a transparent export prints a one-line stderr tip (TTY only, same
  rule as the progress meter) pointing at the flag for Chrome/Firefox playback.
- Help text: document transparent mode, the Safari/Apple-only playback caveat,
  `--webm`, and the manual ffmpeg one-liner for scripted use.
- Version: CLI bump to 1.2.0 + new `cli-v1.2.0` Homebrew release when it ships.

## Tests — `BezelbubKitTests`

1. **Alpha round-trip**: export a tiny transparent-background video, then read the
   first frame back with `AVAssetReader` (BGRA output settings) and assert a corner
   pixel (outside the bezel) has alpha 0 and an in-screen pixel has alpha 255.
2. **Format assertions**: output track codec is HEVC and the format description
   reports `containsAlphaChannel`; audio track count preserved.
3. **CLI**: transparent + `--output foo.mp4` fails with exit 64; default output path
   ends in `-framed.mov`; JSON includes `"transparent": true`; `--webm` without
   `--background transparent` is a usage error; `--webm` with ffmpeg absent from
   PATH exits 7 with the install hint (simulate by clearing PATH in the test).

## Implementation notes

> **Author:** Claude Code (coder)
> **Date:** 2026-07-15
> **Status:** proposed-by-agent (design deviations discovered during implementation; verified by tests and real-file probes)

- **ffmpeg cannot reliably decode HEVC's alpha layer**, so `--webm` does NOT
  feed ffmpeg the final HEVC `.mov`. It renders a temporary **ProRes 4444
  master** (second full export) and converts that. ffmpeg 8.1.1 on this
  machine empirically *does* decode HEVC alpha, but older/common versions
  silently return an all-opaque alpha channel — a silent-corruption failure
  mode the ProRes route eliminates, while also giving VP9 a lossless source.
- **Probe gotcha for future verification**: ffmpeg's *native* VP9 decoder
  ignores WebM's alpha side-channel and reports every pixel opaque. Alpha
  checks must force the libvpx decoder: `ffmpeg -c:v libvpx-vp9 -i in.webm …`.
- In transparent mode the engine now **honors a caller-supplied
  `exportPreset` if it is alpha-capable** (that's how the CLI requests the
  ProRes master), defaulting to HEVC-with-alpha. Consequently the iOS app
  passes `nil` preset when transparent — its usual
  `AVAssetExportPresetHighestQuality` would flatten alpha.
- iOS UI: the controls bar is a horizontal ScrollView, so the toggle fits
  (scrolls); the format caption lives in the video export sheet's footer
  instead of the bar. Charlie's iPhone-fit eyeball check still applies.
- Verified on `~/Desktop/1978.mov` (landscape iPhone 17 Pro recording):
  native and 50% scaled transparent exports both show fully-transparent
  surroundings, opaque screen content, thousands of partial-alpha
  (anti-aliased) edge pixels, AAC audio in the .mov and Opus in the WebM;
  the WebM histogram matches the .mov.

## Out of scope

- Bundling ffmpeg or encoding VP9/WebM in-process. The CLI's `--webm` only delegates
  to a PATH-discovered ffmpeg; the apps never touch ffmpeg at all.
- Partial-alpha backgrounds (a 40%-opaque color over nothing) — the UI is binary:
  a color, or fully transparent.
- Share extension — it is image-only and stays that way.

## Resolved questions

> **Author:** Claude Code (planner)
> **Date:** 2026-07-15
> **Status:** decided-by-user

- Control: **toggle** next to the color picker (not a segmented control).
- Persistence: **reset per session**, like the rest of the video styling — no
  persisted preference.
- Charlie flagged a layout concern: the toggle + caption may not fit comfortably in
  the iPhone background controls — **eyeball this on an iPhone-size device during
  testing** and adjust the layout if it's cramped.
- VP9/WebM: **apps document only; CLI gets `--webm`** with an ffmpeg shell-out
  (details in the CLI section). Neither app bundles or invokes ffmpeg.
