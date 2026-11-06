import XCTest
import SwiftUI
@testable import Claude_Usage

@MainActor
final class CleaningModeTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var permissions: CleaningPermissionsSpy!
    private var blocker: CleaningInputBlockerSpy!
    private var overlay: CleaningOverlaySpy!
    private var awake: CleaningAwakeSpy!
    private var otherInput: CleaningOtherInputSpy!
    private var controller: CleaningModeController!

    override func setUp() async throws {
        suite = "CleaningModeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        permissions = CleaningPermissionsSpy()
        blocker = CleaningInputBlockerSpy()
        overlay = CleaningOverlaySpy()
        awake = CleaningAwakeSpy()
        otherInput = CleaningOtherInputSpy()
        controller = makeController()
    }

    override func tearDown() async throws {
        controller.cleanup()
        defaults.removePersistentDomain(forName: suite)
        controller = nil
        defaults = nil
        permissions = nil
        blocker = nil
        overlay = nil
        awake = nil
        otherInput = nil
    }

    private func makeController() -> CleaningModeController {
        CleaningModeController(defaults: defaults, permissions: permissions, blocker: blocker, overlay: overlay, awake: awake, otherInput: otherInput)
    }

    private func readyStart(now: TimeInterval = 100) {
        controller.start(now: now)
        XCTAssertTrue(controller.isActive)
    }

    // 1 and 23
    func testSettingsSidebarOrderAndEnglishCopy() {
        XCTAssertEqual(SettingsSection.allCases.filter { !$0.isProfileSetting && !$0.isCredential && !$0.isBottomBarItem }.map(\.rawValue).suffix(2), ["keepAwake", "cleaningMode"])
        XCTAssertEqual(SettingsSection.cleaningMode.title, "Cleaning Mode")
        XCTAssertTrue(SettingsSection.cleaningMode.description.contains("Clean your keyboard"))
        XCTAssertEqual(CleaningModeCopy.safety, "Cleaning Mode always ends when the timer runs out. Your power button and Touch ID still work. This is not a privacy lock.")
        XCTAssertEqual(CleaningModeCopy.holdInstruction, "Hold any mouse or trackpad button for 3 seconds to finish.")
    }

    // 2
    func testNoActivityOrPermissionRequestBeforeExplicitStart() {
        controller.startListening()
        controller.refreshPermissions()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(blocker.startCount, 0)
        XCTAssertEqual(overlay.updateCount, 0)
        XCTAssertEqual(awake.acquireCount, 0)
        XCTAssertEqual(permissions.opened, [])
    }

    // 3 and 7
    func testMissingAccessibilityNeverStartsAndShortcutOpensExplanation() {
        permissions.accessibility = false
        XCTAssertEqual(controller.start(now: 100), .permissionMissing)
        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(controller.shouldOpenSettings)
        XCTAssertEqual(controller.permissionState, .accessibilityNeeded)
        XCTAssertFalse(controller.canStart)
        XCTAssertEqual(blocker.startCount, 0)
        controller.consumeSettingsRequest()
        XCTAssertFalse(controller.shouldOpenSettings)
    }

    // 4
    func testPermissionButtonsOnlyOpenNamedSystemPanes() {
        controller.openAccessibilitySettings()
        controller.openInputMonitoringSettings()
        XCTAssertEqual(permissions.opened, [.accessibility, .inputMonitoring])
        XCTAssertFalse(controller.isActive)
    }

    // 5 and 6
    func testReturningToSettingsUsesRealPermissionState() {
        permissions.accessibility = false
        controller.refreshPermissions()
        XCTAssertEqual(controller.permissionState, .accessibilityNeeded)
        permissions.accessibility = true
        controller.settingsBecameActive()
        XCTAssertEqual(controller.permissionState, .inputMonitoringNeeded)
        XCTAssertFalse(controller.canStart)
        permissions.inputMonitoring = true
        permissions.requiresRelaunch = true
        controller.settingsBecameActive()
        XCTAssertEqual(controller.permissionState, .relaunchNeeded)
        permissions.requiresRelaunch = false
        controller.settingsBecameActive()
        XCTAssertEqual(controller.permissionState, .ready)
        XCTAssertTrue(controller.canStart)
    }

    // 8
    func testShortcutHasNoDefaultAndUsesExistingClashBehavior() throws {
        let store = ShortcutStoreSpy()
        let registrar = ShortcutRegistrarSpy()
        let manager = ShortcutManager(store: store, registrar: registrar.register)
        XCTAssertNil(manager.shortcuts[.cleaningMode])
        let combo = KeyCombo(keyCode: 8, modifierFlags: [.command, .option])
        XCTAssertEqual(manager.setShortcut(combo, for: .cleaningMode), .success)
        XCTAssertEqual(ShortcutManager(store: store, registrar: registrar.register).shortcuts[.cleaningMode], combo)
        XCTAssertEqual(manager.setShortcut(combo, for: .keepAwake), .duplicate("Start Cleaning Mode"))
    }

    // 9, 10 and 11
    func testBlockerCoversKeyboardAndOptionalPointerWithoutReadingContents() {
        readyStart()
        XCTAssertEqual(blocker.lastConfiguration, CleaningInputConfiguration(blockPointer: true))
        controller.update(\.blockPointer, value: false)
        controller.stop(reason: .manual)
        readyStart(now: 200)
        XCTAssertEqual(blocker.lastConfiguration, CleaningInputConfiguration(blockPointer: false))
    }

    // 12 and 13
    func testEveryDurationIsBoundedPersistedAndExpiresOnRealTime() {
        XCTAssertEqual(CleaningDuration.allCases.map(\.seconds), [30, 60, 120, 300])
        XCTAssertEqual(CleaningDuration.oneMinute.seconds, 60)
        for duration in CleaningDuration.allCases {
            controller.update(\.duration, value: duration)
            readyStart(now: 50)
            XCTAssertEqual(controller.remaining(at: 50), duration.seconds)
            controller.tick(now: 50 + duration.seconds - 0.01)
            XCTAssertTrue(controller.isActive)
            controller.tick(now: 50 + duration.seconds)
            XCTAssertFalse(controller.isActive)
        }
        controller.update(\.duration, value: .fiveMinutes)
        let restored = makeController()
        XCTAssertEqual(restored.settings.duration, .fiveMinutes)
        restored.cleanup()
        XCTAssertNil(UserDefaults.standard.object(forKey: "cleaningMode.duration"))
    }

    // 14
    func testThreeSecondHoldEndsOnceEarlyReleaseAndClickDoNot() {
        readyStart()
        controller.pointerDown(at: 100)
        controller.tick(now: 102.99)
        XCTAssertTrue(controller.isActive)
        controller.pointerUp(at: 102.99)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.holdProgress(at: 102.99), 0)
        controller.pointerDown(at: 103)
        controller.pointerUp(at: 103.05)
        XCTAssertTrue(controller.isActive)
        controller.pointerDown(at: 104)
        controller.tick(now: 107)
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(overlay.hideCount, 1)
        XCTAssertEqual(blocker.stopCount, 1)
    }

    func testMovingDuringHoldDoesNotResetProgress() {
        readyStart()
        controller.pointerDown(at: 100)
        controller.pointerMoved(at: 101)
        controller.tick(now: 102)
        XCTAssertEqual(controller.holdProgress(at: 102), 2.0 / 3.0, accuracy: 0.001)
        controller.tick(now: 103)
        XCTAssertFalse(controller.isActive)
    }

    // 15
    func testTimerWinsWhileButtonIsStillHeldAndRestoresEverything() {
        readyStart()
        controller.pointerDown(at: 159.9)
        controller.tick(now: 160)
        XCTAssertFalse(controller.isActive)
        controller.tick(now: 163)
        controller.pointerUp(at: 163)
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(blocker.stopCount, 1)
        XCTAssertEqual(awake.releaseCount, 1)
        XCTAssertEqual(otherInput.resumeCount, 1)
    }

    // 17
    func testDisplayChangesKeepOriginalEndTimeAndRefreshEveryScreen() {
        readyStart()
        controller.screensChanged()
        XCTAssertEqual(overlay.screenRefreshCount, 1)
        XCTAssertEqual(controller.endTime, 160)
        controller.tick(now: 160)
        XCTAssertEqual(overlay.hideCount, 1)
    }

    // 18
    func testPermissionLossAndInputFailureEndImmediatelyAndClearOverlay() {
        readyStart()
        permissions.accessibility = false
        controller.refreshPermissions()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.endReason, .permissionLost)
        XCTAssertEqual(overlay.hideCount, 1)
        readyStart(now: 200)
        controller.inputMechanismFailed()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.endReason, .inputFailure)
        XCTAssertEqual(overlay.hideCount, 2)
    }

    func testTapCreationFailureProducesNoHalfWorkingSession() {
        blocker.startSucceeds = false
        XCTAssertEqual(controller.start(now: 100), .inputUnavailable)
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(overlay.updateCount, 0)
        XCTAssertEqual(blocker.stopCount, 1)
        XCTAssertEqual(awake.releaseCount, 1)
    }

    // 19
    func testAppTerminationAndLoginSessionEventsReleaseEverything() {
        for cleanupPath in [0, 1, 2] {
            readyStart()
            switch cleanupPath {
            case 0: controller.cleanup()
            case 1: controller.screenLocked()
            default: controller.sessionSwitched()
            }
            XCTAssertFalse(controller.isActive)
            XCTAssertGreaterThanOrEqual(blocker.stopCount, cleanupPath + 1)
            XCTAssertGreaterThanOrEqual(awake.releaseCount, cleanupPath + 1)
        }
        controller.startListening()
        XCTAssertFalse(controller.isActive, "A fresh app launch must never restore an active session")
    }

    // 20
    func testOtherShortcutsSuspendAndRestoreWithoutChangingSavedSettings() {
        otherInput.suspendSucceeds = false
        XCTAssertEqual(controller.start(now: 100), .inputUnavailable)
        XCTAssertEqual(overlay.updateCount, 0)
        otherInput.suspendSucceeds = true
        readyStart(now: 200)
        XCTAssertGreaterThanOrEqual(otherInput.suspendCount, 1)
        controller.stop(reason: .manual)
        XCTAssertEqual(otherInput.resumeCount, 1)
    }

    // 21
    func testAwakeIsSessionScopedAndDoesNotUseKeepAwakeSettings() {
        let keepAwakeSuite = "CleaningModeKeepAwake-\(UUID().uuidString)"
        let keepDefaults = UserDefaults(suiteName: keepAwakeSuite)!
        keepDefaults.set("fourHours", forKey: "keepAwake.duration")
        readyStart()
        XCTAssertEqual(awake.acquireCount, 1)
        controller.stop(reason: .manual)
        XCTAssertEqual(awake.releaseCount, 1)
        XCTAssertEqual(keepDefaults.string(forKey: "keepAwake.duration"), "fourHours")
        keepDefaults.removePersistentDomain(forName: keepAwakeSuite)
    }

    // 16 and 22
    func testBothAppearancesRenderInLightAndDarkWithoutRealOverlay() throws {
        let folder = URL(fileURLWithPath: "/tmp/usage-shelf-cleaning-mode-shots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        readyStart(now: 18)
        controller.tick(now: 36)
        permissions.accessibility = false
        for appearance in CleaningScreenAppearance.allCases {
            controller.stop(reason: .manual)
        controller.update(\.screenAppearance, value: appearance)
            for scheme in [ColorScheme.light, .dark] {
                permissions.accessibility = true
                permissions.inputMonitoring = true
                controller.refreshPermissions()
                let name = "\(appearance.rawValue)-\(scheme == .light ? "light" : "dark")"
                try CleaningModePreviewRenderer.renderSettings(controller: controller, scheme: scheme, to: folder.appendingPathComponent("settings-\(name).png"))
                try CleaningModePreviewRenderer.renderActive(controller: controller, scheme: scheme, to: folder.appendingPathComponent("active-\(name).png"))
            }
        }
        permissions.accessibility = false
        for scheme in [ColorScheme.light, .dark] {
            try CleaningModePreviewRenderer.renderSettings(controller: controller, scheme: scheme, to: folder.appendingPathComponent("permission-\(scheme == .light ? "light" : "dark").png"))
        }
        try CleaningModePreviewRenderer.renderShortcuts(scheme: .light, to: folder.appendingPathComponent("shortcuts.png"))
        try CleaningModePreviewRenderer.renderContextMenu(scheme: .light, to: folder.appendingPathComponent("menu.png"))
        XCTAssertEqual(blocker.startCount, 1)
    }
}

final class CleaningPermissionsSpy: CleaningPermissionHandling {
    var accessibility = true
    var inputMonitoring = true
    var requiresRelaunch = false
    var accessibilityGranted: Bool { accessibility }
    var inputMonitoringGranted: Bool { inputMonitoring }
    var needsInputMonitoring: Bool { !inputMonitoring }
    var needsRelaunch: Bool { requiresRelaunch }
    private(set) var opened: [CleaningPermissionPane] = []
    func open(_ pane: CleaningPermissionPane) { opened.append(pane) }
}

final class CleaningInputBlockerSpy: CleaningInputBlocking {
    var startSucceeds = true
    var isActive = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastConfiguration: CleaningInputConfiguration?
    var onPointerDown: (() -> Void)?
    var onPointerUp: (() -> Void)?
    var onPointerMoved: (() -> Void)?
    var onFailure: (() -> Void)?
    func start(configuration: CleaningInputConfiguration) -> Bool {
        startCount += 1
        lastConfiguration = configuration
        isActive = startSucceeds
        return startSucceeds
    }
    func stop() { stopCount += 1; isActive = false }
}

final class CleaningOverlaySpy: CleaningOverlayHandling {
    private(set) var updateCount = 0
    private(set) var hideCount = 0
    private(set) var screenRefreshCount = 0
    func show(appearance: CleaningScreenAppearance) { updateCount += 1 }
    func update(remaining: TimeInterval, holdProgress: Double) { updateCount += 1 }
    func screensChanged() { screenRefreshCount += 1 }
    func hide() { hideCount += 1 }
}

final class CleaningAwakeSpy: CleaningAwakeHandling {
    private(set) var acquireCount = 0
    private(set) var releaseCount = 0
    func acquire() { acquireCount += 1 }
    func release() { releaseCount += 1 }
}

final class CleaningOtherInputSpy: CleaningOtherInputHandling {
    var suspendSucceeds = true
    private(set) var suspendCount = 0
    private(set) var resumeCount = 0
    func suspend() -> Bool { suspendCount += 1; return suspendSucceeds }
    func resume() { resumeCount += 1 }
}
