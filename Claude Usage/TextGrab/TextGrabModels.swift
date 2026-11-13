import AppKit
import CoreGraphics
import Foundation

// Text Grab: press a shortcut, drag a box over any text on screen, and the text is on the
// clipboard. Everything here is pure value logic, so the self-tests cover it without a
// real screen capture, permission, or window.

/// English copy, shown in every locale like the other Usage Shelf features.
nonisolated enum TextGrabCopy {
    static let sectionTitle = "Text Grab"
    static let sectionDescription = "Copy text from anywhere on your screen, even inside pictures"
    static let menuItemTitle = "Grab Text from Screen"
    static let shortcutRowTitle = "Grab text from screen"
    static let shortcutRowDescription = "Drag over text to copy it. No shortcut is set by default."
    static let shortcutCardSubtitle = "Press it, then drag over any text you can see"
    static let shortcutNote = "No shortcut is set by default. Also on the Shortcuts page."
    static let overlayHint = "Drag over the text to copy \u{00B7} Esc to cancel"
    static let readyTitle = "Ready"
    static let readyDetail = "Screen Recording is turned on for Usage Shelf."
    static let permissionTitle = "Permission needed"
    static let permissionSubtitle = "Usage Shelf cannot read your screen yet."
    static let permissionHeading = "Turn on Screen Recording"
    static let permissionExplanation = "macOS asks for this before any app can see what is on screen. Usage Shelf looks only at the area you select, only when you use Text Grab. The picture is never saved or sent anywhere."
    static let openSettingsButton = "Open Screen Recording Settings"
    static let reopenNote = "After turning it on, quit and reopen Usage Shelf."
    static let notNow = "Not now"
    static let notNowDetail = "Nothing changes until you choose in System Settings."
    static let tryItNow = "Try it now"
    static let tryItNowUnavailable = "Try it now is unavailable"
    static let privacy = "Text Grab reads the area you select on your Mac. The picture is never saved or sent anywhere. Only the text is copied."
    static let keepLineBreaks = "Keep line breaks"
    static let keepLineBreaksDetail = "Off joins all lines into one paragraph."
    static let showPreview = "Show the Copied preview"
    static let showPreviewDetail = "A small note under the menu bar with the first lines of text."
    static let playSound = "Play a sound when done"
    static let playSoundDetail = "A short sound when text is copied or none is found."
    static let copiedSound = "Sound when text is copied"
    static let copiedSoundDetail = "Choose a built-in Mac sound. The speaker plays it once."
    static let playCopiedSound = "Play sound"
    static let language = "Recognition language"
    static let languageDetail = "Automatic detects the language. Pick one for short or mixed text."
    static let automatic = "Automatic"
    static let noTextTitle = "No text found"
    static let noTextHint = "Try a larger area, or zoom in on small text. Your clipboard was not changed."
    static let reading = "Reading text..."
    static let failedTitle = "Couldn't read the screen"
    static let failedHint = "Nothing was copied. Try again."
}

/// Automatic lets Vision detect the language; a fixed choice is a Vision language code.
nonisolated enum TextGrabLanguage: Hashable, Sendable {
    case automatic
    case fixed(String)

    var storedValue: String {
        switch self {
        case .automatic: return "automatic"
        case .fixed(let code): return code
        }
    }

    init(storedValue: String?) {
        guard let storedValue, !storedValue.isEmpty, storedValue != "automatic" else {
            self = .automatic
            return
        }
        self = .fixed(storedValue)
    }

    var label: String {
        switch self {
        case .automatic: return TextGrabCopy.automatic
        case .fixed(let code):
            // English names in every locale, like the rest of the page.
            return Locale(identifier: "en_US").localizedString(forIdentifier: code) ?? code
        }
    }
}

/// The built-in Mac sounds in /System/Library/Sounds, in menu order. The list is fixed
/// here on purpose: nothing reads, copies or adds sound files.
nonisolated enum TextGrabCaptureSound: String, CaseIterable, Hashable, Sendable {
    case basso = "Basso", blow = "Blow", bottle = "Bottle", frog = "Frog", funk = "Funk"
    case glass = "Glass", hero = "Hero", morse = "Morse", ping = "Ping", pop = "Pop"
    case purr = "Purr", sosumi = "Sosumi", submarine = "Submarine", tink = "Tink"

    /// The sound a successful grab always played before this setting existed.
    static let standard = TextGrabCaptureSound.glass

    /// A missing or unknown saved name falls back to Glass.
    init(storedValue: String?) {
        self = storedValue.flatMap(TextGrabCaptureSound.init(rawValue:)) ?? .standard
    }

    /// The system sound name, also shown in the menu.
    var name: String { rawValue }
}

nonisolated struct TextGrabSettings: Equatable, Sendable {
    var keepLineBreaks = true
    var playSound = false
    var language = TextGrabLanguage.automatic
    var showPreview = true
    var copiedSound = TextGrabCaptureSound.standard

    nonisolated enum Key {
        static let keepLineBreaks = "textGrab.keepLineBreaks"
        static let playSound = "textGrab.playSound"
        static let language = "textGrab.language"
        static let showPreview = "textGrab.showPreview"
        static let copiedSound = "textGrab.copiedSound"
    }

    static func load(from defaults: UserDefaults) -> TextGrabSettings {
        TextGrabSettings(
            keepLineBreaks: defaults.object(forKey: Key.keepLineBreaks) as? Bool ?? true,
            playSound: defaults.object(forKey: Key.playSound) as? Bool ?? false,
            language: TextGrabLanguage(storedValue: defaults.string(forKey: Key.language)),
            showPreview: defaults.object(forKey: Key.showPreview) as? Bool ?? true,
            copiedSound: TextGrabCaptureSound(storedValue: defaults.string(forKey: Key.copiedSound))
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(keepLineBreaks, forKey: Key.keepLineBreaks)
        defaults.set(playSound, forKey: Key.playSound)
        defaults.set(language.storedValue, forKey: Key.language)
        defaults.set(showPreview, forKey: Key.showPreview)
        defaults.set(copiedSound.name, forKey: Key.copiedSound)
    }
}

/// One finished drag: the box in global AppKit points (origin bottom-left of the main
/// display), the frame of the display it was drawn on, that display's id, and its scale.
nonisolated struct TextGrabSelection: Equatable, Sendable {
    var rect: CGRect
    var screenFrame: CGRect
    var displayID: CGDirectDisplayID
    var scale: CGFloat
}

nonisolated enum TextGrabSelectionResult: Equatable, Sendable {
    case selected(TextGrabSelection)
    case cancelled
}

/// One line Vision read, with its box in normalized image coordinates (origin bottom-left).
nonisolated struct TextGrabLine: Equatable, Sendable {
    var text: String
    var box: CGRect
}

nonisolated enum TextGrabToastContent: Equatable, Sendable {
    case reading
    case copied(title: String, preview: String?)
    case noText
    case failed

    var title: String {
        switch self {
        case .reading: return TextGrabCopy.reading
        case .copied(let title, _): return title
        case .noText: return TextGrabCopy.noTextTitle
        case .failed: return TextGrabCopy.failedTitle
        }
    }

    var detail: String? {
        switch self {
        case .reading: return nil
        case .copied(_, let preview): return preview
        case .noText: return TextGrabCopy.noTextHint
        case .failed: return TextGrabCopy.failedHint
        }
    }
}

/// What to play: the chosen capture sound after a copy, or Basso when no text is found.
nonisolated enum TextGrabSound: Equatable, Sendable {
    case copied(TextGrabCaptureSound)
    case notFound

    var soundName: String {
        switch self {
        case .copied(let sound): return sound.name
        case .notFound: return "Basso"
        }
    }
}

nonisolated enum TextGrabGeometry {
    /// A box smaller than this in either direction is a plain click and cancels.
    static let minimumSide: CGFloat = 6

    /// The box between the drag's start and the pointer, in any direction, stopped at the
    /// edge of the display the drag started on.
    static func box(from start: CGPoint, to current: CGPoint, within screenFrame: CGRect) -> CGRect {
        func clamp(_ point: CGPoint) -> CGPoint {
            CGPoint(x: min(max(point.x, screenFrame.minX), screenFrame.maxX),
                    y: min(max(point.y, screenFrame.minY), screenFrame.maxY))
        }
        let a = clamp(start), b = clamp(current)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    static func isTooSmall(_ rect: CGRect) -> Bool {
        rect.width < minimumSide || rect.height < minimumSide
    }

    /// Converts a global AppKit box (origin bottom-left) into the display-relative,
    /// top-left-origin points ScreenCaptureKit's source rectangle uses.
    static func displayLocalRect(_ rect: CGRect, in screenFrame: CGRect) -> CGRect {
        let clipped = rect.intersection(screenFrame)
        guard !clipped.isNull else { return .zero }
        return CGRect(x: clipped.minX - screenFrame.minX,
                      y: screenFrame.maxY - clipped.maxY,
                      width: clipped.width,
                      height: clipped.height)
    }

    /// Full pixel size of the box on its display, so Retina and non-Retina are both read sharp.
    static func pixelSize(of rect: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        (max(1, Int((rect.width * scale).rounded())), max(1, Int((rect.height * scale).rounded())))
    }

    static func sizeLabel(for rect: CGRect) -> String {
        "\(Int(rect.width.rounded())) \u{00D7} \(Int(rect.height.rounded()))"
    }
}

nonisolated enum TextGrabFormatter {
    /// Lines in reading order: top to bottom, and left to right within a row. Pieces Vision
    /// returns separately on the same row are joined with a space.
    static func orderedRows(_ lines: [TextGrabLine]) -> [String] {
        let pieces = lines
            .map { TextGrabLine(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), box: $0.box) }
            .filter { !$0.text.isEmpty }
            .sorted { $0.box.midY > $1.box.midY }
        var rows: [[TextGrabLine]] = []
        for piece in pieces {
            if let last = rows.last, let anchor = last.first, sameRow(anchor.box, piece.box) {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
        }
    }

    private static func sameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let smaller = min(a.height, b.height)
        guard smaller > 0 else { return abs(a.midY - b.midY) < 0.001 }
        return overlap >= smaller * 0.5
    }

    /// Plain text for the clipboard, or nil when nothing was read. Line breaks are kept,
    /// or with them off, lines are joined with single spaces into one paragraph.
    static func clipboardText(from lines: [TextGrabLine], keepLineBreaks: Bool) -> String? {
        let rows = orderedRows(lines)
        let text: String
        if keepLineBreaks {
            text = rows.joined(separator: "\n")
        } else {
            text = rows.joined(separator: " ")
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .joined(separator: " ")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// One line with more words than this reads better as a word count.
    static let wordCountThreshold = 8

    /// "Copied 3 lines", "Copied 1 line", or "Copied 42 words" for one long line.
    static func toastTitle(for text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count > 1 { return "Copied \(lines.count) lines" }
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        if words > wordCountThreshold { return "Copied \(words) words" }
        return "Copied 1 line"
    }

    static let previewCharacterLimit = 90

    /// The first two lines, cut with "..." after about 90 characters or when more follows.
    static func preview(for text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        var preview = lines.prefix(2).joined(separator: "\n")
        var cut = lines.count > 2
        if preview.count > previewCharacterLimit {
            preview = String(preview.prefix(previewCharacterLimit)).trimmingCharacters(in: .whitespacesAndNewlines)
            cut = true
        }
        return cut ? preview + " ..." : preview
    }
}
