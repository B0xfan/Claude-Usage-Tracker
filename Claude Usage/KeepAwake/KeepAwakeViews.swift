import SwiftUI
import Carbon
import AppKit
import UniformTypeIdentifiers

struct KeepAwakePopoverSection: View {
    @ObservedObject var controller: KeepAwakeController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep awake")
                        .font(.system(size: 12, weight: .semibold))
                    if controller.isActive {
                        Text(controller.isPaused ? "Paused while locked" : controller.popupTime(at: controller.currentTimeForDisplay))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(nsColor: controller.settings.markColor.nsColor))
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(get: { controller.isActive }, set: { _ in controller.toggle() }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            KeepAwakeDurationPicker(controller: controller)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }
}

struct KeepAwakeDurationPicker: View {
    @ObservedObject var controller: KeepAwakeController

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 44), spacing: 5)]
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(KeepAwakeDuration.allCases) { duration in
                Button {
                    controller.update(\.duration, value: duration)
                    if controller.isActive { controller.start(duration: duration, now: Date().timeIntervalSinceReferenceDate) }
                } label: {
                    Text(duration.label)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundColor(controller.selectedDuration == duration ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(controller.selectedDuration == duration ? Color.accentColor : Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct KeepAwakeSettingsView: View {
    @ObservedObject var controller: KeepAwakeController
    @State private var batteryLevel = 10.0

    init(controller: KeepAwakeController = .shared) {
        self.controller = controller
        _batteryLevel = State(initialValue: Double(controller.settings.batteryLevel))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "Keep Awake",
                    subtitle: "Stop your Mac from sleeping when you need it awake. Sleep returns to normal when the timer ends or you quit Usage Shelf."
                )

                SettingsSectionCard(title: "Automatic start", subtitle: "Turn keep-awake on by itself when one of these is true") {
                    VStack(spacing: DesignTokens.Spacing.medium) {
                        SettingToggle(title: "When an external display is connected", description: "Useful at a desk with a monitor plugged in", isOn: binding(\.displayTrigger))
                        SettingToggle(title: "When the Mac is on power", description: "Not while running on battery alone", isOn: binding(\.powerTrigger))
                        VStack(alignment: .leading, spacing: 8) {
                            SettingToggle(title: "When chosen apps are running", description: "Pick apps below. Keep-awake turns on while any of them is open.", isOn: binding(\.appsTrigger))
                            if controller.settings.appsTrigger {
                                VStack(alignment: .leading, spacing: 6) {
                                    if controller.chosenApps.isEmpty {
                                        Text("No apps chosen").font(.system(size: 11)).foregroundColor(.secondary)
                                    } else {
                                        ForEach(controller.chosenApps) { app in
                                            HStack {
                                                Text(app.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                                Spacer()
                                                Button("Remove") { controller.setChosenApps(controller.chosenApps.filter { $0 != app }) }
                                                    .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    Button("Add app…", action: chooseApp)
                                        .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(.accentColor)
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                            }
                        }
                    }
                }

                SettingsSectionCard(title: "Options", subtitle: "How keep-awake behaves day to day") {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                        SettingToggle(title: "Start when Usage Shelf launches", description: "Uses your last chosen duration", isOn: binding(\.startOnLaunch))
                        SettingToggle(title: "Show time left beside the menu bar icon", description: "Example: orange mark + 1:42 next to your rings", isOn: binding(\.showTime))
                        SettingToggle(title: "Allow the display to sleep", description: "Screen can go dark; the Mac itself stays awake", isOn: binding(\.allowDisplaySleep))
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 6) {
                                SettingToggle(title: "Slight pointer movement", description: controller.pointerPermissionGranted ? "Off by default. Moves the pointer a tiny bit so some apps think you are still there." : "Off by default. Needs Accessibility permission. Usage Shelf never asks at launch.", isOn: binding(\.pointerMovement))
                                Text("Needs permission")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange))
                            }
                            if !controller.pointerPermissionGranted {
                                Button("Open Accessibility Settings", action: controller.openAccessibilitySettings)
                                    .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(.accentColor)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Active mark color").font(DesignTokens.Typography.body)
                            Text("Color of the small keep-awake mark while it is on").font(DesignTokens.Typography.caption).foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                ForEach(KeepAwakeMarkColor.allCases) { color in
                                    Button { controller.update(\.markColor, value: color) } label: {
                                        Circle().fill(Color(nsColor: color.nsColor)).frame(width: 18, height: 18)
                                            .overlay(Circle().stroke(Color.primary, lineWidth: controller.settings.markColor == color ? 2 : 0).padding(-3))
                                    }
                                    .buttonStyle(.plain).accessibilityLabel(color.rawValue.capitalized)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            SettingToggle(title: "Turn off below battery level", description: "While on battery, end keep-awake at this percent so the Mac can sleep and save power", isOn: binding(\.batteryCutoff))
                            if controller.settings.batteryCutoff {
                                HStack(spacing: 8) {
                                    Stepper(value: $batteryLevel, in: 1...50, step: 1) {
                                        Text("\(Int(batteryLevel))%").font(.system(size: 12, weight: .semibold))
                                    }
                                    Text("default 10%").font(.system(size: 11)).foregroundColor(.secondary)
                                }
                                .onChange(of: batteryLevel) { _, value in controller.update(\.batteryLevel, value: Int(value)) }
                            }
                        }
                    }
                }

                SettingsSectionCard(title: "While locked", subtitle: "Keep-awake pauses when the Mac is locked and resumes the remaining time when you unlock. Quitting Usage Shelf always lets the Mac sleep again.") {
                    EmptyView()
                }
            }
            .padding()
        }
    }

    private func binding(_ keyPath: WritableKeyPath<KeepAwakeSettings, Bool>) -> Binding<Bool> {
        Binding(get: { controller.settings[keyPath: keyPath] }, set: { controller.update(keyPath, value: $0) })
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        var apps = controller.chosenApps.filter { $0.bundleID != bundleID }
        apps.append(KeepAwakeApp(bundleID: bundleID, name: name))
        controller.setChosenApps(apps)
    }
}

@MainActor
enum KeepAwakePreviewRenderer {
    static func isMostlyWhite(_ data: Data) -> Bool {
        guard let image = NSImage(data: data),
              let bitmap = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()) else { return true }
        var white = 0
        let samples = 400
        for index in 0..<samples {
            let x = index % 20 * max(1, bitmap.pixelsWide / 20)
            let y = index / 20 * max(1, bitmap.pixelsHigh / 20)
            if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
               color.redComponent > 0.9 && color.greenComponent > 0.9 && color.blueComponent > 0.9 {
                white += 1
            }
        }
        return white > samples / 2
    }

    static func renderPopup(controller: KeepAwakeController, scheme: ColorScheme, to url: URL) throws {
        let view = VStack(spacing: 0) {
            KeepAwakePopoverSection(controller: controller)
        }
        .frame(width: 280)
        .padding(1)
        .background(Color(nsColor: .windowBackgroundColor))
        try render(view, scheme: scheme, size: nil, to: url)
    }

    static func renderSettings(controller: KeepAwakeController, scheme: ColorScheme, to url: URL) throws {
        // Use the real Settings page and its vibrancy backgrounds, but no NSWindow.
        // A hidden SettingsWindowBuilder window keeps the XCTest host alive on macOS 27.
        let content = HStack(spacing: 0) {
            AppSettingsSection(selectedSection: .constant(.keepAwake))
                .padding(12)
                .frame(width: 190, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(SidebarVisualEffect())
            KeepAwakeSettingsView(controller: controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(scheme == .dark ? Color.black.opacity(0.15) : Color.white.opacity(0.3))
        }
        .frame(width: 720, height: 1050)
        .background(SettingsBackground())
        let hosting = NSHostingView(rootView: content.environment(\.colorScheme, scheme))
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: CGSize(width: 720, height: 1050))
        try capture(hosting, to: url)
    }

    static func renderContextMenu(controller: KeepAwakeController, scheme: ColorScheme, to url: URL) throws {
        let view = VStack(alignment: .leading, spacing: 0) {
            menuRow("Keep awake", checked: controller.isActive, scheme: scheme)
            Divider().padding(.vertical, 4)
            menuRow("Refresh", scheme: scheme)
            Divider().padding(.vertical, 4)
            menuRow("Settings                                      ⌘,", scheme: scheme)
            menuRow("Quit                                               ⌘Q", scheme: scheme)
        }
        .padding(.vertical, 5)
        .frame(width: 200)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
        try render(view, scheme: scheme, size: nil, to: url)
    }

    private static func menuRow(_ title: String, checked: Bool = false, scheme: ColorScheme) -> some View {
        HStack(spacing: 8) {
            Text(checked ? "✓" : " ").frame(width: 12)
            Text(title).font(.system(size: 13))
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
    }

    static func renderShortcuts(manager: ShortcutManager, state: ShortcutPreviewState, scheme: ColorScheme, to url: URL) throws {
        let example = KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.control, .option, .command])
        let clash = KeyCombo(keyCode: UInt16(kVK_ANSI_T), modifierFlags: [.command, .option])
        let combo = state == .set ? example : state == .clash ? clash : nil
        let rows = VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
            SettingsPageHeader(title: "Keyboard Shortcuts", subtitle: "Set global shortcuts for common actions")
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                Text("Keyboard Shortcuts").font(DesignTokens.Typography.sectionTitle)
                VStack(spacing: DesignTokens.Spacing.small) {
                    shortcutPreviewRow(icon: "rectangle.portrait.and.arrow.right", title: "Toggle popover", description: "Show or hide the usage panel", combo: nil)
                    shortcutPreviewRow(icon: "arrow.clockwise", title: "Refresh usage", description: "Get the latest usage data", combo: nil)
                    shortcutPreviewRow(icon: "gearshape", title: "Open Settings", description: "Open the Settings window", combo: nil)
                    shortcutPreviewRow(icon: "person.and.arrow.left.and.arrow.right", title: "Next profile", description: "Switch to the next profile", combo: nil)
                    shortcutPreviewRow(icon: "sun.max", title: "Keep awake", description: state == .recording ? "Escape cancels. A modifier is required." : "Turn Keep awake on with the last duration, or turn it off", combo: combo, recording: state == .recording)
                    if state == .clash {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Already used by Top Shelf. Choose another shortcut.").fixedSize(horizontal: false, vertical: true)
                        }
                        .font(DesignTokens.Typography.caption).foregroundColor(.orange).padding(DesignTokens.Spacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.small).fill(Color.orange.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.small).strokeBorder(Color.orange.opacity(0.3)))
                    }
                }
            }
            HStack(spacing: DesignTokens.Spacing.medium) {
                Image(systemName: "info.circle.fill").foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Global shortcuts").font(DesignTokens.Typography.body)
                    Text("Shortcuts work in any app. Use at least one modifier: Command, Option, Control, or Shift. No Accessibility permission is needed.")
                        .font(DesignTokens.Typography.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DesignTokens.Spacing.medium)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.small).fill(Color.blue.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.small).strokeBorder(Color.blue.opacity(0.2)))
        }
        .padding(28)
        let content = HStack(spacing: 0) {
            AppSettingsSection(selectedSection: .constant(.shortcuts)).padding(12).frame(width: 190, alignment: .topLeading).frame(maxHeight: .infinity, alignment: .top).background(SidebarVisualEffect())
            rows.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(scheme == .dark ? Color.black.opacity(0.15) : Color.white.opacity(0.3))
        }
        .frame(width: 720, height: 800).background(SettingsBackground())
        let hosting = NSHostingView(rootView: content.environment(\.colorScheme, scheme))
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: CGSize(width: 720, height: 800))
        try capture(hosting, to: url)
    }

    private static func shortcutPreviewRow(icon: String, title: String, description: String, combo: KeyCombo?, recording: Bool = false) -> some View {
        HStack {
            HStack(spacing: DesignTokens.Spacing.iconText) {
                Image(systemName: icon).font(.system(size: DesignTokens.Icons.standard)).foregroundColor(.accentColor).frame(width: DesignTokens.Spacing.iconFrame)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DesignTokens.Typography.body)
                    Text(description).font(DesignTokens.Typography.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            ShortcutRecorderView(keyCombo: .constant(combo), previewRecording: recording)
        }
        .padding(DesignTokens.Spacing.medium)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.small).fill(DesignTokens.Colors.cardBackground))
    }

    static func renderMenuBarV3(controller: KeepAwakeController, active: Bool, scheme: ColorScheme, to url: URL) throws {
        let isDark = scheme == .dark
        let renderer = MenuBarIconRenderer()
        let rings = renderer.createCombinedRingsIcon(sessionPercentage: 25, weekPercentage: 50, sessionLevel: .safe, weekLevel: .safe, isDarkMode: isDark)
        if active { controller.start(duration: .untilOff, now: 0) } else { controller.stop() }
        let accessory = active ? controller.menuBarAccessoryImage(isDarkMode: isDark) : nil
        let image = renderer.appendingKeepAwakeAccessory(accessory, to: rings)
        let scale: CGFloat = 4
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * scale), pixelsHigh: Int(image.size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: image.size.width, height: image.size.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        (isDark ? NSColor.black : NSColor.white).setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "KeepAwakePreviewRenderer", code: 2) }
        try data.write(to: url)
    }

    private static func capture(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "KeepAwakePreviewRenderer", code: 1)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "KeepAwakePreviewRenderer", code: 2)
        }
        try data.write(to: url)
    }

    private static func render<Content: View>(_ view: Content, scheme: ColorScheme, size: CGSize?, to url: URL) throws {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        let fitting = size ?? hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: fitting)
        hosting.layoutSubtreeIfNeeded()
        try capture(hosting, to: url)
    }
}
