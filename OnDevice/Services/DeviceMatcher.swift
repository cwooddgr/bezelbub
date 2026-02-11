import CoreGraphics

enum DeviceMatcher {
    struct Match {
        let device: DeviceDefinition
        let isLandscape: Bool
    }

    static func match(screenshotWidth: Int, screenshotHeight: Int, devices: [DeviceDefinition]) -> [Match] {
        let portraitW = min(screenshotWidth, screenshotHeight)
        let portraitH = max(screenshotWidth, screenshotHeight)
        let isLandscape = screenshotWidth > screenshotHeight

        var matches: [Match] = []

        for device in devices {
            guard let region = device.screenRegion else { continue }
            let regionW = Int(region.width)
            let regionH = Int(region.height)
            let regionPortraitW = min(regionW, regionH)
            let regionPortraitH = max(regionW, regionH)
            if portraitW == regionPortraitW && portraitH == regionPortraitH {
                matches.append(Match(device: device, isLandscape: isLandscape))
            }
        }

        // Prefer newest devices first (later entries in catalog)
        return matches.reversed()
    }
}
