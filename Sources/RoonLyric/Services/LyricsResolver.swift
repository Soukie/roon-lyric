import Foundation

protocol LyricsProvider {
    var name: String { get }
    func fetchLyrics(for track: TrackIdentity) async throws -> Lyrics?
}

final class LyricsResolver {
    private let cache: LyricsCache
    private let providers: [LyricsProvider]
    private let settingsProvider: () -> LyricsProviderSettings

    init(
        cache: LyricsCache = LyricsCache(),
        settingsProvider: @escaping () -> LyricsProviderSettings = { .defaults },
        providers: [LyricsProvider]? = nil
    ) {
        self.cache = cache
        self.settingsProvider = settingsProvider
        self.providers = providers ?? [
            LRCLIBLyricsProvider(),
            QQMusicOfficialLyricsProvider(settingsProvider: settingsProvider),
            SpotifyMetadataLyricsProvider(settingsProvider: settingsProvider)
        ]
    }

    func resolve(track: TrackIdentity) async -> Lyrics {
        if let cached = cache.lyrics(for: track) {
            AppLogger.info("Lyrics", "cache hit track=\(track.displayTitle)")
            return cached
        }

        AppLogger.info("Lyrics", "resolving track=\(track.displayTitle)")
        for provider in providers {
            guard isEnabled(provider: provider) else {
                AppLogger.debug("Lyrics", "provider disabled provider=\(provider.name)")
                continue
            }
            do {
                if let lyrics = try await provider.fetchLyrics(for: track) {
                    cache.store(lyrics, for: track)
                    AppLogger.info("Lyrics", "provider hit provider=\(provider.name) kind=\(lyrics.kind.rawValue) lineCount=\(lyrics.lines.count)")
                    return lyrics
                }
                AppLogger.info("Lyrics", "provider miss provider=\(provider.name)")
            } catch {
                AppLogger.error("Lyrics", "provider error provider=\(provider.name) error=\(error.localizedDescription)")
                continue
            }
        }

        AppLogger.warning("Lyrics", "lyrics not found track=\(track.displayTitle)")
        return .notFound
    }

    private func isEnabled(provider: LyricsProvider) -> Bool {
        let settings = settingsProvider()
        switch provider.name {
        case "LRCLIB":
            return settings.lrclibEnabled
        case "QQ Music Official":
            return settings.qqMusicEnabled
        case "Spotify":
            return settings.spotifyEnabled
        default:
            return true
        }
    }
}

final class LRCLIBLyricsProvider: LyricsProvider {
    let name = "LRCLIB"

    func fetchLyrics(for track: TrackIdentity) async throws -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist)
        ]
        if !track.album.isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: track.album))
        }
        if let duration = track.duration {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components.queryItems = queryItems

        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("RoonLyric/0.1.0 (https://example.local/roon-lyric)", forHTTPHeaderField: "User-Agent")

        AppLogger.debug("Lyrics", "requesting LRCLIB")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        guard http.statusCode == 200 else {
            AppLogger.warning("Lyrics", "LRCLIB status=\(http.statusCode)")
            return nil
        }

        let decoded = try JSONDecoder().decode(LRCLIBResponse.self, from: data)
        if let synced = decoded.syncedLyrics, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Lyrics(kind: .synced, source: name, lines: LRCParser.parse(synced), plainText: decoded.plainLyrics)
        }
        if let plain = decoded.plainLyrics, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = plain.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .enumerated()
                .map { LyricLine(time: Double($0.offset) * 5, text: $0.element) }
            return Lyrics(kind: .plain, source: name, lines: lines, plainText: plain)
        }
        return nil
    }
}

private struct LRCLIBResponse: Decodable {
    var syncedLyrics: String?
    var plainLyrics: String?
}

struct QQMusicOfficialLyricsProvider: LyricsProvider {
    let name = "QQ Music Official"
    let settingsProvider: () -> LyricsProviderSettings

    func fetchLyrics(for track: TrackIdentity) async throws -> Lyrics? {
        let settings = settingsProvider()
        guard let baseURL = URL(string: settings.qqMusicBaseURL), !settings.qqMusicBaseURL.isEmpty else {
            AppLogger.warning("Lyrics", "QQ Music official provider enabled without base URL")
            return nil
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "track", value: track.title),
            URLQueryItem(name: "artist", value: track.artist),
            URLQueryItem(name: "album", value: track.album),
            URLQueryItem(name: "duration", value: track.duration.map { String(Int($0.rounded())) })
        ].filter { $0.value != nil }

        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("RoonLyric/0.1.0", forHTTPHeaderField: "User-Agent")
        if !settings.qqMusicAppID.isEmpty {
            request.setValue(settings.qqMusicAppID, forHTTPHeaderField: "X-App-Id")
        }
        if !settings.qqMusicAccessToken.isEmpty {
            request.setValue("Bearer \(settings.qqMusicAccessToken)", forHTTPHeaderField: "Authorization")
        }

        AppLogger.info("Lyrics", "requesting QQ Music official-compatible provider")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        guard http.statusCode == 200 else {
            AppLogger.warning("Lyrics", "QQ Music official-compatible status=\(http.statusCode)")
            return nil
        }

        let decoded = try JSONDecoder().decode(GenericLyricsResponse.self, from: data)
        return decoded.toLyrics(source: name)
    }
}

struct SpotifyMetadataLyricsProvider: LyricsProvider {
    let name = "Spotify"
    let settingsProvider: () -> LyricsProviderSettings

    func fetchLyrics(for track: TrackIdentity) async throws -> Lyrics? {
        let settings = settingsProvider()
        guard !settings.spotifyClientID.isEmpty, !settings.spotifyClientSecret.isEmpty else {
            AppLogger.warning("Lyrics", "Spotify provider enabled without client credentials")
            return nil
        }
        AppLogger.info("Lyrics", "Spotify configured for metadata matching only; official lyrics endpoint unavailable")
        return nil
    }
}

private struct GenericLyricsResponse: Decodable {
    var syncedLyrics: String?
    var plainLyrics: String?
    var lrc: String?
    var lyric: String?

    func toLyrics(source: String) -> Lyrics? {
        let synced = syncedLyrics ?? lrc
        if let synced, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Lyrics(kind: .synced, source: source, lines: LRCParser.parse(synced), plainText: plainLyrics ?? lyric)
        }

        let plain = plainLyrics ?? lyric
        if let plain, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = plain.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .enumerated()
                .map { LyricLine(time: Double($0.offset) * 5, text: $0.element) }
            return Lyrics(kind: .plain, source: source, lines: lines, plainText: plain)
        }

        return nil
    }
}
