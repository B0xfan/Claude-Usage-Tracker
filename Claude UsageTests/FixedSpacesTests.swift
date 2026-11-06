import XCTest
import SwiftUI
@testable import Claude_Usage

@MainActor
final class FixedSpacesTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var system: FixedSpacesSystemSpy!
    private var controller: FixedSpacesController!

    override func setUp() async throws {
        suite = "FixedSpacesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        system = FixedSpacesSystemSpy()
        controller = FixedSpacesController(defaults: defaults, system: system)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        controller = nil
        defaults = nil
        system = nil
    }

    func testMirrorsRealMacStateWithoutWritingOrRestartingDock() {
        system.rearranges = false
        controller.refresh()
        XCTAssertTrue(controller.keepFixed)
        system.rearranges = true
        controller.refresh()
        XCTAssertFalse(controller.keepFixed)
        XCTAssertEqual(system.writes, [])
        XCTAssertEqual(system.restartCount, 0)
    }

    func testTurningOnSavesPreviousValueAndRestartsDockOnce() {
        system.rearranges = true
        controller.refresh()
        controller.setFixed(true)
        XCTAssertEqual(system.writes, [false])
        XCTAssertEqual(system.restartCount, 1)
        XCTAssertTrue(controller.keepFixed)
        XCTAssertEqual(defaults.object(forKey: FixedSpacesController.previousRearrangeKey) as? Bool, true)
    }

    func testTurningOffRestoresAndClearsSavedValue() {
        system.rearranges = true
        controller.refresh()
        controller.setFixed(true)
        controller.setFixed(false)
        XCTAssertEqual(system.writes, [false, true])
        XCTAssertEqual(system.restartCount, 2)
        XCTAssertFalse(controller.keepFixed)
        XCTAssertNil(defaults.object(forKey: FixedSpacesController.previousRearrangeKey))
    }

    func testAlreadyFixedDoesNotWriteReplaceSavedValueOrRestartDock() {
        system.rearranges = true
        controller.refresh()
        controller.setFixed(true)
        system.rearranges = false
        controller.refresh()
        controller.setFixed(true)
        XCTAssertEqual(system.writes, [false])
        XCTAssertEqual(system.restartCount, 1)
        XCTAssertEqual(defaults.object(forKey: FixedSpacesController.previousRearrangeKey) as? Bool, true)
        system.rearranges = true
        controller.refresh()
        XCTAssertEqual(system.writes, [false])
        XCTAssertEqual(system.restartCount, 1)
        XCTAssertTrue(defaults.object(forKey: FixedSpacesController.previousRearrangeKey) != nil)
    }

    func testTurningOffWithoutSavedValueEnablesRearrange() {
        system.rearranges = false
        controller.refresh()
        controller.setFixed(false)
        XCTAssertEqual(system.writes, [true])
        XCTAssertEqual(system.restartCount, 1)
        XCTAssertFalse(controller.keepFixed)
    }

    func testExternalChangeIsReflectedWithoutFightingTheUser() {
        system.rearranges = true
        controller.refresh()
        controller.setFixed(true)
        system.rearranges = true
        controller.refresh()
        XCTAssertFalse(controller.keepFixed)
        XCTAssertEqual(system.writes, [false])
        XCTAssertEqual(system.restartCount, 1)
        XCTAssertEqual(defaults.object(forKey: FixedSpacesController.previousRearrangeKey) as? Bool, true)
    }

    func testFailedWriteReportsFailureAndDoesNotClaimSuccess() {
        system.rearranges = true
        system.writeSucceeds = false
        controller.refresh()
        controller.setFixed(true)
        XCTAssertTrue(controller.keepFixed == false)
        XCTAssertNil(defaults.object(forKey: FixedSpacesController.previousRearrangeKey))
        XCTAssertEqual(system.restartCount, 0)
    }

    func testSavedValueSurvivesRelaunch() {
        system.rearranges = true
        controller.refresh()
        controller.setFixed(true)
        controller = FixedSpacesController(defaults: defaults, system: system)
        controller.setFixed(false)
        XCTAssertEqual(system.writes, [false, true])
        XCTAssertEqual(system.restartCount, 2)
    }

    func testAlreadyRearrangedTurningOffDoesNotClearSavedValueOrRestartDock() {
        system.rearranges = true
        controller.refresh()
        controller.setFixed(true)
        system.rearranges = true
        controller.refresh()
        controller.setFixed(false)
        XCTAssertEqual(system.writes, [false])
        XCTAssertEqual(system.restartCount, 1)
        XCTAssertEqual(defaults.object(forKey: FixedSpacesController.previousRearrangeKey) as? Bool, true)
    }

    func testSettingsViewRefreshesFromTheLiveState() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Claude Usage/Views/Settings/App/AppSettingsView.swift")
        let source = try String(contentsOf: file)
        XCTAssertTrue(source.contains(".onAppear { fixedSpaces.refresh() }"))
        XCTAssertTrue(source.contains("NSApplication.didBecomeActiveNotification"))
        XCTAssertTrue(source.contains("Timer.publish(every: 2"))
        XCTAssertFalse(source.contains("setFixed(true)") || source.contains("setFixed(false)"), "Refresh hooks must never write")
    }

    func testRealSystemReaderUsesOnlyTheDockPreferenceAndKillall() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Claude Usage/FixedSpaces/FixedSpacesSystem.swift")
        let source = try String(contentsOf: file)
        XCTAssertTrue(source.contains("com.apple.dock"))
        XCTAssertTrue(source.contains("mru-spaces"))
        XCTAssertTrue(source.contains("/usr/bin/killall"))
        XCTAssertFalse(source.contains("AXIsProcessTrusted"))
        XCTAssertFalse(source.contains("AppleEvents"))
    }

    func testSettingsSourceKeepsEnglishCopyAndFlickerHelp() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Claude Usage/Views/Settings/App/AppSettingsView.swift")
        let source = try String(contentsOf: file)
        for text in ["Desktop Spaces", "Keep Spaces in a fixed order", "Stops macOS from rearranging your Spaces by recent use. The screen flickers briefly when this changes."] {
            XCTAssertTrue(source.contains("\"\(text)\""))
        }
        XCTAssertTrue(source.contains("LaunchAtLoginManager.shared"))
        XCTAssertTrue(source.contains("SettingToggle"))
        XCTAssertTrue(source.contains("SettingsSectionCard"))
        XCTAssertFalse(source.contains("\"Keep Spaces in a fixed order\".localized"))
    }

    func testToggleBindingUsesInjectedController() {
        var submitted: [Bool] = []
        let content = AppSettingsContent(
            launchAtLoginTitle: "Launch at login",
            launchAtLoginDescription: "Start Usage Shelf when you log in",
            launchAtLogin: .constant(false),
            fixedSpaces: controller.keepFixed,
            onFixedSpacesChange: { submitted.append($0) }
        )
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 720, height: 520)
        hosting.layoutSubtreeIfNeeded()
        let toggles = allToggles(in: hosting)
        XCTAssertEqual(toggles.count, 2)
        XCTAssertEqual(toggles[1].state == .on, controller.keepFixed)
        toggles[1].state = controller.keepFixed ? .off : .on
        _ = toggles[1].target?.perform(toggles[1].action, with: toggles[1])
        XCTAssertEqual(submitted, [!controller.keepFixed])
    }

    private func allToggles(in view: NSView) -> [NSSwitch] {
        if let toggle = view as? NSSwitch { return [toggle] }
        return view.subviews.flatMap(allToggles)
    }

    func testSettingsRenderUsesFakeInLightAndDarkOnAndOff() throws {
        let folder = URL(fileURLWithPath: "/tmp/usage-shelf-fixed-spaces-shots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            for fixed in [false, true] {
                system.rearranges = !fixed
                controller.refresh()
                let name = scheme == .light ? "light" : "dark"
                try KeepAwakePreviewRenderer.renderFixedSpaces(controller: controller, scheme: scheme, to: folder.appendingPathComponent("settings-\(name)-\(fixed ? "on" : "off").png"))
            }
        }
        XCTAssertEqual(system.writes, [])
        XCTAssertEqual(system.restartCount, 0)
        let light = try Data(contentsOf: folder.appendingPathComponent("settings-light-on.png"))
        let dark = try Data(contentsOf: folder.appendingPathComponent("settings-dark-on.png"))
        XCTAssertTrue(KeepAwakePreviewRenderer.isMostlyWhite(light))
        XCTAssertFalse(KeepAwakePreviewRenderer.isMostlyWhite(dark))
        for name in ["light", "dark"] {
            let on = try Data(contentsOf: folder.appendingPathComponent("settings-\(name)-on.png"))
            let off = try Data(contentsOf: folder.appendingPathComponent("settings-\(name)-off.png"))
            XCTAssertNotEqual(on, off, "The \(name) Off render must show the Off toggle")
        }
    }
}

final class FixedSpacesSystemSpy: FixedSpacesSystemHandling {
    var rearranges = true
    var writeSucceeds = true
    private(set) var writes: [Bool] = []
    private(set) var restartCount = 0

    func automaticallyRearrangesSpaces() -> Bool { rearranges }
    func setAutomaticallyRearrangesSpaces(_ enabled: Bool) -> Bool {
        if !writeSucceeds { return false }
        rearranges = enabled
        writes.append(enabled)
        restartCount += 1
        return true
    }
    func restartDock() { restartCount += 1 }
}
