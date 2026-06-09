import ArgumentParser

/// `bezelbub` — a headless front end to BezelbubKit so other apps and AI agents
/// can frame screenshots without driving the GUI. Every input is a flag with a
/// sensible default; nothing prompts interactively.
@main
struct Bezelbub: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bezelbub",
        abstract: "Composite Apple device bezels onto screenshots.",
        version: "1.0.0",
        subcommands: [Frame.self, Devices.self]
    )
}
