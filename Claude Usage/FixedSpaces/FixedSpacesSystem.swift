import Foundation

protocol FixedSpacesSystemHandling: AnyObject {
    func automaticallyRearrangesSpaces() -> Bool
    func setAutomaticallyRearrangesSpaces(_ enabled: Bool) -> Bool
    func restartDock()
}

/// The only production type that can touch Dock preferences or restart Dock.
final class FixedSpacesSystem: FixedSpacesSystemHandling {
    private static let domain = "com.apple.dock"
    private static let key = "mru-spaces"

    func automaticallyRearrangesSpaces() -> Bool {
        // The usual macOS default is rearranging by recent use.
        (readDockValue() as? Bool) ?? true
    }

    func setAutomaticallyRearrangesSpaces(_ enabled: Bool) -> Bool {
        guard enabled != automaticallyRearrangesSpaces() else { return true }
        guard runDefaults(["write", Self.domain, Self.key, "-bool", enabled ? "true" : "false"]) != nil else { return false }
        restartDock()
        return true
    }

    func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                LoggingService.shared.logWarning("Fixed Spaces: Dock restart exited with \(process.terminationStatus)")
            }
        } catch {
            LoggingService.shared.logWarning("Fixed Spaces: could not restart Dock: \(error.localizedDescription)")
        }
    }

    private func readDockValue() -> Any? {
        guard let text = runDefaults(["read", Self.domain, Self.key]) else { return nil }
        switch text {
        case "0", "false": return false
        case "1", "true": return true
        default: return nil
        }
    }

    private func runDefaults(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
            process.waitUntilExit()
            let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard process.terminationStatus == 0 else {
                let errorText = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !errorText.isEmpty && !errorText.contains("does not exist") {
                    LoggingService.shared.logWarning("Fixed Spaces: \(errorText)")
                }
                return nil
            }
            return text
        } catch {
            LoggingService.shared.logWarning("Fixed Spaces: could not access Dock preferences: \(error.localizedDescription)")
            return nil
        }
    }
}
