//
//  ShortcutManager.swift
//  Claude Usage
//
//  Global keyboard shortcut manager using Carbon RegisterEventHotKey
//  No Accessibility permission required.
//

import Cocoa
import Carbon

// MARK: - Models

enum ShortcutSetResult: Equatable {
    case success
    case duplicate(String)
    case registrationFailed
}

protocol ShortcutStoring {
    func saveShortcut(_ combo: KeyCombo?, for action: ShortcutAction)
    func loadShortcut(for action: ShortcutAction) -> KeyCombo?
}

extension SharedDataStore: ShortcutStoring {}

func resultWarning(_ result: ShortcutSetResult, combo: KeyCombo) -> String? {
    switch result {
    case .success: return nil
    case .duplicate(let name): return "Already used by \(name). Choose another shortcut."
    case .registrationFailed: return "This shortcut is already in use. Choose another one."
    }
}

enum ShortcutPreviewState: String, CaseIterable { case empty, recording, set, clash }

enum ShortcutAction: String, CaseIterable {
    case togglePopover
    case refresh
    case openSettings
    case nextProfile
    case keepAwake
    case cleaningMode

    var displayName: String {
        switch self {
        case .togglePopover: return "Toggle popover"
        case .refresh: return "Refresh usage"
        case .openSettings: return "Open Settings"
        case .nextProfile: return "Next profile"
        case .keepAwake: return "Keep awake"
        case .cleaningMode: return "Start Cleaning Mode"
        }
    }
}

struct KeyCombo: Codable, Equatable, Hashable {
    let keyCode: UInt16
    let modifierFlags: UInt

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags.intersection([.command, .option, .control, .shift]).rawValue
    }

    var nsModifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }

    /// Convert NSEvent modifier flags to Carbon modifier flags
    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        let flags = nsModifierFlags
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    var carbonKeyCode: UInt32 {
        UInt32(keyCode)
    }

    var displayComponents: [String] {
        var parts: [String] = []
        let flags = nsModifierFlags
        if flags.contains(.control) { parts.append("\u{2303}") }
        if flags.contains(.option) { parts.append("\u{2325}") }
        if flags.contains(.shift) { parts.append("\u{21E7}") }
        if flags.contains(.command) { parts.append("\u{2318}") }
        parts.append(KeyCombo.keyName(for: keyCode))
        return parts
    }

    var displayString: String {
        displayComponents.joined()
    }

    static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "\u{21A9}" // Return
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "\u{21E5}" // Tab
        case 49: return "\u{2423}" // Space
        case 50: return "`"
        case 51: return "\u{232B}" // Delete
        case 53: return "\u{238B}" // Escape
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        case 123: return "\u{2190}" // Left
        case 124: return "\u{2192}" // Right
        case 125: return "\u{2193}" // Down
        case 126: return "\u{2191}" // Up
        default: return "Key\(keyCode)"
        }
    }
}

// MARK: - ShortcutManager

class ShortcutManager {
    static let shared = ShortcutManager()

    private static let hotKeySignature: FourCharCode = {
        var result: FourCharCode = 0
        for char in "CUHk".utf16 { result = (result << 8) + FourCharCode(char) }
        return result
    }()

    private var registeredHotKeys: [UInt32: (ref: EventHotKeyRef, action: ShortcutAction)] = [:]
    private var nextHotKeyID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private let store: ShortcutStoring
    private let registrar: (KeyCombo, ShortcutAction, EventHotKeyID) -> (OSStatus, EventHotKeyRef?)

    private(set) var shortcuts: [ShortcutAction: KeyCombo] = [:]
    var onTogglePopover: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onNextProfile: (() -> Void)?
    var onToggleKeepAwake: (() -> Void)?
    var onStartCleaningMode: (() -> Void)?

    private convenience init() {
        self.init(store: SharedDataStore.shared)
    }

    init(store: ShortcutStoring, registrar: @escaping (KeyCombo, ShortcutAction, EventHotKeyID) -> (OSStatus, EventHotKeyRef?) = ShortcutManager.registerCarbonHotKey) {
        self.store = store
        self.registrar = registrar
        loadShortcuts()
    }

    private func loadShortcuts() {
        for action in ShortcutAction.allCases {
            if let combo = store.loadShortcut(for: action) { shortcuts[action] = combo }
        }
    }

    @discardableResult
    func setShortcut(_ combo: KeyCombo?, for action: ShortcutAction) -> ShortcutSetResult {
        if let combo {
            if let duplicate = shortcuts.first(where: { $0.key != action && $0.value == combo }) {
                return .duplicate(duplicate.key.displayName)
            }
            if combo.carbonModifiers == cmdKey | optionKey,
               combo.keyCode == kVK_ANSI_T || combo.keyCode == kVK_ANSI_V {
                return .duplicate("Top Shelf")
            }
        }
        let previous = shortcuts[action]
        shortcuts[action] = combo
        stopListening()
        startListening()
        guard combo == nil || shortcuts[action] == combo else {
            shortcuts[action] = previous
            stopListening()
            startListening()
            return .registrationFailed
        }
        store.saveShortcut(combo, for: action)
        return .success
    }

    func perform(_ combo: KeyCombo) -> Bool {
        guard let entry = registeredHotKeys.values.first(where: { shortcuts[$0.action] == combo }) else { return false }
        executeAction(entry.action)
        return true
    }

    func startListening() {
        guard eventHandler == nil else { return }
        guard !shortcuts.isEmpty else { return }
        installEventHandler()
        for (action, combo) in shortcuts { registerHotKey(combo, for: action) }
    }

    func stopListening() {
        for entry in registeredHotKeys.values { UnregisterEventHotKey(entry.ref) }
        registeredHotKeys.removeAll()
        nextHotKeyID = 1
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    private func installEventHandler() {
        var eventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()
            return manager.handleCarbonEvent(event)
        }, eventTypes.count, &eventTypes, selfPtr, &eventHandler)
    }

    private static func registerCarbonHotKey(_ combo: KeyCombo, action: ShortcutAction, id: EventHotKeyID) -> (OSStatus, EventHotKeyRef?) {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.carbonKeyCode, combo.carbonModifiers, id, GetEventDispatcherTarget(), 0, &ref)
        return (status, ref)
    }

    private func registerHotKey(_ combo: KeyCombo, for action: ShortcutAction) {
        let id = EventHotKeyID(signature: Self.hotKeySignature, id: nextHotKeyID)
        let (status, ref) = registrar(combo, action, id)
        guard status == noErr, let ref else {
            if action == .keepAwake || action == .cleaningMode { shortcuts.removeValue(forKey: action) }
            LoggingService.shared.log("ShortcutManager: Failed to register hotkey \(combo.displayString), status=\(status)")
            return
        }
        registeredHotKeys[nextHotKeyID] = (ref: ref, action: action)
        nextHotKeyID += 1
    }

    private func handleCarbonEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        guard status == noErr else { return status }
        guard hotKeyID.signature == Self.hotKeySignature, let entry = registeredHotKeys[hotKeyID.id] else { return OSStatus(eventNotHandledErr) }
        DispatchQueue.main.async { [weak self] in self?.executeAction(entry.action) }
        return noErr
    }

    private func executeAction(_ action: ShortcutAction) {
        switch action {
        case .togglePopover: onTogglePopover?()
        case .refresh: onRefresh?()
        case .openSettings: onOpenSettings?()
        case .nextProfile: onNextProfile?()
        case .keepAwake: onToggleKeepAwake?()
        case .cleaningMode: onStartCleaningMode?()
        }
    }
}
