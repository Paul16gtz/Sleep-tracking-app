import Combine
import Foundation

/// Observable, persistent holder of `AppSettings`. Every mutation of `settings` is written to `UserDefaults`.
@MainActor
final class SettingsStore: ObservableObject {
    static let storageKey = "appSettings"

    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        // Assign the backing storage directly so loading does not trigger `didSet` and write back.
        _settings = Published(initialValue: SettingsStore.load(from: userDefaults))
    }

    func resetToDefaults() {
        settings = AppSettings()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: SettingsStore.storageKey)
    }

    private static func load(from userDefaults: UserDefaults) -> AppSettings {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return decoded
    }
}
