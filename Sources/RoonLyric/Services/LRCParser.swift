import Foundation

enum LRCParser {
    static func parse(_ text: String) -> [LyricLine] {
        let pattern = #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var lines: [LyricLine] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let nsLine = rawLine as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            let matches = regex.matches(in: rawLine, range: range)
            guard !matches.isEmpty else { continue }

            let lyricText = regex.stringByReplacingMatches(in: rawLine, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lyricText.isEmpty else { continue }

            for match in matches {
                let minute = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
                let second = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound {
                    let rawFraction = nsLine.substring(with: match.range(at: 3))
                    fraction = (Double(rawFraction) ?? 0) / pow(10, Double(rawFraction.count))
                }
                lines.append(LyricLine(time: minute * 60 + second + fraction, text: lyricText))
            }
        }

        return lines.sorted { $0.time < $1.time }
    }
}
