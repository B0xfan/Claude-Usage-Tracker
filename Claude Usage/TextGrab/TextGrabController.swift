import AppKit
import Combine
import CoreGraphics
import Foundation

/// Silent, read-only checks. Nothing here may show the macOS prompt: no request API and no
/// ScreenCaptureKit call happen while the permission is missing.
protocol TextGrabPermissionChecking: AnyObject {
    var screenCaptureGranted: Bool { get }
    /// Only reveals Privacy & Security > Screen & System Audio Recording. Never grants anything.
    func openScreenRecordingSettings()
}

/// Takes one still image of the selected box, in memory only.
protocol TextGrabCapturing: AnyObject {
    func capture(_ selection: TextGrabSelection) async throws -> CGImage
}

/// Reads the text in an image on the Mac itself.
protocol TextGrabRecognizing: AnyObject {
    func recognize(_ image: CGImage, language: TextGrabLanguage) async throws -> [TextGrabLine]
    func supportedLanguages() -> [String]
}

protocol TextGrabClipboardWriting: AnyObject {
    /// Replaces the clipboard with plain text only.
    func writePlainText(_ text: String)
}

/// The dimmed, crosshair selection overlay. `cancel()` closes it without calling `onFinish`.
protocol TextGrabSelectionPresenting: AnyObject {
    func begin(onFinish: @escaping (TextGrabSelectionResult) -> Void)
    func cancel()
}

/// The toast under the menu bar rings, and the optional sound.
/// Plays one built-in Mac sound by name. Injected so self-tests never make a sound.
protocol TextGrabSoundPlaying: AnyObject {
    func play(named name: String)
}

protocol TextGrabFeedbackPresenting: AnyObject {
    func show(_ toast: TextGrabToastContent, displayID: CGDirectDisplayID?)
    func hide()
    func play(_ sound: TextGrabSound)
}

enum TextGrabPermissionState: Equatable { case needed, ready }
enum TextGrabStartResult: Equatable { case started, permissionMissing, blockedByCleaning, alreadyRunning }
enum TextGrabPhase: Equatable { case idle, selecting, reading }
enum TextGrabOutcome: Equatable { case copied(String), noText, cancelled, failed }

@MainActor
final class TextGrabController: ObservableObject {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}
    static let shared = TextGrabController(defaults: .standard)

    @Published private(set) var settings: TextGrabSettings
    @Published private(set) var permissionState: TextGrabPermissionState = .needed
    @Published private(set) var phase: TextGrabPhase = .idle
    @Published private(set) var lastOutcome: TextGrabOutcome?
    @Published private(set) var shouldOpenSettings = false

    let permissions: TextGrabPermissionChecking
    let capturer: TextGrabCapturing
    let recognizer: TextGrabRecognizing
    let clipboard: TextGrabClipboardWriting
    let selection: TextGrabSelectionPresenting
    let feedback: TextGrabFeedbackPresenting
    private let defaults: UserDefaults
    private let isCleaningActive: () -> Bool
    private let readingNoticeDelay: TimeInterval
    private var generation = 0

    var canTryNow: Bool { permissionState == .ready && phase == .idle && !isCleaningActive() }

    /// Defaults are resolved inside the main-actor init body rather than as
    /// default-argument expressions, which Swift evaluates outside the actor.
    init(defaults: UserDefaults,
         permissions: TextGrabPermissionChecking? = nil,
         capturer: TextGrabCapturing? = nil,
         recognizer: TextGrabRecognizing? = nil,
         clipboard: TextGrabClipboardWriting? = nil,
         selection: TextGrabSelectionPresenting? = nil,
         feedback: TextGrabFeedbackPresenting? = nil,
         isCleaningActive: (() -> Bool)? = nil,
         readingNoticeDelay: TimeInterval = 0.5) {
        self.defaults = defaults
        self.permissions = permissions ?? TextGrabPermissions()
        self.capturer = capturer ?? TextGrabScreenCapturer()
        self.recognizer = recognizer ?? TextGrabVisionRecognizer()
        self.clipboard = clipboard ?? TextGrabPasteboard()
        self.selection = selection ?? TextGrabSelectionOverlay()
        self.feedback = feedback ?? TextGrabFeedback()
        self.isCleaningActive = isCleaningActive ?? { CleaningModeController.shared.isActive }
        self.readingNoticeDelay = readingNoticeDelay
        self.settings = TextGrabSettings.load(from: defaults)
        // Deliberately no permission check here: it runs when the shortcut is pressed
        // and when the Text Grab page opens.
    }

    /// Silent preflight only.
    func refreshPermission() {
        permissionState = permissions.screenCaptureGranted ? .ready : .needed
    }

    /// Shortcut, menu item and Try it now all come here.
    @discardableResult
    func start() -> TextGrabStartResult {
        guard !isCleaningActive() else { return .blockedByCleaning }
        guard phase == .idle else { return .alreadyRunning }
        refreshPermission()
        guard permissionState == .ready else {
            shouldOpenSettings = true
            return .permissionMissing
        }
        feedback.hide()
        phase = .selecting
        generation += 1
        let current = generation
        selection.begin { [weak self] result in
            self?.selectionFinished(result, generation: current)
        }
        return .started
    }

    func selectionFinished(_ result: TextGrabSelectionResult, generation finished: Int) {
        guard finished == generation, phase == .selecting else { return }
        switch result {
        case .cancelled:
            phase = .idle
            lastOutcome = .cancelled
        case .selected(let box):
            guard !TextGrabGeometry.isTooSmall(box.rect) else {
                phase = .idle
                lastOutcome = .cancelled
                return
            }
            phase = .reading
            Task { @MainActor [weak self] in await self?.read(box, generation: finished) }
        }
    }

    private func read(_ box: TextGrabSelection, generation current: Int) async {
        guard current == generation else { return }
        // Checked again right before the capture: it may have been withdrawn mid-drag.
        refreshPermission()
        guard permissionState == .ready else {
            phase = .idle
            lastOutcome = .cancelled
            shouldOpenSettings = true
            return
        }
        scheduleReadingNotice(displayID: box.displayID, generation: current)
        let lines: [TextGrabLine]
        do {
            // The image only lives inside this scope and is released right after reading.
            let image = try await capturer.capture(box)
            guard current == generation else { return }
            lines = try await recognizer.recognize(image, language: settings.language)
        } catch {
            guard current == generation else { return }
            phase = .idle
            lastOutcome = .failed
            feedback.show(.failed, displayID: box.displayID)
            return
        }
        guard current == generation else { return }
        finish(with: lines, displayID: box.displayID)
    }

    private func scheduleReadingNotice(displayID: CGDirectDisplayID, generation current: Int) {
        let delay = readingNoticeDelay
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard let self, self.generation == current, self.phase == .reading else { return }
            self.feedback.show(.reading, displayID: displayID)
        }
    }

    private func finish(with lines: [TextGrabLine], displayID: CGDirectDisplayID) {
        phase = .idle
        guard let text = TextGrabFormatter.clipboardText(from: lines, keepLineBreaks: settings.keepLineBreaks) else {
            // The clipboard is left exactly as it was.
            lastOutcome = .noText
            feedback.show(.noText, displayID: displayID)
            if settings.playSound { feedback.play(.notFound) }
            return
        }
        clipboard.writePlainText(text)
        lastOutcome = .copied(text)
        let preview = settings.showPreview ? TextGrabFormatter.preview(for: text) : nil
        feedback.show(.copied(title: TextGrabFormatter.toastTitle(for: text), preview: preview), displayID: displayID)
        if settings.playSound { feedback.play(.copied(settings.copiedSound)) }
    }

    /// Cleaning Mode started: drop any selection or reading in progress. Nothing is copied.
    func cleaningModeStarted() {
        switch phase {
        case .idle: return
        case .selecting: selection.cancel()
        case .reading: feedback.hide()
        }
        generation += 1
        phase = .idle
        lastOutcome = .cancelled
    }

    /// The capture sound menu and speaker only work while "Play a sound when done" is on.
    var copiedSoundControlsEnabled: Bool { settings.playSound }

    /// Picking a sound in the menu saves it and plays it once. Does nothing while sound is off.
    func chooseCopiedSound(_ sound: TextGrabCaptureSound) {
        guard copiedSoundControlsEnabled else { return }
        update(\.copiedSound, value: sound)
        feedback.play(.copied(sound))
    }

    /// The speaker: plays the selected sound once. No grab, no toast, no clipboard change.
    func previewCopiedSound() {
        guard copiedSoundControlsEnabled else { return }
        feedback.play(.copied(settings.copiedSound))
    }

    func consumeSettingsRequest() { shouldOpenSettings = false }
    func openScreenRecordingSettings() { permissions.openScreenRecordingSettings() }
    func supportedLanguages() -> [TextGrabLanguage] {
        [.automatic] + recognizer.supportedLanguages().map { TextGrabLanguage.fixed($0) }
    }

    func update<Value>(_ keyPath: WritableKeyPath<TextGrabSettings, Value>, value: Value) {
        settings[keyPath: keyPath] = value
        settings.save(to: defaults)
    }
}
