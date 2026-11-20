import AppKit

/// Only successful shutdown of an existing Top Shelf host requires restoration.
/// Other features share the process-wide hosts but no new saved preference.
final class CleaningOtherInputCoordinator: CleaningOtherInputHandling {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}
    private let shortcuts: ShortcutManager
    private let topShelf: TopShelfHost
    private var resumeShortcuts = false
    private var resumeTopShelf = false

    init(shortcuts: ShortcutManager = .shared, topShelf: TopShelfHost = .shared) {
        self.shortcuts = shortcuts
        self.topShelf = topShelf
    }

    func suspend() -> Bool {
        resumeShortcuts = !shortcuts.shortcuts.isEmpty
        shortcuts.stopListening()
        resumeTopShelf = topShelf.suspendForCleaning()
        return true
    }

    func resume() {
        if resumeShortcuts { shortcuts.startListening() }
        resumeTopShelf = false
        resumeShortcuts = false
    }
}

extension TopShelfHost {
    func suspendForCleaning() -> Bool {
        guard model != nil else { return false }
        model?.close()   // its shortcuts live in ShortcutManager, which Cleaning Mode pauses on its own
        return true
    }
}

extension ShortcutManager {
    func resumeAfterCleaningInterruption() {
        guard CleaningModeController.shared.isActive == false, !shortcuts.isEmpty else { return }
        startListening()
    }
}

extension TopShelfHost {
    func resumeAfterCleaningInterruption() {
        guard Constants.NotchHUD.replacedByTopShelf, Self.isRunningTests == false else { return }
        start()
    }
}
