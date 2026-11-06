import AppKit
import Combine
import Foundation

/// Every choice is finite. Invalid saved values fall back to the one-minute default.
enum CleaningDuration: String, CaseIterable, Codable, Identifiable {
    case thirtySeconds, oneMinute, twoMinutes, fiveMinutes
    var id: String { rawValue }
    var seconds: TimeInterval {
        switch self {
        case .thirtySeconds: 30
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        }
    }
    var label: String {
        switch self {
        case .thirtySeconds: "30 seconds"
        case .oneMinute: "1 minute"
        case .twoMinutes: "2 minutes"
        case .fiveMinutes: "5 minutes"
        }
    }
}

enum CleaningScreenAppearance: String, CaseIterable, Codable, Identifiable {
    case dimmed, visible
    var id: String { rawValue }
    var label: String { self == .dimmed ? "Dimmed overlay" : "Keep screen visible" }
}

struct CleaningModeSettings: Equatable {
    var duration = CleaningDuration.oneMinute
    var screenAppearance = CleaningScreenAppearance.dimmed
    var blockPointer = true

    static func load(from defaults: UserDefaults) -> CleaningModeSettings {
        CleaningModeSettings(
            duration: CleaningDuration(rawValue: defaults.string(forKey: "cleaningMode.duration") ?? "") ?? .oneMinute,
            screenAppearance: CleaningScreenAppearance(rawValue: defaults.string(forKey: "cleaningMode.screenAppearance") ?? "") ?? .dimmed,
            blockPointer: defaults.object(forKey: "cleaningMode.blockPointer") as? Bool ?? true
        )
    }
}

enum CleaningPermissionState: Equatable {
    case accessibilityNeeded, inputMonitoringNeeded, relaunchNeeded, ready
}

enum CleaningPermissionPane { case accessibility, inputMonitoring }

/// Read-only checks. Opening a pane never requests or grants access.
protocol CleaningPermissionHandling: AnyObject {
    var accessibilityGranted: Bool { get }
    var inputMonitoringGranted: Bool { get }
    var needsInputMonitoring: Bool { get }
    var needsRelaunch: Bool { get }
    func open(_ pane: CleaningPermissionPane)
}

struct CleaningInputConfiguration: Equatable {
    var blockPointer: Bool
}

/// Only the production implementation creates a CGEventTap. It reports gesture
/// timing, never event characters, key codes, or other input contents.
protocol CleaningInputBlocking: AnyObject {
    var onPointerDown: (() -> Void)? { get set }
    var onPointerUp: (() -> Void)? { get set }
    var onPointerMoved: (() -> Void)? { get set }
    var onFailure: (() -> Void)? { get set }
    func start(configuration: CleaningInputConfiguration) -> Bool
    func stop()
}

protocol CleaningOverlayHandling: AnyObject {
    func show(appearance: CleaningScreenAppearance)
    func update(remaining: TimeInterval, holdProgress: Double)
    func screensChanged()
    func hide()
}

protocol CleaningAwakeHandling: AnyObject {
    func acquire()
    func release()
}

protocol CleaningOtherInputHandling: AnyObject {
    func suspend() -> Bool
    func resume()
}

enum CleaningStartResult: Equatable { case started, permissionMissing, inputUnavailable }
enum CleaningEndReason: Equatable { case timer, hold, manual, permissionLost, inputFailure, system }

enum CleaningModeCopy {
    static let holdInstruction = "Hold any mouse or trackpad button for 3 seconds to finish."
    static let safety = "Cleaning Mode always ends when the timer runs out. Your power button and Touch ID still work. This is not a privacy lock."
}

@MainActor
final class CleaningModeController: ObservableObject {
    static let shared = CleaningModeController(defaults: .standard)
    static let holdSeconds: TimeInterval = 3

    @Published private(set) var settings: CleaningModeSettings
    @Published private(set) var isActive = false
    @Published private(set) var endTime: TimeInterval?
    @Published private(set) var displayRemaining: TimeInterval?
    @Published private(set) var displayHoldProgress = 0.0
    @Published private(set) var permissionState: CleaningPermissionState = .accessibilityNeeded
    @Published private(set) var endReason: CleaningEndReason?
    @Published private(set) var shouldOpenSettings = false

    let permissions: CleaningPermissionHandling
    let blocker: CleaningInputBlocking
    let overlay: CleaningOverlayHandling
    let awake: CleaningAwakeHandling
    let otherInput: CleaningOtherInputHandling
    private let defaults: UserDefaults
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var holdStartedAt: TimeInterval?
    private var holdsPointer = false
    private var currentTime = 0.0
    private var shouldRestoreOtherInput = false
    private var hasStartedListening = false
    private var sessionGeneration = 0

    var canStart: Bool { permissionState == .ready && !isActive }

    init(defaults: UserDefaults,
         permissions: CleaningPermissionHandling = CleaningPermissions(),
         blocker: CleaningInputBlocking = CleaningInputBlocker(),
         overlay: CleaningOverlayHandling = CleaningOverlayController.shared,
         awake: CleaningAwakeHandling = CleaningAwakeAssertion(),
         otherInput: CleaningOtherInputHandling = CleaningOtherInputCoordinator()) {
        self.defaults = defaults
        self.permissions = permissions
        self.blocker = blocker
        self.overlay = overlay
        self.awake = awake
        self.otherInput = otherInput
        self.settings = CleaningModeSettings.load(from: defaults)
        self.blocker.onPointerDown = { [weak self] in
            let now = Date().timeIntervalSinceReferenceDate
            Task { @MainActor in self?.pointerDown(at: now) }
        }
        self.blocker.onPointerUp = { [weak self] in
            let now = Date().timeIntervalSinceReferenceDate
            Task { @MainActor in self?.pointerUp(at: now) }
        }
        self.blocker.onPointerMoved = { [weak self] in
            let now = Date().timeIntervalSinceReferenceDate
            Task { @MainActor in self?.pointerMoved(at: now) }
        }
        self.blocker.onFailure = { [weak self] in
            Task { @MainActor in self?.inputMechanismFailed() }
        }
        refreshPermissions()
    }

    /// Monitoring starts only listeners and a shared timer. It never starts a
    /// session, an event tap, a prompt, or an overlay.
    func startListening() {
        guard !hasStartedListening else { return }
        hasStartedListening = true
        currentTime = Date().timeIntervalSinceReferenceDate
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.settingsBecameActive() }
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        })
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cleanup() }
        })
        for name in ["com.apple.screenIsLocked", "com.apple.sessionDidResignActive"] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.screenLocked() }
            })
        }
        // A repeat interval faster than the three-second gesture and all four
        // finite durations makes the watchdog independent of input callbacks.
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(now: Date().timeIntervalSinceReferenceDate) }
        }
        timer?.tolerance = 0.01
    }

    /// A one-shot deadline remains independent of progress UI and gesture
    /// processing; it fires even while a button is held down.
    private func scheduleDeadline(at end: TimeInterval) {
        let delay = max(0, end - Date().timeIntervalSinceReferenceDate)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.tick(now: Date().timeIntervalSinceReferenceDate)
        }
    }

    @discardableResult
    func start(now: TimeInterval) -> CleaningStartResult {
        guard !isActive else { stop(reason: .manual) }
        refreshPermissions()
        guard permissionState == .ready else {
            shouldOpenSettings = true
            return .permissionMissing
        }
        let duration = settings.duration.seconds
        guard duration > 0 && duration <= CleaningDuration.fiveMinutes.seconds else { return .inputUnavailable }
        // Capture preparingInput from an optional start captured inside a Task
        // when the caller needs to let the initiating mouse release finish.
        if now < 0 {
            Task { @MainActor in self?.start(now: Date().timeIntervalSinceReferenceDate) }
            return .started
        }
        shouldRestoreOtherInput = otherInput.suspend()
        guard blocker.start(configuration: CleaningInputConfiguration(blockPointer: settings.blockPointer && settings.screenAppearance == .dimmed)) else {
            end(reason: .inputFailure)
            return .inputUnavailable
        }
        currentTime = now
        endTime = now + duration
        scheduleDeadline(at: now + duration)
        displayRemaining = duration
        displayHoldProgress = 0
        holdStartedAt = nil
        holdsPointer = false
        endReason = nil
        isActive = true
        sessionGeneration += 1
        let generation = sessionGeneration
        shouldOpenSettings = false
        // Defer creation so the release of the click that chose the menu item is
        // delivered normally rather than treated as a cleaning release.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive, self.sessionGeneration == generation else { return }
            self.awake.acquire()
            self.overlay.show(appearance: self.settings.screenAppearance)
            self.overlay.update(remaining: self.remaining(at: Date().timeIntervalSinceReferenceDate), holdProgress: 0)
        }
        return .started
    }

    func tick(now: TimeInterval) {
        guard isActive, let endTime else { return }
        currentTime = now
        if currentTime >= endTime {
            stop(reason: .timer)
            return
        }
        if !permissions.accessibilityGranted || (permissions.needsInputMonitoring && !permissions.inputMonitoringGranted) {
            stop(reason: .permissionLost)
            return
        }
        if holdsPointer, let holdStartedAt, currentTime - holdStartedAt >= Self.holdSeconds {
            stop(reason: .hold)
            return
        }
        displayRemaining = max(0, endTime - currentTime)
        displayHoldProgress = holdProgress(at: currentTime)
        overlay.update(remaining: displayRemaining ?? 0, holdProgress: displayHoldProgress)
        // A pointer press timer is not needed for a normal click; it runs only
        // while a button is held, so missing a single up callback cannot lock input.
        if holdsPointer, let holdStartedAt {
            let delay = max(0, Self.holdSeconds - (currentTime - holdStartedAt))
            let generation = sessionGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isActive, self.sessionGeneration == generation else { return }
                self.stop(reason: .hold)
            }
        }
    }

    func remaining(at now: TimeInterval) -> TimeInterval {
        guard isActive, let endTime else { return 0 }
        return max(0, endTime - now)
    }

    func holdProgress(at now: TimeInterval) -> Double {
        guard isActive, holdsPointer, let holdStartedAt else { return 0 }
        return min(1, max(0, now - holdStartedAt) / Self.holdSeconds)
    }

    func countdownText(at now: TimeInterval) -> String {
        let total = Int(ceil(remaining(at: now)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    func pointerDown(at now: TimeInterval) {
        guard isActive else { return }
        tick(now: now)
        guard isActive, !holdsPointer else { return }
        holdsPointer = true
        holdStartedAt = now
    }

    func pointerUp(at now: TimeInterval) {
        tick(now: now)
        holdsPointer = false
        holdStartedAt = nil
        displayHoldProgress = 0
    }

    func pointerMoved(at now: TimeInterval) {
        // Movement deliberately does not interrupt the continuous hold.
        tick(now: now)
    }

    func stop(reason: CleaningEndReason) { end(reason: reason) }

    private func end(reason: CleaningEndReason) {
        // Capture belongs to this process and is released first on every path.
        blocker.stop()
        awake.release()
        if shouldRestoreOtherInput {
            otherInput.resume()
        }
        shouldRestoreOtherInput = false
        overlay.hide()
        holdsPointer = false
        holdStartedAt = nil
        isActive = false
        sessionGeneration += 1
        endTime = nil
        displayRemaining = nil
        displayHoldProgress = 0
        endReason = reason
    }

    func refreshPermissions() {
        if !permissions.accessibilityGranted {
            permissionState = .accessibilityNeeded
        } else if permissions.needsRelaunch {
            permissionState = .relaunchNeeded
        } else if permissions.needsInputMonitoring && !permissions.inputMonitoringGranted {
            permissionState = .inputMonitoringNeeded
        } else {
            permissionState = .ready
        }
        if isActive && permissionState != .ready { stop(reason: .permissionLost) }
    }

    func settingsBecameActive() { refreshPermissions() }
    func screensChanged() {
        guard isActive else { return }
        refreshPermissions()
        guard isActive else { return }
        overlay.screensChanged()
    }
    func inputMechanismFailed() {
        if isActive { stop(reason: .inputFailure) }
        else { sessionUnavailable() }
    }
    func screenLocked() { if isActive { stop(reason: .system) } }
    func sessionSwitched() { screenLocked() }
    private func sessionUnavailable() {
        guard !shouldRestoreOtherInput else { return }
        blocker.stop()
        overlay.hide()
        ShortcutManager.shared.resumeAfterCleaningInterruption()
        TopShelfHost.shared.resumeAfterCleaningInterruption()
    }
    func openAccessibilitySettings() { permissions.open(.accessibility) }
    func openInputMonitoringSettings() { permissions.open(.inputMonitoring) }

    func update<Value>(_ keyPath: WritableKeyPath<CleaningModeSettings, Value>, value: Value) {
        guard !isActive else { return }
        settings[keyPath: keyPath] = value
        switch keyPath {
        case \CleaningModeSettings.duration: defaults.set((value as! CleaningDuration).rawValue, forKey: "cleaningMode.duration")
        case \CleaningModeSettings.screenAppearance: defaults.set((value as! CleaningScreenAppearance).rawValue, forKey: "cleaningMode.screenAppearance")
        case \CleaningModeSettings.blockPointer: defaults.set(value as! Bool, forKey: "cleaningMode.blockPointer")
        default: break
        }
    }

    func cleanup() {
        end(reason: .system)
        timer?.invalidate()
        timer = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
        hasStartedListening = false
        // Release callback captures so no gesture can arrive after teardown.
        blocker.onPointerDown = nil
        blocker.onPointerUp = nil
        blocker.onPointerMoved = nil
        blocker.onFailure = nil
    }
}
