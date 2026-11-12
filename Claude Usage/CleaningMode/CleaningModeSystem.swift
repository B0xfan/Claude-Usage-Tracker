import ApplicationServices
import AppKit
import CoreGraphics
import IOKit
import IOKit.pwr_mgt

final class CleaningPermissions: CleaningPermissionHandling {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}
    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    var inputMonitoringGranted: Bool {
        if #available(macOS 10.15, *) { return CGPreflightListenEventAccess() }
        return true
    }
    var needsInputMonitoring: Bool {
        // CGEvent taps need listen access on macOS Catalina and newer. Only show
        // the second state when this read-only preflight actually says it is absent.
        accessibilityGranted && !inputMonitoringGranted
    }
    var needsRelaunch: Bool { false }

    func open(_ pane: CleaningPermissionPane) {
        // Deliberately no AXIsProcessTrustedWithOptions and no CGRequest* call:
        // only John can grant permission. These URLs only reveal the named pane.
        let fragment = pane == .accessibility ? "Privacy_Accessibility" : "Privacy_ListenEvent"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(fragment)") else { return }
        NSWorkspace.shared.open(url)
    }
}

final class CleaningInputBlocker: CleaningInputBlocking {
    var onPointerDown: (() -> Void)?
    var onPointerUp: (() -> Void)?
    var onPointerMoved: (() -> Void)?
    var onFailure: (() -> Void)?
    var onOffShortcut: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var configuration = CleaningInputConfiguration(blockPointer: true)
    /// Every key press, release and modifier change is swallowed while cleaning.
    static let keyboardMask: CGEventMask =
        (1 << CGEventType.keyDown.rawValue) |
        (1 << CGEventType.keyUp.rawValue) |
        (1 << CGEventType.flagsChanged.rawValue)

    func start(configuration: CleaningInputConfiguration) -> Bool {
        stop()
        self.configuration = configuration
        let keyboard = Self.keyboardMask
        let pointerTypes: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown,
            .otherMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDragged, .scrollWheel
        ]
        let allowedPointerTypes: [CGEventType] = [.mouseMoved]
        let pointer = pointerTypes.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let allowedPointer = allowedPointerTypes.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let mask = keyboard | (configuration.blockPointer ? pointer : pointerTypes.filter { !allowedPointerTypes.contains($0) }.reduce(allowedPointer) { $0 | (1 << $1.rawValue) })
        let userData = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userData in
                guard let userData else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<CleaningInputBlocker>.fromOpaque(userData).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    owner.onFailure?()
                    return nil
                }
                // Input contents are never read, logged, stored, or displayed.
                switch type {
                case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                    owner.onPointerDown?()
                case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                    owner.onPointerUp?()
                case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                    owner.onPointerMoved?()
                case .keyDown:
                    // Compared in memory against the one recorded off combo, then forgotten.
                    // The press is still swallowed below, so it never reaches another app.
                    let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
                    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                    if CleaningKeyGate.isOffPress(type: type, keyCode: keyCode, flags: event.flags, isRepeat: isRepeat, shortcut: owner.configuration.offShortcut) {
                        owner.onOffShortcut?()
                    }
                default: break
                }
                // Always suppress matching events. The local callbacks above are
                // the only escape gesture path; the independent Timer still runs.
                return nil
            },
            userInfo: userData
        ) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
    }

    deinit { stop() }
}

final class CleaningAwakeAssertion: CleaningAwakeHandling {
    private var assertionID: IOPMAssertionID = 0
    private var acquired = false

    func acquire() {
        release()
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Usage Shelf: Cleaning Mode" as CFString,
            &assertionID
        )
        acquired = result == kIOReturnSuccess
        if result != kIOReturnSuccess {
            LoggingService.shared.logWarning("Cleaning Mode: could not keep the display awake (\(result))")
        }
    }

    func release() {
        if acquired { IOPMAssertionRelease(assertionID) }
        acquired = false
        assertionID = 0
    }

    deinit { release() }
}
