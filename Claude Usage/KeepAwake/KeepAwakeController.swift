import AppKit
import Combine
import CoreGraphics
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

enum KeepAwakeDuration: String, CaseIterable, Codable, Identifiable {
    case fifteenMinutes, thirtyMinutes, oneHour, twoHours, fourHours, eightHours, untilOff
    var id: String { rawValue }
    var seconds: TimeInterval? {
        switch self {
        case .fifteenMinutes: 900
        case .thirtyMinutes: 1800
        case .oneHour: 3600
        case .twoHours: 7200
        case .fourHours: 14400
        case .eightHours: 28800
        case .untilOff: nil
        }
    }
    var label: String {
        switch self {
        case .fifteenMinutes: "15 m"
        case .thirtyMinutes: "30 m"
        case .oneHour: "1 h"
        case .twoHours: "2 h"
        case .fourHours: "4 h"
        case .eightHours: "8 h"
        case .untilOff: "Until off"
        }
    }
}

enum KeepAwakeMarkColor: String, CaseIterable, Codable, Identifiable {
    case orange, green, teal, blue
    var id: String { rawValue }
    var nsColor: NSColor {
        switch self {
        case .orange: NSColor(srgbRed: 1, green: 0x9f / 255, blue: 0x0a / 255, alpha: 1)
        case .green: NSColor(srgbRed: 0x30 / 255, green: 0xd1 / 255, blue: 0x58 / 255, alpha: 1)
        case .teal: NSColor(srgbRed: 0x64 / 255, green: 0xd2 / 255, blue: 1, alpha: 1)
        case .blue: NSColor(srgbRed: 0x0a / 255, green: 0x84 / 255, blue: 1, alpha: 1)
        }
    }
}

struct KeepAwakeApp: Codable, Equatable, Identifiable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

struct KeepAwakePower: Equatable {
    let isOnBattery: Bool
    let level: Double?
}

struct KeepAwakeSettings: Equatable {
    var startOnLaunch = false
    var showTime = true
    var allowDisplaySleep = true
    var pointerMovement = false
    var markColor = KeepAwakeMarkColor.orange
    var batteryCutoff = false
    var batteryLevel = 10
    var displayTrigger = false
    var powerTrigger = false
    var appsTrigger = false
    var duration = KeepAwakeDuration.oneHour

    static func load(from defaults: UserDefaults) -> KeepAwakeSettings {
        var result = KeepAwakeSettings()
        result.startOnLaunch = defaults.bool(forKey: "keepAwake.startOnLaunch")
        result.showTime = defaults.object(forKey: "keepAwake.showTime") as? Bool ?? true
        result.allowDisplaySleep = defaults.object(forKey: "keepAwake.allowDisplaySleep") as? Bool ?? true
        result.pointerMovement = defaults.bool(forKey: "keepAwake.pointerMovement")
        result.markColor = KeepAwakeMarkColor(rawValue: defaults.string(forKey: "keepAwake.markColor") ?? "") ?? .orange
        result.batteryCutoff = defaults.bool(forKey: "keepAwake.batteryCutoff")
        result.batteryLevel = defaults.object(forKey: "keepAwake.batteryLevel") as? Int ?? 10
        result.displayTrigger = defaults.bool(forKey: "keepAwake.displayTrigger")
        result.powerTrigger = defaults.bool(forKey: "keepAwake.powerTrigger")
        result.appsTrigger = defaults.bool(forKey: "keepAwake.appsTrigger")
        result.duration = KeepAwakeDuration(rawValue: defaults.string(forKey: "keepAwake.duration") ?? "") ?? .oneHour
        return result
    }
}

protocol KeepAwakeAssertionHandling: AnyObject {
    var isAcquired: Bool { get }
    func acquire(allowDisplaySleep: Bool)
    func release()
}

final class IOPMKeepAwakeAssertion: KeepAwakeAssertionHandling {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isAcquired = false

    func acquire(allowDisplaySleep: Bool) {
        release()
        let type = allowDisplaySleep ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Usage Shelf: Keep awake" as CFString, &assertionID)
        isAcquired = result == kIOReturnSuccess
        if result != kIOReturnSuccess { LoggingService.shared.logWarning("Keep awake: could not create sleep assertion (\(result))") }
    }

    func release() {
        if isAcquired { IOPMAssertionRelease(assertionID) }
        isAcquired = false
        assertionID = 0
    }

    deinit { release() }
}

protocol KeepAwakePointerHandling: AnyObject {
    var isTrusted: Bool { get }
    func requestTrust()
    func moveSlightly()
}

final class KeepAwakePointer: KeepAwakePointerHandling {
    var isTrusted: Bool { AXIsProcessTrusted() }
    func requestTrust() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
    func moveSlightly() {
        guard isTrusted, let location = CGEvent(source: nil)?.location else { return }
        let point = CGPoint(x: location.x + 0.1, y: location.y)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
}

protocol KeepAwakeEnvironmentHandling: AnyObject {
    var hasExternalDisplay: Bool { get }
    var isOnPower: Bool { get }
    var runningApplicationBundleIDs: Set<String> { get }
    var currentPower: KeepAwakePower { get }
}

final class KeepAwakeSystemEnvironment: KeepAwakeEnvironmentHandling {
    var hasExternalDisplay: Bool { NSScreen.screens.count > 1 }
    var currentPower: KeepAwakePower {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [[String: Any]] else {
            return KeepAwakePower(isOnBattery: false, level: nil)
        }
        for source in list where (source[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType {
            let current = source[kIOPSCurrentCapacityKey] as? Double
            let maximum = source[kIOPSMaxCapacityKey] as? Double
            let level = current.flatMap { value in maximum.map { max in max > 0 ? value / max : nil } } ?? nil
            let external = source[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return KeepAwakePower(isOnBattery: !external, level: level)
        }
        return KeepAwakePower(isOnBattery: false, level: nil)
    }
    var isOnPower: Bool { !currentPower.isOnBattery }
    var runningApplicationBundleIDs: Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}

@MainActor
final class KeepAwakeController: ObservableObject {
    static let shared = KeepAwakeController(defaults: .standard)

    @Published private(set) var settings: KeepAwakeSettings
    @Published private(set) var isActive = false
    @Published private(set) var isPaused = false
    @Published private(set) var displayRemaining: TimeInterval?
    @Published private(set) var chosenApps: [KeepAwakeApp]

    let assertion: KeepAwakeAssertionHandling
    let pointer: KeepAwakePointerHandling
    let environment: KeepAwakeEnvironmentHandling
    private let defaults: UserDefaults
    private var startedAt: TimeInterval?
    private var pausedRemaining: TimeInterval?
    private var automatic = false
    private var lastAutomaticCondition = false
    private var currentTime: TimeInterval = 0
    private var timer: Timer?
    private var pointerTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    var selectedDuration: KeepAwakeDuration { settings.duration }
    var currentTimeForDisplay: TimeInterval { currentTime }
    var pointerPermissionGranted: Bool { pointer.isTrusted }

    init(defaults: UserDefaults, assertion: KeepAwakeAssertionHandling = IOPMKeepAwakeAssertion(), pointer: KeepAwakePointerHandling = KeepAwakePointer(), environment: KeepAwakeEnvironmentHandling = KeepAwakeSystemEnvironment()) {
        self.defaults = defaults
        self.assertion = assertion
        self.pointer = pointer
        self.environment = environment
        self.settings = KeepAwakeSettings.load(from: defaults)
        self.chosenApps = (try? JSONDecoder().decode([KeepAwakeApp].self, from: defaults.data(forKey: "keepAwake.chosenApps") ?? Data())) ?? []
        if !pointer.isTrusted { self.settings.pointerMovement = false }
        updatePower(environment.currentPower, now: Date().timeIntervalSinceReferenceDate, stopOnly: true)
    }

    func startListening() {
        guard timer == nil else { return }
        currentTime = Date().timeIntervalSinceReferenceDate
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(now: Date().timeIntervalSinceReferenceDate) }
        }
        timer?.tolerance = 0.2
        evaluateAutomaticTriggers(now: currentTime)
        startOnAppLaunch(now: currentTime)
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pointerTick() }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.evaluateAutomaticTriggers(now: Date().timeIntervalSinceReferenceDate) }
        })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.evaluateAutomaticTriggers(now: Date().timeIntervalSinceReferenceDate) }
            })
        }
        for (rawName, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name(rawName), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setLocked(locked, now: Date().timeIntervalSinceReferenceDate) }
            })
        }
        lastAutomaticCondition = automaticCondition()
    }

    func startOnAppLaunch(now: TimeInterval) {
        guard settings.startOnLaunch else { return }
        start(duration: settings.duration, now: now)
    }

    func start(duration: KeepAwakeDuration, now: TimeInterval, automatic: Bool = false) {
        tick(now: now)
        settings.duration = duration
        save("duration", duration.rawValue)
        self.automatic = automatic
        currentTime = now
        startedAt = now
        pausedRemaining = nil
        lastAutomaticCondition = automaticCondition()
        isActive = true
        isPaused = false
        currentTime = now
        displayRemaining = duration.seconds
        acquireAssertion()
    }

    func toggle(now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        if isActive { stop() } else { start(duration: settings.duration, now: now) }
    }

    func stop() {
        isActive = false
        isPaused = false
        lastAutomaticCondition = automaticCondition()
        automatic = false
        startedAt = nil
        pausedRemaining = nil
        displayRemaining = nil
        assertion.release()
    }

    func tick(now: TimeInterval) {
        guard now >= currentTime else { return }
        currentTime = now
        updatePower(environment.currentPower, now: now, stopOnly: true)
        guard isActive else { return }
        if isPaused { displayRemaining = pausedRemaining; return }
        if let end = endDate(at: now), now >= end {
            stop()
            return
        }
        displayRemaining = remaining(at: now)
    }

    func remaining(at now: TimeInterval) -> TimeInterval? {
        guard isActive, let seconds = settings.duration.seconds else { return nil }
        if isPaused { return pausedRemaining }
        guard let end = endDate(at: now) else { return nil }
        return max(0, end - now)
    }

    private func endDate(at now: TimeInterval) -> TimeInterval? {
        guard let startedAt, let seconds = settings.duration.seconds else { return nil }
        return startedAt + seconds
    }

    func setLocked(_ locked: Bool, now: TimeInterval) {
        guard isActive, locked != isPaused else { return }
        tick(now: now)
        guard isActive else { return }
        if locked {
            pausedRemaining = remainingBeforePause(now: now)
            isPaused = true
            displayRemaining = pausedRemaining
            assertion.release()
        } else {
            isPaused = false
            if let pausedRemaining, let seconds = settings.duration.seconds {
                startedAt = now - (seconds - pausedRemaining)
            }
            self.pausedRemaining = nil
            acquireAssertion()
            tick(now: now)
        }
    }

    private func remainingBeforePause(now: TimeInterval) -> TimeInterval? {
        guard let seconds = settings.duration.seconds else { return nil }
        if let end = endDate(at: now) { return max(0, end - now) }
        return seconds
    }

    func updatePower(_ power: KeepAwakePower, now: TimeInterval, stopOnly: Bool = false) {
        if settings.batteryCutoff, power.isOnBattery, let level = power.level,
           level * 100 <= Double(settings.batteryLevel) {
            if isActive { stop() }
            lastAutomaticCondition = false
        }
        if !stopOnly { evaluateAutomaticTriggers(now: now) }
    }

    func update<Value>(_ keyPath: WritableKeyPath<KeepAwakeSettings, Value>, value: Value) {
        if keyPath == \KeepAwakeSettings.pointerMovement, let enabled = value as? Bool, enabled, !pointer.isTrusted {
            settings.pointerMovement = false
            defaults.set(false, forKey: "keepAwake.pointerMovement")
            return
        }
        settings[keyPath: keyPath] = value
        switch keyPath {
        case \KeepAwakeSettings.startOnLaunch: save("startOnLaunch", value as! Bool)
        case \KeepAwakeSettings.showTime: save("showTime", value as! Bool)
        case \KeepAwakeSettings.allowDisplaySleep: save("allowDisplaySleep", value as! Bool)
        case \KeepAwakeSettings.pointerMovement: save("pointerMovement", value as! Bool)
        case \KeepAwakeSettings.markColor: save("markColor", (value as! KeepAwakeMarkColor).rawValue)
        case \KeepAwakeSettings.batteryCutoff: save("batteryCutoff", value as! Bool)
        case \KeepAwakeSettings.batteryLevel: save("batteryLevel", value as! Int)
        case \KeepAwakeSettings.displayTrigger: save("displayTrigger", value as! Bool)
        case \KeepAwakeSettings.powerTrigger: save("powerTrigger", value as! Bool)
        case \KeepAwakeSettings.appsTrigger: save("appsTrigger", value as! Bool)
        case \KeepAwakeSettings.duration: save("duration", (value as! KeepAwakeDuration).rawValue)
        default: break
        }
        if keyPath == \KeepAwakeSettings.allowDisplaySleep, isActive, !isPaused { acquireAssertion() }
        if keyPath == \KeepAwakeSettings.displayTrigger || keyPath == \KeepAwakeSettings.powerTrigger || keyPath == \KeepAwakeSettings.appsTrigger {
            lastAutomaticCondition = false
            evaluateAutomaticTriggers(now: currentTime)
        }
    }

    func openAccessibilitySettings() { pointer.requestTrust() }

    func setChosenApps(_ apps: [KeepAwakeApp]) {
        chosenApps = apps
        defaults.set(try? JSONEncoder().encode(apps), forKey: "keepAwake.chosenApps")
        lastAutomaticCondition = false
        evaluateAutomaticTriggers(now: currentTime)
    }

    func evaluateAutomaticTriggers(now: TimeInterval) {
        currentTime = max(currentTime, now)
        let condition = automaticCondition()
        if condition && !lastAutomaticCondition && !isActive {
            start(duration: settings.duration, now: now, automatic: true)
        } else if !condition && lastAutomaticCondition && isActive && automatic {
            stop()
        }
        lastAutomaticCondition = condition
    }

    private func automaticCondition() -> Bool {
        let power = environment.currentPower
        guard !(settings.batteryCutoff && power.isOnBattery && (power.level.map { $0 * 100 <= Double(settings.batteryLevel) } ?? false)) else { return false }
        return (settings.displayTrigger && environment.hasExternalDisplay) ||
        (settings.powerTrigger && environment.isOnPower) ||
        (settings.appsTrigger && !Set(chosenApps.map(\.bundleID)).isDisjoint(with: environment.runningApplicationBundleIDs))
    }

    func pointerTick() {
        guard isActive, !isPaused, settings.pointerMovement, pointer.isTrusted else { return }
        pointer.moveSlightly()
    }

    private func acquireAssertion() {
        guard isActive, !isPaused else { return }
        assertion.acquire(allowDisplaySleep: settings.allowDisplaySleep)
    }

    private func save(_ key: String, _ value: Any) { defaults.set(value, forKey: "keepAwake.\(key)") }

    func menuBarTime(at now: TimeInterval) -> String {
        guard let remaining = remaining(at: now) else { return "On" }
        let total = max(0, Int(ceil(remaining)))
        return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
    }

    func popupTime(at now: TimeInterval) -> String {
        guard let remaining = remaining(at: now) else { return "Until turned off" }
        let total = max(0, Int(ceil(remaining / 60)))
        let hours = total / 60
        let minutes = total % 60
        if hours > 0 { return "\(hours) hr \(minutes) min left" }
        return "\(minutes) min left"
    }

    func contextMenuTitles(isOn: Bool) -> [String] { ["Keep awake", "Refresh", "Settings", "Quit"] }

    func menuBarAccessoryImage(isDarkMode: Bool) -> NSImage {
        let showTime = settings.showTime
        let text = isPaused ? "Paused" : (showTime ? menuBarTime(at: currentTime) : "")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: isDarkMode ? NSColor.white : NSColor.black
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let size = NSSize(width: 18 + (!text.isEmpty ? textSize.width + 3 : 0), height: 18)
        return NSImage(size: size, flipped: false) { rect in
            let color = self.settings.markColor.nsColor
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 4, y: 5, width: 8, height: 8)).fill()
            color.withAlphaComponent(0.25).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: 2, y: 3, width: 12, height: 12))
            ring.lineWidth = 2
            ring.stroke()
            if !text.isEmpty { (text as NSString).draw(at: NSPoint(x: 18, y: (18 - textSize.height) / 2), withAttributes: attributes) }
            return true
        }
    }

    func cleanup() {
        stop()
        timer?.invalidate()
        timer = nil
        pointerTimer?.invalidate()
        pointerTimer = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
    }
}
