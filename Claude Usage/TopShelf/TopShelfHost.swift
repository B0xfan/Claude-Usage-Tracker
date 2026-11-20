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
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}
    static let shared = TopShelfHost()

    private(set) var model: ShelfModel?
    private var controller: ShelfController?
    private var statusItem: NSStatusItem?

    /// True while the unit tests run inside the app: Top Shelf then stays off (no listener, no notch window).
    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    func start() {
        guard model == nil, !Self.isRunningTests else { return }
        let model = ShelfModel(live: true)
        self.model = model
        controller = ShelfController(model: model)
        ShortcutManager.shared.onShelf = { [weak model] action in
            switch action {
            case .shelfTray: model?.toggle(.tray)
            case .shelfClipboard: model?.toggle(.clipboard)
            case .moveScreenshots: model?.screenshots.moveAll()
            default: model?.openLibrary?()
            }
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Top Shelf")
        item.menu = makeMenu(model)
        item.isVisible = model.showMenuBarIcon
        statusItem = item
        model.menuBarIconChanged = { [weak self, weak model] in
            if let model { self?.statusItem?.isVisible = model.showMenuBarIcon }
        }
        model.openSettings = { [weak model] in if let model { SettingsWindow.show(model) } }
        model.openLibrary = { [weak model] in if let model { ClipboardLibraryWindow.show(model) } }
    }

    /// Puts the shelf back at the notch (the Settings window's "Show the shelf" button).
    func showShelf() { controller?.showAgain() }

    private func makeMenu(_ model: ShelfModel) -> NSMenu {
        let menu = ShortcutMenu(title: "")
        menu.add(MenuAction(title: "Open Top Shelf", key: "") { [weak model] in model?.open(.tray) }, .shelfTray)
        menu.add(MenuAction(title: "Open Clipboard", key: "") { [weak model] in model?.open(.clipboard) }, .shelfClipboard)
        menu.add(MenuAction(title: "Open Clipboard Library", key: "") { [weak model] in model?.openLibrary?() }, .shelfLibrary)
        menu.addItem(.separator())
        menu.addItem(MenuAction(title: "Usage Shelf Settings…", key: "") { [weak model] in if let model { SettingsWindow.show(model) } })
        return menu
    }
}

/// The menu bar menu: each item shows the shortcut John set in Settings, read again every time it opens.
final class ShortcutMenu: NSMenu, NSMenuDelegate {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}
    private var entries: [(NSMenuItem, ShortcutAction)] = []
    override init(title: String) { super.init(title: title); delegate = self }
    required init(coder: NSCoder) { fatalError() }

    func add(_ item: NSMenuItem, _ action: ShortcutAction) {
        entries.append((item, action))
        addItem(item)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for (item, action) in entries { item.showShortcut(ShortcutManager.shared.shortcuts[action]) }
    }
}

extension NSMenuItem {
    /// shortcut: only single-character keys show in the menu (letters, digits, punctuation); F-keys and arrows still work, just unlisted.
    func showShortcut(_ combo: KeyCombo?) {
        let name = combo.map { KeyCombo.keyName(for: $0.keyCode) } ?? ""
        keyEquivalent = name.count == 1 ? name.lowercased() : ""
        keyEquivalentModifierMask = keyEquivalent.isEmpty ? [] : NSEvent.ModifierFlags(rawValue: combo?.modifierFlags ?? 0)
    }
}

/// A menu item that runs a closure, so the menu needs no selector plumbing.
final class MenuAction: NSMenuItem {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}
    private let run: () -> Void
    init(title: String, key: String, action: @escaping () -> Void) {
        run = action
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { run() }
}
