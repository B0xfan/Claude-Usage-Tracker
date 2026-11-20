//
//  ScreenshotChecks.swift
//  Claude UsageTests
//
//  Screenshot naming, shrinking and moving, run from TopShelfTests (so its throwaway settings store is in place).
//  Everything happens in a temporary folder; the real Desktop, Pictures and settings are never touched.
//

import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import Claude_Usage

@MainActor
enum ScreenshotChecks {
    /// A screenshot-like PNG: a soft gradient, some text and a see-through corner, marked 144 dpi like a Retina screenshot.
    static func samplePNG(width: Int = 640, height: Int = 400) throws -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGradient(starting: .systemBlue, ending: .systemTeal)!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 30)
        ("Login page" as NSString).draw(at: NSPoint(x: 40, y: 180), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 40), .foregroundColor: NSColor.white])
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: 40, height: 40).fill(using: .copy)
        NSColor.red.withAlphaComponent(0.5).set()
        NSRect(x: 50, y: 0, width: 40, height: 40).fill(using: .copy)
        NSGraphicsContext.restoreGraphicsState()
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try XCTUnwrap(rep.cgImage), [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    static func run() async throws {
        // Shrinking: smaller, still a PNG of the same size and density, see-through parts kept.
        let png = try samplePNG()
        let small = try XCTUnwrap(PNGShrinker.shrink(png, .balanced), "a gradient screenshot shrinks")
        XCTAssertLessThan(small.count, png.count)
        XCTAssertEqual(Array(small.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let src = try XCTUnwrap(CGImageSourceCreateWithData(small as CFData, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(cg.width, 640); XCTAssertEqual(cg.height, 400)
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        XCTAssertEqual((props?[kCGImagePropertyDPIWidth] as? Double).map { $0.rounded() }, 144)
        let bmp = NSBitmapImageRep(cgImage: cg)
        XCTAssertLessThan(try XCTUnwrap(bmp.colorAt(x: 10, y: 390)).alphaComponent, 0.05, "clear corner stays clear")
        let half = try XCTUnwrap(bmp.colorAt(x: 70, y: 390)).alphaComponent
        XCTAssertEqual(half, 0.5, accuracy: 0.1, "half see-through stays half")
        for level in ShrinkLevel.allCases {
            if let s = PNGShrinker.shrink(png, level) { XCTAssertLessThan(s.count, png.count, "\(level) never makes it bigger") }
        }
        XCTAssertNil(PNGShrinker.shrink(Data("not a picture".utf8), .smaller))
        // A Display P3 screenshot keeps its colour profile, so its colours don't shift.
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: p3,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.drawLinearGradient(CGGradient(colorsSpace: p3, colors: [CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 1, blue: 0, alpha: 1)] as CFArray, locations: nil)!,
                               start: .zero, end: CGPoint(x: 300, y: 200), options: [])
        let p3PNG = NSMutableData()
        let p3Dest = try XCTUnwrap(CGImageDestinationCreateWithData(p3PNG, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(p3Dest, try XCTUnwrap(ctx.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(p3Dest))
        let p3Small = try XCTUnwrap(PNGShrinker.shrink(p3PNG as Data, .balanced))
        let p3Back = try XCTUnwrap(CGImageSourceCreateImageAtIndex(XCTUnwrap(CGImageSourceCreateWithData(p3Small as CFData, nil)), 0, nil))
        let back = try XCTUnwrap(p3Back.colorSpace)   // a palette picture: the profile sits on its base colour space
        XCTAssertEqual((back.baseColorSpace ?? back).copyICCData() as Data?, p3.copyICCData() as Data?, "same colour profile")

        // Which files count.
        let words = ["Screenshot", "clop", "cleanyard"]
        XCTAssertTrue(Screenshots.isNew("Screenshot 2026-11-19 at 12.39.10.png", words: words))
        XCTAssertTrue(Screenshots.isNew("CLOP_2026-11-19_1061.png", words: words))
        XCTAssertFalse(Screenshots.isNew(".Screenshot 2026-11-19 at 12.39.10.png", words: words), "the Mac's hidden file while it saves")
        XCTAssertFalse(Screenshots.isNew("Screenshot notes.txt", words: words))
        XCTAssertFalse(Screenshots.isNew("Login page (2026-11-19 12.39.10).png", words: words), "already named")
        XCTAssertTrue(Screenshots.isNamed("Login page (2026-11-19 12.39.10).png"))
        XCTAssertFalse(Screenshots.isNew("Screenshot settings (2026-11-19 12.39.10) 2.png", words: words), "a taken-name copy is named too, so it is never renamed again")
        XCTAssertFalse(Screenshots.isNew("Screenshot.png", words: []))
        XCTAssertEqual(ScreenshotNamer.sanitize("\"Login: page/report.png\"\n"), "Login pagereport")
        XCTAssertEqual(ScreenshotNamer.sanitize(String(repeating: "word ", count: 30)).count, 64)
        let date = DateComponents(calendar: .current, year: 2026, month: 11, day: 19, hour: 12, minute: 39, second: 10).date!
        XCTAssertEqual(Screenshots.namedForm("Login page", date, ext: "png"), "Login page (2026-11-19 12.39.10).png")

        // One step: named and shrunk, written once, original gone, nothing else in the folder.
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ScreenshotChecks-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let shot = dir.appendingPathComponent("Screenshot 2026-11-19 at 12.39.10.png")
        try png.write(to: shot)
        try fm.setAttributes([.creationDate: date], ofItemAtPath: shot.path)
        let done = try await Screenshots.process(shot, shrink: .balanced, title: { _ in "Login page" })
        XCTAssertEqual(done.lastPathComponent, "Login page (2026-11-19 12.39.10).png")
        XCTAssertFalse(fm.fileExists(atPath: shot.path))
        XCTAssertLessThan(try Data(contentsOf: done).count, png.count)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir.path), [done.lastPathComponent])

        // Naming off and nothing to shrink: the file stays exactly as it was.
        let jpg = dir.appendingPathComponent("cleanyard shot.jpg")
        try Data("jpeg bytes".utf8).write(to: jpg)
        let same = try await Screenshots.process(jpg, shrink: .balanced, title: nil)
        XCTAssertEqual(same, jpg)
        XCTAssertEqual(try Data(contentsOf: jpg), Data("jpeg bytes".utf8))
        // A taken name gets " 2".
        let again = dir.appendingPathComponent("Screenshot again.png")
        try png.write(to: again)
        try fm.setAttributes([.creationDate: date], ofItemAtPath: again.path)
        let second = try await Screenshots.process(again, shrink: nil, title: { _ in "Login page" })
        XCTAssertEqual(second.lastPathComponent, "Login page (2026-11-19 12.39.10) 2.png")
        XCTAssertEqual(try Data(contentsOf: second), png, "naming alone moves the file without rewriting it")

        // Moving: screenshots (named or not) go, other files stay; clashes get " 2".
        let shots = Screenshots(live: false)
        shots.watchFolder = dir
        shots.moveFolder = dir.appendingPathComponent("Moved")
        try Data().write(to: dir.appendingPathComponent("notes.txt"))
        try fm.createDirectory(at: shots.moveFolder, withIntermediateDirectories: true)
        try Data().write(to: shots.moveFolder.appendingPathComponent("cleanyard shot.jpg"))
        XCTAssertEqual(shots.moveAll(), 3)
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: dir.path)), ["notes.txt", "Moved"])
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: shots.moveFolder.path)),
                       ["cleanyard shot.jpg", "cleanyard shot 2.jpg", done.lastPathComponent, second.lastPathComponent])
        XCTAssertEqual(shots.moveAll(), 0)
        try Data().write(to: dir.appendingPathComponent("Invoice (2026-11-19 12.39.10).pdf"))
        XCTAssertEqual(shots.moveAll(), 0, "a named file that isn't a picture stays")
        shots.moveFolder = dir
        try png.write(to: dir.appendingPathComponent("Screenshot same.png"))
        XCTAssertEqual(shots.moveAll(), 0, "moving into the watched folder itself does nothing")

        // The new shortcut starts with no keys.
        XCTAssertNil(ShortcutAction.moveScreenshots.defaultCombo)
        XCTAssertEqual(ScreenshotSettings.shown(fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Screenshots")), "Pictures \u{203A} Screenshots")
    }
}
