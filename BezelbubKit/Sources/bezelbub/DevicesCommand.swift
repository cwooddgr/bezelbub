import ArgumentParser
import BezelbubKit
import Foundation

struct Devices: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "devices",
        abstract: "List device ids, colors, and screen sizes; optionally filter to a screenshot's matches.",
        discussion: """
        Examples:
          bezelbub devices                          # full catalog, human-readable
          bezelbub devices --json                   # full catalog, machine-readable
          bezelbub devices --input shot.png         # which devices fit this screenshot?
          bezelbub devices --dimensions 1206x2622   # same, without an image on disk

        When filtering, devices whose screen pixel size matches the query are \
        listed; if none match, the nearest devices by aspect ratio are shown \
        instead (in JSON, under "nearest"). Filtering exits 0 either way — an \
        empty "matches" array is the signal, not the exit code.
        """
    )

    @Option(help: "Filter to devices whose screen matches this screenshot's pixel size.")
    var input: String?

    @Option(help: "Filter to devices matching a pixel size like 1206x2622 (width x height).")
    var dimensions: String?

    @Flag(help: "Emit JSON instead of human-readable text.")
    var json = false

    func validate() throws {
        if input != nil && dimensions != nil {
            throw ValidationError("Pass --input or --dimensions, not both.")
        }
    }

    func run() throws {
        let devices = DeviceCatalog.hydrated()

        if let size = try querySize() {
            try listMatches(for: size, in: devices)
            return
        }

        if json {
            print(try JSON.string(devices.map(DeviceInfo.init)))
            return
        }

        for device in devices {
            let orientation = device.hasPortraitBezel ? "portrait + landscape" : "landscape"
            let colors = device.colors.map(\.id).joined(separator: ", ")
            print(device.id)
            print("    name:    \(device.displayName)")
            print("    colors:  \(colors)  (default: \(device.defaultColor.id))")
            print("    orient:  \(orientation)")
            if let region = device.screenRegion {
                print("    screen:  \(Int(region.width))×\(Int(region.height)) px")
            }
        }
    }

    /// The pixel size to filter by, from `--input` or `--dimensions`; nil when
    /// neither flag is set (full listing).
    private func querySize() throws -> (width: Int, height: Int)? {
        if let input {
            guard let image = loadImage(at: URL(fileURLWithPath: input)) else {
                throw fail(
                    "Could not read input image at \(input). Expected a PNG, JPEG, or HEIC file.",
                    code: .unreadableInput
                )
            }
            return (image.width, image.height)
        }
        if let dimensions {
            guard let size = parseDimensions(dimensions) else {
                throw fail(
                    "Invalid --dimensions '\(dimensions)'. Use WIDTHxHEIGHT, e.g. 1206x2622.",
                    code: .usage
                )
            }
            return size
        }
        return nil
    }

    private func listMatches(for size: (width: Int, height: Int), in devices: [DeviceDefinition]) throws {
        let matches = DeviceMatcher.match(
            screenshotWidth: size.width,
            screenshotHeight: size.height,
            devices: devices
        ).map(\.device)
        let nearest = matches.isEmpty
            ? DeviceMatcher.nearest(
                screenshotWidth: size.width,
                screenshotHeight: size.height,
                devices: devices
            ).map(\.device)
            : []

        if json {
            let result = DeviceMatchResult(
                width: size.width,
                height: size.height,
                matches: matches.map(DeviceInfo.init),
                nearest: nearest.map(DeviceInfo.init)
            )
            print(try JSON.string(result))
            return
        }

        if matches.isEmpty {
            print("No device screen matches \(size.width)×\(size.height) px. Nearest by aspect ratio:")
            print(deviceList(nearest))
        } else {
            print("Devices matching \(size.width)×\(size.height) px:")
            print(deviceList(matches))
        }
    }
}
