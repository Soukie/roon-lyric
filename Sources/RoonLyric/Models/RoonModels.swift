import Foundation
import SwiftUI

enum RoonCoreSource: String, Codable, CaseIterable {
    case discovered
    case manual
}

struct RoonCore: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var host: String
    var port: Int
    var source: RoonCoreSource
    var lastSeen: Date?
    var lastConnected: Date?

    var endpoint: String {
        "\(host):\(port)"
    }
}

enum RoonConnectionPhase: Equatable {
    case disconnected
    case scanning
    case connecting
    case waitingForAuthorization
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .disconnected:
            return "未连接"
        case .scanning:
            return "正在扫描"
        case .connecting:
            return "正在连接"
        case .waitingForAuthorization:
            return "等待 Roon 授权"
        case .connected:
            return "已连接"
        case .failed(let message):
            return "连接失败：\(message)"
        }
    }
}

struct RoonNowPlaying: Codable, Hashable {
    var title: String
    var artist: String
    var album: String
    var length: TimeInterval?
    var seekPosition: TimeInterval?

    var trackIdentity: TrackIdentity? {
        guard !title.isEmpty else { return nil }
        return TrackIdentity(title: title, artist: artist, album: album, duration: length)
    }
}

struct RoonZone: Identifiable, Codable, Hashable {
    var id: String
    var displayName: String
    var state: String
    var nowPlaying: RoonNowPlaying?
    var lastSeekUpdate: Date

    var isPlaying: Bool {
        state == "playing"
    }
}

struct TrackIdentity: Codable, Hashable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval?

    var displayTitle: String {
        artist.isEmpty ? title : "\(title) - \(artist)"
    }

    var cacheKey: String {
        let durationPart = duration.map { String(Int($0.rounded())) } ?? "unknown"
        return [title, artist, album, durationPart]
            .map { $0.normalizedForLookup }
            .joined(separator: "|")
    }
}

struct LyricLine: Identifiable, Codable, Hashable {
    var id = UUID()
    var time: TimeInterval
    var text: String
}

struct Lyrics: Codable, Hashable {
    enum Kind: String, Codable {
        case synced
        case plain
        case notFound
    }

    var kind: Kind
    var source: String
    var lines: [LyricLine]
    var plainText: String?

    static let notFound = Lyrics(kind: .notFound, source: "none", lines: [], plainText: nil)
}

struct DisplayPreferences: Codable, Hashable {
    var fontSize: Double = 34
    var opacity: Double = 0.92
    var red: Double = 1.0
    var green: Double = 0.95
    var blue: Double = 0.38
    var showNextLine: Bool = true

    var color: Color {
        Color(red: red, green: green, blue: blue).opacity(opacity)
    }

    static let defaults = DisplayPreferences()
}
