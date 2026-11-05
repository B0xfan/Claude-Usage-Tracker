import SwiftUI

@main
struct ClaudeUsageTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // First launch under the Usage Shelf name: copy settings and data over from the
        // old "Claude Usage" identity before anything reads them. Skipped inside unit tests.
        if NSClassFromString("XCTestCase") == nil {
            LegacyDataMigration.runIfNeeded()
        }
    }

    var body: some Scene {
        // This app is menu bar only, no windows by default
        Settings {
            SettingsView()
        }
    }
}
