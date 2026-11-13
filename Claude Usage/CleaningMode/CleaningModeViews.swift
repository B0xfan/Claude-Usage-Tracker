import SwiftUI

struct CleaningModeSettingsView: View {
    @ObservedObject var controller: CleaningModeController

    init(controller: CleaningModeController = .shared) { self.controller = controller }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(title: "Cleaning Mode", subtitle: "Clean your keyboard and screen without accidental input")
                SettingsSectionCard(title: "Cleaning session", subtitle: "Your Mac and displays stay on until the session ends") {
                    VStack(spacing: DesignTokens.Spacing.medium) {
                        settingRow(title: "Automatically end after", description: "Always ends, even if you do nothing. There is no unlimited option.") {
                            Picker("", selection: Binding(get: { controller.settings.duration }, set: { controller.update(\.duration, value: $0) })) {
                                ForEach(CleaningDuration.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }
                        Divider()
                        settingRow(title: "Screen while cleaning", description: "Choose a dark overlay to see smudges, or keep your desktop visible.") {
                            Picker("", selection: Binding(get: { controller.settings.screenAppearance }, set: { controller.update(\.screenAppearance, value: $0) })) {
                                ForEach(CleaningScreenAppearance.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden().pickerStyle(.segmented).fixedSize()
                        }
                        Divider()
                        SettingToggle(title: "Block trackpad and mouse", description: "Also blocks movement, clicks and scrolling. Holding a button for 3 seconds still ends cleaning.", isOn: Binding(get: { controller.settings.blockPointer }, set: { controller.update(\.blockPointer, value: $0) }))
                    }
                }
                permissionCard
                HStack(alignment: .bottom, spacing: 18) {
                    Text(CleaningModeCopy.safety)
                        .font(DesignTokens.Typography.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Start Cleaning Mode") {
                        if controller.start(now: Date().timeIntervalSinceReferenceDate) == .permissionMissing {
                            NotificationCenter.default.post(name: .showCleaningModeSettings, object: nil)
                        }
                    }
                    .buttonStyle(.borderedProminent).disabled(!controller.canStart)
                }
            }
            .padding(28)
        }
        .onAppear { controller.settingsBecameActive() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.settingsBecameActive()
        }
    }

    @ViewBuilder private var permissionCard: some View {
        SettingsSectionCard(title: controller.permissionState == .ready ? "Permission ready" : "Permission needed", subtitle: controller.permissionState == .ready ? "Usage Shelf can pause input only after you start cleaning" : "Usage Shelf cannot pause your keyboard yet") {
            VStack(alignment: .leading, spacing: 12) {
                switch controller.permissionState {
                case .accessibilityNeeded:
                    permissionExplanation(title: "Why Usage Shelf needs access", text: "Usage Shelf needs this only while Cleaning Mode is on so your keystrokes and cleaning gestures do not reach other apps. It does not save what you type.")
                    Button("Open Accessibility Settings", action: controller.openAccessibilitySettings)
                    permissionReturnText
                case .inputMonitoringNeeded:
                    permissionExplanation(title: "Your Mac also needs Input Monitoring for Usage Shelf", text: "This allows Usage Shelf to pause keyboard input during cleaning. It is used only while Cleaning Mode is on. Your typing is not saved or sent anywhere.")
                    Button("Open Input Monitoring Settings", action: controller.openInputMonitoringSettings)
                    permissionReturnText
                case .relaunchNeeded:
                    permissionExplanation(title: "Quit and reopen Usage Shelf", text: "macOS needs you to quit and reopen Usage Shelf before the new permission takes effect. Nothing starts by itself.")
                case .ready:
                    Label("Permission ready", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                }
                Text("Not now. Nothing changes if you leave this off. The rest of Usage Shelf keeps working.")
                    .font(DesignTokens.Typography.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                if !controller.canStart { Text("Start is unavailable").font(DesignTokens.Typography.caption).foregroundColor(.secondary) }
            }
        }
    }

    private func permissionExplanation(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(DesignTokens.Typography.body).fontWeight(.semibold)
            Text(text).font(DesignTokens.Typography.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionReturnText: some View {
        Text("Turn on Usage Shelf in System Settings, then return here. Your Mac may ask you to quit and reopen Usage Shelf.")
            .font(DesignTokens.Typography.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func settingRow<Control: View>(title: String, description: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(DesignTokens.Typography.body)
                Text(description).font(DesignTokens.Typography.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control().layoutPriority(1)
        }
    }
}

struct CleaningSessionView: View {
    let appearance: CleaningScreenAppearance
    var blockPointer = true
    let remaining: TimeInterval
    let holdProgress: Double
    /// "or press ⌃⌥⌘C again" with John's real combo; nil when no on/off shortcut is recorded.
    var offShortcutHint: String? = nil

    private var countdown: String {
        let total = Int(ceil(max(0, remaining)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        Group {
            if appearance == .dimmed {
                ZStack {
                    Color.black.opacity(0.72).ignoresSafeArea()
                    VStack(spacing: 14) {
                        Image(systemName: "sparkles").font(.system(size: 26))
                        Text("Cleaning Mode").font(.system(size: 28, weight: .semibold))
                        Text(blockPointer ? "Keyboard and trackpad are paused" : "Keyboard is paused").font(.system(size: 15)).foregroundStyle(.secondary)
                        Text("Ends in \(countdown)").font(.system(size: 34, weight: .semibold)).monospacedDigit().padding(.top, 4)
                        exitInstructions
                        Text("Ends automatically. Your power button and Touch ID still work.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(28).frame(maxWidth: 440)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.1).opacity(0.95)))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.2)))
                    .foregroundColor(.white)
                }
            } else {
                VStack {
                    Text("Your desktop stays visible. This is not a privacy screen.")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.black.opacity(0.65))).padding(.top, 10)
                    VStack(spacing: 9) {
                        HStack(spacing: 16) {
                            Label("Cleaning Mode", systemImage: "sparkles").font(.system(size: 16, weight: .semibold))
                            Text(countdown).font(.system(size: 18, weight: .semibold)).monospacedDigit().foregroundColor(.green)
                        }
                        exitInstructions
                        Text("Ends automatically. Power button and Touch ID still work.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .padding(16).frame(maxWidth: 480)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Color(white: 0.1).opacity(0.96)))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.25)))
                    .foregroundColor(.white).padding(.top, 38)
                    Spacer()
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var exitInstructions: some View {
        VStack(spacing: 8) {
            Text(CleaningModeCopy.holdInstruction)
                .font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(.black).padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule().fill(Color.white).frame(width: geometry.size.width * min(1, max(0, holdProgress)))
                }
            }
            .frame(height: 4).padding(.horizontal, 24)
            if let offShortcutHint {
                Text(offShortcutHint)
                    .font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.white.opacity(0.85))
            }
        }
    }
}
