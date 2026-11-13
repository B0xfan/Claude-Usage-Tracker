import XCTest
import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import Vision
@testable import Claude_Usage

/// Text Grab's numbered checks, as far as they can be tested without a real screen.
/// Only fakes are used for permission, capture, clipboard, overlay and toast: no real
/// screen capture, no permission prompt, no Keychain, no login. Recognition tests feed a
/// rendered test image straight to Vision, as the spec allows.
@MainActor
final class TextGrabTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var log: TextGrabEventLog!
    private var permissions: TextGrabPermissionFake!
    private var capturer: TextGrabCapturerFake!
    private var recognizer: TextGrabRecognizerFake!
    private var clipboard: TextGrabClipboardFake!
    private var selection: TextGrabSelectionFake!
    private var feedback: TextGrabFeedbackFake!
    private var cleaningActive = false
    private var controller: TextGrabController!

    private let mainScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let sideScreen = CGRect(x: 1440, y: -180, width: 1920, height: 1080)

    override func setUp() async throws {
        suite = "TextGrabTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        log = TextGrabEventLog()
        permissions = TextGrabPermissionFake(log: log)
        capturer = TextGrabCapturerFake(log: log)
        recognizer = TextGrabRecognizerFake(log: log)
        clipboard = TextGrabClipboardFake(log: log)
        selection = TextGrabSelectionFake(log: log)
        feedback = TextGrabFeedbackFake(log: log)
        cleaningActive = false
        controller = makeController()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        controller = nil
        defaults = nil
    }

    private func makeController(readingNoticeDelay: TimeInterval = 0.5) -> TextGrabController {
        TextGrabController(defaults: defaults, permissions: permissions, capturer: capturer, recognizer: recognizer,
                           clipboard: clipboard, selection: selection, feedback: feedback,
                           isCleaningActive: { [weak self] in self?.cleaningActive ?? false },
                           readingNoticeDelay: readingNoticeDelay)
    }

    private func box(_ rect: CGRect = CGRect(x: 100, y: 500, width: 212, height: 128), on screen: CGRect? = nil, displayID: CGDirectDisplayID = 1, scale: CGFloat = 2) -> TextGrabSelection {
        TextGrabSelection(rect: rect, screenFrame: screen ?? mainScreen, displayID: displayID, scale: scale)
    }

    private func line(_ text: String, x: CGFloat = 0.1, y: CGFloat, width: CGFloat = 0.6, height: CGFloat = 0.1) -> TextGrabLine {
        TextGrabLine(text: text, box: CGRect(x: x, y: y, width: width, height: height))
    }

    private var threeLines: [TextGrabLine] {
        [line("Saturday 4:30 PM", y: 0.5), line("Sunset Kayak Tour", y: 0.7), line("Meet at the blue dock", y: 0.3)]
    }

    /// Waits for the reading task, which runs on the main actor, to finish.
    private func waitUntilIdle(file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<400 where controller.phase != .idle {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(controller.phase, .idle, "Text Grab did not finish", file: file, line: line)
    }

    private func grab(_ lines: [TextGrabLine], selection chosen: TextGrabSelection? = nil) async {
        recognizer.lines = lines
        XCTAssertEqual(controller.start(), .started)
        selection.finish(.selected(chosen ?? box()))
        await waitUntilIdle()
    }

    // 1 and 23
    func testSettingsPageSitsBelowCleaningModeAndRendersInLightAndDark() throws {
        let order = SettingsSection.allCases.filter { !$0.isProfileSetting && !$0.isCredential && !$0.isBottomBarItem }.map(\.rawValue)
        XCTAssertEqual(order.suffix(3), ["keepAwake", "cleaningMode", "textGrab"])
        XCTAssertEqual(SettingsSection.textGrab.title, "Text Grab")
        XCTAssertEqual(SettingsSection.textGrab.description, "Copy text from anywhere on your screen, even inside pictures")
        let folder = URL(fileURLWithPath: "/tmp/usage-shelf-text-grab-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manager = ShortcutManager(store: ShortcutStoreSpy(), registrar: ShortcutRegistrarSpy().register)
        recognizer.supported = ["en-US", "es-ES"]
        for granted in [true, false] {
            permissions.granted = granted
            controller.refreshPermission()
            for scheme in [ColorScheme.light, .dark] {
                let name = "settings-\(granted ? "ready" : "permission")-\(scheme == .light ? "light" : "dark").png"
                try TextGrabPreviewRenderer.renderSettings(controller: controller, manager: manager, scheme: scheme, to: folder.appendingPathComponent(name))
                XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path))
            }
        }
        // Capture sound row (sound spec check 1): switch on, Submarine chosen, light and dark.
        permissions.granted = true
        controller.refreshPermission()
        controller.update(\.playSound, value: true)
        controller.chooseCopiedSound(.submarine)
        for scheme in [ColorScheme.light, .dark] {
            let name = "settings-ready-sound-on-\(scheme == .light ? "light" : "dark").png"
            try TextGrabPreviewRenderer.renderSettings(controller: controller, manager: manager, scheme: scheme, to: folder.appendingPathComponent(name))
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path))
        }
        for (content, name) in [(TextGrabToastContent.copied(title: "Copied 3 lines", preview: "Sunset Kayak Tour\nSaturday 4:30 PM ..."), "copied"), (TextGrabToastContent.noText, "no-text")] {
            for scheme in [ColorScheme.light, .dark] {
                try TextGrabPreviewRenderer.renderToast(content, scheme: scheme, to: folder.appendingPathComponent("toast-\(name)-\(scheme == .light ? "light" : "dark").png"))
            }
        }
    }

    // 2
    func testNoDefaultShortcutAndNothingRegistered() {
        let store = ShortcutStoreSpy()
        let registrar = ShortcutRegistrarSpy()
        let manager = ShortcutManager(store: store, registrar: registrar.register)
        manager.startListening()
        XCTAssertNil(manager.shortcuts[.textGrab])
        XCTAssertNil(store.loadShortcut(for: .textGrab))
        XCTAssertTrue(registrar.combos.isEmpty)
        XCTAssertEqual(ShortcutAction.textGrab.displayName, "Grab text from screen")
        XCTAssertEqual(ShortcutAction.textGrab.minimumModifierCount, 1)
        XCTAssertNil(UserDefaults.standard.object(forKey: "shortcutTextGrab.test-marker"))
    }

    // 3
    func testRecorderClashWarningsSaveNothing() {
        let store = ShortcutStoreSpy()
        let registrar = ShortcutRegistrarSpy()
        let manager = ShortcutManager(store: store, registrar: registrar.register)
        let keepAwake = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.command, .option])
        XCTAssertEqual(manager.setShortcut(keepAwake, for: .keepAwake), .success)
        XCTAssertEqual(manager.setShortcut(keepAwake, for: .textGrab), .duplicate("Keep awake"))
        XCTAssertEqual(resultWarning(.duplicate("Keep awake"), combo: keepAwake), "Already used by Keep awake. Choose another shortcut.")
        let refused = KeyCombo(keyCode: UInt16(kVK_ANSI_G), modifierFlags: [.command, .shift])
        registrar.failures.insert(refused)
        XCTAssertEqual(manager.setShortcut(refused, for: .textGrab), .registrationFailed)
        XCTAssertNil(manager.shortcuts[.textGrab])
        XCTAssertNil(store.loadShortcut(for: .textGrab))
        XCTAssertEqual(manager.shortcuts[.keepAwake], keepAwake)
    }

    // 4
    func testOneShortcutEditedFromTwoPlaces() {
        let store = ShortcutStoreSpy()
        let manager = ShortcutManager(store: store, registrar: ShortcutRegistrarSpy().register)
        let pageCombo = TextGrabTestBox<KeyCombo?>(nil)
        let pageWarning = TextGrabTestBox<String?>(nil)
        let page = ShortcutBinding.make(for: .textGrab, combo: Binding(get: { pageCombo.value }, set: { pageCombo.value = $0 }),
                                        warning: Binding(get: { pageWarning.value }, set: { pageWarning.value = $0 }), manager: manager)
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_G), modifierFlags: [.control, .option])
        page.wrappedValue = combo
        XCTAssertEqual(pageCombo.value, combo)
        XCTAssertNil(pageWarning.value)
        // The Shortcuts page starts from the same saved value.
        let listCombo = TextGrabTestBox<KeyCombo?>(manager.shortcuts[.textGrab])
        XCTAssertEqual(listCombo.value, combo)
        let list = ShortcutBinding.make(for: .textGrab, combo: Binding(get: { listCombo.value }, set: { listCombo.value = $0 }), warning: nil, manager: manager)
        list.wrappedValue = nil
        XCTAssertNil(manager.shortcuts[.textGrab])
        XCTAssertNil(store.loadShortcut(for: .textGrab))
        XCTAssertNil(ShortcutManager(store: store, registrar: ShortcutRegistrarSpy().register).shortcuts[.textGrab])
    }

    // 5
    func testNoPromptEverWithPermissionMissing() {
        permissions.granted = false
        XCTAssertEqual(permissions.checkCount, 0, "Nothing is checked at launch")
        XCTAssertEqual(controller.start(), .permissionMissing)
        XCTAssertTrue(controller.shouldOpenSettings)
        XCTAssertEqual(controller.permissionState, .needed)
        XCTAssertFalse(controller.canTryNow)
        controller.refreshPermission()   // the page opening
        XCTAssertEqual(selection.beginCount, 0)
        XCTAssertEqual(capturer.captures.count, 0)
        XCTAssertGreaterThanOrEqual(permissions.checkCount, 2)
        XCTAssertEqual(permissions.openCount, 0)
        XCTAssertEqual(clipboard.writes, [])
    }

    func testPermissionWithdrawnMidSelectionNeverCaptures() async {
        XCTAssertEqual(controller.start(), .started)
        permissions.granted = false
        selection.finish(.selected(box()))
        await waitUntilIdle()
        XCTAssertEqual(capturer.captures.count, 0)
        XCTAssertTrue(controller.shouldOpenSettings)
        XCTAssertEqual(clipboard.writes, [])
    }

    // 6
    func testSettingsButtonOnlyOpensThePane() {
        permissions.granted = false
        controller.openScreenRecordingSettings()
        XCTAssertEqual(permissions.openCount, 1)
        controller.refreshPermission()
        XCTAssertEqual(controller.permissionState, .needed, "Opening the pane is not treated as granted")
        XCTAssertEqual(selection.beginCount, 0)
    }

    // 7
    func testStatusFollowsTheRealPermission() {
        permissions.granted = false
        controller.refreshPermission()
        XCTAssertEqual(controller.permissionState, .needed)
        permissions.granted = true
        controller.refreshPermission()
        XCTAssertEqual(controller.permissionState, .ready)
        XCTAssertTrue(controller.canTryNow)
        permissions.granted = false
        controller.refreshPermission()
        XCTAssertEqual(controller.permissionState, .needed)
        XCTAssertEqual(TextGrabCopy.reopenNote, "After turning it on, quit and reopen Usage Shelf.")
    }

    // 8
    func testOverlayStartsWithPermissionAndUsesTheHintCopy() {
        XCTAssertEqual(controller.start(), .started)
        XCTAssertEqual(selection.beginCount, 1)
        XCTAssertEqual(controller.phase, .selecting)
        XCTAssertEqual(controller.start(), .alreadyRunning)
        XCTAssertEqual(selection.beginCount, 1)
        XCTAssertEqual(TextGrabCopy.overlayHint, "Drag over the text to copy · Esc to cancel")
        XCTAssertEqual(TextGrabGeometry.sizeLabel(for: CGRect(x: 0, y: 0, width: 212, height: 128)), "212 × 128")
    }

    // 9
    func testPlainTextWithLineBreaksKept() async {
        clipboard.writes = ["previous"]
        await grab(threeLines)
        XCTAssertEqual(clipboard.writes.last, "Sunset Kayak Tour\nSaturday 4:30 PM\nMeet at the blue dock")
        XCTAssertEqual(controller.lastOutcome, .copied("Sunset Kayak Tour\nSaturday 4:30 PM\nMeet at the blue dock"))
        XCTAssertEqual(clipboard.writes.count, 2)
    }

    // 10 (order) — real Vision on a rendered picture is in testVisionReadsARenderedPictureInReadingOrder
    func testReadingOrderTopToBottomLeftToRight() {
        let pieces = [
            line("right", x: 0.6, y: 0.8, width: 0.3),
            line("left", x: 0.05, y: 0.81, width: 0.3),
            line("second row", y: 0.6),
            line("   ", y: 0.4),
            line("third", y: 0.2)
        ]
        XCTAssertEqual(TextGrabFormatter.orderedRows(pieces), ["left right", "second row", "third"])
    }

    func testVisionReadsARenderedPictureInReadingOrder() async throws {
        let image = try XCTUnwrap(TextGrabTestImage.render(["Sunset Kayak Tour", "Saturday 4:30 PM", "Meet at the blue dock"]))
        let lines = try await TextGrabVisionRecognizer().recognize(image, language: .automatic)
        let text = try XCTUnwrap(TextGrabFormatter.clipboardText(from: lines, keepLineBreaks: true)).lowercased()
        XCTAssertTrue(text.contains("sunset kayak tour"), text)
        XCTAssertTrue(text.contains("blue dock"), text)
        let first = try XCTUnwrap(text.range(of: "sunset")).lowerBound
        let last = try XCTUnwrap(text.range(of: "blue dock")).lowerBound
        XCTAssertLessThan(first, last)
    }

    // 11
    func testLineBreaksOffJoinsWithSingleSpaces() async {
        controller.update(\.keepLineBreaks, value: false)
        await grab([line("  Sunset   Kayak Tour ", y: 0.7), line("Saturday 4:30 PM", y: 0.5), line("Meet at the blue dock", y: 0.3)])
        XCTAssertEqual(clipboard.writes.last, "Sunset Kayak Tour Saturday 4:30 PM Meet at the blue dock")
        XCTAssertFalse(clipboard.writes.last?.contains("\n") ?? true)
    }

    // 12
    func testCopiedToastTitlePreviewPlacementAndFocus() async {
        await grab(threeLines)
        XCTAssertEqual(feedback.toasts.last, .copied(title: "Copied 3 lines", preview: "Sunset Kayak Tour\nSaturday 4:30 PM ..."))
        XCTAssertEqual(feedback.displays.last, 1)
        XCTAssertEqual(TextGrabFormatter.toastTitle(for: "One line"), "Copied 1 line")
        XCTAssertEqual(TextGrabFormatter.toastTitle(for: Array(repeating: "word", count: 42).joined(separator: " ")), "Copied 42 words")
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(TextGrabFormatter.preview(for: long), String(repeating: "a", count: 90) + " ...")
        XCTAssertEqual(TextGrabFormatter.preview(for: "Two\nlines"), "Two\nlines")
        XCTAssertEqual(TextGrabToastLayout.visibleSeconds, 2.5)
        let panel = TextGrabToastPanel.make()
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.isVisible)
        // Under the rings on that display, otherwise top right of it.
        let size = CGSize(width: 300, height: 60)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let anchor = CGRect(x: 1200, y: 877, width: 40, height: 22)
        let under = TextGrabToastLayout.origin(size: size, screenFrame: mainScreen, visibleFrame: visible, anchor: anchor)
        XCTAssertEqual(under.x, 1070)
        XCTAssertLessThanOrEqual(under.y + size.height, anchor.minY)
        let elsewhere = TextGrabToastLayout.origin(size: size, screenFrame: sideScreen, visibleFrame: CGRect(x: 1440, y: -180, width: 1920, height: 1055), anchor: anchor)
        XCTAssertEqual(elsewhere.x, 1440 + 1920 - 300 - 12)
        // Preview off keeps the short confirmation without the copied lines.
        controller.update(\.showPreview, value: false)
        await grab(threeLines)
        XCTAssertEqual(feedback.toasts.last, .copied(title: "Copied 3 lines", preview: nil))
    }

    func testReadingNoticeAppearsOnlyWhenSlow() async {
        controller = makeController(readingNoticeDelay: 0.05)
        recognizer.delay = 0.3
        await grab(threeLines)
        XCTAssertEqual(feedback.toasts.first, .reading)
        XCTAssertEqual(feedback.toasts.last, .copied(title: "Copied 3 lines", preview: "Sunset Kayak Tour\nSaturday 4:30 PM ..."))
        XCTAssertEqual(TextGrabCopy.reading, "Reading text...")
        feedback.toasts.removeAll()
        recognizer.delay = 0
        controller = makeController(readingNoticeDelay: 0.5)
        await grab(threeLines)
        XCTAssertFalse(feedback.toasts.contains(.reading))
    }

    // 13
    func testNoTextLeavesTheClipboardAlone() async {
        clipboard.writes = ["previous"]
        await grab([])
        XCTAssertEqual(clipboard.writes, ["previous"])
        XCTAssertEqual(feedback.toasts.last, .noText)
        XCTAssertEqual(controller.lastOutcome, .noText)
        await grab([line("   ", y: 0.5), line("\n", y: 0.3)])
        XCTAssertEqual(clipboard.writes, ["previous"])
        XCTAssertEqual(TextGrabToastContent.noText.title, "No text found")
        XCTAssertEqual(TextGrabToastContent.noText.detail, "Try a larger area, or zoom in on small text. Your clipboard was not changed.")
    }

    func testCaptureFailureCopiesNothing() async {
        clipboard.writes = ["previous"]
        capturer.error = TextGrabError.displayUnavailable
        await grab(threeLines)
        XCTAssertEqual(clipboard.writes, ["previous"])
        XCTAssertEqual(controller.lastOutcome, .failed)
        XCTAssertEqual(feedback.toasts.last, .failed)
    }

    // 14
    func testEscRightClickAndPlainClickCancelWithoutCapturing() async {
        clipboard.writes = ["previous"]
        for _ in 0..<2 {   // Esc and right click both arrive as a cancel
            XCTAssertEqual(controller.start(), .started)
            selection.finish(.cancelled)
            XCTAssertEqual(controller.phase, .idle)
            XCTAssertEqual(controller.lastOutcome, .cancelled)
        }
        // A click without dragging: a box under 6 × 6 points.
        XCTAssertEqual(controller.start(), .started)
        selection.finish(.selected(box(CGRect(x: 10, y: 10, width: 5, height: 80))))
        await waitUntilIdle()
        XCTAssertTrue(TextGrabGeometry.isTooSmall(CGRect(x: 0, y: 0, width: 80, height: 5.9)))
        XCTAssertFalse(TextGrabGeometry.isTooSmall(CGRect(x: 0, y: 0, width: 6, height: 6)))
        XCTAssertEqual(capturer.captures.count, 0)
        XCTAssertEqual(clipboard.writes, ["previous"])
        XCTAssertEqual(feedback.toasts, [])
    }

    // 15
    func testBoxStopsAtTheDisplayEdgeAndTheRightDisplayIsRead() async {
        // Dragged from the main display toward the shared edge and beyond.
        let clamped = TextGrabGeometry.box(from: CGPoint(x: 1300, y: 400), to: CGPoint(x: 1700, y: 300), within: mainScreen)
        XCTAssertEqual(clamped, CGRect(x: 1300, y: 300, width: 140, height: 100))
        // Any direction works.
        XCTAssertEqual(TextGrabGeometry.box(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 10, y: 90), within: mainScreen), CGRect(x: 10, y: 50, width: 40, height: 40))
        // The side display's box becomes display-relative, top-left-origin points.
        let side = CGRect(x: 1540, y: 700, width: 300, height: 100)
        XCTAssertEqual(TextGrabGeometry.displayLocalRect(side, in: sideScreen), CGRect(x: 100, y: 100, width: 300, height: 100))
        // Full pixel resolution on Retina and non-Retina.
        XCTAssertTrue(TextGrabGeometry.pixelSize(of: side, scale: 2) == (600, 200))
        XCTAssertTrue(TextGrabGeometry.pixelSize(of: side, scale: 1) == (300, 100))
        let chosen = box(side, on: sideScreen, displayID: 7, scale: 1)
        await grab(threeLines, selection: chosen)
        XCTAssertEqual(capturer.captures, [chosen])
        XCTAssertEqual(feedback.displays.last, 7)
        XCTAssertEqual(controller.phase, .idle)
    }

    // 16
    func testOverlayIsGoneBeforeTheCapture() async {
        await grab(threeLines)
        let finished = log.events.firstIndex(of: "selection.finished")
        let captured = log.events.firstIndex(of: "capture")
        XCTAssertNotNil(finished)
        XCTAssertNotNil(captured)
        XCTAssertLessThan(finished!, captured!)
        XCTAssertGreaterThan(TextGrabSelectionOverlay.captureDelay, 0)
        XCTAssertFalse(clipboard.writes.last?.contains(TextGrabCopy.overlayHint) ?? true)
    }

    // 17
    func testLanguageChoiceIsPassedToVisionAndAccentsAreKept() async throws {
        controller.update(\.language, value: .fixed("es-ES"))
        await grab(threeLines)
        XCTAssertEqual(recognizer.languages.last, .fixed("es-ES"))
        XCTAssertEqual(TextGrabSettings.load(from: defaults).language, .fixed("es-ES"))
        let automatic = TextGrabVisionReader.makeRequest(language: .automatic)
        XCTAssertTrue(automatic.automaticallyDetectsLanguage)
        XCTAssertTrue(automatic.usesLanguageCorrection)
        XCTAssertEqual(automatic.recognitionLevel, .accurate)
        let fixed = TextGrabVisionReader.makeRequest(language: .fixed("es-ES"))
        XCTAssertFalse(fixed.automaticallyDetectsLanguage)
        XCTAssertEqual(fixed.recognitionLanguages, ["es-ES"])
        XCTAssertEqual(TextGrabLanguage.fixed("es-ES").label, "Spanish (Spain)")
        XCTAssertEqual(TextGrabLanguage.automatic.label, "Automatic")
    }

    func testVisionKeepsSpanishAccents() async throws {
        guard let spanish = TextGrabVisionReader.supportedLanguages().first(where: { $0.hasPrefix("es") }) else {
            throw XCTSkip("Vision on this Mac has no Spanish")
        }
        let image = try XCTUnwrap(TextGrabTestImage.render(["Mañana habrá café", "Canción del océano"]))
        let fixed = try await TextGrabVisionRecognizer().recognize(image, language: .fixed(spanish))
        let fixedText = try XCTUnwrap(TextGrabFormatter.clipboardText(from: fixed, keepLineBreaks: true))
        XCTAssertTrue(fixedText.contains("Mañana"), fixedText)
        XCTAssertTrue(fixedText.contains("café"), fixedText)
        XCTAssertTrue(fixedText.contains("océano"), fixedText)
        let automatic = try await TextGrabVisionRecognizer().recognize(image, language: .automatic)
        let automaticText = try XCTUnwrap(TextGrabFormatter.clipboardText(from: automatic, keepLineBreaks: true))
        let folded = automaticText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        XCTAssertTrue(folded.contains("manana"), automaticText)
        XCTAssertTrue(folded.contains("cafe"), automaticText)
    }

    // 18
    func testSoundIsOffByDefaultAndMatchesTheOutcomeWhenOn() async {
        await grab(threeLines)
        await grab([])
        XCTAssertEqual(feedback.sounds, [])
        controller.update(\.playSound, value: true)
        await grab(threeLines)
        await grab([])
        XCTAssertEqual(feedback.sounds, [.copied(.glass), .notFound])
    }

    // MARK: Capture sound setting (text-grab-sound-spec.md checks 1-13)

    private let builtInSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
                                 "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

    // Sound 1, 2 and 11
    func testCaptureSoundRowCopyDefaultAndTheFourteenSounds() {
        XCTAssertEqual(TextGrabCopy.copiedSound, "Sound when text is copied")
        XCTAssertEqual(TextGrabCopy.copiedSoundDetail, "Choose a built-in Mac sound. The speaker plays it once.")
        XCTAssertEqual(TextGrabCopy.playCopiedSound, "Play sound")
        XCTAssertEqual(TextGrabCaptureSound.allCases.map(\.name), builtInSounds)
        for sound in TextGrabCaptureSound.allCases {
            XCTAssertTrue(FileManager.default.fileExists(atPath: "/System/Library/Sounds/\(sound.name).aiff"), "\(sound.name) is not a built-in Mac sound")
        }
        XCTAssertFalse(controller.settings.playSound)
        XCTAssertEqual(controller.settings.copiedSound, .glass)
        XCTAssertFalse(controller.copiedSoundControlsEnabled)
    }

    // Sound 2
    func testDimmedSoundControlsDoNothingWhileSoundIsOff() {
        controller.chooseCopiedSound(.submarine)
        controller.previewCopiedSound()
        XCTAssertEqual(feedback.sounds, [])
        XCTAssertEqual(controller.settings.copiedSound, .glass)
        XCTAssertNil(defaults.object(forKey: TextGrabSettings.Key.copiedSound))
    }

    // Sound 3
    func testTurningTheSwitchOnPlaysNothing() {
        controller.update(\.playSound, value: true)
        XCTAssertTrue(controller.copiedSoundControlsEnabled)
        XCTAssertEqual(feedback.sounds, [])
    }

    // Sound 4
    func testChoosingASoundPlaysItOnceAndSavesIt() {
        controller.update(\.playSound, value: true)
        controller.chooseCopiedSound(.submarine)
        XCTAssertEqual(feedback.sounds, [.copied(.submarine)])
        XCTAssertEqual(controller.settings.copiedSound, .submarine)
        XCTAssertEqual(defaults.string(forKey: TextGrabSettings.Key.copiedSound), "Submarine")
    }

    // Sound 5
    func testSpeakerPlaysTheSelectedSoundOnceWithoutAGrab() {
        controller.update(\.playSound, value: true)
        controller.chooseCopiedSound(.hero)
        controller.previewCopiedSound()
        XCTAssertEqual(feedback.sounds, [.copied(.hero), .copied(.hero)])
        XCTAssertEqual(selection.beginCount, 0)
        XCTAssertEqual(capturer.captures.count, 0)
        XCTAssertEqual(clipboard.writes, [])
        XCTAssertEqual(feedback.toasts, [])
        XCTAssertEqual(controller.phase, .idle)
    }

    // Sound 6 and 7
    func testGrabPlaysTheChosenSoundAndNoTextStillPlaysBasso() async {
        controller.update(\.playSound, value: true)
        controller.chooseCopiedSound(.submarine)
        await grab(threeLines)
        await grab([])
        XCTAssertEqual(feedback.sounds, [.copied(.submarine), .copied(.submarine), .notFound])
        XCTAssertEqual(clipboard.writes.count, 1)
        XCTAssertEqual(controller.settings.copiedSound, .submarine)
    }

    // Sound 8
    func testSwitchOffSilencesEverythingAndKeepsTheChoice() async {
        controller.update(\.playSound, value: true)
        controller.chooseCopiedSound(.submarine)
        controller.update(\.playSound, value: false)
        await grab(threeLines)
        await grab([])
        controller.chooseCopiedSound(.hero)
        controller.previewCopiedSound()
        XCTAssertEqual(feedback.sounds, [.copied(.submarine)])
        XCTAssertEqual(controller.settings.copiedSound, .submarine)
        XCTAssertFalse(controller.copiedSoundControlsEnabled)
        controller.update(\.playSound, value: true)
        XCTAssertEqual(controller.settings.copiedSound, .submarine)
    }

    // Sound 9
    func testCaptureSoundAndSwitchPersistAcrossRelaunch() {
        controller.update(\.playSound, value: true)
        controller.chooseCopiedSound(.ping)
        let reopened = makeController()
        XCTAssertTrue(reopened.settings.playSound)
        XCTAssertEqual(reopened.settings.copiedSound, .ping)
        XCTAssertTrue(reopened.copiedSoundControlsEnabled)
        reopened.update(\.playSound, value: false)
        let again = makeController()
        XCTAssertEqual(again.settings.copiedSound, .ping)
        XCTAssertFalse(again.copiedSoundControlsEnabled)
    }

    // Sound 10
    func testUnknownOrMissingSoundFallsBackToGlass() async {
        XCTAssertEqual(TextGrabCaptureSound(storedValue: nil), .glass)
        XCTAssertEqual(TextGrabCaptureSound(storedValue: ""), .glass)
        XCTAssertEqual(TextGrabCaptureSound(storedValue: "Nope.aiff"), .glass)
        XCTAssertEqual(TextGrabCaptureSound(storedValue: "Submarine"), .submarine)
        defaults.set("Nope.aiff", forKey: TextGrabSettings.Key.copiedSound)
        defaults.set(true, forKey: TextGrabSettings.Key.playSound)
        controller = makeController()
        XCTAssertEqual(controller.settings.copiedSound, .glass)
        await grab(threeLines)
        XCTAssertEqual(feedback.sounds, [.copied(.glass)])
    }

    // Sound 6, 7 and 10 at the speaker: the real feedback plays by name through an injected player.
    func testFeedbackPlaysTheNamedSoundThroughTheInjectedPlayer() {
        let player = TextGrabSoundPlayerFake()
        let real = TextGrabFeedback(player: player)
        real.play(.copied(.submarine))
        real.play(.notFound)
        real.play(.copied(.glass))
        XCTAssertEqual(player.played, ["Submarine", "Basso", "Glass"])
    }

    // Sound 13
    func testCaptureSoundWritesOnlyTheAppSettings() {
        controller.update(\.playSound, value: true)
        controller.chooseCopiedSound(.tink)
        controller.previewCopiedSound()
        XCTAssertNil(UserDefaults.standard.object(forKey: TextGrabSettings.Key.copiedSound))
        let written = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("textGrab.") }
        XCTAssertEqual(Set(written), [TextGrabSettings.Key.keepLineBreaks, TextGrabSettings.Key.playSound,
                                      TextGrabSettings.Key.language, TextGrabSettings.Key.showPreview,
                                      TextGrabSettings.Key.copiedSound])
        XCTAssertEqual(clipboard.writes, [])
    }

    // 19
    func testMenuItemSitsAboveStartCleaningModeAndShowsTheShortcut() {
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_G), modifierFlags: [.control, .option])
        let items = MenuBarManager.makeTextGrabAndCleaningItems(cleaningActive: false, textGrabShortcut: combo, target: nil)
        XCTAssertEqual(items.map(\.title), ["Grab Text from Screen", "Start Cleaning Mode"])
        XCTAssertEqual(items[0].keyEquivalent, "g")
        XCTAssertEqual(items[0].keyEquivalentModifierMask, [.control, .option])
        XCTAssertTrue(items[0].isEnabled)
        let none = MenuBarManager.makeTextGrabAndCleaningItems(cleaningActive: false, textGrabShortcut: nil, target: nil)
        XCTAssertEqual(none[0].keyEquivalent, "")
        XCTAssertNil(MenuBarManager.menuKeyEquivalent(for: UInt16(kVK_LeftArrow)))
        // The menu item and the shortcut start the same flow.
        XCTAssertEqual(controller.start(), .started)
        XCTAssertEqual(selection.beginCount, 1)
    }

    // 20
    func testNothingIsSavedOrSentBySource() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Claude Usage").appendingPathComponent("TextGrab")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThanOrEqual(files.count, 5)
        let forbidden = ["URLSession", "import Network", "NWConnection", "write(to", "createFile", "CGImageDestination",
                         "representation(using", "tiffRepresentation", "FileManager", "NSTemporaryDirectory", "temporaryDirectory",
                         "print(", "NSLog", "os_log", "Logger(", "LoggingService", "CGRequestScreenCaptureAccess", "requestAccess"]
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                XCTAssertFalse(source.contains(token), "\(file.lastPathComponent) contains \(token)")
            }
            if file.lastPathComponent != "TextGrabSystem.swift" {
                XCTAssertFalse(source.contains("SCShareableContent"), "\(file.lastPathComponent) touches ScreenCaptureKit")
                XCTAssertFalse(source.contains("SCScreenshotManager"), "\(file.lastPathComponent) touches ScreenCaptureKit")
            }
        }
        let system = try String(contentsOf: folder.appendingPathComponent("TextGrabSystem.swift"), encoding: .utf8)
        XCTAssertTrue(system.contains("CGPreflightScreenCaptureAccess()"))
    }

    // 21
    func testNoClashWithCleaningMode() async {
        cleaningActive = true
        XCTAssertEqual(controller.start(), .blockedByCleaning)
        XCTAssertEqual(selection.beginCount, 0)
        XCTAssertFalse(controller.canTryNow)
        cleaningActive = false
        XCTAssertEqual(controller.start(), .started)
        controller.cleaningModeStarted()
        XCTAssertEqual(selection.cancelCount, 1)
        XCTAssertEqual(controller.phase, .idle)
        // A late result from the cancelled overlay is ignored.
        selection.finish(.selected(box()))
        await waitUntilIdle()
        XCTAssertEqual(capturer.captures.count, 0)
        XCTAssertEqual(clipboard.writes, [])
        // Cleaning starting while text is being read drops the result too.
        recognizer.delay = 0.2
        recognizer.lines = threeLines
        XCTAssertEqual(controller.start(), .started)
        selection.finish(.selected(box()))
        XCTAssertEqual(controller.phase, .reading)
        controller.cleaningModeStarted()
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(clipboard.writes, [])
    }

    // 22
    func testExistingShortcutsAndCallbacksStillRoute() {
        let manager = ShortcutManager(store: ShortcutStoreSpy(), registrar: ShortcutRegistrarSpy().register)
        var fired: [String] = []
        manager.onToggleKeepAwake = { fired.append("keepAwake") }
        manager.onToggleCleaningMode = { fired.append("cleaning") }
        manager.onTextGrab = { fired.append("textGrab") }
        manager.onRefresh = { fired.append("refresh") }
        let combos: [(ShortcutAction, KeyCombo)] = [
            (.keepAwake, KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.control, .option])),
            (.cleaningMode, KeyCombo(keyCode: UInt16(kVK_ANSI_C), modifierFlags: [.control, .option, .command])),
            (.textGrab, KeyCombo(keyCode: UInt16(kVK_ANSI_G), modifierFlags: [.control, .option])),
            (.refresh, KeyCombo(keyCode: UInt16(kVK_ANSI_R), modifierFlags: [.command, .shift]))
        ]
        for (action, combo) in combos { XCTAssertEqual(manager.setShortcut(combo, for: action), .success) }
        for (_, combo) in combos { XCTAssertTrue(manager.perform(combo)) }
        XCTAssertEqual(fired, ["keepAwake", "cleaning", "textGrab", "refresh"])
    }

    // 23
    func testEnglishCopyInEveryLocale() {
        XCTAssertEqual(TextGrabCopy.menuItemTitle, "Grab Text from Screen")
        XCTAssertEqual(TextGrabCopy.privacy, "Text Grab reads the area you select on your Mac. The picture is never saved or sent anywhere. Only the text is copied.")
        XCTAssertEqual(TextGrabCopy.openSettingsButton, "Open Screen Recording Settings")
        XCTAssertEqual(TextGrabCopy.permissionTitle, "Permission needed")
        XCTAssertEqual(TextGrabCopy.readyTitle, "Ready")
        XCTAssertEqual(TextGrabCopy.tryItNow, "Try it now")
    }

    func testDefaultsArePersistedOnlyInTheGivenStore() {
        XCTAssertEqual(controller.settings, TextGrabSettings(keepLineBreaks: true, playSound: false, language: .automatic, showPreview: true, copiedSound: .glass))
        controller.update(\.playSound, value: true)
        controller.update(\.keepLineBreaks, value: false)
        let restored = makeController()
        XCTAssertTrue(restored.settings.playSound)
        XCTAssertFalse(restored.settings.keepLineBreaks)
        XCTAssertNil(UserDefaults.standard.object(forKey: TextGrabSettings.Key.playSound))
        XCTAssertEqual(TextGrabLanguage(storedValue: nil), .automatic)
        XCTAssertEqual(TextGrabLanguage(storedValue: "automatic"), .automatic)
        XCTAssertEqual(TextGrabLanguage(storedValue: "de-DE"), .fixed("de-DE"))
    }
}

// MARK: - Fakes

final class TextGrabTestBox<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@MainActor final class TextGrabEventLog {
    var events: [String] = []
}

@MainActor final class TextGrabPermissionFake: TextGrabPermissionChecking {
    private let log: TextGrabEventLog
    var granted = true
    private(set) var checkCount = 0
    private(set) var openCount = 0
    init(log: TextGrabEventLog) { self.log = log }
    var screenCaptureGranted: Bool { checkCount += 1; log.events.append("permission.check"); return granted }
    func openScreenRecordingSettings() { openCount += 1; log.events.append("permission.open") }
}

@MainActor final class TextGrabCapturerFake: TextGrabCapturing {
    private let log: TextGrabEventLog
    var error: Error?
    private(set) var captures: [TextGrabSelection] = []
    init(log: TextGrabEventLog) { self.log = log }
    func capture(_ selection: TextGrabSelection) async throws -> CGImage {
        captures.append(selection)
        log.events.append("capture")
        if let error { throw error }
        return TextGrabTestImage.blank()
    }
}

@MainActor final class TextGrabRecognizerFake: TextGrabRecognizing {
    private let log: TextGrabEventLog
    var lines: [TextGrabLine] = []
    var delay: TimeInterval = 0
    var supported: [String] = ["en-US"]
    private(set) var languages: [TextGrabLanguage] = []
    init(log: TextGrabEventLog) { self.log = log }
    func recognize(_ image: CGImage, language: TextGrabLanguage) async throws -> [TextGrabLine] {
        languages.append(language)
        log.events.append("recognize")
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return lines
    }
    func supportedLanguages() -> [String] { supported }
}

@MainActor final class TextGrabClipboardFake: TextGrabClipboardWriting {
    private let log: TextGrabEventLog
    var writes: [String] = []
    init(log: TextGrabEventLog) { self.log = log }
    func writePlainText(_ text: String) { writes.append(text); log.events.append("clipboard") }
}

@MainActor final class TextGrabSelectionFake: TextGrabSelectionPresenting {
    private let log: TextGrabEventLog
    private(set) var beginCount = 0
    private(set) var cancelCount = 0
    private var onFinish: ((TextGrabSelectionResult) -> Void)?
    private var lastOnFinish: ((TextGrabSelectionResult) -> Void)?
    init(log: TextGrabEventLog) { self.log = log }
    func begin(onFinish: @escaping (TextGrabSelectionResult) -> Void) {
        beginCount += 1
        self.onFinish = onFinish
        lastOnFinish = onFinish
        log.events.append("selection.begin")
    }
    func cancel() { cancelCount += 1; onFinish = nil; log.events.append("selection.cancel") }
    /// Delivers a result like the overlay does after it has closed. After a cancel it
    /// replays the stale callback to prove the controller ignores it.
    func finish(_ result: TextGrabSelectionResult) {
        log.events.append("selection.finished")
        let callback = onFinish ?? lastOnFinish
        onFinish = nil
        callback?(result)
    }
}

@MainActor final class TextGrabFeedbackFake: TextGrabFeedbackPresenting {
    private let log: TextGrabEventLog
    var toasts: [TextGrabToastContent] = []
    private(set) var displays: [CGDirectDisplayID?] = []
    private(set) var sounds: [TextGrabSound] = []
    private(set) var hideCount = 0
    init(log: TextGrabEventLog) { self.log = log }
    func show(_ toast: TextGrabToastContent, displayID: CGDirectDisplayID?) { toasts.append(toast); displays.append(displayID); log.events.append("toast") }
    func hide() { hideCount += 1 }
    func play(_ sound: TextGrabSound) { sounds.append(sound) }
}

/// Records sound names instead of playing them, so no test makes a sound.
@MainActor final class TextGrabSoundPlayerFake: TextGrabSoundPlaying {
    private(set) var played: [String] = []
    func play(named name: String) { played.append(name) }
}

// MARK: - Test images and renders (test target only; the app never writes images)

enum TextGrabTestImage {
    static func blank() -> CGImage {
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return context.makeImage()!
    }

    /// Black text on white at a size Vision reads reliably, top line first.
    @MainActor static func render(_ lines: [String], fontSize: CGFloat = 56) -> CGImage? {
        let width = 1400
        let lineHeight = Int(fontSize * 1.8)
        let height = lineHeight * lines.count + 80
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .regular), .foregroundColor: NSColor.black]
        for (index, text) in lines.enumerated() {
            let y = CGFloat(height - 40 - (index + 1) * lineHeight)
            (text as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}

@MainActor enum TextGrabPreviewRenderer {
    static func renderSettings(controller: TextGrabController, manager: ShortcutManager, scheme: ColorScheme, to url: URL) throws {
        let sidebar = scheme == .dark ? Color(white: 0.08) : Color(white: 0.93)
        let content = HStack(spacing: 0) {
            AppSettingsSection(selectedSection: .constant(.textGrab))
                .padding(12).frame(width: 190, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .top).background(sidebar)
            TextGrabSettingsView(controller: controller, shortcuts: manager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(scheme == .dark ? Color.black.opacity(0.15) : Color.white.opacity(0.3))
        }
        .frame(width: 720, height: 1100)
        .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.97))
        try render(content, scheme: scheme, size: CGSize(width: 720, height: 1100), to: url)
    }

    static func renderToast(_ content: TextGrabToastContent, scheme: ColorScheme, to url: URL) throws {
        let view = TextGrabToastView(content: content).padding(20)
            .background(scheme == .dark ? Color(white: 0.15) : Color(white: 0.9))
        try render(view, scheme: scheme, size: nil, to: url)
    }

    private static func render<Content: View>(_ view: Content, scheme: ColorScheme, size: CGSize?, to url: URL) throws {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: size ?? hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw NSError(domain: "TextGrabPreviewRenderer", code: 1)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "TextGrabPreviewRenderer", code: 2)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
