import AppKit
import SwiftUI

/// All real presentation is isolated here. Tests inject a recording fake and never
/// instantiate this controller or show a window.
@MainActor
final class CleaningOverlayController: CleaningOverlayHandling {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}
    static let shared = CleaningOverlayController()
    private var windows: [NSWindow] = []
    private var appearance = CleaningScreenAppearance.dimmed
    private var offShortcutHint: String?
    private var remaining = 0.0
    private var progress = 0.0

    func show(appearance: CleaningScreenAppearance, offShortcutHint: String?) {
        self.appearance = appearance
        self.offShortcutHint = offShortcutHint
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { makeWindow(on: $0) }
        windows.forEach { $0.orderFrontRegardless() }
    }

    func update(remaining: TimeInterval, holdProgress: Double) {
        self.remaining = remaining
        self.progress = holdProgress
        for window in windows { update(window) }
    }

    func screensChanged() { show(appearance: appearance, offShortcutHint: offShortcutHint) }
    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func makeWindow(on screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = appearance == .dimmed ? .clear : .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        update(window)
        return window
    }

    private func update(_ window: NSWindow) {
        window.contentViewController = NSHostingController(rootView:
            CleaningSessionView(appearance: appearance, remaining: remaining, holdProgress: progress, offShortcutHint: offShortcutHint)
        )
    }
}
