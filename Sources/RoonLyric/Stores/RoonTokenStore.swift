import Foundation

final class RoonTokenStore {
    private let key = "roonCoreTokens"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func token(for coreID: String) -> String? {
        tokens()[coreID]
    }

    func save(token: String, for coreID: String) {
        var values = tokens()
        values[coreID] = token
        defaults.set(values, forKey: key)
    }

    private func tokens() -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
