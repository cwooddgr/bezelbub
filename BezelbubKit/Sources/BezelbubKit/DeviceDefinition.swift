import Foundation
import CoreGraphics

public struct DeviceColor: Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public let fileComponent: String

    public init(_ name: String, file: String? = nil) {
        self.id = name
        self.displayName = name
        self.fileComponent = file ?? name
    }
}

public struct DeviceDefinition: Identifiable {
    public let id: String
    public let displayName: String
    public let colors: [DeviceColor]
    public let defaultColorID: String
    public var screenRegion: CGRect?
    /// When true, the device has special screenshot handling: variable-resolution
    /// inputs are upscaled to match the bezel's screen region and matched by aspect
    /// ratio (e.g. Apple TV accepts both 1080p and 4K). Implies no portrait bezel.
    public var landscapeOnly: Bool = false
    /// Whether a portrait bezel PNG exists for this device. Macs/iMac ship landscape-only
    /// bezels but are otherwise "normal" (pixel-matched, no screenshot rescaling).
    public var hasPortraitBezel: Bool = true
    /// Pixel sizes a screenshot or screen recording of this display can have —
    /// one per macOS display-zoom preset ("Larger Text" … "More Space"), i.e.
    /// the preset's point size × 2, plus any 1× modes — in landscape. Empty for
    /// devices whose captures are always the native panel size (iPhone, iPad).
    /// A capture whose size is in this list identifies the device exactly, the
    /// way a native-resolution capture identifies an iPhone; display devices
    /// still fall back to aspect-ratio matching for sizes not listed here
    /// (see `DeviceMatcher`). Sources are noted per entry in `DeviceCatalog`.
    public var captureSizes: [CGSize] = []

    public var defaultColor: DeviceColor {
        colors.first { $0.id == defaultColorID } ?? colors[0]
    }

    public func bezelFileName(color: DeviceColor, landscape: Bool) -> String {
        let slug = color.fileComponent.lowercased().replacingOccurrences(of: " ", with: "")
        let useLandscape = landscape || !hasPortraitBezel
        return "\(id)-\(slug)-\(useLandscape ? "l" : "p").png"
    }
}

public enum DeviceCatalog {
    /// Capture sizes in pixels, written as (width, height) pairs.
    private static func px(_ pairs: (Int, Int)...) -> [CGSize] {
        pairs.map { CGSize(width: $0.0, height: $0.1) }
    }

    /// macOS display-zoom capture sizes per panel. Each preset "looks like"
    /// W×H points and captures at 2W×2H pixels. The 15" Air list was enumerated
    /// on hardware (CGDisplayCopyAllDisplayModes, MacBook Air 15" M4,
    /// 2026-09-11) and matches Wikipedia's table exactly, which is why the other
    /// MacBook rows are taken from the same Wikipedia tables ("MacBook Air
    /// (Apple silicon)", "MacBook Pro (Apple silicon)"; the Pro rows also match
    /// 9to5Mac's 2021 list from the Monterey RC). The iMac 24" row was likewise
    /// enumerated on hardware. Neo and Studio Display rows come from owner
    /// reports on MacRumors/Apple Support Communities and carry lower
    /// confidence; a size missing here only costs precision, since the
    /// aspect-ratio fallback still matches it.
    private enum MacCaptures {
        /// 2560×1664 panel (MacBook Air 13" M2/M3/M4/M5): looks-like 1710×1112,
        /// 1470×956 (default), 1280×832 (native), 1024×666.
        static let air13 = px((3420, 2224), (2940, 1912), (2560, 1664), (2048, 1332))
        /// 2880×1864 panel (MacBook Air 15" M2/M3/M4/M5): looks-like 1920×1243,
        /// 1710×1107 (default), 1440×932 (native), 1280×828, 1024×663.
        /// The panel also exposes 16:10 "notch hidden" modes (3840×2400 …
        /// 2048×1280, and 1920×1200 at 1×) whose captures omit the menu-bar
        /// strip; they're 3.6% off the bezel's aspect and would need the
        /// compositor to letterbox that strip, so they're deliberately not
        /// listed — same for the other notched MacBooks.
        static let air15 = px((3840, 2486), (3420, 2214), (2880, 1864), (2560, 1656), (2048, 1326))
        /// 3024×1964 panel (MacBook Pro 14" M1 Pro → M5): looks-like 1800×1169,
        /// 1512×982 (default, native), 1352×878, 1147×745, 1024×665.
        static let pro14 = px((3600, 2338), (3024, 1964), (2704, 1756), (2294, 1490), (2048, 1330))
        /// 3456×2234 panel (MacBook Pro 16" M1 Pro → M5): looks-like 2056×1329,
        /// 1728×1117 (default, native), 1496×967, 1312×848, 1168×755.
        static let pro16 = px((4112, 2658), (3456, 2234), (2992, 1934), (2624, 1696), (2336, 1510))
        /// 2408×1506 panel (MacBook Neo): looks-like 1637×1024, 1408×881
        /// (default — a scaled mode, not native), 1204×753 (native), 1024×640.
        /// Owner-reported (MacRumors "Neo Display Thoughts?", 2026); single source.
        static let neo = px((3274, 2048), (2816, 1762), (2408, 1506), (2048, 1280))
        /// 4480×2520 panel (iMac 24" M1/M3/M4): presets looks-like 2560×1440,
        /// 2240×1260 (default, native), 1920×1080, 1600×900, 1280×720; plus the
        /// "Show all resolutions" modes — 1120×630 and 960×540 at 2×, and the
        /// 1× modes down to 1152×648 — all 16:9. Enumerated on hardware
        /// (CGDisplayCopyAllDisplayModes, iMac 24" M1, 2026-09-11).
        static let imac24 = px(
            (5120, 2880), (4480, 2520), (3840, 2160), (3200, 1800), (2560, 1440),
            (2240, 1260), (1920, 1080), (1680, 945), (1600, 900), (1280, 720), (1152, 648)
        )
        /// 5120×2880 panel (Studio Display, 2022 and 2026, and XDR): looks-like
        /// 3200×1800, 2880×1620, 2560×1440 (default, native), 2048×1152,
        /// 1600×900 — the 5K list, with 1920×1080 also offered. The top three
        /// are owner-confirmed; the lower ones are the standard 5K set.
        static let studio = px((6400, 3600), (5760, 3240), (5120, 2880), (4096, 2304), (3840, 2160), (3200, 1800))
        /// Apple TV 4K captures at 1080p or 4K.
        static let appleTV = px((3840, 2160), (1920, 1080))
    }

    public static let allDevices: [DeviceDefinition] = [
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

        // MARK: - iPhone 18 family
        DeviceDefinition(
            id: "iphone18pro",
            displayName: "iPhone 18 Pro",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Black"),
                DeviceColor("Burgundy"),
                DeviceColor("Glacier"),
            ],
            defaultColorID: "Silver"
        ),
        DeviceDefinition(
            id: "iphone18promax",
            displayName: "iPhone 18 Pro Max",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Black"),
                DeviceColor("Burgundy"),
                DeviceColor("Glacier"),
            ],
            defaultColorID: "Silver"
        ),

        // MARK: - iPhone Duo
        // The foldable is three catalog entries, one per Apple bezel view, each
        // with a single screen region: the inner display (open), the outer
        // display with the device closed, and the outer display with the device
        // open, seen from the back. Apple ships the last one once, as a wide
        // canvas with a portrait screen; that's our portrait file, and the
        // landscape file is the same art rotated 90° with the display on top.
        // The two outer views share a resolution, so an outer-display screenshot
        // lists both as candidates; "closed" comes last to win the default.
        DeviceDefinition(
            id: "iphoneduo",
            displayName: "iPhone Duo",
            colors: [
                DeviceColor("Night Sky"),
                DeviceColor("Star White"),
            ],
            defaultColorID: "Night Sky"
        ),
        DeviceDefinition(
            id: "iphoneduoouteropen",
            displayName: "iPhone Duo (open, outer display)",
            colors: [
                DeviceColor("Night Sky"),
                DeviceColor("Star White"),
            ],
            defaultColorID: "Night Sky"
        ),
        DeviceDefinition(
            id: "iphoneduoouter",
            displayName: "iPhone Duo (closed, outer display)",
            colors: [
                DeviceColor("Night Sky"),
                DeviceColor("Star White"),
            ],
            defaultColorID: "Night Sky"
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
            hasPortraitBezel: false,
            captureSizes: MacCaptures.appleTV
        ),

        // MARK: - Mac family
        DeviceDefinition(
            id: "macbookair13",
            displayName: "MacBook Air 13\"",
            colors: [DeviceColor("Midnight")],
            defaultColorID: "Midnight",
            hasPortraitBezel: false,
            captureSizes: MacCaptures.air13
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
            hasPortraitBezel: false,
            captureSizes: MacCaptures.air13
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
            hasPortraitBezel: false,
            captureSizes: MacCaptures.air15
        ),
        DeviceDefinition(
            id: "macbookpro14",
            displayName: "MacBook Pro 14\"",
            colors: [DeviceColor("Silver")],
            defaultColorID: "Silver",
            hasPortraitBezel: false,
            captureSizes: MacCaptures.pro14
        ),
        DeviceDefinition(
            id: "macbookprom514",
            displayName: "MacBook Pro 14\" M5",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Space Black"),
            ],
            defaultColorID: "Silver",
            hasPortraitBezel: false,
            captureSizes: MacCaptures.pro14
        ),
        DeviceDefinition(
            id: "macbookpro16",
            displayName: "MacBook Pro 16\"",
            colors: [DeviceColor("Silver")],
            defaultColorID: "Silver",
            hasPortraitBezel: false,
            captureSizes: MacCaptures.pro16
        ),
        DeviceDefinition(
            id: "macbookprom516",
            displayName: "MacBook Pro 16\" M5",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Space Black"),
            ],
            defaultColorID: "Silver",
            hasPortraitBezel: false,
            captureSizes: MacCaptures.pro16
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
            hasPortraitBezel: false,
            captureSizes: MacCaptures.neo
        ),
        DeviceDefinition(
            id: "imac24",
            displayName: "iMac 24\"",
            colors: [DeviceColor("Silver")],
            defaultColorID: "Silver",
            hasPortraitBezel: false,
            captureSizes: MacCaptures.imac24
        ),
        // Apple's "Studio Displays" pack ships four PNGs — Studio Display and
        // Studio Display XDR, each "on light" and "on dark" background — that are
        // pixel-identical, so one entry covers all of them. Screen hole 5120×2880;
        // XDR captures (6016×3384) are 16:9 too and match by aspect ratio.
        DeviceDefinition(
            id: "studiodisplay",
            displayName: "Studio Display (2026)",
            colors: [DeviceColor("Silver")],
            defaultColorID: "Silver",
            hasPortraitBezel: false,
            captureSizes: MacCaptures.studio
        ),
        DeviceDefinition(
            id: "imacm4",
            displayName: "iMac 24\" M4",
            colors: [
                DeviceColor("Silver"),
                DeviceColor("Blue"),
                DeviceColor("Green"),
                DeviceColor("Orange"),
                DeviceColor("Pink"),
                DeviceColor("Purple"),
                DeviceColor("Yellow"),
            ],
            defaultColorID: "Silver",
            hasPortraitBezel: false,
            captureSizes: MacCaptures.imac24
        ),
    ]

    /// The catalog with each device's `screenRegion` populated from the bundled
    /// regions map. Callers should use this for matching and compositing —
    /// `allDevices` alone has `nil` screen regions until hydrated.
    public static func hydrated() -> [DeviceDefinition] {
        ScreenRegionDetector.detectAll(devices: allDevices)
    }
}
