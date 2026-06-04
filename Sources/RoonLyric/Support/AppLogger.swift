import Foundation
import OSLog

enum AppLogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

enum AppLogger {
    static let subsystem = "com.soukie.RoonLyric"

    static var logFileURL: URL {
        logsDirectory.appendingPathComponent("roon-lyric.log")
    }

    private static let queue = DispatchQueue(label: "RoonLyric.AppLogger")
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static var logsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("RoonLyric", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
    }

    static func startSession() {
        log(.info, category: "Lifecycle", "session started logFile=\(logFileURL.path)")
    }

    static func debug(_ category: String, _ message: String) {
        log(.debug, category: category, message)
    }

    static func info(_ category: String, _ message: String) {
        log(.info, category: category, message)
    }

    static func warning(_ category: String, _ message: String) {
        log(.warning, category: category, message)
    }

    static func error(_ category: String, _ message: String) {
        log(.error, category: category, message)
    }

    static func log(_ level: AppLogLevel, category: String, _ message: String) {
        let logger = Logger(subsystem: subsystem, category: category)
        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }

        queue.async {
            write(level: level, category: category, message: message)
        }
    }

    private static func write(level: AppLogLevel, category: String, message: String) {
        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            rotateIfNeeded()

            let timestamp = dateFormatter.string(from: Date())
            let line = "\(timestamp) [\(level.rawValue)] [\(category)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if FileManager.default.fileExists(atPath: logFileURL.path) {
                let handle = try FileHandle(forWritingTo: logFileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logFileURL, options: .atomic)
            }
        } catch {
            Logger(subsystem: subsystem, category: "Logging").error("failed to write file log: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func rotateIfNeeded() {
        let maxBytes: UInt64 = 5 * 1024 * 1024
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attributes[.size] as? UInt64,
              size >= maxBytes else {
            return
        }

        let archived = logsDirectory.appendingPathComponent("roon-lyric.previous.log")
        try? FileManager.default.removeItem(at: archived)
        try? FileManager.default.moveItem(at: logFileURL, to: archived)
    }
}
