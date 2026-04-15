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
    var screenRegion: CGRect?
    /// When true, the device has special screenshot handling: variable-resolution
    /// inputs are upscaled to match the bezel's screen region and matched by aspect
    /// ratio (e.g. Apple TV accepts both 1080p and 4K). Implies no portrait bezel.
    var landscapeOnly: Bool = false
    /// Whether a portrait bezel PNG exists for this device. Macs/iMac ship landscape-only
    /// bezels but are otherwise "normal" (pixel-matched, no screenshot rescaling).
    var hasPortraitBezel: Bool = true

    var defaultColor: DeviceColor {
        colors.first { $0.id == defaultColorID } ?? colors[0]
    }

    func bezelFileName(color: DeviceColor, landscape: Bool) -> String {
        let slug = color.fileComponent.lowercased().replacingOccurrences(of: " ", with: "")
        let useLandscape = landscape || !hasPortraitBezel
        return "\(id)-\(slug)-\(useLandscape ? "l" : "p").png"
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
            defaultColorID: "Midnight"
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
            defaultColorID: "Midnight"
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
            defaultColorID: "Space Black"
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
            defaultColorID: "Space Black"
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
            defaultColorID: "Black"
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
            defaultColorID: "Black"
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
            defaultColorID: "Black Titanium"
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
            defaultColorID: "Black Titanium"
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
            defaultColorID: "Black"
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
            defaultColorID: "Black"
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
            defaultColorID: "Black Titanium"
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
            defaultColorID: "Black Titanium"
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
            defaultColorID: "Black"
        ),
        DeviceDefinition(
            id: "iphone17pro",
            displayName: "iPhone 17 Pro",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Cosmic Orange"),
                DeviceColor("Deep Blue"),
            ],
            defaultColorID: "Silver"
        ),
        DeviceDefinition(
            id: "iphone17promax",
            displayName: "iPhone 17 Pro Max",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Cosmic Orange"),
                DeviceColor("Deep Blue"),
            ],
            defaultColorID: "Silver"
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
            defaultColorID: "Space Black"
        ),

        // MARK: - iPad family
        DeviceDefinition(
            id: "ipad",
            displayName: "iPad",
            colors: [DeviceColor("Silver")],
            defaultColorID: "Silver"
        ),
        DeviceDefinition(
            id: "ipada16",
            displayName: "iPad (A16)",
            colors: [
                DeviceColor("Blue"),
                DeviceColor("Pink"),
                DeviceColor("Silver"),
                DeviceColor("Yellow"),
            ],
            defaultColorID: "Silver"
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
            defaultColorID: "Space Gray"
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
            defaultColorID: "Space Gray"
        ),
        DeviceDefinition(
            id: "ipadair11m4",
            displayName: "iPad Air 11\" M4",
            colors: [
                DeviceColor("Blue"),
                DeviceColor("Purple"),
                DeviceColor("Space Gray"),
                DeviceColor("Starlight"),
            ],
            defaultColorID: "Space Gray"
        ),
        DeviceDefinition(
            id: "ipadair13m4",
            displayName: "iPad Air 13\" M4",
            colors: [
                DeviceColor("Blue"),
                DeviceColor("Purple"),
                DeviceColor("Space Gray"),
                DeviceColor("Starlight"),
            ],
            defaultColorID: "Space Gray"
        ),
        DeviceDefinition(
            id: "ipadmini",
            displayName: "iPad mini",
            colors: [DeviceColor("Starlight")],
            defaultColorID: "Starlight"
        ),
        DeviceDefinition(
            id: "ipadminia17pro",
            displayName: "iPad mini (A17 Pro)",
            colors: [
                DeviceColor("Blue"),
                DeviceColor("Purple"),
                DeviceColor("Space Gray"),
                DeviceColor("Starlight"),
            ],
            defaultColorID: "Space Gray"
        ),
        DeviceDefinition(
            id: "ipadpro11m4",
            displayName: "iPad Pro 11\" M4",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Space Gray"),
            ],
            defaultColorID: "Silver"
        ),
        DeviceDefinition(
            id: "ipadpro13m4",
            displayName: "iPad Pro 13\" M4",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Space Gray"),
            ],
            defaultColorID: "Silver"
        ),
        DeviceDefinition(
            id: "ipadpro11m5",
            displayName: "iPad Pro 11\" M5",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Space Black"),
            ],
            defaultColorID: "Silver"
        ),
        DeviceDefinition(
            id: "ipadpro13m5",
            displayName: "iPad Pro 13\" M5",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Space Black"),
            ],
            defaultColorID: "Silver"
        ),

        // MARK: - Apple TV
        DeviceDefinition(
            id: "appletv4k",
            displayName: "Apple TV 4K",
            colors: [DeviceColor("Black")],
            defaultColorID: "Black",
            landscapeOnly: true,
            hasPortraitBezel: false
        ),

        // MARK: - Mac family
        DeviceDefinition(
            id: "macbookair13",
            displayName: "MacBook Air 13\"",
            colors: [DeviceColor("Midnight")],
            defaultColorID: "Midnight",
            hasPortraitBezel: false
        ),
        DeviceDefinition(
            id: "macbookairm513",
            displayName: "MacBook Air 13\" M5",
            colors: [
                DeviceColor("Midnight"),
                DeviceColor("Silver"),
                DeviceColor("Sky Blue"),
                DeviceColor("Starlight"),
            ],
            defaultColorID: "Midnight",
            hasPortraitBezel: false
        ),
        DeviceDefinition(
            id: "macbookairm515",
            displayName: "MacBook Air 15\" M5",
            colors: [
                DeviceColor("Midnight"),
                DeviceColor("Silver"),
                DeviceColor("Sky Blue"),
                DeviceColor("Starlight"),
            ],
            defaultColorID: "Midnight",
            hasPortraitBezel: false
        ),
        DeviceDefinition(
            id: "macbookpro14",
            displayName: "MacBook Pro 14\"",
            colors: [DeviceColor("Silver")],
            defaultColorID: "Silver",
            hasPortraitBezel: false
        ),
        DeviceDefinition(
            id: "macbookprom514",
            displayName: "MacBook Pro 14\" M5",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Space Black"),
            ],
            defaultColorID: "Silver",
            hasPortraitBezel: false
        ),
        DeviceDefinition(
            id: "macbookpro16",
            displayName: "MacBook Pro 16\"",
            colors: [DeviceColor("Silver")],
            defaultColorID: "Silver",
            hasPortraitBezel: false
        ),
        DeviceDefinition(
            id: "macbookprom516",
            displayName: "MacBook Pro 16\" M5",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Space Black"),
            ],
            defaultColorID: "Silver",
            hasPortraitBezel: false
        ),
        DeviceDefinition(
            id: "macbookneo",
            displayName: "MacBook Neo",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Blush"),
                DeviceColor("Citrus"),
                DeviceColor("Indigo"),
            ],
            defaultColorID: "Silver",
            hasPortraitBezel: false
        ),
        DeviceDefinition(
            id: "imac24",
            displayName: "iMac 24\"",
            colors: [DeviceColor("Silver")],
            defaultColorID: "Silver",
            hasPortraitBezel: false
        ),
    ]
}
