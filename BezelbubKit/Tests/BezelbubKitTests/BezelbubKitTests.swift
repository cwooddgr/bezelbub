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
