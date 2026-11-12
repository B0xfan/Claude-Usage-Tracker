import AppKit
import CoreGraphics

/// The selection overlay: every display dims a little, the pointer is a crosshair, and the
/// box is drawn on the display where the drag started. Esc, a right click, or a plain click
/// cancels; so do a Space switch, a lock, sleep, a user switch, or a display change.
/// Tests never create this; they inject a fake selection presenter.
final class TextGrabSelectionOverlay: TextGrabSelectionPresenting {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}

    /// Time for the window server to take the overlay off screen before the capture.
    /// Usage Shelf's own windows are also excluded from the capture itself.
    static let captureDelay: TimeInterval = 0.08

    private var windows: [TextGrabOverlayWindow] = []
    private var onFinish: ((TextGrabSelectionResult) -> Void)?
    private var delivering: ((TextGrabSelectionResult) -> Void)?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var previousApp: NSRunningApplication?
    private var cursorPushed = false

    func begin(onFinish: @escaping (TextGrabSelectionResult) -> Void) {
        close()
        self.onFinish = onFinish
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        let mouse = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let window = TextGrabOverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            let view = TextGrabOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.screenFrame = screen.frame
            view.topInset = screen.frame.maxY - screen.visibleFrame.maxY
            view.displayID = screen.textGrabDisplayID ?? CGMainDisplayID()
            view.scale = screen.backingScaleFactor
            view.showsHint = NSMouseInRect(mouse, screen.frame, false)
            view.onFinish = { [weak self] result in self?.finish(result) }
            window.contentView = view
            windows.append(window)
        }
        // Keyboard focus is taken only so Esc can cancel; it goes back on close.
        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { $0.orderFrontRegardless() }
        let keyWindow = windows.first(where: { ($0.contentView as? TextGrabOverlayView)?.showsHint == true }) ?? windows.first
        keyWindow?.makeKey()
        if let view = keyWindow?.contentView { keyWindow?.makeFirstResponder(view) }
        NSCursor.crosshair.push()
        cursorPushed = true
        observeInterruptions()
    }

    func cancel() {
        onFinish = nil
        delivering = nil
        close()
    }

    private func finish(_ result: TextGrabSelectionResult) {
        guard let onFinish else { return }
        self.onFinish = nil
        delivering = onFinish
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.captureDelay) { [weak self] in
            self?.deliver(result)
        }
    }

    private func deliver(_ result: TextGrabSelectionResult) {
        guard let delivering else { return }
        self.delivering = nil
        delivering(result)
    }

    private func close() {
        for window in windows {
            (window.contentView as? TextGrabOverlayView)?.onFinish = nil
            window.orderOut(nil)
        }
        windows.removeAll()
        for observer in observers { observer.center.removeObserver(observer.token) }
        observers.removeAll()
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
        if let previousApp {
            _ = previousApp.activate()
            self.previousApp = nil
        }
    }

    private func observeInterruptions() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.finish(.cancelled) }
            }
            observers.append((center: workspace, token: token))
        }
        let app = NotificationCenter.default
        let screens = app.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finish(.cancelled) }
        }
        observers.append((center: app, token: screens))
        let distributed = DistributedNotificationCenter.default()
        let lock = distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finish(.cancelled) }
        }
        observers.append((center: distributed, token: lock))
    }
}

final class TextGrabOverlayWindow: NSWindow {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Draws the dim, the bright box with its outline and size label, and the hint pill.
/// Works in global AppKit points; the box stops at this display's edge.
final class TextGrabOverlayView: NSView {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}

    var screenFrame: CGRect = .zero
    var topInset: CGFloat = 0
    var displayID: CGDirectDisplayID = 0
    var scale: CGFloat = 1
    var showsHint = false
    var onFinish: ((TextGrabSelectionResult) -> Void)?
    private var start: CGPoint?
    private var current: CGPoint?

    var box: CGRect? {
        guard let start, let current else { return nil }
        return TextGrabGeometry.box(from: start, to: current, within: screenFrame)
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseMoved(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseDown(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        start = point
        current = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard start != nil else { return }
        current = NSEvent.mouseLocation
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        current = NSEvent.mouseLocation
        let rect = box ?? .zero
        if TextGrabGeometry.isTooSmall(rect) {
            onFinish?(.cancelled)
        } else {
            onFinish?(.selected(TextGrabSelection(rect: rect, screenFrame: screenFrame, displayID: displayID, scale: scale)))
        }
    }

    override func rightMouseDown(with event: NSEvent) { onFinish?(.cancelled) }

    override func keyDown(with event: NSEvent) {
        // Only Esc does anything. Other keys are ignored while selecting.
        if event.keyCode == 53 { onFinish?(.cancelled) }
    }

    override func cancelOperation(_ sender: Any?) { onFinish?(.cancelled) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()
        if let box {
            let local = box.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
            NSColor.clear.setFill()
            local.fill(using: .copy)
            let outline = NSBezierPath(rect: local.insetBy(dx: 0.75, dy: 0.75))
            outline.lineWidth = 1.5
            NSColor.systemBlue.setStroke()
            outline.stroke()
            drawLabel(TextGrabGeometry.sizeLabel(for: box), near: local)
        }
        if showsHint { drawHint() }
    }

    private func drawLabel(_ text: String, near rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var frame = CGRect(x: rect.maxX - size.width - 10, y: rect.minY - size.height - 10, width: size.width + 10, height: size.height + 4)
        frame.origin.x = min(max(frame.origin.x, bounds.minX + 4), bounds.maxX - frame.width - 4)
        if frame.minY < bounds.minY + 4 { frame.origin.y = rect.minY + 4 }
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: frame.minX + 5, y: frame.minY + 2), withAttributes: attributes)
    }

    private func drawHint() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let text = TextGrabCopy.overlayHint as NSString
        let size = text.size(withAttributes: attributes)
        let pill = CGRect(x: bounds.midX - (size.width + 28) / 2,
                          y: bounds.maxY - topInset - 18 - (size.height + 12),
                          width: size.width + 28,
                          height: size.height + 12)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        text.draw(at: CGPoint(x: pill.minX + 14, y: pill.minY + 6), withAttributes: attributes)
    }
}
