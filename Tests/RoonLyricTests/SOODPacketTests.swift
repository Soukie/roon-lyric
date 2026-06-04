import XCTest
@testable import RoonLyric

final class SOODPacketTests: XCTestCase {
    func testQueryContainsRoonServiceID() {
        let data = SOODPacket.queryData(transactionID: "test")
        let text = String(data: data, encoding: .utf8) ?? ""

        XCTAssertTrue(text.contains("SOOD"))
        XCTAssertTrue(text.contains(SOODPacket.serviceID))
    }
}
