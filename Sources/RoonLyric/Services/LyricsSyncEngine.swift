import Combine
import Foundation

final class LyricsSyncEngine: ObservableObject {
    @Published private(set) var lyrics: Lyrics = .notFound
    @Published private(set) var currentLine: LyricLine?
    @Published private(set) var nextLine: LyricLine?
    @Published private(set) var statusText: String = "等待 Roon 播放"

    private let resolver: LyricsResolver
    private var currentTrack: TrackIdentity?
    private var currentZone: RoonZone?
    private var timer: Timer?
    private var resolveTask: Task<Void, Never>?

    init(resolver: LyricsResolver = LyricsResolver()) {
        self.resolver = resolver
        AppLogger.info("LyricsSync", "sync engine initialized")
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func update(zone: RoonZone?) {
        currentZone = zone
        guard let track = zone?.nowPlaying?.trackIdentity else {
            if currentTrack != nil {
                AppLogger.info("LyricsSync", "cleared current track")
            }
            currentTrack = nil
            lyrics = .notFound
            currentLine = nil
            nextLine = nil
            statusText = "等待 Roon 播放"
            return
        }

        if track != currentTrack {
            currentTrack = track
            AppLogger.info("LyricsSync", "track changed title=\(track.displayTitle)")
            lyrics = .notFound
            currentLine = nil
            nextLine = nil
            statusText = "正在查找歌词：\(track.displayTitle)"
            resolveTask?.cancel()
            resolveTask = Task { [weak self] in
                guard let self else { return }
                let resolved = await self.resolver.resolve(track: track)
                await MainActor.run {
                    guard self.currentTrack == track else { return }
                    self.lyrics = resolved
                    AppLogger.info("LyricsSync", "lyrics resolved kind=\(resolved.kind.rawValue) source=\(resolved.source) lineCount=\(resolved.lines.count)")
                    self.statusText = resolved.kind == .notFound ? "未找到歌词：\(track.displayTitle)" : "歌词来源：\(resolved.source)"
                    self.tick()
                }
            }
        } else {
            tick()
        }
    }

    private func tick() {
        guard let zone = currentZone,
              let seek = zone.nowPlaying?.seekPosition,
              !lyrics.lines.isEmpty else {
            return
        }

        let progress: TimeInterval
        if zone.isPlaying {
            progress = seek + Date().timeIntervalSince(zone.lastSeekUpdate)
        } else {
            progress = seek
        }

        let index = lyrics.lines.lastIndex { $0.time <= progress } ?? 0
        currentLine = lyrics.lines[index]
        if lyrics.lines.indices.contains(index + 1) {
            nextLine = lyrics.lines[index + 1]
        } else {
            nextLine = nil
        }
    }

    deinit {
        timer?.invalidate()
        resolveTask?.cancel()
    }
}
