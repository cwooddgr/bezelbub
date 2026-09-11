import CoreGraphics
import XCTest
@testable import BezelbubKit

final class BezelbubKitTests: XCTestCase {

    // The catalog hydrates from the bundled screen-regions.json, so every device
    // should come back with a non-nil screen region. This also proves Bundle.module
    // resolves the package resources outside any app.
    func testHydratedCatalogHasScreenRegions() {
        let devices = DeviceCatalog.hydrated()
        XCTAssertFalse(devices.isEmpty, "Catalog should not be empty")
        for device in devices {
            XCTAssertNotNil(
                device.screenRegion,
                "Expected a precomputed screen region for \(device.id)"
            )
        }
    }

    // A native-resolution capture should resolve to its device. iPhone 17 Pro's
    // portrait screen region is the device's native pixel size.
    func testMatcherResolvesNativeResolution() throws {
        let devices = DeviceCatalog.hydrated()
        let iphone = try XCTUnwrap(devices.first { $0.id == "iphone17pro" })
        let region = try XCTUnwrap(iphone.screenRegion)

        let matches = DeviceMatcher.match(
            screenshotWidth: Int(region.width),
            screenshotHeight: Int(region.height),
            devices: devices
        )
        XCTAssertTrue(
            matches.contains { $0.device.id == "iphone17pro" },
            "iPhone 17 Pro native resolution should match itself"
        )
    }

    // End-to-end: composite a solid screenshot at the device's screen-region size
    // and confirm we get a framed image strictly larger than the screen hole
    // (the bezel surrounds the screen on all sides).
    func testCompositeProducesFramedImage() throws {
        let devices = DeviceCatalog.hydrated()
        let device = try XCTUnwrap(devices.first { $0.id == "iphone17pro" })
        let region = try XCTUnwrap(device.screenRegion)

        let screenshot = try XCTUnwrap(
            makeSolidImage(width: Int(region.width), height: Int(region.height))
        )

        let framed = try XCTUnwrap(
            FrameCompositor.composite(
                screenshot: screenshot,
                device: device,
                color: device.defaultColor,
                isLandscape: false
            ),
            "Compositing should succeed for a native-size portrait screenshot"
        )

        XCTAssertGreaterThan(framed.width, Int(region.width))
        XCTAssertGreaterThan(framed.height, Int(region.height))
    }

    // MARK: - Suggestions

    // A one-typo device id should still surface the intended device.
    func testSuggestDevicesToleratesTypo() {
        let devices = DeviceCatalog.allDevices
        let suggestions = DeviceCatalog.suggestDevices(matching: "iphone17por", in: devices)
        XCTAssertTrue(
            suggestions.contains { $0.id == "iphone17pro" },
            "Expected 'iphone17por' to suggest iphone17pro, got \(suggestions.map(\.id))"
        )
    }

    // A display-name fragment should match by substring across the family.
    func testSuggestDevicesMatchesDisplayNameSubstring() {
        let devices = DeviceCatalog.allDevices
        let suggestions = DeviceCatalog.suggestDevices(matching: "macbook", in: devices)
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertTrue(suggestions.allSatisfy { $0.id.hasPrefix("macbook") })
    }

    // Spaces and case in a display name shouldn't matter: "iPhone Air" → iphoneair.
    func testSuggestDevicesNormalizesDisplayName() {
        let devices = DeviceCatalog.allDevices
        let suggestions = DeviceCatalog.suggestDevices(matching: "iPhone Air", in: devices)
        XCTAssertEqual(suggestions.first?.id, "iphoneair")
    }

    func testSuggestColorsToleratesTypo() throws {
        let device = try XCTUnwrap(DeviceCatalog.allDevices.first { $0.id == "iphone16" })
        let suggestions = DeviceCatalog.suggestColors(matching: "blak", in: device)
        XCTAssertEqual(suggestions.first?.id, "Black")
    }

    // An arbitrary portrait size matches nothing exactly, but nearest-by-aspect
    // should return portrait-capable devices only (no landscape-only Macs/TV).
    func testNearestExcludesLandscapeOnlyForPortraitInput() {
        let devices = DeviceCatalog.hydrated()
        let nearest = DeviceMatcher.nearest(
            screenshotWidth: 1000, screenshotHeight: 2000, devices: devices
        )
        XCTAssertFalse(nearest.isEmpty)
        XCTAssertTrue(
            nearest.allSatisfy { $0.device.hasPortraitBezel },
            "Portrait input should never suggest landscape-only devices, got "
                + "\(nearest.map(\.device.id))"
        )
    }

    // MARK: - iPhone Duo

    // The Duo's "open, outer display" bezel is the one catalog image whose
    // center pixel is opaque (it lands on the hinge), so the runtime detector
    // must fall back from the center seed to the enclosed transparent region.
    // Its region must equal the precomputed one and the closed-outer region's
    // size — same physical display.
    func testDuoOuterOpenRegionDetectsOffCenterScreen() throws {
        let fileName = "iphoneduoouteropen-nightsky-p.png"
        let detected = try XCTUnwrap(
            ScreenRegionDetector.detectScreenRegion(bezelFileName: fileName),
            "Runtime flood-fill should find the off-center screen hole"
        )
        let bundled = try XCTUnwrap(ScreenRegionDetector.bundledRegions[fileName])
        XCTAssertEqual(detected, bundled)

        let closed = try XCTUnwrap(ScreenRegionDetector.bundledRegions["iphoneduoouter-nightsky-p.png"])
        XCTAssertEqual(detected.size, closed.size)
        XCTAssertGreaterThan(detected.minX, 1000, "Screen sits on the right half of the wide canvas")
    }

    // An outer-display screenshot is ambiguous between the closed and open
    // views; both must be offered, closed first (the default), and the inner
    // display must resolve to the single "iphoneduo" entry.
    func testDuoOuterDisplayListsBothViews() throws {
        let devices = DeviceCatalog.hydrated()
        let outer = try XCTUnwrap(devices.first { $0.id == "iphoneduoouter" }?.screenRegion)
        let matches = DeviceMatcher.match(
            screenshotWidth: Int(outer.width), screenshotHeight: Int(outer.height), devices: devices
        )
        XCTAssertEqual(matches.map(\.device.id), ["iphoneduoouter", "iphoneduoouteropen"])

        let inner = try XCTUnwrap(devices.first { $0.id == "iphoneduo" }?.screenRegion)
        let innerMatches = DeviceMatcher.match(
            screenshotWidth: Int(inner.width), screenshotHeight: Int(inner.height), devices: devices
        )
        XCTAssertEqual(innerMatches.map(\.device.id), ["iphoneduo"])
    }

    // iPhone 18 Pro shares its screen with 17 Pro; the newer device should be
    // listed first among the candidates.
    func testIPhone18ProRanksFirstAtSharedResolution() {
        let devices = DeviceCatalog.hydrated()
        let matches = DeviceMatcher.match(screenshotWidth: 1206, screenshotHeight: 2622, devices: devices)
        XCTAssertEqual(matches.first?.device.id, "iphone18pro")
        XCTAssertTrue(matches.contains { $0.device.id == "iphone17pro" })
    }

    // MARK: - Displays

    // A native 5K capture is 16:9, so every 16:9 display device is a candidate
    // (matched by aspect ratio), with the newest catalog entry — iMac M4 — first.
    func testFiveKCaptureListsSixteenByNineDisplays() {
        let devices = DeviceCatalog.hydrated()
        let matches = DeviceMatcher.match(screenshotWidth: 5120, screenshotHeight: 2880, devices: devices)
        let ids = matches.map(\.device.id)
        XCTAssertEqual(ids.first, "imacm4")
        for expected in ["studiodisplay", "imac24", "appletv4k"] {
            XCTAssertTrue(ids.contains(expected), "Expected \(expected) among \(ids)")
        }
        XCTAssertTrue(matches.allSatisfy(\.matchedByAspectRatio))
    }

    // MARK: - Helpers

    private func makeSolidImage(width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
