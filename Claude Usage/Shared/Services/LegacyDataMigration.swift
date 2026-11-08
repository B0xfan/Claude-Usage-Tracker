//
//  LegacyDataMigration.swift
//  Usage Shelf
//
//  One-time, first-launch carry-over from the app's earlier identity
//  ("Claude Usage", bundle id HamedElfayome.Claude-Usage) to Usage Shelf
//  (com.johnhesch.usageshelf). It only ever COPIES: nothing in the old
//  preferences domain or the old Application Support folder is changed or deleted.
//
//  What it does not touch: Keychain items. Their service names are fixed strings,
//  so the new app finds the same items; macOS asks once for permission because
//  the app's identity changed (see KeychainService).
//

import Foundation

enum LegacyDataMigration {
    /// Preferences domain of the old app (its old bundle id).
    static let oldPrefsDomain = "HamedElfayome.Claude-Usage"
    /// Application Support folder names, old and new.
    static let oldSupportFolderName = "Claude Usage"
    static let newSupportFolderName = "Usage Shelf"
    /// Set in the new domain once the carry-over has run (so it never runs twice).
    static let doneFlagKey = "UsageShelfLegacyMigrationDone.v1"

    /// Keys that must not be carried over: system keys and the removed
    /// update, analytics and support-reminder features.
    private static let skippedKeyPrefixes = ["NS", "Apple", "SU", "heartbeat.", "supportReminder", "AK", "com.apple."]

    struct Outcome: Equatable {
        var ranNow: Bool
        var keysCopied: Int
        var filesCopied: Int
    }

    /// Runs the carry-over once. All inputs can be swapped so tests use throwaway data.
    @discardableResult
    static func runIfNeeded(
        destination: UserDefaults = .standard,
        sourceDomain: String = oldPrefsDomain,
        readSourceDomain: (String) -> [String: Any]? = { UserDefaults.standard.persistentDomain(forName: $0) },
        oldSupportDirectory: URL? = defaultSupportDirectory(named: oldSupportFolderName),
        newSupportDirectory: URL? = defaultSupportDirectory(named: newSupportFolderName),
        ownBundleID: String? = Bundle.main.bundleIdentifier
    ) -> Outcome {
        if destination.bool(forKey: doneFlagKey) || ownBundleID == sourceDomain {
            return Outcome(ranNow: false, keysCopied: 0, filesCopied: 0)
        }

        var keysCopied = 0
        if let old = readSourceDomain(sourceDomain) {
            for (key, value) in old {
                if skippedKeyPrefixes.contains(where: { key.hasPrefix($0) }) { continue }
                if destination.object(forKey: key) != nil { continue }   // never overwrite newer values
                destination.set(value, forKey: key)
                keysCopied += 1
            }
        }

        var filesCopied = 0
        if let oldDir = oldSupportDirectory, let newDir = newSupportDirectory {
            filesCopied = copyMissingItems(from: oldDir, to: newDir)
        }

        destination.set(true, forKey: doneFlagKey)
        destination.synchronize()
        return Outcome(ranNow: true, keysCopied: keysCopied, filesCopied: filesCopied)
    }

    static func defaultSupportDirectory(named name: String) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(name, isDirectory: true)
    }

    /// Copies every file and folder from `source` that is not already in `destination`.
    /// Returns how many top-level items were copied. Never deletes or overwrites.
    private static func copyMissingItems(from source: URL, to destination: URL) -> Int {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDir), isDir.boolValue else { return 0 }
        try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let children = try? fm.contentsOfDirectory(atPath: source.path) else { return 0 }
        var copied = 0
        for name in children {
            let from = source.appendingPathComponent(name)
            let to = destination.appendingPathComponent(name)
            var childIsDir: ObjCBool = false
            fm.fileExists(atPath: from.path, isDirectory: &childIsDir)
            if fm.fileExists(atPath: to.path) {
                if childIsDir.boolValue { copied += copyMissingItems(from: from, to: to) }
                continue
            }
            if (try? fm.copyItem(at: from, to: to)) != nil { copied += 1 }
        }
        return copied
    }
}
