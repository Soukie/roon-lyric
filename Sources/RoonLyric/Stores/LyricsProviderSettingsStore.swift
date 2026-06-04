import Combine
import Foundation

struct LyricsProviderSettings: Codable, Hashable {
    var lrclibEnabled = true

    var qqMusicEnabled = false
    var qqMusicBaseURL = ""
    var qqMusicAppID = ""
    var qqMusicAccessToken = ""

    var spotifyEnabled = false
    var spotifyClientID = ""
    var spotifyClientSecret = ""
    var spotifyMarket = "US"

    static let defaults = LyricsProviderSettings()
}

final class LyricsProviderSettingsStore: ObservableObject {
    @Published var settings: LyricsProviderSettings {
        didSet { save() }
    }

    private let key = "lyricsProviderSettings"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(LyricsProviderSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .defaults
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
