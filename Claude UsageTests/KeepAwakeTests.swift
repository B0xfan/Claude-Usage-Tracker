import XCTest
import AppKit
import SwiftUI
@testable import Claude_Usage

@MainActor
final class KeepAwakeTests: XCTestCase {
    nonisolated(unsafe) private var suite = ""
    nonisolated(unsafe) private var controller: KeepAwakeController!

    nonisolated override func setUp() {
        super.setUp()
        let name = "KeepAwakeTests-\(UUID().uuidString)"
        suite = name
        MainActor.assumeIsolated {
            let defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
            controller = KeepAwakeController(
                defaults: defaults,
                assertion: KeepAwakeAssertionSpy(),
                pointer: KeepAwakePointerSpy(),
                environment: KeepAwakeEnvironmentSpy()
            )
        }
    }

    nonisolated override func tearDown() {
        let name = suite
        MainActor.assumeIsolated {
            controller.stop()
            controller = nil
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        super.tearDown()
    }

    func testDefaultsAndEveryDuration() {
        XCTAssertFalse(controller.settings.pointerMovement)
        XCTAssertEqual(controller.settings.batteryLevel, 10)
        XCTAssertTrue(controller.settings.showTime)
        XCTAssertTrue(controller.settings.allowDisplaySleep)
        XCTAssertFalse(controller.settings.batteryCutoff)
        XCTAssertFalse(controller.settings.startOnLaunch)
        XCTAssertFalse(controller.isActive)
        let expected: [(KeepAwakeDuration, TimeInterval?)] = [
            (.fifteenMinutes, 900), (.thirtyMinutes, 1800), (.oneHour, 3600),
            (.twoHours, 7200), (.fourHours, 14400), (.eightHours, 28800), (.untilOff, nil)
        ]
        XCTAssertEqual(Set(KeepAwakeDuration.allCases), Set(expected.map(\.0)))
        for (duration, seconds) in expected {
            XCTAssertEqual(duration.seconds, seconds)
            controller.start(duration: duration, now: 100)
            XCTAssertTrue(controller.isActive)
            XCTAssertEqual(controller.remaining(at: 100), seconds)
            controller.stop()
        }
    }

    func testCountdownExpiryAndSleepRelease() {
        let assertion = controller.assertion as! KeepAwakeAssertionSpy
        controller.start(duration: .fifteenMinutes, now: 100)
        XCTAssertEqual(controller.remaining(at: 640), 360)
        XCTAssertEqual(assertion.acquireCount, 1)
        controller.tick(now: 1000)
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.remaining(at: 1000))
        XCTAssertEqual(assertion.releaseCount, 1)
        controller.start(duration: .oneHour, now: 1000)
        controller.stop()
        XCTAssertEqual(assertion.releaseCount, 2)
    }

    func testLockPausesAndUnlockResumesRemainingTime() {
        let assertion = controller.assertion as! KeepAwakeAssertionSpy
        controller.start(duration: .twoHours, now: 100)
        controller.tick(now: 400.25)
        controller.setLocked(true, now: 400.25)
        XCTAssertEqual(controller.remaining(at: 1000) ?? -1, 6899.75, accuracy: 0.001)
        XCTAssertTrue(controller.isPaused)
        XCTAssertEqual(assertion.releaseCount, 1)
        controller.tick(now: 5000)
        XCTAssertTrue(controller.isActive)
        controller.setLocked(false, now: 5000)
        XCTAssertEqual(controller.remaining(at: 5000) ?? -1, 6899.75, accuracy: 0.001)
        controller.tick(now: 5000 + 6899.75)
        XCTAssertFalse(controller.isActive)
    }

    func testIndefiniteAlsoPausesWithoutCountingLockedTime() {
        controller.start(duration: .untilOff, now: 10)
        controller.setLocked(true, now: 20)
        controller.setLocked(false, now: 1000)
        XCTAssertTrue(controller.isActive)
        XCTAssertNil(controller.remaining(at: 1000))
    }

    func testBatteryCutoffOnlyWhileOnBattery() {
        controller.update(\.batteryCutoff, value: true)
        controller.update(\.batteryLevel, value: 10)
        controller.start(duration: .oneHour, now: 0)
        controller.updatePower(KeepAwakePower(isOnBattery: true, level: 0.11), now: 0)
        XCTAssertTrue(controller.isActive)
        controller.updatePower(KeepAwakePower(isOnBattery: true, level: 0.10), now: 1)
        XCTAssertFalse(controller.isActive)
        controller.start(duration: .oneHour, now: 2)
        controller.updatePower(KeepAwakePower(isOnBattery: false, level: 0.05), now: 2)
        XCTAssertTrue(controller.isActive)
    }

    func testTriggerRulesAndDisablingAutomaticStarts() {
        let environment = controller.environment as! KeepAwakeEnvironmentSpy
        environment.externalDisplay = true
        controller.update(\.displayTrigger, value: true)
        controller.evaluateAutomaticTriggers(now: 100)
        XCTAssertTrue(controller.isActive)
        controller.stop()
        controller.update(\.displayTrigger, value: false)
        controller.update(\.powerTrigger, value: true)
        environment.onPower = true
        controller.evaluateAutomaticTriggers(now: 200)
        XCTAssertTrue(controller.isActive)
        controller.stop()
        controller.update(\.powerTrigger, value: false)
        controller.update(\.appsTrigger, value: true)
        controller.setChosenApps([KeepAwakeApp(bundleID: "us.zoom.xos", name: "Zoom")])
        environment.runningBundleIDs = ["us.zoom.xos"]
        controller.evaluateAutomaticTriggers(now: 300)
        XCTAssertTrue(controller.isActive)
        environment.runningBundleIDs = []
        controller.evaluateAutomaticTriggers(now: 301)
        XCTAssertFalse(controller.isActive)
        controller.update(\.appsTrigger, value: false)
        environment.runningBundleIDs = ["us.zoom.xos"]
        controller.evaluateAutomaticTriggers(now: 302)
        XCTAssertFalse(controller.isActive)
    }

    func testManualStopSuppressesAutomaticRestartUntilConditionCycles() {
        let environment = controller.environment as! KeepAwakeEnvironmentSpy
        environment.externalDisplay = true
        controller.update(\.displayTrigger, value: true)
        controller.evaluateAutomaticTriggers(now: 100)
        XCTAssertTrue(controller.isActive)
        controller.stop()
        controller.evaluateAutomaticTriggers(now: 101)
        XCTAssertFalse(controller.isActive)
        controller.tick(now: 102)
        XCTAssertFalse(controller.isActive)
        environment.externalDisplay = false
        controller.evaluateAutomaticTriggers(now: 103)
        environment.externalDisplay = true
        controller.evaluateAutomaticTriggers(now: 104)
        XCTAssertTrue(controller.isActive)
    }

    func testBatteryCutoffPreventsImmediateAutomaticRestart() {
        let environment = controller.environment as! KeepAwakeEnvironmentSpy
        controller.update(\.powerTrigger, value: true)
        controller.update(\.batteryCutoff, value: true)
        environment.onPower = false
        environment.power = KeepAwakePower(isOnBattery: true, level: 0.05)
        controller.start(duration: .oneHour, now: 0)
        controller.tick(now: 1)
        XCTAssertFalse(controller.isActive)
        controller.evaluateAutomaticTriggers(now: 2)
        XCTAssertFalse(controller.isActive)
    }

    func testSettingsRenderWithChosenAppsAndBatteryEnabled() throws {
        controller.update(\.appsTrigger, value: true)
        controller.setChosenApps([KeepAwakeApp(bundleID: "us.zoom.xos", name: "Zoom"), KeepAwakeApp(bundleID: "com.obsproject.obs-studio", name: "OBS")])
        controller.update(\.batteryCutoff, value: true)
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "light" : "dark"
            try KeepAwakePreviewRenderer.renderSettings(controller: controller, scheme: scheme, to: URL(fileURLWithPath: "/tmp/usage-shelf-keep-awake-shots/settings-full-\(name).png"))
        }
    }

    func testManualSessionSurvivesAutomaticConditionEnding() {
        let environment = controller.environment as! KeepAwakeEnvironmentSpy
        controller.update(\.displayTrigger, value: true)
        environment.externalDisplay = true
        controller.start(duration: .oneHour, now: 100)
        environment.externalDisplay = false
        controller.evaluateAutomaticTriggers(now: 200)
        XCTAssertTrue(controller.isActive)
    }

    func testAssertionTypeFollowsDisplaySleepOption() {
        let assertion = controller.assertion as! KeepAwakeAssertionSpy
        controller.update(\.allowDisplaySleep, value: false)
        controller.start(duration: .oneHour, now: 0)
        XCTAssertEqual(assertion.types, [.systemAndDisplay])
        controller.update(\.allowDisplaySleep, value: true)
        XCTAssertEqual(assertion.types, [.systemAndDisplay, .systemOnly])
        controller.stop()
    }

    func testPointerDoesNothingWithoutPermissionAndNeverAutoPrompts() {
        let pointer = controller.pointer as! KeepAwakePointerSpy
        controller.update(\.pointerMovement, value: true)
        XCTAssertFalse(controller.settings.pointerMovement)
        XCTAssertEqual(pointer.moveCount, 0)
        XCTAssertEqual(pointer.promptCount, 0)
        pointer.trusted = true
        controller.start(duration: .oneHour, now: 0)
        controller.update(\.pointerMovement, value: true)
        XCTAssertTrue(controller.settings.pointerMovement)
        controller.pointerTick()
        XCTAssertEqual(pointer.moveCount, 1)
        pointer.trusted = false
        controller.pointerTick()
        XCTAssertEqual(pointer.moveCount, 1)
        XCTAssertEqual(pointer.promptCount, 0)
    }

    func testSettingsPersistInInjectedSuiteOnly() {
        controller.update(\.startOnLaunch, value: true)
        controller.update(\.batteryCutoff, value: true)
        controller.update(\.batteryLevel, value: 25)
        controller.update(\.markColor, value: .teal)
        let restored = KeepAwakeSettings.load(from: UserDefaults(suiteName: suite)!)
        XCTAssertTrue(restored.startOnLaunch)
        XCTAssertTrue(restored.batteryCutoff)
        XCTAssertEqual(restored.batteryLevel, 25)
        XCTAssertEqual(restored.markColor, .teal)
        XCTAssertNil(UserDefaults.standard.object(forKey: "keepAwake.batteryLevel"))
    }

    func testStartOnLaunchUsesLastDuration() {
        controller.start(duration: .fourHours, now: 10)
        controller.stop()
        controller.update(\.startOnLaunch, value: true)
        controller.startOnAppLaunch(now: 100)
        XCTAssertEqual(controller.selectedDuration, .fourHours)
        XCTAssertEqual(controller.remaining(at: 100), 14400)
    }

    func testCompactAndPopupTimeFormatting() {
        controller.start(duration: .twoHours, now: 0)
        controller.tick(now: 18 * 60)
        XCTAssertEqual(controller.menuBarTime(at: 18 * 60), "1:42")
        XCTAssertEqual(controller.popupTime(at: 18 * 60), "1 hr 42 min left")
        controller.start(duration: .untilOff, now: 0)
        XCTAssertEqual(controller.menuBarTime(at: 0), "On")
        XCTAssertEqual(controller.popupTime(at: 0), "Until turned off")
    }

    func testContextMenuPutsKeepAwakeAboveExistingRows() {
        let titles = controller.contextMenuTitles(isOn: true)
        XCTAssertEqual(titles, ["Keep awake", "Refresh", "Settings", "Quit"])
    }

    func testActiveMarkUsesChosenColorWithoutChangingUsageRings() {
        let orange = KeepAwakeMarkColor.orange.nsColor.usingColorSpace(.sRGB)!
        XCTAssertEqual(orange.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(orange.greenComponent, 0x9f / 255.0, accuracy: 0.01)
        XCTAssertEqual(orange.blueComponent, 0x0a / 255.0, accuracy: 0.01)
        XCTAssertEqual(KeepAwakeMarkColor.allCases.map(\.rawValue), ["orange", "green", "teal", "blue"])
        let image = controller.menuBarAccessoryImage(isDarkMode: true)
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testMenuBarCompositionLeavesIconUnchangedWhenKeepAwakeIsOff() {
        let renderer = MenuBarIconRenderer()
        let rings = renderer.createCombinedRingsIcon(
            sessionPercentage: 25, weekPercentage: 50,
            sessionLevel: .safe, weekLevel: .safe, isDarkMode: true
        )
        let combined = renderer.appendingKeepAwakeAccessory(nil, to: rings)
        XCTAssertTrue(combined === rings, "Off must preserve the original image and width exactly")
        XCTAssertEqual(combined.size, rings.size)
    }

    func testMenuBarCompositionPutsMarkImmediatelyRightOfRings() throws {
        controller.start(duration: .untilOff, now: 0)
        let renderer = MenuBarIconRenderer()
        let rings = renderer.createCombinedRingsIcon(
            sessionPercentage: 25, weekPercentage: 50,
            sessionLevel: .safe, weekLevel: .safe, isDarkMode: true
        )
        let accessory = controller.menuBarAccessoryImage(isDarkMode: true)
        let combined = renderer.appendingKeepAwakeAccessory(accessory, to: rings)
        XCTAssertEqual(combined.size.width, rings.size.width + 4 + accessory.size.width, accuracy: 0.01)
        XCTAssertEqual(combined.size.height, max(rings.size.height, accessory.size.height), accuracy: 0.01)

        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: combined.tiffRepresentation ?? Data()))
        let orange = KeepAwakeMarkColor.orange.nsColor.usingColorSpace(.sRGB)!
        var markPixels: [Int] = []
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), pixel.alphaComponent > 0.8 else { continue }
                let close = abs(pixel.redComponent - orange.redComponent) < 0.08
                    && abs(pixel.greenComponent - orange.greenComponent) < 0.08
                    && abs(pixel.blueComponent - orange.blueComponent) < 0.08
                if close { markPixels.append(x) }
            }
        }
        let markLeft = CGFloat(try XCTUnwrap(markPixels.min()))
        let expectedLeft = rings.size.width + 4
        XCTAssertGreaterThanOrEqual(markLeft, expectedLeft, "The mark must be to the right of all ring pixels")
        XCTAssertLessThanOrEqual(markLeft, expectedLeft + 4, "The gap must stay tight")
    }

    func testMenuBarCompositionWorksForOtherIconStylesAndMultipleProfiles() {
        let renderer = MenuBarIconRenderer()
        controller.start(duration: .untilOff, now: 0)
        let activeAccessory = controller.menuBarAccessoryImage(isDarkMode: false)
        let otherIcon = renderer.createCompactDot(percentage: 50, status: .safe, profileInitial: "W", monochromeMode: false, isDarkMode: false)
        let combined = renderer.appendingKeepAwakeAccessory(activeAccessory, to: otherIcon)
        XCTAssertEqual(combined.size.width, otherIcon.size.width + 4 + activeAccessory.size.width, accuracy: 0.01)
        let firstProfile = renderer.appendingKeepAwakeAccessory(activeAccessory, to: otherIcon)
        let secondProfile = renderer.appendingKeepAwakeAccessory(nil, to: otherIcon)
        XCTAssertGreaterThan(firstProfile.size.width, secondProfile.size.width)
        XCTAssertTrue(secondProfile === otherIcon)
    }

    func testKeepAwakeHaloHasClearSpaceAroundFullCircle() throws {
        controller.start(duration: .untilOff, now: 0)
        for dark in [false, true] {
            let image = controller.menuBarAccessoryImage(isDarkMode: dark)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: image.tiffRepresentation ?? Data()))
            var firstInk = bitmap.pixelsWide
            var lastInk = -1
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                    firstInk = min(firstInk, x)
                    lastInk = max(lastInk, x)
                }
            }
            XCTAssertGreaterThan(firstInk, 0, "The halo must not touch the left image edge")
            XCTAssertLessThan(lastInk, bitmap.pixelsWide - 1, "The halo must not be clipped by the text at the right image edge")
        }
    }

    func testMenuBarPausedStateUsesReadableText() {
        controller.start(duration: .untilOff, now: 0)
        controller.setLocked(true, now: 0)
        XCTAssertTrue(controller.isPaused)
        let image = controller.menuBarAccessoryImage(isDarkMode: true)
        let activeSize = image.size
        controller.setLocked(false, now: 30)
        XCTAssertFalse(controller.isPaused)
        XCTAssertLessThan(controller.menuBarAccessoryImage(isDarkMode: true).size.width, activeSize.width)
    }

    func testMenuBarOnOffLightAndDarkPNGs() throws {
        let folder = URL(fileURLWithPath: "/tmp/usage-shelf-keep-awake-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "light" : "dark"
            for active in [false, true] {
                let state = active ? "on" : "off"
                try KeepAwakePreviewRenderer.renderMenuBarV3(controller: controller, active: active, scheme: scheme, to: folder.appendingPathComponent("menu-bar-\(state)-\(name)-v3.png"))
            }
        }
    }

    func testDarkSettingsPreviewUsesActualSettingsBackgrounds() throws {
        let controller = self.controller!
        try KeepAwakePreviewRenderer.renderSettings(controller: controller, scheme: .dark, to: URL(fileURLWithPath: "/tmp/usage-shelf-keep-awake-shots/settings-dark.png"))
        let data = try Data(contentsOf: URL(fileURLWithPath: "/tmp/usage-shelf-keep-awake-shots/settings-dark.png"))
        XCTAssertFalse(KeepAwakePreviewRenderer.isMostlyWhite(data), "Dark Settings must have the real dark window background, not a detached white canvas")
    }

    func testOffscreenChangedScreensRenderLightAndDark() throws {
        let folder = URL(fileURLWithPath: "/tmp/usage-shelf-keep-awake-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "light" : "dark"
            try KeepAwakePreviewRenderer.renderPopup(controller: controller, scheme: scheme, to: folder.appendingPathComponent("popup-off-\(name).png"))
            controller.start(duration: .twoHours, now: 0)
            controller.tick(now: 18 * 60)
            try KeepAwakePreviewRenderer.renderPopup(controller: controller, scheme: scheme, to: folder.appendingPathComponent("popup-on-\(name).png"))
            try KeepAwakePreviewRenderer.renderSettings(controller: controller, scheme: scheme, to: folder.appendingPathComponent("settings-\(name).png"))
            try KeepAwakePreviewRenderer.renderContextMenu(controller: controller, scheme: scheme, to: folder.appendingPathComponent("menu-\(name).png"))
            let menuBarURL = folder.appendingPathComponent("menu-bar-\(name).png")
            try KeepAwakePreviewRenderer.renderMenuBarV3(controller: controller, active: true, scheme: scheme, to: menuBarURL)
            controller.stop()
        }
    }
}

final class KeepAwakeAssertionSpy: KeepAwakeAssertionHandling {
    enum Kind { case systemOnly, systemAndDisplay }
    private(set) var acquireCount = 0
    private(set) var releaseCount = 0
    private(set) var types: [Kind] = []
    var isAcquired = false
    func acquire(allowDisplaySleep: Bool) {
        acquireCount += 1
        isAcquired = true
        types.append(allowDisplaySleep ? .systemOnly : .systemAndDisplay)
    }
    func release() {
        releaseCount += 1
        isAcquired = false
    }
}

final class KeepAwakePointerSpy: KeepAwakePointerHandling {
    var trusted = false
    private(set) var moveCount = 0
    private(set) var promptCount = 0
    var isTrusted: Bool { trusted }
    func requestTrust() { promptCount += 1 }
    func moveSlightly() { moveCount += 1 }
}

final class KeepAwakeEnvironmentSpy: KeepAwakeEnvironmentHandling {
    var externalDisplay = false
    var onPower = false
    var runningBundleIDs: Set<String> = []
    var power = KeepAwakePower(isOnBattery: false, level: nil)
    var currentPower: KeepAwakePower { power }
    var hasExternalDisplay: Bool { externalDisplay }
    var isOnPower: Bool { onPower }
    var runningApplicationBundleIDs: Set<String> { runningBundleIDs }
}
