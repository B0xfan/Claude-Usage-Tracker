//
//  TopShelfHost.swift
//  Claude Usage
//
//  John Hesch's Top Shelf, built into the usage tracker in place of the tracker's own
//  notch display ("Dynamic Island"). Everything in this folder comes from his Top Shelf app;
//  this file replaces that app's own entry point (App.swift).
//

import AppKit
import Carbon.HIToolbox

/// Top Shelf's settings stay where the separate Top Shelf app kept them (its own preferences,
/// com.johnhesch.topshelf), so John's choices carry over. Tests swap in a throwaway store.
enum TopShelfDefaults {
    static let suiteName = "com.johnhesch.topshelf"
    static var store: UserDefaults = UserDefaults(suiteName: suiteName) ?? .standard
}

/// Starts Top Shelf inside the tracker: the shelf at the notch, its shortcuts and its optional menu bar icon.
final class TopShelfHost {
    static let shared = TopShelfHost()

    private(set) var model: ShelfModel?
    private var controller: ShelfController?
    private var statusItem: NSStatusItem?
    private var hotKeys: [HotKey] = []

    /// True while the unit tests run inside the app: Top Shelf then stays off (no listener, no notch window).
    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    func start() {
        guard model == nil, !Self.isRunningTests else { return }
        let model = ShelfModel(live: true)
        self.model = model
        controller = ShelfController(model: model)
        hotKeys = [
            HotKey(keyCode: kVK_ANSI_T, modifiers: cmdKey | optionKey) { [weak model] in model?.toggle(.tray) },
            HotKey(keyCode: kVK_ANSI_V, modifiers: cmdKey | optionKey) { [weak model] in model?.toggle(.clipboard) },
        ]
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Top Shelf")
        item.menu = makeMenu(model)
        item.isVisible = model.showMenuBarIcon
        statusItem = item
        model.menuBarIconChanged = { [weak self, weak model] in
            if let model { self?.statusItem?.isVisible = model.showMenuBarIcon }
        }
        model.openSettings = { [weak model] in if let model { SettingsWindow.show(model) } }
    }

    private func makeMenu(_ model: ShelfModel) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Open Top Shelf", "t", [.command, .option]) { [weak model] in model?.open(.tray) })
        menu.addItem(item("Open Clipboard", "v", [.command, .option]) { [weak model] in model?.open(.clipboard) })
        menu.addItem(.separator())
        menu.addItem(item("Top Shelf Settings…", "", []) { [weak model] in if let model { SettingsWindow.show(model) } })
        return menu
    }

    private func item(_ title: String, _ key: String, _ mods: NSEvent.ModifierFlags, action: @escaping () -> Void) -> NSMenuItem {
        let i = MenuAction(title: title, key: key, action: action)
        i.keyEquivalentModifierMask = mods
        return i
    }
}

/// A menu item that runs a closure, so the menu needs no selector plumbing.
final class MenuAction: NSMenuItem {
    private let run: () -> Void
    init(title: String, key: String, action: @escaping () -> Void) {
        run = action
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { run() }
}

/// System-wide shortcut through Carbon, which needs no Accessibility permission. Only answers its own
/// shortcuts (signature "TSHF"), so the tracker's own shortcuts (ShortcutManager) keep working.
final class HotKey {
    static let signature: OSType = 0x5453_4846
    nonisolated(unsafe) private static var actions: [UInt32: () -> Void] = [:]
    private var ref: EventHotKeyRef?

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        if Self.actions.isEmpty { Self.installHandler() }
        let id = UInt32(Self.actions.count + 1)
        Self.actions[id] = action
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: Self.signature, id: id),
                            GetApplicationEventTarget(), 0, &ref)
    }

    private static func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == 0x5453_4846, let action = HotKey.actions[id.id] else { return OSStatus(eventNotHandledErr) }
            action()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
