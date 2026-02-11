import Foundation
import CoreGraphics

struct DeviceColor: Identifiable, Hashable {
    let id: String
    let displayName: String
    let fileComponent: String

    init(_ name: String, file: String? = nil) {
        self.id = name
        self.displayName = name
        self.fileComponent = file ?? name
    }
}

struct DeviceDefinition: Identifiable {
    let id: String
    let displayName: String
    let colors: [DeviceColor]
    let defaultColorID: String
    let bezelFilePrefix: String
    var screenRegion: CGRect?

    var defaultColor: DeviceColor {
        colors.first { $0.id == defaultColorID } ?? colors[0]
    }

    func bezelFileName(color: DeviceColor, landscape: Bool) -> String {
        "\(bezelFilePrefix) - \(color.fileComponent) - \(landscape ? "Landscape" : "Portrait").png"
    }
}

enum DeviceCatalog {
    static let allDevices: [DeviceDefinition] = [
        // MARK: - iPhone 14 family
        DeviceDefinition(
            id: "iphone14",
            displayName: "iPhone 14",
            colors: [
                DeviceColor("Blue"),
                DeviceColor("Midnight"),
                DeviceColor("Purple"),
                DeviceColor("Red"),
                DeviceColor("Starlight"),
            ],
            defaultColorID: "Midnight",
            bezelFilePrefix: "iPhone 14"
        ),
        DeviceDefinition(
            id: "iphone14plus",
            displayName: "iPhone 14 Plus",
            colors: [
                DeviceColor("Blue"),
                DeviceColor("Midnight"),
                DeviceColor("Purple"),
                DeviceColor("Red"),
                DeviceColor("Starlight"),
            ],
            defaultColorID: "Midnight",
            bezelFilePrefix: "iPhone 14 Plus"
        ),
        DeviceDefinition(
            id: "iphone14pro",
            displayName: "iPhone 14 Pro",
            colors: [
                DeviceColor("Deep Purple"),
                DeviceColor("Gold"),
                DeviceColor("Silver"),
                DeviceColor("Space Black"),
            ],
            defaultColorID: "Space Black",
            bezelFilePrefix: "iPhone 14 Pro"
        ),
        DeviceDefinition(
            id: "iphone14promax",
            displayName: "iPhone 14 Pro Max",
            colors: [
                DeviceColor("Deep Purple"),
                DeviceColor("Gold"),
                DeviceColor("Silver"),
                DeviceColor("Space Black"),
            ],
            defaultColorID: "Space Black",
            bezelFilePrefix: "iPhone 14 Pro Max"
        ),

        // MARK: - iPhone 15 family
        DeviceDefinition(
            id: "iphone15",
            displayName: "iPhone 15",
            colors: [
                DeviceColor("Black"),
                DeviceColor("Blue"),
                DeviceColor("Green"),
                DeviceColor("Pink"),
                DeviceColor("Yellow"),
            ],
            defaultColorID: "Black",
            bezelFilePrefix: "iPhone 15"
        ),
        DeviceDefinition(
            id: "iphone15plus",
            displayName: "iPhone 15 Plus",
            colors: [
                DeviceColor("Black"),
                DeviceColor("Blue"),
                DeviceColor("Green"),
                DeviceColor("Pink"),
                DeviceColor("Yellow"),
            ],
            defaultColorID: "Black",
            bezelFilePrefix: "iPhone 15 Plus"
        ),
        DeviceDefinition(
            id: "iphone15pro",
            displayName: "iPhone 15 Pro",
            colors: [
                DeviceColor("Black Titanium"),
                DeviceColor("Blue Titanium"),
                DeviceColor("Natural Titanium"),
                DeviceColor("White Titanium"),
            ],
            defaultColorID: "Black Titanium",
            bezelFilePrefix: "iPhone 15 Pro"
        ),
        DeviceDefinition(
            id: "iphone15promax",
            displayName: "iPhone 15 Pro Max",
            colors: [
                DeviceColor("Black Titanium"),
                DeviceColor("Blue Titanium"),
                DeviceColor("Natural Titanium"),
                DeviceColor("White Titanium"),
            ],
            defaultColorID: "Black Titanium",
            bezelFilePrefix: "iPhone 15 Pro Max"
        ),

        // MARK: - iPhone 16 family
        DeviceDefinition(
            id: "iphone16",
            displayName: "iPhone 16",
            colors: [
                DeviceColor("Black"),
                DeviceColor("Pink"),
                DeviceColor("Teal"),
                DeviceColor("Ultramarine"),
                DeviceColor("White"),
            ],
            defaultColorID: "Black",
            bezelFilePrefix: "iPhone 16"
        ),
        DeviceDefinition(
            id: "iphone16plus",
            displayName: "iPhone 16 Plus",
            colors: [
                DeviceColor("Black"),
                DeviceColor("Pink"),
                DeviceColor("Teal"),
                DeviceColor("Ultramarine"),
                DeviceColor("White"),
            ],
            defaultColorID: "Black",
            bezelFilePrefix: "iPhone 16 Plus"
        ),
        DeviceDefinition(
            id: "iphone16pro",
            displayName: "iPhone 16 Pro",
            colors: [
                DeviceColor("Black Titanium"),
                DeviceColor("Desert Titanium"),
                DeviceColor("Natural Titanium"),
                DeviceColor("White Titanium"),
            ],
            defaultColorID: "Black Titanium",
            bezelFilePrefix: "iPhone 16 Pro"
        ),
        DeviceDefinition(
            id: "iphone16promax",
            displayName: "iPhone 16 Pro Max",
            colors: [
                DeviceColor("Black Titanium"),
                DeviceColor("Desert Titanium"),
                DeviceColor("Natural Titanium"),
                DeviceColor("White Titanium"),
            ],
            defaultColorID: "Black Titanium",
            bezelFilePrefix: "iPhone 16 Pro Max"
        ),

        // MARK: - iPhone 17 family
        DeviceDefinition(
            id: "iphone17",
            displayName: "iPhone 17",
            colors: [
                DeviceColor("Black"),
                DeviceColor("Lavender"),
                DeviceColor("Mist Blue"),
                DeviceColor("Sage"),
                DeviceColor("White"),
            ],
            defaultColorID: "Black",
            bezelFilePrefix: "iPhone 17"
        ),
        DeviceDefinition(
            id: "iphone17pro",
            displayName: "iPhone 17 Pro",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Cosmic Orange"),
                DeviceColor("Deep Blue"),
            ],
            defaultColorID: "Silver",
            bezelFilePrefix: "iPhone 17 Pro"
        ),
        DeviceDefinition(
            id: "iphone17promax",
            displayName: "iPhone 17 Pro Max",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Cosmic Orange"),
                DeviceColor("Deep Blue"),
            ],
            defaultColorID: "Silver",
            bezelFilePrefix: "iPhone 17 Pro Max"
        ),
        DeviceDefinition(
            id: "iphoneair",
            displayName: "iPhone Air",
            colors: [
                DeviceColor("Cloud White"),
                DeviceColor("Light Gold"),
                DeviceColor("Sky Blue"),
                DeviceColor("Space Black"),
            ],
            defaultColorID: "Space Black",
            bezelFilePrefix: "iPhone Air"
        ),

        // MARK: - iPad family
        DeviceDefinition(
            id: "ipad",
            displayName: "iPad",
            colors: [DeviceColor("Silver")],
            defaultColorID: "Silver",
            bezelFilePrefix: "iPad"
        ),
        DeviceDefinition(
            id: "ipadair11m2",
            displayName: "iPad Air 11\" M2",
            colors: [
                DeviceColor("Blue"),
                DeviceColor("Purple"),
                DeviceColor("Space Gray"),
                DeviceColor("Stardust"),
            ],
            defaultColorID: "Space Gray",
            bezelFilePrefix: "iPad Air 11\" - M2"
        ),
        DeviceDefinition(
            id: "ipadair13m2",
            displayName: "iPad Air 13\" M2",
            colors: [
                DeviceColor("Blue"),
                DeviceColor("Purple"),
                DeviceColor("Space Gray"),
                DeviceColor("Stardust"),
            ],
            defaultColorID: "Space Gray",
            bezelFilePrefix: "iPad Air 13\" - M2"
        ),
        DeviceDefinition(
            id: "ipadmini",
            displayName: "iPad mini",
            colors: [DeviceColor("Starlight")],
            defaultColorID: "Starlight",
            bezelFilePrefix: "iPad mini"
        ),
        DeviceDefinition(
            id: "ipadpro11m4",
            displayName: "iPad Pro 11\" M4",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Space Gray"),
            ],
            defaultColorID: "Silver",
            bezelFilePrefix: "iPad Pro 11 - M4"
        ),
        DeviceDefinition(
            id: "ipadpro13m4",
            displayName: "iPad Pro 13\" M4",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Space Gray"),
            ],
            defaultColorID: "Silver",
            bezelFilePrefix: "iPad Pro 13 - M4"
        ),
    ]
}
