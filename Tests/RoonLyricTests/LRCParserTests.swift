import XCTest
@testable import RoonLyric

final class LRCParserTests: XCTestCase {
    func testParsesMultipleTimestampFormats() {
        let lines = LRCParser.parse("""
        [00:01.20]First line
        [00:03:500]Second line
        [01:02]Third line
        """)

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].text, "First line")
        XCTAssertEqual(lines[0].time, 1.2, accuracy: 0.001)
        XCTAssertEqual(lines[1].time, 3.5, accuracy: 0.001)
        XCTAssertEqual(lines[2].time, 62.0, accuracy: 0.001)
    }
}
