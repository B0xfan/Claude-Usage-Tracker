import Combine
import SwiftUI

struct AppSettingsView: View {
    @State private var launchAtLogin = LaunchAtLoginManager.shared.isEnabled
    @StateObject private var fixedSpaces: FixedSpacesController

    init(controller: FixedSpacesController = .shared) {
        _fixedSpaces = StateObject(wrappedValue: controller)
    }

    /// Set when this sits inside a combined page, which brings its own header and scrolling.
    var embedded = false

    var body: some View {
        PageScroll(embedded: embedded) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                AppSettingsContent(
                    launchAtLoginTitle: "general.launch_at_login".localized,
                    launchAtLoginDescription: "general.launch_at_login.description".localized,
                    launchAtLogin: $launchAtLogin,
                    fixedSpaces: fixedSpaces.keepFixed,
                    onFixedSpacesChange: fixedSpaces.setFixed,
                    showHeader: !embedded
                )
            }
            .padding()
        }
        .onChange(of: launchAtLogin) { _, newValue in
            LaunchAtLoginManager.shared.setEnabled(newValue)
        }
        .onAppear { fixedSpaces.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            fixedSpaces.refresh()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            fixedSpaces.refresh()
        }
    }
}

struct AppSettingsContent: View {
    let launchAtLoginTitle: String
    let launchAtLoginDescription: String
    @Binding var launchAtLogin: Bool
    let fixedSpaces: Bool
    let onFixedSpacesChange: (Bool) -> Void
    var showHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
            if showHeader {
                SettingsPageHeader(
                    title: "section.app_settings_title".localized,
                    subtitle: "section.app_settings_desc".localized
                )
            }
            SettingsSectionCard(title: launchAtLoginTitle, subtitle: launchAtLoginDescription) {
                SettingToggle(
                    title: launchAtLoginTitle,
                    description: launchAtLoginDescription,
                    isOn: $launchAtLogin
                )
            }
            SettingsSectionCard(
                title: "Desktop Spaces",
                subtitle: "Control whether macOS keeps your Spaces where you put them"
            ) {
                SettingToggle(
                    title: "Keep Spaces in a fixed order",
                    description: "Stops macOS from rearranging your Spaces by recent use. The screen flickers briefly when this changes.",
                    isOn: Binding(get: { fixedSpaces }, set: onFixedSpacesChange)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    AppSettingsView()
        .frame(width: 520, height: 400)
}
