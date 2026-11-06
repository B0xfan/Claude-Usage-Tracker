import XCTest
import AppKit
import Carbon
import SwiftUI
@testable import Claude_Usage

@MainActor
final class KeepAwakeShortcutTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var store: ShortcutStoreSpy!
    private var registrar: ShortcutRegistrarSpy!
    private var manager: ShortcutManager!
    private var controller: KeepAwakeController!

    override func setUp() {
        suite = "KeepAwakeShortcutTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        store = ShortcutStoreSpy()
        registrar = ShortcutRegistrarSpy()
        manager = ShortcutManager(store: store, registrar: registrar.register)
        controller = KeepAwakeController(defaults: defaults, assertion: KeepAwakeAssertionSpy(), pointer: KeepAwakePointerSpy(), environment: KeepAwakeEnvironmentSpy())
        manager.onToggleKeepAwake = { [controller] in controller?.toggle(now: 0) }
        manager.startListening()
    }

    override func tearDown() {
        manager.stopListening()
        controller.stop()
        defaults.removePersistentDomain(forName: suite)
        manager = nil
        controller = nil
    }

    func testNoDefaultAndPersistenceUsesInjectedStore() throws {
        XCTAssertNil(manager.shortcuts[.keepAwake])
        XCTAssertTrue(registrar.combos.isEmpty)
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.command, .option, .control])
        XCTAssertEqual(manager.setShortcut(combo, for: .keepAwake), .success)
        let restored = ShortcutManager(store: store, registrar: registrar.register)
        XCTAssertEqual(restored.shortcuts[.keepAwake], combo)
        XCTAssertNil(UserDefaults.standard.object(forKey: "shortcutKeepAwake"))
    }

    func testToggleStartsLastDurationAndStops() {
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.command, .option])
        XCTAssertEqual(manager.setShortcut(combo, for: .keepAwake), .success)
        controller.start(duration: .twoHours, now: 0)
        controller.stop()
        XCTAssertTrue(manager.perform(combo))
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.selectedDuration, .twoHours)
        XCTAssertEqual(controller.remaining(at: 0), 7200)
        XCTAssertTrue(manager.perform(combo))
        XCTAssertFalse(controller.isActive)
        controller.start(duration: .untilOff, now: 0)
        controller.stop()
        XCTAssertTrue(manager.perform(combo))
        XCTAssertNil(controller.remaining(at: 0))
    }

    func testClearingAndReplacingUnregistersOldCombo() {
        let first = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.command, .option])
        let second = KeyCombo(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [.command, .shift])
        XCTAssertEqual(manager.setShortcut(first, for: .keepAwake), .success)
        XCTAssertEqual(manager.setShortcut(second, for: .keepAwake), .success)
        XCTAssertFalse(manager.perform(first))
        XCTAssertTrue(manager.perform(second))
        XCTAssertEqual(manager.setShortcut(nil, for: .keepAwake), .success)
        XCTAssertFalse(manager.perform(second))
        XCTAssertNil(store.loadShortcut(for: .keepAwake))
    }

    func testAppAndTopShelfClashesKeepPreviousWorkingCombo() {
        let old = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.command, .option])
        let refresh = KeyCombo(keyCode: UInt16(kVK_ANSI_R), modifierFlags: [.command, .shift])
        XCTAssertEqual(manager.setShortcut(old, for: .keepAwake), .success)
        XCTAssertEqual(manager.setShortcut(refresh, for: .refresh), .success)
        let result = manager.setShortcut(refresh, for: .keepAwake)
        XCTAssertEqual(result, .duplicate("Refresh usage"))
        XCTAssertEqual(manager.shortcuts[.keepAwake], old)
        for (keyCode, name) in [(kVK_ANSI_T, "Top Shelf"), (kVK_ANSI_V, "Top Shelf")] {
            let combo = KeyCombo(keyCode: UInt16(keyCode), modifierFlags: [.command, .option])
            XCTAssertEqual(manager.setShortcut(combo, for: .keepAwake), .duplicate(name))
            XCTAssertEqual(manager.shortcuts[.keepAwake], old)
        }
        XCTAssertTrue(manager.perform(old))
    }

    func testRegistrationFailureKeepsPreviousWorkingComboAndShowsWarning() {
        let old = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.command, .option])
        let rejected = KeyCombo(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [.command, .option])
        XCTAssertEqual(manager.setShortcut(old, for: .keepAwake), .success)
        registrar.failures.insert(rejected)
        XCTAssertEqual(manager.setShortcut(rejected, for: .keepAwake), .registrationFailed)
        XCTAssertEqual(manager.shortcuts[.keepAwake], old)
        XCTAssertEqual(resultWarning(.registrationFailed, combo: rejected), "This shortcut is already in use. Choose another one.")
        XCTAssertTrue(manager.perform(old))
    }

    func testShortcutSymbolsAreSeparateAndLightPreviewIsActuallyLight() throws {
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.control, .option, .command])
        XCTAssertEqual(combo.displayComponents, ["⌃", "⌥", "⌘", "K"])
        for scheme in [ColorScheme.light, .dark] {
            XCTAssertGreaterThan(ShortcutWarningStyle.textColor(for: scheme).contrastRatio(with: ShortcutWarningStyle.backgroundColor(for: scheme)), 4.5)
        }
        let folder = URL(fileURLWithPath: "/tmp/usage-shelf-keep-awake-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let originalAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .darkAqua)
        defer { NSApp.appearance = originalAppearance }
        let lightURL = folder.appendingPathComponent("shortcut-set-light.png")
        try KeepAwakePreviewRenderer.renderShortcuts(manager: manager, state: .set, scheme: .light, to: lightURL)
        XCTAssertTrue(KeepAwakePreviewRenderer.isMostlyWhite(try Data(contentsOf: lightURL)), "A light render must not inherit the test host's dark appearance")
        let image = NSImage(contentsOf: lightURL)!
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let pixel = bitmap.colorAt(x: 20, y: 20)!.usingColorSpace(.sRGB)!
        XCTAssertGreaterThan(pixel.redComponent, 0.95)
        XCTAssertGreaterThan(pixel.greenComponent, 0.95)
        XCTAssertGreaterThan(pixel.blueComponent, 0.95)
    }

    func testModifierRuleAndRecordingPreviewStates() throws {
        XCTAssertFalse(ShortcutRecorderView.accepts(keyCode: UInt16(kVK_ANSI_K), modifiers: []))
        XCTAssertTrue(ShortcutRecorderView.accepts(keyCode: UInt16(kVK_ANSI_K), modifiers: [.control]))
        let folder = URL(fileURLWithPath: "/tmp/usage-shelf-keep-awake-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            for state in ShortcutPreviewState.allCases {
                let name = scheme == .light ? "light" : "dark"
                try KeepAwakePreviewRenderer.renderShortcuts(manager: manager, state: state, scheme: scheme, to: folder.appendingPathComponent("shortcut-\(state.rawValue)-\(name).png"))
            }
        }
    }
}

final class ShortcutStoreSpy: ShortcutStoring {
    private var values: [ShortcutAction: KeyCombo] = [:]
    func saveShortcut(_ combo: KeyCombo?, for action: ShortcutAction) { values[action] = combo }
    func loadShortcut(for action: ShortcutAction) -> KeyCombo? { values[action] }
}

final class ShortcutRegistrarSpy {
    var combos: [KeyCombo] = []
    var failures: Set<KeyCombo> = []
    func register(_ combo: KeyCombo, action: ShortcutAction, id: EventHotKeyID) -> (OSStatus, EventHotKeyRef?) {
        combos.append(combo)
        let status = failures.contains(combo) ? OSStatus(eventHotKeyExistsErr) : noErr
        return (status, status == noErr ? OpaquePointer(bitPattern: combos.count) : nil)
    }
}

private extension NSColor {
    func contrastRatio(with other: NSColor) -> CGFloat {
        func luminance(_ color: NSColor) -> CGFloat {
            guard let color = color.usingColorSpace(.sRGB) else { return 0 }
            func channel(_ value: CGFloat) -> CGFloat { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(color.redComponent) + 0.7152 * channel(color.greenComponent) + 0.0722 * channel(color.blueComponent)
        }
        let values = [luminance(self), luminance(other)].sorted()
        return (values[1] + 0.05) / (values[0] + 0.05)
    }
}
