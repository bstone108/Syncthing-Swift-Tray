import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    private enum Keys {
        static let launchAtLoginEnabled = "preferences.launchAtLoginEnabled"
        static let startSyncthingAutomatically = "preferences.startSyncthingAutomatically"
        static let autoCheckUpdates = "preferences.autoCheckUpdates"
    }

    private let defaults: UserDefaults

    @Published var launchAtLoginEnabled: Bool {
        didSet { defaults.set(launchAtLoginEnabled, forKey: Keys.launchAtLoginEnabled) }
    }

    @Published var startSyncthingAutomatically: Bool {
        didSet { defaults.set(startSyncthingAutomatically, forKey: Keys.startSyncthingAutomatically) }
    }

    @Published var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: Keys.autoCheckUpdates) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLoginEnabled = defaults.object(forKey: Keys.launchAtLoginEnabled) as? Bool ?? false
        startSyncthingAutomatically = defaults.object(forKey: Keys.startSyncthingAutomatically) as? Bool ?? true
        autoCheckUpdates = defaults.object(forKey: Keys.autoCheckUpdates) as? Bool ?? true
    }
}
