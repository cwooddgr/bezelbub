import CoreGraphics

public enum DeviceMatcher {
    public struct Match {
        public let device: DeviceDefinition
        public let isLandscape: Bool
        /// True when the device was matched by aspect ratio (display devices —
        /// Macs, iMac, Apple TV — whose screenshots arrive at many scaled
        /// resolutions and are rescaled at composite time), false when the
        /// screenshot's pixel size matched the device's screen exactly (±1px).
        public let matchedByAspectRatio: Bool
    }

    public static func match(screenshotWidth: Int, screenshotHeight: Int, devices: [DeviceDefinition]) -> [Match] {
        let portraitW = min(screenshotWidth, screenshotHeight)
        let portraitH = max(screenshotWidth, screenshotHeight)
        let isLandscape = screenshotWidth > screenshotHeight
        // Orientation-independent aspect (always ≥ 1) for ranking candidates.
        let screenshotAspect = Double(portraitH) / Double(portraitW)

        // Track each match's aspect error and catalog index so we can order by
        // closest aspect first, breaking ties toward the newest device.
        var matches: [(match: Match, aspectError: Double, index: Int)] = []

        for (index, device) in devices.enumerated() {
            guard let region = device.screenRegion else { continue }

            let regionLong = Double(max(region.width, region.height))
            let regionShort = Double(min(region.width, region.height))
            let regionAspect = regionLong / regionShort
            let aspectError = abs(screenshotAspect - regionAspect) / regionAspect

            if !device.hasPortraitBezel {
                // Display devices (Apple TV, Macs/iMac) have no portrait bezel and
                // are captured at many scaled resolutions, so match by aspect ratio
                // (±2%) rather than exact pixels — e.g. Apple TV accepts both
                // 1920×1080 and 3840×2160, and an iMac at any "More Space" scaled
                // setting still resolves to the same 16:9 bezel. The screenshot is
                // rescaled to the bezel's screen region at composite time.
                //
                // 16:9 displays (Apple TV, iMac) are mutually ambiguous, as are the
                // ~16:10 MacBooks; the matcher returns every candidate so the user
                // can disambiguate with the device picker.
                guard isLandscape else { continue }
                if aspectError < 0.02 {
                    matches.append((
                        Match(device: device, isLandscape: true, matchedByAspectRatio: true),
                        aspectError, index
                    ))
                }
            } else {
                let regionW = Int(region.width)
                let regionH = Int(region.height)
                let regionPortraitW = min(regionW, regionH)
                let regionPortraitH = max(regionW, regionH)
                // Allow ±1px tolerance — iOS screenshots can differ by 1px from display resolution
                if abs(portraitW - regionPortraitW) <= 1 && abs(portraitH - regionPortraitH) <= 1 {
                    matches.append((
                        Match(device: device, isLandscape: isLandscape, matchedByAspectRatio: false),
                        aspectError, index
                    ))
                }
            }
        }

        // Closest aspect first so the default selection is the best fit; ties
        // (e.g. Apple TV vs iMac, both 16:9, or two iPhones sharing a resolution)
        // break toward the newest device (later catalog entry).
        return matches
            .sorted { lhs, rhs in
                lhs.aspectError != rhs.aspectError
                    ? lhs.aspectError < rhs.aspectError
                    : lhs.index > rhs.index
            }
            .map(\.match)
    }
}
