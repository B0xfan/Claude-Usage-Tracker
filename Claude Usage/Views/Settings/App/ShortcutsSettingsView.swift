//
//  ShortcutsSettingsView.swift
//  Claude Usage
//
//  Keyboard shortcuts configuration settings
//

import SwiftUI

struct ShortcutsSettingsView: View {
    @State private var togglePopoverCombo: KeyCombo? = ShortcutManager.shared.shortcuts[.togglePopover]
    @State private var refreshCombo: KeyCombo? = ShortcutManager.shared.shortcuts[.refresh]
    @State private var openSettingsCombo: KeyCombo? = ShortcutManager.shared.shortcuts[.openSettings]
    @State private var keepAwakeCombo: KeyCombo? = ShortcutManager.shared.shortcuts[.keepAwake]
    @State private var keepAwakeWarning: String?
    @State private var nextProfileCombo: KeyCombo? = ShortcutManager.shared.shortcuts[.nextProfile]
    @State private var cleaningModeCombo: KeyCombo? = ShortcutManager.shared.shortcuts[.cleaningMode]
    @State private var cleaningModeWarning: String?
    /// The shelf's shortcuts, moved here from the old Dynamic Island page so every shortcut is in one list.
    private static let shelfActions: [(ShortcutAction, String, String)] = [
        (.shelfTray, "tray", "Open the shelf at the notch"),
        (.shelfClipboard, "doc.on.clipboard", "Open the shelf on its clipboard page"),
        (.shelfLibrary, "books.vertical", "The whole clipboard history in a big window"),
        (.moveScreenshots, "folder", "Move screenshots to the folder set on the Screenshots page"),
    ]
    @State private var shelfCombos: [ShortcutAction: KeyCombo?] = Dictionary(uniqueKeysWithValues:
        shelfActions.map { ($0.0, ShortcutManager.shared.shortcuts[$0.0]) })
    @State private var shelfWarning: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                // Page Header
                SettingsPageHeader(
                    title: "shortcuts.title".localized,
                    subtitle: "shortcuts.subtitle".localized
                )

                // Shortcuts Section
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                    Text("shortcuts.title".localized)
                        .font(DesignTokens.Typography.sectionTitle)

                    VStack(spacing: DesignTokens.Spacing.small) {
                        // Toggle Popover
                        shortcutRow(
                            icon: "rectangle.portrait.and.arrow.right",
                            title: "shortcuts.open_popover".localized,
                            description: "shortcuts.open_popover_desc".localized,
                            combo: $togglePopoverCombo,
                            action: .togglePopover
                        )

                        // Refresh Usage
                        shortcutRow(
                            icon: "arrow.clockwise",
                            title: "shortcuts.refresh".localized,
                            description: "shortcuts.refresh_desc".localized,
                            combo: $refreshCombo,
                            action: .refresh
                        )

                        // Open Settings
                        shortcutRow(
                            icon: "gearshape",
                            title: "shortcuts.open_settings".localized,
                            description: "shortcuts.open_settings_desc".localized,
                            combo: $openSettingsCombo,
                            action: .openSettings
                        )

                        // Next Profile
                        shortcutRow(
                            icon: "person.and.arrow.left.and.arrow.right",
                            title: "shortcuts.next_profile".localized,
                            description: "shortcuts.next_profile_desc".localized,
                            combo: $nextProfileCombo,
                            action: .nextProfile
                        )
                        ForEach(Self.shelfActions.indices, id: \.self) { i in
                            let (action, icon, description) = Self.shelfActions[i]
                            shortcutRow(
                                icon: icon,
                                title: action.displayName,
                                description: description,
                                combo: Binding(get: { shelfCombos[action] ?? nil }, set: { shelfCombos[action] = $0 }),
                                action: action,
                                warning: $shelfWarning
                            )
                        }
                        if let shelfWarning { ShortcutWarningView(message: shelfWarning) }
                        // Keep awake
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                            shortcutRow(
                                icon: "sun.max",
                                title: "Keep awake",
                                description: "Turn Keep awake on with the last duration, or turn it off",
                                combo: $keepAwakeCombo,
                                action: .keepAwake,
                                warning: $keepAwakeWarning
                            )
                            if let keepAwakeWarning {
                                ShortcutWarningView(message: keepAwakeWarning)
                            }
                        }
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                            shortcutRow(
                                icon: "sparkles",
                                title: "Start Cleaning Mode",
                                description: "Start with your saved cleaning choices. No shortcut is set by default.",
                                combo: $cleaningModeCombo,
                                action: .cleaningMode,
                                warning: $cleaningModeWarning
                            )
                            if let cleaningModeWarning { ShortcutWarningView(message: cleaningModeWarning) }
                            Text("The shortcut never replaces the timer or the 3-second mouse or trackpad hold.")
                                .font(DesignTokens.Typography.caption).foregroundColor(.secondary)
                        }
                    }
                }

                // Info Box
                HStack(spacing: DesignTokens.Spacing.medium) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: DesignTokens.Icons.standard))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("shortcuts.info_title".localized)
                            .font(DesignTokens.Typography.body)
                        Text("shortcuts.info_desc".localized)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(DesignTokens.Spacing.medium)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                        .fill(Color.blue.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                        .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                )

                Spacer()
            }
            .padding(28)
        }
    }

    @ViewBuilder
    private func shortcutRow(
        icon: String,
        title: String,
        description: String,
        combo: Binding<KeyCombo?>,
        action: ShortcutAction,
        warning: Binding<String?>? = nil
    ) -> some View {
        HStack {
            HStack(spacing: DesignTokens.Spacing.iconText) {
                Image(systemName: icon)
                    .font(.system(size: DesignTokens.Icons.standard))
                    .foregroundColor(.accentColor)
                    .frame(width: DesignTokens.Spacing.iconFrame)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignTokens.Typography.body)
                    Text(description)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            ShortcutRecorderView(keyCombo: Binding(
                get: { combo.wrappedValue },
                set: { newValue in
                    let result = ShortcutManager.shared.setShortcut(newValue, for: action)
                    warning?.wrappedValue = resultWarning(result, combo: newValue ?? KeyCombo(keyCode: 0, modifierFlags: []))
                    combo.wrappedValue = ShortcutManager.shared.shortcuts[action]
                }
            ))
        }
        .padding(DesignTokens.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                .fill(DesignTokens.Colors.cardBackground)
        )
    }
}

#Preview {
    ShortcutsSettingsView()
        .frame(width: 520, height: 680)
}
