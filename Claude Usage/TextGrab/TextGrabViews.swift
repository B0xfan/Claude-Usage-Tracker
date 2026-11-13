import SwiftUI

/// Settings > Text Grab: status, Try it now, shortcut, copying options, language, privacy.
struct TextGrabSettingsView: View {
    @ObservedObject var controller: TextGrabController
    private let shortcuts: ShortcutManager
    @State private var shortcut: KeyCombo?
    @State private var shortcutWarning: String?
    @State private var languages: [TextGrabLanguage] = [.automatic]

    /// Shared instances are resolved in the body, on the main actor, not as default arguments.
    init(controller: TextGrabController? = nil, shortcuts: ShortcutManager? = nil) {
        let shortcuts = shortcuts ?? ShortcutManager.shared
        self.controller = controller ?? TextGrabController.shared
        self.shortcuts = shortcuts
        _shortcut = State(initialValue: shortcuts.shortcuts[.textGrab])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(title: TextGrabCopy.sectionTitle, subtitle: TextGrabCopy.sectionDescription)
                statusCard
                SettingsSectionCard(title: "Shortcut", subtitle: TextGrabCopy.shortcutCardSubtitle) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(TextGrabCopy.shortcutRowTitle).font(DesignTokens.Typography.body)
                                Text(TextGrabCopy.shortcutNote).font(DesignTokens.Typography.caption).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            ShortcutRecorderView(keyCombo: ShortcutBinding.make(for: .textGrab, combo: $shortcut, warning: $shortcutWarning, manager: shortcuts))
                                .layoutPriority(1)
                        }
                        if let shortcutWarning { ShortcutWarningView(message: shortcutWarning) }
                    }
                }
                SettingsSectionCard(title: "Copying", subtitle: "What goes on your clipboard") {
                    VStack(spacing: DesignTokens.Spacing.medium) {
                        SettingToggle(title: TextGrabCopy.keepLineBreaks, description: TextGrabCopy.keepLineBreaksDetail,
                                      isOn: Binding(get: { controller.settings.keepLineBreaks }, set: { controller.update(\.keepLineBreaks, value: $0) }))
                        Divider()
                        SettingToggle(title: TextGrabCopy.showPreview, description: TextGrabCopy.showPreviewDetail,
                                      isOn: Binding(get: { controller.settings.showPreview }, set: { controller.update(\.showPreview, value: $0) }))
                        Divider()
                        SettingToggle(title: TextGrabCopy.playSound, description: TextGrabCopy.playSoundDetail,
                                      isOn: Binding(get: { controller.settings.playSound }, set: { controller.update(\.playSound, value: $0) }))
                        Divider()
                        copiedSoundRow
                        Divider()
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(TextGrabCopy.language).font(DesignTokens.Typography.body)
                                Text(TextGrabCopy.languageDetail).font(DesignTokens.Typography.caption).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Picker("", selection: Binding(get: { controller.settings.language }, set: { controller.update(\.language, value: $0) })) {
                                ForEach(languageChoices, id: \.self) { Text($0.label).tag($0) }
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.fill").foregroundColor(.secondary)
                    Text(TextGrabCopy.privacy)
                        .font(DesignTokens.Typography.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
        }
        .onAppear {
            controller.refreshPermission()
            shortcut = shortcuts.shortcuts[.textGrab]
            languages = controller.supportedLanguages()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshPermission()
        }
    }

    /// Sound when text is copied: menu plus speaker, dimmed and disabled while sound is off.
    private var copiedSoundRow: some View {
        let enabled = controller.copiedSoundControlsEnabled
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(TextGrabCopy.copiedSound).font(DesignTokens.Typography.body)
                Text(TextGrabCopy.copiedSoundDetail).font(DesignTokens.Typography.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Picker("", selection: Binding(get: { controller.settings.copiedSound }, set: { controller.chooseCopiedSound($0) })) {
                    ForEach(TextGrabCaptureSound.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                Button { controller.previewCopiedSound() } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .help(TextGrabCopy.playCopiedSound)
                .accessibilityLabel(TextGrabCopy.playCopiedSound)
            }
            .disabled(!enabled)
        }
        .opacity(enabled ? 1 : 0.45)
    }

    /// Always includes the saved choice, even if this macOS no longer lists it.
    private var languageChoices: [TextGrabLanguage] {
        languages.contains(controller.settings.language) ? languages : languages + [controller.settings.language]
    }

    @ViewBuilder private var statusCard: some View {
        if controller.permissionState == .ready {
            SettingsContentCard {
                HStack(spacing: 12) {
                    Circle().fill(Color.green).frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TextGrabCopy.readyTitle).font(DesignTokens.Typography.body).fontWeight(.semibold)
                        Text(TextGrabCopy.readyDetail).font(DesignTokens.Typography.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button(TextGrabCopy.tryItNow) { tryItNow() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!controller.canTryNow)
                }
            }
        } else {
            SettingsSectionCard(title: TextGrabCopy.permissionTitle, subtitle: TextGrabCopy.permissionSubtitle) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(TextGrabCopy.permissionHeading).font(DesignTokens.Typography.body).fontWeight(.semibold)
                        Text(TextGrabCopy.permissionExplanation).font(DesignTokens.Typography.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 10) {
                        Button(TextGrabCopy.openSettingsButton) { controller.openScreenRecordingSettings() }
                            .buttonStyle(.borderedProminent)
                        Button(TextGrabCopy.notNow) { controller.consumeSettingsRequest() }
                    }
                    Text(TextGrabCopy.reopenNote).font(DesignTokens.Typography.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(TextGrabCopy.notNowDetail).font(DesignTokens.Typography.caption).foregroundColor(.secondary)
                    Text(TextGrabCopy.tryItNowUnavailable).font(DesignTokens.Typography.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    private func tryItNow() {
        // Settings would cover the text he wants; it simply stays behind the dimmed overlay.
        if controller.start() == .permissionMissing { controller.consumeSettingsRequest() }
    }
}

/// The Copied / No text found note under the menu bar. Hover keeps it, a click dismisses it.
struct TextGrabToastView: View {
    let content: TextGrabToastContent
    var onHover: (Bool) -> Void = { _ in }
    var onClick: () -> Void = {}

    private var symbol: String {
        switch content {
        case .copied: return "checkmark.circle.fill"
        case .reading: return "text.viewfinder"
        case .noText: return "questionmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch content {
        case .copied: return .green
        case .reading: return .accentColor
        case .noText, .failed: return .orange
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundColor(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(content.title).font(.system(size: 13, weight: .semibold))
                if let detail = content.detail {
                    Text(detail).font(.system(size: 12)).foregroundColor(.secondary)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(width: TextGrabToastLayout.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
        .contentShape(Rectangle())
        .onHover { onHover($0) }
        .onTapGesture { onClick() }
    }
}
