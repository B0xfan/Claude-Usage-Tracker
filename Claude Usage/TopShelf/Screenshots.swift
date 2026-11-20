import AppKit
import ImageIO
import Observation
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

/// How hard pictures are shrunk (Settings > Screenshots > Shrink by), as pngquant quality ranges.
nonisolated enum ShrinkLevel: String, CaseIterable, Sendable {
    case smaller = "Smaller", balanced = "Balanced", best = "Best"
    var quality: (min: Int32, max: Int32) {
        switch self {
        case .smaller: (30, 70)
        case .balanced: (60, 85)
        case .best: (90, 100)   // below 90 the engine gives up and the picture is left as it is
        }
    }
    var help: String {
        switch self {
        case .smaller: "Smallest files, a little softer"
        case .balanced: "Much smaller, looks the same"
        case .best: "Only safe savings, never changes how it looks"
        }
    }
}

/// Turns a picture into a smaller palette PNG with pngquant's engine (libimagequant, bundled; GPL v3, see its licence file).
nonisolated enum PNGShrinker {
    /// The smaller PNG, or nil when it can't be read, the engine can't keep the quality, or the result is not smaller.
    static func shrink(_ data: Data, _ level: ShrinkLevel) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        // the picture keeps its own colour profile (screenshots are Display P3), so colours never shift
        let space = cg.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? srgb
        let icc = space === srgb ? nil : space.copyICCData() as Data?
        let w = cg.width, h = cg.height
        guard w > 0, h > 0, w * h <= 80_000_000 else { return nil }   // ~8K x 10K; bigger would need over 300 MB
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let dpi = props?[kCGImagePropertyDPIWidth] as? Double ?? 0
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: icc == nil ? srgb : space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        // the engine wants straight alpha; Core Graphics only draws premultiplied
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = Int(px[i + 3])
            guard a != 0, a != 255 else { continue }
            for c in i..<(i + 3) { px[c] = UInt8(min(255, (Int(px[c]) * 255 + a / 2) / a)) }
        }
        var len = 0
        let q = level.quality
        let made = icc.map { p in p.withUnsafeBytes { us_shrink_png(px, Int32(w), Int32(h), q.min, q.max, dpi, $0.bindMemory(to: UInt8.self).baseAddress, p.count, &len) } }
            ?? us_shrink_png(px, Int32(w), Int32(h), q.min, q.max, dpi, nil, 0, &len)
        guard let out = made else { return nil }
        defer { free(out) }
        return len < data.count ? Data(bytes: out, count: len) : nil
    }
}

/// Names a screenshot with Apple Intelligence on this Mac, from the words on it and the app it was taken in.
nonisolated enum ScreenshotNamer {
    /// shortcut: reads the screenshot's words, not the picture itself; picture input needs the macOS 27 tools, which the cloud build Macs don't have yet.
    static func title(_ cg: CGImage, app: String?) async -> String? {
        let request = VNRecognizeTextRequest()
        try? VNImageRequestHandler(cgImage: cg).perform([request])
        let words = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        guard !words.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let session = LanguageModelSession(instructions: """
                You name macOS screenshot files. Reply with ONLY a concise, descriptive title of 2 to 6 words for what the screenshot shows. \
                No file extension, no quotes, no leading article like A or The, no date.
                """)
            let place = app.map { "The screenshot was taken in \($0). " } ?? ""
            guard let reply = try? await session.respond(to: "\(place)Words on the screenshot: \(words.prefix(1500))") else { return nil }
            let name = sanitize(reply.content)
            return name.isEmpty ? nil : name
        }
        #endif
        return nil
    }

    /// The model's reply made safe for a file name: no quotes, no characters macOS refuses, one line, at most 64 characters.
    static func sanitize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’ .").union(.whitespacesAndNewlines))
        for ext in [".png", ".jpg", ".jpeg", ".heic"] where t.lowercased().hasSuffix(ext) { t = String(t.dropLast(ext.count)) }
        t = t.components(separatedBy: CharacterSet(charactersIn: ":/\\?*[]<>|\"\n\r\t")).joined()
        t = t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(t.prefix(64)).trimmingCharacters(in: .whitespaces)
    }
}

/// Usage Shelf's screenshot helper (from File Sorter and Clop): new screenshots in the watched folder are named
/// and shrunk in one step, copied pictures are shrunk, and screenshots can be moved off the Desktop.
@Observable
final class Screenshots {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}
    var nameOn: Bool = TopShelfDefaults.store.object(forKey: "shotsName") as? Bool ?? true { didSet { TopShelfDefaults.store.set(nameOn, forKey: "shotsName") } }
    var shrinkOn: Bool = TopShelfDefaults.store.object(forKey: "shotsShrink") as? Bool ?? true { didSet { TopShelfDefaults.store.set(shrinkOn, forKey: "shotsShrink") } }
    var shrinkCopiedOn: Bool = TopShelfDefaults.store.object(forKey: "shotsShrinkCopied") as? Bool ?? true { didSet { TopShelfDefaults.store.set(shrinkCopiedOn, forKey: "shotsShrinkCopied") } }
    var level: ShrinkLevel = ShrinkLevel(rawValue: TopShelfDefaults.store.string(forKey: "shotsLevel") ?? "") ?? .balanced {
        didSet { TopShelfDefaults.store.set(level.rawValue, forKey: "shotsLevel") }
    }
    /// Words that make a file in the watched folder count as a screenshot (any of them, any case).
    var words: [String] = TopShelfDefaults.store.stringArray(forKey: "shotsWords") ?? ["Screenshot", "clop", "cleanyard"] {
        didSet { TopShelfDefaults.store.set(words, forKey: "shotsWords") }
    }
    var watchFolder: URL = TopShelfDefaults.store.string(forKey: "shotsWatch").map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop") {
        didSet { TopShelfDefaults.store.set(watchFolder.path, forKey: "shotsWatch"); if live { watch() } }
    }
    var moveFolder: URL = TopShelfDefaults.store.string(forKey: "shotsMoveTo").map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Screenshots") {
        didSet { TopShelfDefaults.store.set(moveFolder.path, forKey: "shotsMoveTo") }
    }
    /// The level copied pictures are shrunk at, or nil when that is switched off.
    var copiedLevel: ShrinkLevel? { shrinkCopiedOn ? level : nil }

    private let live: Bool
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var seen: Set<String> = []   // names already in the folder, so only new files are handled

    init(live: Bool) {
        self.live = live
        if live { watch() }
    }

    /// The name a screenshot gets: "Login page (2026-11-19 12.39.10).png".
    nonisolated static func namedForm(_ title: String, _ date: Date, ext: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(title) (\(f.string(from: date))).\(ext)"
    }

    nonisolated static func isPicture(_ name: String) -> Bool {
        !name.hasPrefix(".") && ["png", "jpg", "jpeg", "heic"].contains((name as NSString).pathExtension.lowercased())
    }

    nonisolated static func isNamed(_ name: String) -> Bool {
        name.range(of: #" \(\d{4}-\d{2}-\d{2} \d{2}\.\d{2}\.\d{2}\)( \d+)?\.[A-Za-z]+$"#, options: .regularExpression) != nil
    }

    /// A new file to name and shrink: a picture whose name has one of the words and that isn't named yet.
    nonisolated static func isNew(_ name: String, words: [String]) -> Bool {
        guard isPicture(name), !isNamed(name) else { return false }
        return words.contains { !$0.isEmpty && name.localizedCaseInsensitiveContains($0) }
    }

    private func watch() {
        source?.cancel()
        seen = Set((try? FileManager.default.contentsOfDirectory(atPath: watchFolder.path)) ?? [])
        let fd = open(watchFolder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        s.setEventHandler { [weak self] in self?.scan() }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
    }

    private func scan() {
        let now = Set((try? FileManager.default.contentsOfDirectory(atPath: watchFolder.path)) ?? [])
        let fresh = now.subtracting(seen)
        seen = now
        guard nameOn || shrinkOn else { return }
        let app = NSWorkspace.shared.frontmostApplication?.localizedName
        let level = shrinkOn ? level : nil
        let name = nameOn
        for file in fresh where Self.isNew(file, words: words) {
            let url = watchFolder.appendingPathComponent(file)
            Task.detached(priority: .utility) { await Self.handle(url, shrink: level, name: name, app: app) }
        }
    }

    nonisolated static func handle(_ url: URL, shrink: ShrinkLevel?, name: Bool, app: String?) async {
        guard await waitUntilSaved(url) else { return }
        if name {
            _ = try? await process(url, shrink: shrink, title: { (cg: CGImage) async -> String? in await ScreenshotNamer.title(cg, app: app) })
        } else {
            _ = try? await process(url, shrink: shrink, title: nil)
        }
    }

    /// True once the file's size has held still for half a second (the Mac writes screenshots in steps).
    nonisolated static func waitUntilSaved(_ url: URL) async -> Bool {
        var last = -1
        for _ in 0..<20 {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            if size > 0, size == last { return true }
            last = size
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    /// Names and shrinks one screenshot, writing it once. The original is removed only after the new file is written,
    /// and it is left alone when neither step changes anything. Returns where the file ended up.
    @discardableResult
    nonisolated static func process(_ url: URL, shrink: ShrinkLevel?, title: ((CGImage) async -> String?)?) async throws -> URL {
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension
        let small = ext.lowercased() == "png" ? shrink.flatMap { PNGShrinker.shrink(data, $0) } : nil
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let created = attrs[.creationDate] as? Date ?? Date()
        var dest = url
        if let title, let src = CGImageSourceCreateWithData(data as CFData, nil),
           let cg = CGImageSourceCreateImageAtIndex(src, 0, nil), let t = await title(cg) {
            dest = unique(url.deletingLastPathComponent(), namedForm(t, created, ext: ext))
        }
        if let small {
            try small.write(to: dest, options: dest == url ? .atomic : .withoutOverwriting)   // never over another screenshot named at the same moment
            try? FileManager.default.setAttributes([.creationDate: created, .modificationDate: attrs[.modificationDate] ?? created], ofItemAtPath: dest.path)
            if dest != url { try FileManager.default.removeItem(at: url) }
        } else if dest != url {
            try FileManager.default.moveItem(at: url, to: dest)
        }
        return dest
    }

    /// `name` in `folder`, or "name 2", "name 3"… when that is taken.
    nonisolated static func unique(_ folder: URL, _ name: String) -> URL {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var url = folder.appendingPathComponent(name), n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }

    /// Moves every screenshot (named or not yet) from the watched folder to the move folder. Returns how many moved.
    @discardableResult
    func moveAll() -> Int {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: watchFolder.path)) ?? []
        let shots = names.filter { Self.isNew($0, words: words) || (Self.isPicture($0) && Self.isNamed($0)) }
        guard !shots.isEmpty, moveFolder.resolvingSymlinksInPath() != watchFolder.resolvingSymlinksInPath(), (try? fm.createDirectory(at: moveFolder, withIntermediateDirectories: true)) != nil else { return 0 }
        return shots.filter { (try? fm.moveItem(at: watchFolder.appendingPathComponent($0), to: Self.unique(moveFolder, $0))) != nil }.count
    }
}
