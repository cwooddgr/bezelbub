import ArgumentParser
import BezelbubKit

struct Devices: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "devices",
        abstract: "List available device ids and their colors so agents can discover valid inputs."
    )

    @Flag(help: "Emit JSON instead of human-readable text.")
    var json = false

    func run() throws {
        let devices = DeviceCatalog.hydrated()

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
        }
    }
}
