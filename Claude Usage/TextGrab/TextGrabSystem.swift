import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import SwiftUI
import Vision

/// Read-only permission check. Only John can turn Screen Recording on.
final class TextGrabPermissions: TextGrabPermissionChecking {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}

    /// Preflight never shows a prompt; it only reports the current switch.
    var screenCaptureGranted: Bool { CGPreflightScreenCaptureAccess() }

    func openScreenRecordingSettings() {
        // Only reveals the named pane. Nothing is requested or granted.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

enum TextGrabError: Error { case displayUnavailable, emptySelection }

/// One still image of the dragged box, taken with ScreenCaptureKit and kept in memory.
/// Usage Shelf's own windows are excluded, so the overlay and toast are never in it.
/// Only TextGrabController calls this, and only after the silent preflight said yes.
final class TextGrabScreenCapturer: TextGrabCapturing {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}

    func capture(_ selection: TextGrabSelection) async throws -> CGImage {
        let local = TextGrabGeometry.displayLocalRect(selection.rect, in: selection.screenFrame)
        guard local.width > 0, local.height > 0 else { throw TextGrabError.emptySelection }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw TextGrabError.displayUnavailable
        }
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownProcess }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = local
        let pixels = TextGrabGeometry.pixelSize(of: local, scale: selection.scale)
        configuration.width = pixels.width
        configuration.height = pixels.height
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}

/// Apple Vision text recognition on the Mac itself, at the accurate level (the same
/// framework Top Shelf uses for words in copied pictures). Nothing is sent anywhere.
final class TextGrabVisionRecognizer: TextGrabRecognizing {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}

    func recognize(_ image: CGImage, language: TextGrabLanguage) async throws -> [TextGrabLine] {
        try await Task.detached(priority: .userInitiated) {
            try TextGrabVisionReader.read(image, language: language)
        }.value
    }

    func supportedLanguages() -> [String] { TextGrabVisionReader.supportedLanguages() }
}

nonisolated enum TextGrabVisionReader {
    static func makeRequest(language: TextGrabLanguage) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        switch language {
        case .automatic:
            request.automaticallyDetectsLanguage = true
        case .fixed(let code):
            request.automaticallyDetectsLanguage = false
            request.recognitionLanguages = [code]
        }
        return request
    }

    static func read(_ image: CGImage, language: TextGrabLanguage) throws -> [TextGrabLine] {
        let request = makeRequest(language: language)
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return TextGrabLine(text: text, box: observation.boundingBox)
        }
    }

    static func supportedLanguages() -> [String] {
        let request = makeRequest(language: .automatic)
        return (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
    }
}

final class TextGrabPasteboard: TextGrabClipboardWriting {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}

    func writePlainText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// Never key, never main, never activates Usage Shelf: the toast cannot take focus or keystrokes.
final class TextGrabToastPanel: NSPanel {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}

    static func make() -> TextGrabToastPanel {
        let panel = TextGrabToastPanel(contentRect: NSRect(x: 0, y: 0, width: TextGrabToastLayout.width, height: 64),
                                       styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered,
                                       defer: true)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

nonisolated enum TextGrabToastLayout {
    static let width: CGFloat = 300
    static let visibleSeconds: TimeInterval = 2.5
    static let gapBelowMenuBar: CGFloat = 6

    /// Under the rings when they are on this display, otherwise at the top right of it.
    static func origin(size: CGSize, screenFrame: CGRect, visibleFrame: CGRect, anchor: CGRect?) -> CGPoint {
        let top = visibleFrame.maxY - gapBelowMenuBar
        guard let anchor, screenFrame.intersects(anchor) else {
            return CGPoint(x: visibleFrame.maxX - size.width - 12, y: top - size.height)
        }
        let x = min(max(anchor.midX - size.width / 2, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
        return CGPoint(x: x, y: min(anchor.minY - gapBelowMenuBar, top) - size.height)
    }
}

/// Shows the Copied / No text found toast for about 2.5 seconds, kept open while hovered
/// and dismissed by a click, plus the optional sound.
final class TextGrabFeedback: TextGrabFeedbackPresenting {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}

    /// Where the Usage Shelf rings are on screen, set by MenuBarManager.
    var anchorProvider: (() -> CGRect?)?
    private var panel: TextGrabToastPanel?
    private var hideGeneration = 0
    private var hovering = false
    private var content: TextGrabToastContent?

    func show(_ toast: TextGrabToastContent, displayID: CGDirectDisplayID?) {
        content = toast
        let panel = self.panel ?? TextGrabToastPanel.make()
        self.panel = panel
        let view = TextGrabToastView(content: toast,
                                     onHover: { [weak self] inside in self?.hoverChanged(inside) },
                                     onClick: { [weak self] in self?.hide() })
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        panel.contentView = hosting
        let screen = NSScreen.screens.first(where: { $0.textGrabDisplayID == displayID }) ?? NSScreen.main ?? NSScreen.screens.first
        if let screen {
            let frame = CGSize(width: TextGrabToastLayout.width, height: max(44, size.height))
            let origin = TextGrabToastLayout.origin(size: frame, screenFrame: screen.frame, visibleFrame: screen.visibleFrame, anchor: anchorProvider?())
            panel.setFrame(NSRect(origin: origin, size: frame), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        if toast == .reading { hideGeneration += 1 } else { scheduleHide() }
    }

    func hide() {
        hideGeneration += 1
        hovering = false
        content = nil
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.content == nil else { return }
                self.panel?.orderOut(nil)
            }
        })
    }

    func play(_ sound: TextGrabSound) {
        NSSound(named: NSSound.Name(sound == .copied ? "Glass" : "Basso"))?.play()
    }

    private func hoverChanged(_ inside: Bool) {
        hovering = inside
        if inside { hideGeneration += 1 } else if content != nil && content != .reading { scheduleHide() }
    }

    private func scheduleHide() {
        hideGeneration += 1
        let generation = hideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + TextGrabToastLayout.visibleSeconds) { [weak self] in
            guard let self, self.hideGeneration == generation, !self.hovering else { return }
            self.hide()
        }
    }
}

extension NSScreen {
    var textGrabDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
