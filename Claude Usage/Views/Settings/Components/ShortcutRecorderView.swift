//
//  ShortcutRecorderView.swift
//  Claude Usage
//
//  Reusable keyboard shortcut recorder component
//

import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var keyCombo: KeyCombo?
    var previewRecording = false

    static func accepts(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        !modifiers.intersection([.command, .option, .control, .shift]).isEmpty && ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }
    @State private var isRecording = false
    @State private var localMonitor: Any?

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            // Display area
            Button {
                if isRecording || previewRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.extraSmall) {
                    if isRecording || previewRecording {
                        Text("shortcuts.recording".localized)
                            .font(DesignTokens.Typography.body)
                            .foregroundColor(.accentColor)
                    } else if let combo = keyCombo {
                        HStack(spacing: 4) {
                            ForEach(combo.displayComponents, id: \.self) { component in
                                Text(component)
                                    .fixedSize()
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    } else {
                        Text("shortcuts.record".localized)
                            .font(DesignTokens.Typography.body)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minWidth: 120)
                .padding(.horizontal, DesignTokens.Spacing.medium)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                        .fill((isRecording || previewRecording) ? Color.accentColor.opacity(0.1) : DesignTokens.Colors.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                        .strokeBorder(
                            (isRecording || previewRecording) ? Color.accentColor : DesignTokens.Colors.cardBorder,
                            lineWidth: isRecording || previewRecording ? 2 : 1
                        )
                )
            }
            .buttonStyle(.plain)

            // Clear button
            if keyCombo != nil {
                Button {
                    keyCombo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("shortcuts.clear".localized)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels recording
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            // Require at least one modifier key
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !modifiers.isEmpty else {
                return nil // Ignore plain keys
            }

            // Don't capture modifier-only presses (no actual key)
            let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            guard !modifierOnlyKeyCodes.contains(event.keyCode) else {
                return event
            }

            keyCombo = KeyCombo(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ShortcutRecorderView(keyCombo: .constant(nil))
        ShortcutRecorderView(keyCombo: .constant(
            KeyCombo(keyCode: 15, modifierFlags: [.command, .shift])
        ))
    }
    .padding()
    .frame(width: 300)
}

enum ShortcutWarningStyle {
    static func textColor(for scheme: ColorScheme) -> NSColor {
        scheme == .dark ? .systemOrange : NSColor(red: 0.43, green: 0.20, blue: 0.00, alpha: 1)
    }

    static func backgroundColor(for scheme: ColorScheme) -> NSColor {
        let background = scheme == .dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.97, alpha: 1)
        guard let foreground = textColor(for: scheme).usingColorSpace(.sRGB),
              let background = background.usingColorSpace(.sRGB) else { return background }
        func composite(_ foreground: CGFloat, _ background: CGFloat) -> CGFloat { foreground * 0.08 + background * 0.92 }
        return NSColor(srgbRed: composite(foreground.redComponent, background.redComponent), green: composite(foreground.greenComponent, background.greenComponent), blue: composite(foreground.blueComponent, background.blueComponent), alpha: 1)
    }

    static var text: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let scheme: ColorScheme = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
            return textColor(for: scheme)
        })
    }
}

struct ShortcutWarningView: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).fixedSize(horizontal: false, vertical: true)
        }
        .font(DesignTokens.Typography.caption)
        .foregroundColor(ShortcutWarningStyle.text)
        .padding(DesignTokens.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.small).fill(ShortcutWarningStyle.text.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.small).strokeBorder(ShortcutWarningStyle.text.opacity(0.3)))
    }
}
