import AppKit
import Observation
import SwiftUI

enum Page: String, CaseIterable { case tray = "Tray", files = "Files", clipboard = "Clipboard", agents = "Agents" }

@Observable
final class ShelfModel {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}
    var isOpen = false
    var page: Page = .tray
    var openedByHover = false
    /// Seconds before a hover over the notch opens the shelf; negative = hover does not open it.
    // Settings (Settings window). Saved at once and read by the code that uses them, so changes apply without a restart.
    enum OpenMode: String, CaseIterable { case hover = "Hover", click = "Click", both = "Both" }
    var openMode: OpenMode = OpenMode(rawValue: TopShelfDefaults.store.string(forKey: "openMode") ?? "") ?? .both {
        didSet { TopShelfDefaults.store.set(openMode.rawValue, forKey: "openMode") }
    }
    /// Seconds the pointer waits on the notch before the shelf opens (0 to 1.5).
    var hoverDelay: Double = max(0, TopShelfDefaults.store.object(forKey: "hoverDelay") as? Double ?? 0.3) {
        didSet { TopShelfDefaults.store.set(hoverDelay, forKey: "hoverDelay") }
    }
    /// Seconds after the pointer leaves a hover-opened shelf before it closes (0 to 3).
    var hoverCloseDelay: Double = TopShelfDefaults.store.object(forKey: "hoverCloseDelay") as? Double ?? 0.5 {
        didSet { TopShelfDefaults.store.set(hoverCloseDelay, forKey: "hoverCloseDelay") }
    }
    /// The Top Shelf icon in the menu bar. When off, Settings still opens from the shelf's gear button.
    var showMenuBarIcon: Bool = TopShelfDefaults.store.object(forKey: "showMenuBarIcon") as? Bool ?? true {
        didSet { TopShelfDefaults.store.set(showMenuBarIcon, forKey: "showMenuBarIcon"); menuBarIconChanged?() }
    }
    @ObservationIgnored var menuBarIconChanged: (() -> Void)?
    /// Open the shelf on the Agents page when a chat needs permission, so John can answer it from the notch.
    var openForApproval: Bool = TopShelfDefaults.store.object(forKey: "openForApproval") as? Bool ?? true {
        didSet { TopShelfDefaults.store.set(openForApproval, forKey: "openForApproval") }
    }
    /// Sounds for John's main chats (Settings > Sounds); the names are sound file names, as NSSound takes them.
    var questionSoundOn: Bool = TopShelfDefaults.store.object(forKey: "questionSoundOn") as? Bool ?? true {
        didSet { TopShelfDefaults.store.set(questionSoundOn, forKey: "questionSoundOn") }
    }
    var questionSound: String = TopShelfDefaults.store.string(forKey: "questionSound") ?? "Glass" {
        didSet { TopShelfDefaults.store.set(questionSound, forKey: "questionSound") }
    }
    var finishedSoundOn: Bool = TopShelfDefaults.store.object(forKey: "finishedSoundOn") as? Bool ?? true {
        didSet { TopShelfDefaults.store.set(finishedSoundOn, forKey: "finishedSoundOn") }
    }
    var finishedSound: String = TopShelfDefaults.store.string(forKey: "finishedSound") ?? "Hero" {
        didSet { TopShelfDefaults.store.set(finishedSound, forKey: "finishedSound") }
    }
    /// The sound file to play for a signal, or nil when that sound is switched off.
    func soundFile(_ s: Agents.Sound) -> String? {
        switch s {
        case .question: questionSoundOn ? questionSound : nil
        case .finished: finishedSoundOn ? finishedSound : nil
        }
    }
    /// How long dropped files stay; 0 = until removed.
    var keepFilesFor: TimeInterval = TopShelfDefaults.store.object(forKey: "keepFilesFor") as? Double ?? 86400 {
        didSet { TopShelfDefaults.store.set(keepFilesFor, forKey: "keepFilesFor"); files.keepFor = keepFilesFor > 0 ? keepFilesFor : nil; files.prune() }
    }
    /// How long unpinned clipboard items stay.
    var keepClipsFor: TimeInterval = TopShelfDefaults.store.object(forKey: "keepClipsFor") as? Double ?? 7 * 86400 {
        didSet { TopShelfDefaults.store.set(keepClipsFor, forKey: "keepClipsFor"); clipboard.keepFor = keepClipsFor; clipboard.prune() }
    }
    var geometry = ShelfNotchGeometry(screenWidth: 1512, leftWidth: 662, rightWidth: 662, topInset: 32, menuBarHeight: 32)
    let music: NowPlaying
    let calendar: CalendarService
    let weather: WeatherService
    let files: FilesTray
    let clipboard: ClipboardHistory
    let agents: Agents

    /// `live` starts the system services; the self-test and pictures use a quiet model.
    init(live: Bool = false) {
        music = NowPlaying(resources: live ? Bundle.main.resourceURL : nil)
        calendar = CalendarService(live: live)
        weather = WeatherService(live: live)
        let dir = live ? supportFolder() : nil
        files = FilesTray(store: dir?.appendingPathComponent("files.json"))
        clipboard = ClipboardHistory(dir: dir, live: live)
        agents = Agents(dir: dir, live: live)
        if live { agents.onSound = { [weak self] s in self?.soundFile(s).map(AlertSounds.play) } }
        agents.onApproval = { [weak self] in
            // a request arrived: put it in front of John, on the page he is already looking at or by opening the shelf
            guard let self, self.openForApproval else { return }
            if self.isOpen { if self.page != .agents { self.page = .agents } } else { self.open(.agents) }
        }
        files.keepFor = keepFilesFor > 0 ? keepFilesFor : nil
        clipboard.keepFor = keepClipsFor
        files.prune(); clipboard.prune()
        // the old menu stored "hover off" as a negative delay
        if (TopShelfDefaults.store.object(forKey: "hoverDelay") as? Double ?? 0) < 0, TopShelfDefaults.store.string(forKey: "openMode") == nil {
            openMode = .click
        }
    }

    func open(_ p: Page, byHover: Bool = false) {
        page = p; openedByHover = byHover; isOpen = true
        files.prune()   // expiry is checked whenever the shelf opens, so nothing old is ever shown
    }
    func close() { isOpen = false }
    func toggle(_ p: Page) { if isOpen && page == p { close() } else { open(p) } }

    /// Something shows beside the closed notch: Claude Code activity or music.
    var showsMusic: Bool { music.isPlaying && music.hasTrack }
    var hasBanners: Bool { showsMusic || agents.activeState != nil }
    /// The gear button opens the Settings window (set by the app).
    @ObservationIgnored var openSettings: (() -> Void)?

    /// Sizes measured from John's screenshots of Bartender's Top Shelf (Retina pictures, 2 pixels per point):
    /// closed with activity it is 254 pt wide around a 179 pt notch (37.5 pt a side), the top flaring out 3 pt;
    /// open it is 611 x 174 pt.
    static let side: CGFloat = 37.5
    static let flare: CGFloat = 4.5
    var collapsedSize: CGSize {
        CGSize(width: geometry.notchWidth + (hasBanners ? 2 * (Self.side + Self.flare) : 0), height: geometry.notchHeight)
    }
    var openSize: CGSize { CGSize(width: 611, height: 174) }
}

/// Where the notch is. Screens without a notch get a capsule of the same job at the top center.
struct ShelfNotchGeometry: Equatable {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasNotch: Bool

    init(screenWidth: CGFloat, leftWidth: CGFloat?, rightWidth: CGFloat?, topInset: CGFloat, menuBarHeight: CGFloat) {
        if topInset > 0, let l = leftWidth, let r = rightWidth, screenWidth - l - r > 0 {
            notchWidth = screenWidth - l - r; notchHeight = topInset; hasNotch = true
        } else {
            notchWidth = 200; notchHeight = max(menuBarHeight, 24); hasNotch = false
        }
    }

    init(_ screen: NSScreen) {
        self.init(screenWidth: screen.frame.width, leftWidth: screen.auxiliaryTopLeftArea?.width,
                  rightWidth: screen.auxiliaryTopRightArea?.width, topInset: screen.safeAreaInsets.top,
                  menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY)
    }
}

final class ShelfPanel: NSPanel {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}
    override var canBecomeKey: Bool { true }   // the clipboard search field needs typing
}

/// Accepts the first click even though Top Shelf is never the active app.
final class FirstClickHostingView<V: View>: NSHostingView<V> {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Reports the mouse while it is over the panel, also when another app is active.
final class HoverView: NSView {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}
    var onMove: (NSPoint) -> Void = { _ in }
    var onExit: () -> Void = {}
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { onMove(NSEvent.mouseLocation) }
    override func mouseMoved(with event: NSEvent) { onMove(NSEvent.mouseLocation) }
    override func mouseExited(with event: NSEvent) { onExit() }
}

final class ShelfController {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}
    private let model: ShelfModel
    private let panel: ShelfPanel
    private var screen: NSScreen?
    private var monitors: [Any] = []
    private lazy var hover = HoverLogic(model: model)
    private var wasOpen = false   // layout() also runs for banner changes; only a real close may disarm hover

    init(model: ShelfModel) {
        self.model = model
        panel = ShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)   // above the menu bar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false

        let hover = HoverView()
        let host = FirstClickHostingView(rootView: ShelfView(model: model))
        host.autoresizingMask = [.width, .height]
        hover.addSubview(host)
        hover.onMove = { [weak self] p in self?.mouseMoved(p) }
        hover.onExit = { [weak self] in self?.mouseLeft() }
        panel.contentView = hover

        let nc = NotificationCenter.default, wc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.place() }
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            wc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updateFullscreen()
                // the fullscreen animation may still be running; look again once it has settled
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.updateFullscreen() }
            }
        }
        // A click in any other app closes an open shelf (global monitors only see clicks outside Top Shelf).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            if self?.model.isOpen == true { self?.model.close() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard e.keyCode == 53, self?.model.isOpen == true else { return e }   // Esc
            self?.model.close(); return nil
        }) { monitors.append(m) }

        observe({ _ = model.isOpen; _ = model.collapsedSize; _ = model.page }) { [weak self] in self?.layout() }
        place()
        updateFullscreen()
    }

    /// The built-in notch screen when there is one, else the main screen.
    private func place() {
        screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        if let s = screen { model.geometry = ShelfNotchGeometry(s) }
        layout()
    }

    private func layout() {
        guard let s = screen else { return }
        func frame(_ size: CGSize) -> NSRect {
            NSRect(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height, width: size.width, height: size.height)
        }
        if model.isOpen {
            wasOpen = true
            panel.setFrame(frame(model.openSize), display: true)
            if model.page == .clipboard && !model.openedByHover { panel.makeKey() }   // search takes typing right away
        } else {
            if wasOpen { hover.closed(pointerInNotch: notchRect.insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation)) }
            wasOpen = false
            if panel.isKeyWindow { panel.orderOut(nil) }   // hand typing back to the app John was in
            // shrink the window after the closing animation, unless it was reopened meanwhile
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, !self.model.isOpen else { return }
                self.panel.setFrame(frame(self.model.collapsedSize), display: true)
            }
        }
        if !isFullscreen { panel.orderFrontRegardless() }
    }

    private var notchRect: NSRect {
        guard let s = screen else { return .zero }
        let g = model.geometry
        return NSRect(x: s.frame.midX - g.notchWidth / 2, y: s.frame.maxY - g.notchHeight, width: g.notchWidth, height: g.notchHeight)
    }

    private func mouseMoved(_ p: NSPoint) { hover.moved(inNotch: notchRect.insetBy(dx: -1, dy: -1).contains(p)) }
    private func mouseLeft() { hover.left() }

    /// Finds the notch screen again and brings the shelf back to the front.
    func showAgain() {
        place()
        updateFullscreen()
    }

    // MARK: fullscreen

    private var isFullscreen = false

    /// Hides the shelf while an app covers the whole notch screen.
    private func updateFullscreen() {
        guard let s = screen else { return }
        isFullscreen = Self.coversScreen(s.frame.size)
        if isFullscreen { model.close(); panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    /// True when a normal app window on screen is exactly the screen's size (window bounds need no Screen Recording permission).
    static func coversScreen(_ size: CGSize) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let d = w[kCGWindowBounds as String], let b = CGRect(dictionaryRepresentation: d as! CFDictionary) else { return false }
            return b.size == size
        }
    }
}

/// Hover opening and closing, apart from the window so the self-test can drive it.
final class HoverLogic {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}
    private let model: ShelfModel
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    /// False after a close made with the pointer on the notch, until it leaves, so that close does not reopen it at once.
    private var armed = true

    init(model: ShelfModel) { self.model = model }

    func moved(inNotch: Bool) {
        closeWork?.cancel(); closeWork = nil
        guard !model.isOpen, model.openMode != .click else { return }
        if !inNotch { armed = true; openWork?.cancel(); openWork = nil; return }
        guard armed, openWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.openWork = nil
            if let m = self?.model, !m.isOpen, m.openMode != .click { m.open(.tray, byHover: true) }
        }
        openWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + model.hoverDelay, execute: work)
    }

    func left() {
        armed = true
        openWork?.cancel(); openWork = nil
        // In Click mode every opening closes after the pointer leaves; otherwise a click or shortcut opening stays until dismissed.
        guard model.isOpen, model.openedByHover || model.openMode == .click else { return }
        let work = DispatchWorkItem { [weak self] in self?.model.close() }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + model.hoverCloseDelay, execute: work)
    }

    /// Only a close with the pointer on the notch disarms hover: after a close from leaving, the pointer is already away and the
    /// window hears no more moves until it comes back, so disarming then would ignore the next hover (the bug John saw).
    func closed(pointerInNotch: Bool) {
        armed = !pointerInNotch
        closeWork?.cancel(); closeWork = nil   // a pending close must not shut the next opening
    }
}

/// Runs `onChange` every time something read in `read` changes.
func observe(_ read: @escaping () -> Void, _ onChange: @escaping () -> Void) {
    withObservationTracking(read) {
        DispatchQueue.main.async { onChange(); observe(read, onChange) }
    }
}
