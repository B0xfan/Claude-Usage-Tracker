import Combine
import Foundation

@MainActor
final class FixedSpacesController: ObservableObject {
    // Explicit: an implicit deinit here becomes main-actor isolated and aborts on macOS 15.
    nonisolated deinit {}
    static let shared = FixedSpacesController(defaults: .standard)
    static let previousRearrangeKey = "fixedSpaces.previousAutomaticallyRearranges"

    @Published private(set) var keepFixed = false
    private let defaults: UserDefaults
    private let system: FixedSpacesSystemHandling

    init(defaults: UserDefaults, system: FixedSpacesSystemHandling = FixedSpacesSystem()) {
        self.defaults = defaults
        self.system = system
        refresh()
    }

    func refresh() {
        keepFixed = !system.automaticallyRearrangesSpaces()
    }

    func setFixed(_ fixed: Bool) {
        refresh()
        guard fixed != keepFixed else { return }
        if fixed {
            let previous = system.automaticallyRearrangesSpaces()
            if system.setAutomaticallyRearrangesSpaces(false) {
                defaults.set(previous, forKey: Self.previousRearrangeKey)
            }
        } else {
            if system.setAutomaticallyRearrangesSpaces((defaults.object(forKey: Self.previousRearrangeKey) as? Bool) ?? true) {
                defaults.removeObject(forKey: Self.previousRearrangeKey)
            }
        }
        refresh()
    }
}
