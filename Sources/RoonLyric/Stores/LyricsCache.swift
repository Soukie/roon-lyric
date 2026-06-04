import Foundation

final class LyricsCache {
    private let key = "lyricsCache"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lyrics(for track: TrackIdentity) -> Lyrics? {
        cache()[track.cacheKey]
    }

    func store(_ lyrics: Lyrics, for track: TrackIdentity) {
        guard lyrics.kind != .notFound else { return }
        var values = cache()
        values[track.cacheKey] = lyrics
        if values.count > 300 {
            values = Dictionary(uniqueKeysWithValues: values.prefix(300).map { ($0.key, $0.value) })
        }
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: key)
    }

    private func cache() -> [String: Lyrics] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Lyrics].self, from: data) else {
            return [:]
        }
        return decoded
    }
}
