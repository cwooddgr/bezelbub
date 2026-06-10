import ArgumentParser

/// `bezelbub` — a headless front end to BezelbubKit so other apps and AI agents
/// can frame screenshots without driving the GUI. Every input is a flag with a
/// sensible default; nothing prompts interactively.
@main
struct Bezelbub: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bezelbub",
        abstract: "Composite Apple device bezels onto screenshots and screen recordings.",
        discussion: """
        Headless and agent-friendly: nothing prompts interactively, every input \
        is a flag, --json makes output machine-readable, and errors go to \
        stderr with concrete suggestions (valid ids, matching devices, nearest \
        sizes) so a failed call tells you how to fix the next one.

        Typical workflow:
          bezelbub devices --json            # device ids, colors, screen sizes
          bezelbub devices --input shot.png  # which devices fit this screenshot?
          bezelbub frame --input shot.png    # frame it (device auto-detected)
          bezelbub frame --input shot.png --device iphone17pro --color Silver
          bezelbub frame --input demo.mp4    # frame a screen recording → MP4

        `frame` is the default subcommand, so `bezelbub --input shot.png` works. \
        Video inputs (.mov/.mp4/.m4v) keep their audio and export as MP4.

        Exit codes:
          0   success
          1   invalid flag value (e.g. malformed --background or --output-size)
          2   unknown, ambiguous, or undetectable device (stderr lists candidates)
          3   unknown color (stderr lists the device's valid colors)
          4   input image or video unreadable
          5   compositing or video export failed
          6   output could not be written
          64  malformed arguments (standard EX_USAGE)
        """,
        version: "1.2.0",
        subcommands: [Frame.self, Devices.self],
        defaultSubcommand: Frame.self
    )
}
