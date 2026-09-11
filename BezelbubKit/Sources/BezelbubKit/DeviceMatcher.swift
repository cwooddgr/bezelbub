import CoreGraphics

public enum DeviceMatcher {
    public struct Match {
        public let device: DeviceDefinition
        public let isLandscape: Bool
        /// True when the device was matched only by aspect ratio (a display
        /// device — Mac, iMac, Studio Display, Apple TV — at a capture size we
        /// don't have on file), false when the screenshot's pixel size matched
        /// exactly (±1px): the device's screen for iPhones/iPads, or one of its
        /// known display-zoom capture sizes for display devices. Display
        /// devices are rescaled at composite time either way.
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
                // Display devices (Apple TV, Macs/iMac/Studio Display) have no
                // portrait bezel and are captured at many sizes: each macOS
                // display-zoom preset yields its own pixel size. Those sizes are
                // known per panel (`captureSizes`), so a capture at one of them
                // identifies the panel exactly (±1px) — a 3420×2214 capture can
                // only be a 15" MacBook Air. Sizes we don't have on file (an
                // external monitor, a downscaled recording) fall back to aspect
                // ratio (±2%). Either way the screenshot is rescaled to the
                // bezel's screen region at composite time.
                //
                // Panels shared across models stay ambiguous on purpose (every
                // 15" Air generation, Studio Display vs. an iMac at "More Space"
                // vs. Apple TV at 4K); the matcher returns every candidate so
                // the user can disambiguate with the device picker.
                guard isLandscape else { continue }
                let exact = device.captureSizes.contains {
                    abs(Int($0.width) - screenshotWidth) <= 1 && abs(Int($0.height) - screenshotHeight) <= 1
                }
                if exact {
                    matches.append((
                        Match(device: device, isLandscape: true, matchedByAspectRatio: false),
                        aspectError, index
                    ))
                } else if aspectError < 0.02 {
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

        // Once any display device matched a known capture size exactly, the
        // aspect-only display matches are just noise (a 3420×2214 capture is a
        // 15" Air, not "any 16:10 MacBook"), so drop them.
        if matches.contains(where: { !$0.match.matchedByAspectRatio && !$0.match.device.hasPortraitBezel }) {
            matches.removeAll { $0.match.matchedByAspectRatio }
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
