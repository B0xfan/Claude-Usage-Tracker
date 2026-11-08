import SwiftUI

@MainActor
enum CleaningModePreviewRenderer {
    static func renderSettings(controller: CleaningModeController, scheme: ColorScheme, to url: URL) throws {
        let content = HStack(spacing: 0) {
            AppSettingsSection(selectedSection: .constant(.cleaningMode))
                .padding(12).frame(width: 190, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .top).background(previewSidebar(scheme))
            CleaningModeSettingsView(controller: controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(scheme == .dark ? Color.black.opacity(0.15) : Color.white.opacity(0.3))
        }
        .frame(width: 720, height: 1000).background(previewSettings(scheme))
        try render(content, scheme: scheme, size: CGSize(width: 720, height: 1000), to: url)
    }

    static func renderActive(controller: CleaningModeController, scheme: ColorScheme, to url: URL) throws {
        let view = ZStack {
            LinearGradient(colors: scheme == .dark ? [.black, .indigo] : [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            CleaningSessionView(appearance: controller.settings.screenAppearance, blockPointer: controller.settings.blockPointer, remaining: controller.displayRemaining ?? 42, holdProgress: controller.displayHoldProgress)
        }
        .frame(width: 1100, height: 700)
        try render(view, scheme: scheme, size: CGSize(width: 1100, height: 700), to: url)
    }

    static func renderContextMenu(scheme: ColorScheme, to url: URL) throws {
        let view = VStack(alignment: .leading, spacing: 0) {
            previewMenuRow("Keep awake")
            Divider().padding(.vertical, 4)
            previewMenuRow("Refresh")
            Divider().padding(.vertical, 4)
            previewMenuRow("Start Cleaning Mode")
            Divider().padding(.vertical, 4)
            previewMenuRow("Settings                         ⌘,")
            previewMenuRow("Quit Usage Shelf                 ⌘Q")
        }
        .padding(.vertical, 5).frame(width: 250)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
        try render(view, scheme: scheme, size: nil, to: url)
    }

    static func renderShortcuts(scheme: ColorScheme, to url: URL) throws {
        let rows = VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
            SettingsPageHeader(title: "Shortcuts", subtitle: "Keyboard shortcuts for common actions")
            CleaningShortcutPreviewContent()
            Text("The shortcut never replaces the timer or the 3-second mouse or trackpad hold.")
                .font(DesignTokens.Typography.caption).foregroundColor(.secondary)
        }.padding(28)
        let content = HStack(spacing: 0) {
            AppSettingsSection(selectedSection: .constant(.shortcuts)).padding(12)
                .frame(width: 190, alignment: .topLeading).frame(maxHeight: .infinity, alignment: .top).background(previewSidebar(scheme))
            rows.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(scheme == .dark ? Color.black.opacity(0.15) : Color.white.opacity(0.3))
        }.frame(width: 720, height: 800).background(previewSettings(scheme))
        try render(content, scheme: scheme, size: CGSize(width: 720, height: 800), to: url)
    }

    private static func previewMenuRow(_ title: String) -> some View {
        HStack { Text(title).font(.system(size: 13)); Spacer() }.padding(.horizontal, 14).padding(.vertical, 5)
    }

    private static func previewSettings(_ scheme: ColorScheme) -> some View {
        (scheme == .dark ? Color(white: 0.12) : Color(white: 0.97))
            .overlay((scheme == .dark ? Color.black : Color.white).opacity(scheme == .dark ? 0.35 : 0.4))
    }

    private static func previewSidebar(_ scheme: ColorScheme) -> some View {
        (scheme == .dark ? Color(white: 0.12) : Color(white: 0.97))
            .overlay((scheme == .dark ? Color.black : Color.white).opacity(scheme == .dark ? 0.55 : 0.5))
    }

    private static func render<Content: View>(_ view: Content, scheme: ColorScheme, size: CGSize?, to url: URL) throws {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: size ?? hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw NSError(domain: "CleaningModePreviewRenderer", code: 1)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "CleaningModePreviewRenderer", code: 2)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

/// Deterministic detached rendering. Uses the same row components as Shortcuts
/// Settings but never reads a real profile, creates a global hotkey, or an event tap.
struct CleaningShortcutPreviewContent: View {
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.small) {
            row(icon: "person.and.arrow.left.and.arrow.right", title: "Next profile", description: "Switch to the next usage profile", combo: nil)
            row(icon: "sun.max", title: "Keep awake", description: "Toggle Keep awake with the last duration", combo: KeyCombo(keyCode: 40, modifierFlags: [.control, .option, .command]))
            row(icon: "sparkles", title: "Start Cleaning Mode", description: "Start with your saved cleaning choices. No shortcut is set by default.", combo: nil)
        }
    }

    private func row(icon: String, title: String, description: String, combo: KeyCombo?) -> some View {
        HStack {
            HStack(spacing: DesignTokens.Spacing.iconText) {
                Image(systemName: icon).font(.system(size: DesignTokens.Icons.standard)).foregroundColor(.accentColor).frame(width: DesignTokens.Spacing.iconFrame)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DesignTokens.Typography.body)
                    Text(description).font(DesignTokens.Typography.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            ShortcutRecorderView(keyCombo: .constant(combo))
        }
        .padding(DesignTokens.Spacing.medium)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.small).fill(DesignTokens.Colors.cardBackground))
    }
}
