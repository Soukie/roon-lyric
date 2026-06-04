import Combine
import Foundation

final class DisplayPreferencesStore: ObservableObject {
    @Published var preferences: DisplayPreferences {
        didSet { save() }
    }

    private let key = "displayPreferences"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(DisplayPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = .defaults
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}
