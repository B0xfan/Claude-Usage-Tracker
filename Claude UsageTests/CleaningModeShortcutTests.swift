import XCTest
import AppKit
import Carbon
import CoreGraphics
import SwiftUI
@testable import Claude_Usage

/// The 12 numbered checks of the Cleaning Mode on/off shortcut addendum. Only fakes:
/// no event tap, no Carbon hotkey, no overlay window, no permission, no real keyboard.
@MainActor
final class CleaningModeShortcutTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var permissions: CleaningPermissionsSpy!
    private var blocker: CleaningInputBlockerSpy!
    private var overlay: CleaningOverlaySpy!
    private var awake: CleaningAwakeSpy!
    private var otherInput: CleaningOtherInputSpy!
    private var store: ShortcutStoreSpy!
    private var registrar: ShortcutRegistrarSpy!
    private var manager: ShortcutManager!
    private var controller: CleaningModeController!

    /// ⌃⌥⌘C, the mockup's example. There is still no default.
    private let example = KeyCombo(keyCode: UInt16(kVK_ANSI_C), modifierFlags: [.control, .option, .command])
    private let exampleFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

    override func setUp() async throws {
        suite = "CleaningModeShortcutTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        permissions = CleaningPermissionsSpy()
        blocker = CleaningInputBlockerSpy()
        overlay = CleaningOverlaySpy()
        awake = CleaningAwakeSpy()
        otherInput = CleaningOtherInputSpy()
        store = ShortcutStoreSpy()
        registrar = ShortcutRegistrarSpy()
        manager = ShortcutManager(store: store, registrar: registrar.register)
        controller = CleaningModeController(defaults: defaults, permissions: permissions, blocker: blocker, overlay: overlay,
                                            awake: awake, otherInput: otherInput,
                                            offShortcut: { [weak self] in self?.manager.shortcuts[.cleaningMode] })
        manager.onToggleCleaningMode = { [weak self] in _ = self?.controller.toggleFromShortcut(now: 100) }
        manager.startListening()
    }

    override func tearDown() async throws {
        manager.stopListening()
        controller.cleanup()
        defaults.removePersistentDomain(forName: suite)
        controller = nil
        manager = nil
        defaults = nil
    }

    /// Runs the deferred overlay presentation queued by start().
    private func drainMainQueue() {
        let done = expectation(description: "main queue")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    private func record(_ combo: KeyCombo) {
        XCTAssertEqual(manager.setShortcut(combo, for: .cleaningMode), .success)
    }

    // 1
    func testRowLabelAndNoDefault() {
        XCTAssertEqual(ShortcutAction.cleaningMode.displayName, "Turn Cleaning Mode on or off")
        XCTAssertEqual(CleaningShortcutCopy.rowTitle, "Turn Cleaning Mode on or off")
        XCTAssertEqual(CleaningShortcutCopy.rowDescription, "Press once to start, press again to finish. No shortcut is set by default.")
        XCTAssertNil(manager.shortcuts[.cleaningMode])
        XCTAssertNil(store.loadShortcut(for: .cleaningMode))
        XCTAssertTrue(registrar.combos.isEmpty)
    }

    // 2
    func testTwoModifierRuleAndExistingWarnings() {
        let bare = KeyCombo(keyCode: UInt16(kVK_ANSI_C), modifierFlags: [])
        let command = KeyCombo(keyCode: UInt16(kVK_ANSI_C), modifierFlags: [.command])
        XCTAssertEqual(manager.setShortcut(bare, for: .cleaningMode), .needsTwoModifiers)
        XCTAssertEqual(manager.setShortcut(command, for: .cleaningMode), .needsTwoModifiers)
        XCTAssertNil(manager.shortcuts[.cleaningMode])
        XCTAssertNil(store.loadShortcut(for: .cleaningMode))
        XCTAssertEqual(resultWarning(.needsTwoModifiers, combo: command), "Use at least two of ⌃ ⌥ ⇧ ⌘ so wiping the keys can't turn this off. The timer and the 3-second hold still work.")
        XCTAssertFalse(ShortcutRecorderView.accepts(keyCode: UInt16(kVK_ANSI_C), modifiers: [], minimumModifiers: 2))
        XCTAssertFalse(ShortcutRecorderView.accepts(keyCode: UInt16(kVK_ANSI_C), modifiers: [.command], minimumModifiers: 2))
        XCTAssertTrue(ShortcutRecorderView.accepts(keyCode: UInt16(kVK_ANSI_C), modifiers: [.control, .option, .command], minimumModifiers: 2))
        XCTAssertEqual(manager.setShortcut(example, for: .cleaningMode), .success)
        XCTAssertEqual(store.loadShortcut(for: .cleaningMode), example)
        // Other actions keep the one-modifier rule.
        XCTAssertEqual(manager.setShortcut(command, for: .refresh), .success)
        // Duplicate and "already in use" still work as today, keeping the working combo.
        let keepAwakeCombo = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.control, .option])
        XCTAssertEqual(manager.setShortcut(keepAwakeCombo, for: .keepAwake), .success)
        XCTAssertEqual(manager.setShortcut(keepAwakeCombo, for: .cleaningMode), .duplicate("Keep awake"))
        let rejected = KeyCombo(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.control, .shift])
        registrar.failures.insert(rejected)
        XCTAssertEqual(manager.setShortcut(rejected, for: .cleaningMode), .registrationFailed)
        XCTAssertEqual(manager.shortcuts[.cleaningMode], example)
    }

    // 3
    func testShortcutTurnsCleaningOnLikeTheMenu() {
        record(example)
        XCTAssertTrue(manager.perform(example))
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(blocker.startCount, 1)
        XCTAssertEqual(awake.acquireCount, 1)
        XCTAssertEqual(otherInput.suspendCount, 1)
        XCTAssertEqual(controller.remaining(at: 100), CleaningDuration.oneMinute.seconds)
        // Same permission checks as the menu: missing permission never starts.
        controller.stop(reason: .manual)
        permissions.accessibility = false
        XCTAssertEqual(controller.toggleFromShortcut(now: 200), .permissionMissing)
        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(controller.shouldOpenSettings)
    }

    // 4
    func testExactComboAfterGraceEndsAtOnceAndIsSwallowed() {
        record(example)
        controller.start(now: 100)
        let configured = blocker.lastConfiguration?.offShortcut
        XCTAssertEqual(configured, CleaningOffShortcut(keyCode: example.keyCode, modifierFlags: example.nsModifierFlags))
        XCTAssertTrue(CleaningKeyGate.isOffPress(type: .keyDown, keyCode: example.keyCode, flags: exampleFlags, isRepeat: false, shortcut: configured))
        controller.offShortcutPressed(at: 101.5)
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.endReason, .manual)
        XCTAssertEqual(blocker.stopCount, 1)
        XCTAssertEqual(awake.releaseCount, 1)
        XCTAssertEqual(otherInput.resumeCount, 1)
        XCTAssertEqual(overlay.hideCount, 1)
        // The production tap returns nil for every event it watches, so the off press
        // never reaches the front app: keyDown stays in the blocked mask.
        XCTAssertTrue(CleaningInputBlocker.keyboardMask & (1 << CGEventType.keyDown.rawValue) != 0)
    }

    // 5
    func testStartGraceIgnoresTheStartingPressAndItsRepeats() {
        record(example)
        controller.start(now: 100)
        for t in [100.0, 100.2, 100.5, 100.99] {
            controller.offShortcutPressed(at: t)
            XCTAssertTrue(controller.isActive, "ended inside the 1-second grace at \(t)")
        }
        XCTAssertEqual(CleaningModeController.offShortcutGrace, 1)
        controller.offShortcutPressed(at: 101)
        XCTAssertFalse(controller.isActive)
    }

    // 6
    func testWipingNeverEndsCleaning() throws {
        record(example)
        controller.start(now: 100)
        let shortcut = try XCTUnwrap(blocker.lastConfiguration?.offShortcut)
        let all: [CGEventFlags] = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        // Every modifier set that is not exactly ⌃⌥⌘, on the recorded key.
        for mask in 0..<16 {
            var flags: CGEventFlags = []
            for (bit, flag) in all.enumerated() where mask & (1 << bit) != 0 { flags.insert(flag) }
            let isExact = flags == exampleFlags
            XCTAssertEqual(CleaningKeyGate.isOffPress(type: .keyDown, keyCode: example.keyCode, flags: flags, isRepeat: false, shortcut: shortcut), isExact)
        }
        // Mashing every other key with the exact modifiers, or none, never matches.
        for keyCode in UInt16(0)...UInt16(127) where keyCode != example.keyCode {
            XCTAssertFalse(CleaningKeyGate.isOffPress(type: .keyDown, keyCode: keyCode, flags: exampleFlags, isRepeat: false, shortcut: shortcut))
            XCTAssertFalse(CleaningKeyGate.isOffPress(type: .keyDown, keyCode: keyCode, flags: [], isRepeat: false, shortcut: shortcut))
        }
        // Key up and modifier changes are never the off press.
        XCTAssertFalse(CleaningKeyGate.isOffPress(type: .keyUp, keyCode: example.keyCode, flags: exampleFlags, isRepeat: false, shortcut: shortcut))
        XCTAssertFalse(CleaningKeyGate.isOffPress(type: .flagsChanged, keyCode: example.keyCode, flags: exampleFlags, isRepeat: false, shortcut: shortcut))
        // Caps Lock or fn being on do not count as extra modifiers.
        XCTAssertTrue(shortcut.matches(keyCode: example.keyCode, flags: exampleFlags.union([.maskAlphaShift, .maskSecondaryFn]), isRepeat: false))
        XCTAssertTrue(controller.isActive)
    }

    // 7
    func testHeldRepeatingKeyNeverCountsAsTheOffPress() throws {
        record(example)
        controller.start(now: 100)
        let shortcut = try XCTUnwrap(blocker.lastConfiguration?.offShortcut)
        XCTAssertFalse(CleaningKeyGate.isOffPress(type: .keyDown, keyCode: example.keyCode, flags: exampleFlags, isRepeat: true, shortcut: shortcut))
        XCTAssertFalse(shortcut.matches(keyCode: example.keyCode, flags: exampleFlags, isRepeat: true))
    }

    // 8
    func testTimerAndHoldStillEndCleaningWithAShortcutRecorded() {
        record(example)
        controller.start(now: 100)
        controller.tick(now: 160)
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.endReason, .timer)
        controller.start(now: 200)
        controller.pointerDown(at: 201)
        controller.tick(now: 204)
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.endReason, .hold)
    }

    // 9
    func testNoShortcutRecordedBehavesAsBefore() {
        controller.start(now: 100)
        XCTAssertEqual(blocker.lastConfiguration, CleaningInputConfiguration(blockPointer: true))
        XCTAssertNil(blocker.lastConfiguration?.offShortcut)
        drainMainQueue()
        XCTAssertEqual(overlay.hints, [nil])
        XCTAssertNil(controller.currentOffShortcut().hint)
        // Without a matcher no key ends cleaning.
        XCTAssertFalse(CleaningKeyGate.isOffPress(type: .keyDown, keyCode: example.keyCode, flags: exampleFlags, isRepeat: false, shortcut: nil))
        // A one-modifier combo saved before this rule never becomes an off combo.
        store.saveShortcut(KeyCombo(keyCode: UInt16(kVK_ANSI_C), modifierFlags: [.command]), for: .cleaningMode)
        let legacy = ShortcutManager(store: store, registrar: registrar.register)
        let legacyController = CleaningModeController(defaults: defaults, permissions: permissions, blocker: CleaningInputBlockerSpy(), overlay: CleaningOverlaySpy(),
                                                      awake: CleaningAwakeSpy(), otherInput: CleaningOtherInputSpy(),
                                                      offShortcut: { legacy.shortcuts[.cleaningMode] })
        XCTAssertNil(legacyController.currentOffShortcut().shortcut)
        XCTAssertNil(legacyController.currentOffShortcut().hint)
        legacyController.cleanup()
    }

    // 10
    func testHintLineUsesTheRealComboInBothStylesLightAndDark() throws {
        record(example)
        controller.start(now: 100)
        drainMainQueue()
        XCTAssertEqual(overlay.hints, ["or press ⌃⌥⌘C again"])
        let other = KeyCombo(keyCode: UInt16(kVK_ANSI_L), modifierFlags: [.shift, .command])
        controller.stop(reason: .manual)
        record(other)
        controller.start(now: 200)
        drainMainQueue()
        XCTAssertEqual(overlay.hints.last, "or press ⇧⌘L again")
        let folder = URL(fileURLWithPath: "/tmp/usage-shelf-cleaning-mode-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let hint = CleaningShortcutCopy.overlayHint(example.displayString)
        for appearance in CleaningScreenAppearance.allCases {
            controller.update(\.screenAppearance, value: appearance)
            for scheme in [ColorScheme.light, .dark] {
                let name = "active-shortcut-hint-\(appearance.rawValue)-\(scheme == .light ? "light" : "dark").png"
                try CleaningModePreviewRenderer.renderActive(controller: controller, scheme: scheme, offShortcutHint: hint, to: folder.appendingPathComponent(name))
                XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path))
            }
        }
        try CleaningModePreviewRenderer.renderShortcuts(scheme: .light, cleaningCombo: example, to: folder.appendingPathComponent("shortcuts-on-off-light.png"))
        try CleaningModePreviewRenderer.renderShortcuts(scheme: .dark, cleaningCombo: example, to: folder.appendingPathComponent("shortcuts-on-off-dark.png"))
    }

    // 11
    func testOtherShortcutsStaySuspendedDuringCleaningAndReturnAfter() {
        record(example)
        let keepAwakeCombo = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.control, .option])
        XCTAssertEqual(manager.setShortcut(keepAwakeCombo, for: .keepAwake), .success)
        controller.start(now: 100)
        XCTAssertEqual(otherInput.suspendCount, 1)
        XCTAssertEqual(otherInput.resumeCount, 0)
        // Only the exact cleaning combo is recognized by the tap; Keep awake's combo is not.
        XCTAssertFalse(CleaningKeyGate.isOffPress(type: .keyDown, keyCode: keepAwakeCombo.keyCode, flags: [.maskControl, .maskAlternate], isRepeat: false, shortcut: blocker.lastConfiguration?.offShortcut))
        controller.offShortcutPressed(at: 102)
        XCTAssertEqual(otherInput.resumeCount, 1)
        XCTAssertEqual(manager.shortcuts[.keepAwake], keepAwakeCombo)
    }

    // 12
    func testMatchingKeepsNoKeyContents() {
        record(example)
        controller.start(now: 100)
        // The tap reports a bare "off pressed" event, nothing about which key was pressed.
        var called = 0
        blocker.onOffShortcut = { called += 1 }
        blocker.onOffShortcut?()
        XCTAssertEqual(called, 1)
        // The configuration holds only the one recorded combo, never pressed keys.
        let mirror = Mirror(reflecting: blocker.lastConfiguration!)
        XCTAssertEqual(mirror.children.compactMap(\.label).sorted(), ["blockPointer", "offShortcut"])
        let shortcutMirror = Mirror(reflecting: blocker.lastConfiguration!.offShortcut!)
        XCTAssertEqual(shortcutMirror.children.compactMap(\.label).sorted(), ["flags", "keyCode"])
        XCTAssertNil(UserDefaults.standard.object(forKey: "cleaningMode.lastKey"))
    }
}
