import XCTest
@testable import Claude_Usage

/// Tests for the first-launch carry-over from the old "Claude Usage" identity.
/// Everything here uses throwaway preference domains and temp folders, never the real ones.
final class LegacyDataMigrationTests: XCTestCase {

    private var oldDomain = ""
    private var newDomain = ""
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        let id = UUID().uuidString
        oldDomain = "com.johnhesch.usageshelf.test.old.\(id)"
        newDomain = "com.johnhesch.usageshelf.test.new.\(id)"
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("usageshelf-migration-\(id)")
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: oldDomain)
        UserDefaults.standard.removePersistentDomain(forName: newDomain)
        try? FileManager.default.removeItem(at: tempRoot)
        // removePersistentDomain leaves an empty plist behind; remove the throwaway files too.
        let prefs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Preferences")
        for domain in [oldDomain, newDomain] {
            if let url = prefs?.appendingPathComponent("\(domain).plist") { try? FileManager.default.removeItem(at: url) }
        }
        super.tearDown()
    }

    private func run(oldDir: URL? = nil, newDir: URL? = nil) -> (LegacyDataMigration.Outcome, UserDefaults) {
        let dest = UserDefaults(suiteName: newDomain)!
        let outcome = LegacyDataMigration.runIfNeeded(
            destination: dest,
            sourceDomain: oldDomain,
            oldSupportDirectory: oldDir,
            newSupportDirectory: newDir,
            ownBundleID: "com.johnhesch.usageshelf.test"
        )
        return (outcome, dest)
    }

    func testCopiesSettingsAndLeavesOldDomainUntouched() {
        let old = UserDefaults(suiteName: oldDomain)!
        old.set("rings", forKey: "menuBarIconStyle")
        old.set(true, forKey: "HasMigratedFromAppGroup")
        old.set(Data([1, 2, 3]), forKey: "profiles_v3")

        let (outcome, dest) = run()

        XCTAssertTrue(outcome.ranNow)
        XCTAssertEqual(outcome.keysCopied, 3)
        XCTAssertEqual(dest.string(forKey: "menuBarIconStyle"), "rings")
        XCTAssertTrue(dest.bool(forKey: "HasMigratedFromAppGroup"))
        XCTAssertEqual(dest.data(forKey: "profiles_v3"), Data([1, 2, 3]))
        // Old domain is only copied from, never changed
        XCTAssertEqual(UserDefaults.standard.persistentDomain(forName: oldDomain)?["menuBarIconStyle"] as? String, "rings")
    }

    func testSkipsRemovedFeatureAndSystemKeys() {
        let old = UserDefaults(suiteName: oldDomain)!
        old.set(true, forKey: "SUEnableAutomaticChecks")
        old.set(Date(), forKey: "heartbeat.lastPingDate")
        old.set(Date(), forKey: "supportReminderLastShownAt")
        old.set("x", forKey: "NSWindow Frame foo")
        old.set("keep", forKey: "language")

        let (_, dest) = run()

        XCTAssertNil(dest.object(forKey: "SUEnableAutomaticChecks"))
        XCTAssertNil(dest.object(forKey: "heartbeat.lastPingDate"))
        XCTAssertNil(dest.object(forKey: "supportReminderLastShownAt"))
        XCTAssertNil(dest.object(forKey: "NSWindow Frame foo"))
        XCTAssertEqual(dest.string(forKey: "language"), "keep")
    }

    func testDoesNotOverwriteExistingNewValues() {
        UserDefaults(suiteName: oldDomain)!.set("old", forKey: "theme")
        UserDefaults(suiteName: newDomain)!.set("new", forKey: "theme")

        let (_, dest) = run()

        XCTAssertEqual(dest.string(forKey: "theme"), "new")
    }

    func testRunsOnlyOnce() {
        UserDefaults(suiteName: oldDomain)!.set("a", forKey: "k1")
        let (first, dest) = run()
        XCTAssertTrue(first.ranNow)

        UserDefaults(suiteName: oldDomain)!.set("b", forKey: "k2")
        let second = LegacyDataMigration.runIfNeeded(
            destination: dest, sourceDomain: oldDomain,
            oldSupportDirectory: nil, newSupportDirectory: nil, ownBundleID: "x")
        XCTAssertFalse(second.ranNow)
        XCTAssertNil(dest.object(forKey: "k2"))
    }

    func testSkipsWhenRunningAsTheOldApp() {
        let dest = UserDefaults(suiteName: newDomain)!
        let outcome = LegacyDataMigration.runIfNeeded(
            destination: dest, sourceDomain: oldDomain,
            oldSupportDirectory: nil, newSupportDirectory: nil, ownBundleID: oldDomain)
        XCTAssertFalse(outcome.ranNow)
    }

    func testCopiesSupportFilesWhenNewFolderIsMissingOrEmptyAndNeverDeletes() throws {
        let fm = FileManager.default
        let oldDir = tempRoot.appendingPathComponent("old")
        let newDir = tempRoot.appendingPathComponent("new")
        try fm.createDirectory(at: oldDir.appendingPathComponent("history"), withIntermediateDirectories: true)
        try Data("h".utf8).write(to: oldDir.appendingPathComponent("history/usageHistory_A.json"))
        try Data("n".utf8).write(to: oldDir.appendingPathComponent("network_logs.json"))
        // New folder exists but is empty, plus one file the new app already wrote
        try fm.createDirectory(at: newDir.appendingPathComponent("history"), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: newDir.appendingPathComponent("network_logs.json"))

        let (outcome, _) = run(oldDir: oldDir, newDir: newDir)

        XCTAssertGreaterThanOrEqual(outcome.filesCopied, 1)
        XCTAssertEqual(try String(contentsOf: newDir.appendingPathComponent("history/usageHistory_A.json")), "h")
        XCTAssertEqual(try String(contentsOf: newDir.appendingPathComponent("network_logs.json")), "keep")
        // Old data still there
        XCTAssertTrue(fm.fileExists(atPath: oldDir.appendingPathComponent("history/usageHistory_A.json").path))
        XCTAssertTrue(fm.fileExists(atPath: oldDir.appendingPathComponent("network_logs.json").path))
    }

    func testMissingOldDataIsNotAnError() {
        let (outcome, dest) = run(oldDir: tempRoot.appendingPathComponent("nope"), newDir: tempRoot.appendingPathComponent("new"))
        XCTAssertTrue(outcome.ranNow)
        XCTAssertEqual(outcome.keysCopied, 0)
        XCTAssertEqual(outcome.filesCopied, 0)
        XCTAssertTrue(dest.bool(forKey: LegacyDataMigration.doneFlagKey))
    }
}
