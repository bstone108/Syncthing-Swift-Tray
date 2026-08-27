import XCTest
@testable import SyncthingTray

final class SupportedRuntimeTests: XCTestCase {
    func testMinimumSupportedRuntimeRejectsOlderMajorVersion() {
        XCTAssertFalse(SupportedRuntime.isSupported(version: "1.27.12"))
        XCTAssertTrue(SupportedRuntime.isSupported(version: "2.0.0"))
        XCTAssertTrue(SupportedRuntime.isSupported(version: "2.0.15"))
    }
}
