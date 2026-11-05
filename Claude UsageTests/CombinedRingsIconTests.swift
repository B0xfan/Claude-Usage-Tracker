import XCTest
import AppKit
@testable import Claude_Usage

/// "Both Rings" style: one menu bar icon, weekly outer ring, 5-hour inner ring.
@MainActor
final class CombinedRingsIconTests: XCTestCase {

    private let renderer = MenuBarIconRenderer()

    /// Draws the image into an RGBA buffer and returns the pixels as (r, g, b, a) bytes.
    private func pixels(of image: NSImage) -> (width: Int, height: Int, data: [UInt8]) {
        let width = 48, height = 48
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        data.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            var rect = CGRect(x: 0, y: 0, width: width, height: height)
            let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
            ctx.draw(cg, in: rect)
        }
        return (width, height, data)
    }

    private func isOrange(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) -> Bool {
        a > 200 && r > 200 && g > 90 && g < 190 && b < 80
    }

    /// Alpha at a point given in icon points (24 x 24), measured from the bottom left.
    private func alpha(_ p: (width: Int, height: Int, data: [UInt8]), x: Double, y: Double) -> UInt8 {
        let scale = Double(p.width) / 24
        let px = Int(x * scale), py = p.height - 1 - Int(y * scale)  // CGContext rows start at the top
        return p.data[(py * p.width + px) * 4 + 3]
    }

    func testLowValuesAreAPlainTemplateIcon() {
        let image = renderer.createCombinedRingsIcon(
            sessionPercentage: 12, weekPercentage: 30,
            sessionWarning: false, weekWarning: false, isDarkMode: true
        )
        XCTAssertTrue(image.isTemplate, "No warning: the icon follows the menu bar color")
        XCTAssertEqual(image.size, NSSize(width: 24, height: 24))
        let p = pixels(of: image)
        for i in stride(from: 0, to: p.data.count, by: 4) {
            XCTAssertFalse(isOrange(p.data[i], p.data[i + 1], p.data[i + 2], p.data[i + 3]))
        }
    }

    func testBothRingsAreDrawn() {
        // 100% fills each ring all the way round; check a point on each ring at 3 o'clock.
        let image = renderer.createCombinedRingsIcon(
            sessionPercentage: 100, weekPercentage: 100,
            sessionWarning: false, weekWarning: false, isDarkMode: true
        )
        let p = pixels(of: image)
        XCTAssertGreaterThan(alpha(p, x: 12 + 10, y: 12), 200, "outer ring (weekly)")
        XCTAssertGreaterThan(alpha(p, x: 12 + 5.5, y: 12), 200, "inner ring (5-hour)")
        XCTAssertLessThan(alpha(p, x: 12 + 8, y: 12), 120, "gap between the rings")
        XCTAssertLessThan(alpha(p, x: 12, y: 12), 60, "center stays empty")
    }

    func testHighValueTurnsOrange() {
        let image = renderer.createCombinedRingsIcon(
            sessionPercentage: 92, weekPercentage: 88,
            sessionWarning: true, weekWarning: false, isDarkMode: true
        )
        XCTAssertFalse(image.isTemplate, "A warning needs real colors, so not a template")
        let p = pixels(of: image)
        var orange = 0
        for i in stride(from: 0, to: p.data.count, by: 4)
            where isOrange(p.data[i], p.data[i + 1], p.data[i + 2], p.data[i + 3]) { orange += 1 }
        XCTAssertGreaterThan(orange, 10, "The 5-hour ring is orange near its limit")
        // Outer weekly ring at 88% without warning stays white at 3 o'clock.
        let i = ((p.height / 2) * p.width + Int(22.0 * Double(p.width) / 24)) * 4
        XCTAssertFalse(isOrange(p.data[i], p.data[i + 1], p.data[i + 2], p.data[i + 3]))
    }

    func testBothRingsStyleShowsOneItemForSessionAndWeek() {
        var config = MenuBarIconConfiguration.default
        for i in config.metrics.indices where config.metrics[i].metricType != .api {
            config.metrics[i].isEnabled = true
            config.metrics[i].iconStyle = .icon
        }
        XCTAssertEqual(Set(config.enabledMetrics.map(\.metricType)), [.session, .week])

        if let s = config.metrics.firstIndex(where: { $0.metricType == .session }) {
            config.metrics[s].iconStyle = .rings
        }
        XCTAssertEqual(config.enabledMetrics.map(\.metricType), [.session])
    }
}
