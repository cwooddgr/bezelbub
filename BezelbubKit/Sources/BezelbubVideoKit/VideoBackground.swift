import CoreGraphics

/// Background for a framed video export.
///
/// `.color` fills behind the bezel and writes an opaque MP4 (H.264/HEVC).
/// `.transparent` keeps the area behind the bezel clear and writes HEVC with
/// alpha in a QuickTime `.mov` — the only alpha-capable video format
/// AVFoundation can encode. Alpha playback is limited to Safari and Apple
/// frameworks; convert to VP9/WebM (via ffmpeg) for other browsers.
public enum VideoBackground {
    case color(CGColor)
    case transparent
}
