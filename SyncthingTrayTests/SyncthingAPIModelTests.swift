import XCTest
@testable import SyncthingTray

final class SyncthingAPIModelTests: XCTestCase {
    func testSystemErrorEnvelopeAllowsNullErrors() throws {
        let json = #"{"errors":null}"#.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(SyncthingSystemErrorEnvelope.self, from: json)

        XCTAssertNil(envelope.errors)
    }

    func testSystemLogEnvelopeAllowsNullMessages() throws {
        let json = #"{"messages":null}"#.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(SyncthingSystemLogEnvelope.self, from: json)

        XCTAssertNil(envelope.messages)
    }
}
