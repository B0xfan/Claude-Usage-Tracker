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

    /// Color at a point given in icon points (24 x 24), measured from the bottom left.
    private func rgba(_ p: (width: Int, height: Int, data: [UInt8]), x: Double, y: Double) -> (UInt8, UInt8, UInt8, UInt8) {
        let scale = Double(p.width) / 24
        let px = Int(x * scale), py = p.height - 1 - Int(y * scale)
        let i = (py * p.width + px) * 4
        return (p.data[i], p.data[i + 1], p.data[i + 2], p.data[i + 3])
    }

    /// systemGreen: green clearly strongest.
    private func isGreen(_ c: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        c.3 > 200 && c.1 > 150 && Int(c.1) > Int(c.0) + 60 && Int(c.1) > Int(c.2) + 40
    }

    /// systemTeal: little red, strong green and blue.
    private func isTeal(_ c: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        c.3 > 200 && c.0 < 140 && c.1 > 140 && c.2 > 160
    }

    func testLowValuesAreGreenInsideTealOutside() {
        for dark in [true, false] {
            let image = renderer.createCombinedRingsIcon(
                sessionPercentage: 30, weekPercentage: 30,
                sessionLevel: .safe, weekLevel: .safe, isDarkMode: dark
            )
            XCTAssertFalse(image.isTemplate, "Always colored, never a template")
            XCTAssertEqual(image.size, NSSize(width: 24, height: 24))
            let p = pixels(of: image)
            // 30% reaches past 3 o'clock on both rings (rings start at 12 and go clockwise).
            XCTAssertTrue(isGreen(rgba(p, x: 12 + 5.5, y: 12)), "inner 5-hour ring is green")
            XCTAssertTrue(isTeal(rgba(p, x: 12 + 10, y: 12)), "outer weekly ring is teal")
            // Empty track (9 o'clock) is still visible but faint.
            let track = rgba(p, x: 12 - 10, y: 12)
            XCTAssertGreaterThan(track.3, 15)
            XCTAssertLessThan(track.3, 120)
            for i in stride(from: 0, to: p.data.count, by: 4) {
                XCTAssertFalse(isOrange(p.data[i], p.data[i + 1], p.data[i + 2], p.data[i + 3]))
            }
        }
    }

    func testBothRingsAreDrawn() {
        // 100% fills each ring all the way round; check a point on each ring at 3 o'clock.
        let image = renderer.createCombinedRingsIcon(
            sessionPercentage: 100, weekPercentage: 100,
            sessionLevel: .safe, weekLevel: .safe, isDarkMode: true
        )
        let p = pixels(of: image)
        XCTAssertGreaterThan(alpha(p, x: 12 + 10, y: 12), 200, "outer ring (weekly)")
        XCTAssertGreaterThan(alpha(p, x: 12 + 5.5, y: 12), 200, "inner ring (5-hour)")
        XCTAssertLessThan(alpha(p, x: 12 + 8, y: 12), 160, "gap between the rings (non-Retina blurs it to about 130; rings are over 200)")
        XCTAssertLessThan(alpha(p, x: 12, y: 12), 60, "center stays empty")
    }

    /// systemRed: strong red, little green and blue.
    private func isRed(_ c: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        c.3 > 200 && c.0 > 200 && c.1 < 90 && c.2 < 90
    }

    private func isOrange(_ c: (UInt8, UInt8, UInt8, UInt8)) -> Bool { isOrange(c.0, c.1, c.2, c.3) }

    /// Draws with the levels upstream's own calculator gives for these used percentages.
    private func icon(session: Double, week: Double, dark: Bool = true) -> (inner: (UInt8, UInt8, UInt8, UInt8), outer: (UInt8, UInt8, UInt8, UInt8)) {
        let image = renderer.createCombinedRingsIcon(
            sessionPercentage: session, weekPercentage: week,
            sessionLevel: UsageStatusCalculator.calculateStatus(usedPercentage: session, showRemaining: false),
            weekLevel: UsageStatusCalculator.calculateStatus(usedPercentage: week, showRemaining: false),
            isDarkMode: dark
        )
        XCTAssertFalse(image.isTemplate)
        let p = pixels(of: image)
        // Every value used here reaches past 3 o'clock, so check both rings there.
        return (rgba(p, x: 12 + 5.5, y: 12), rgba(p, x: 12 + 10, y: 12))
    }

    func testFiveHourRingOnItsOwn() {
        for dark in [true, false] {
            let low = icon(session: 30, week: 30, dark: dark)
            XCTAssertTrue(isGreen(low.inner), "5-hour low: green")
            let mid = icon(session: 75, week: 30, dark: dark)
            XCTAssertTrue(isOrange(mid.inner), "5-hour at 75% (moderate): orange")
            XCTAssertTrue(isTeal(mid.outer), "weekly unaffected")
            let high = icon(session: 92, week: 30, dark: dark)
            XCTAssertTrue(isRed(high.inner), "5-hour at 92% (critical): red")
            XCTAssertTrue(isTeal(high.outer), "weekly unaffected")
        }
    }

    func testWeeklyRingOnItsOwn() {
        for dark in [true, false] {
            let low = icon(session: 30, week: 30, dark: dark)
            XCTAssertTrue(isTeal(low.outer), "weekly low: teal")
            let mid = icon(session: 30, week: 75, dark: dark)
            XCTAssertTrue(isOrange(mid.outer), "weekly at 75% (moderate): orange")
            XCTAssertTrue(isGreen(mid.inner), "5-hour unaffected")
            let high = icon(session: 30, week: 92, dark: dark)
            XCTAssertTrue(isRed(high.outer), "weekly at 92% (critical): red")
            XCTAssertTrue(isGreen(high.inner), "5-hour unaffected")
        }
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
