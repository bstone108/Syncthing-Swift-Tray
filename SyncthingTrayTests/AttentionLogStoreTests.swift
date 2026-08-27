import XCTest
@testable import SyncthingTray

@MainActor
final class AttentionLogStoreTests: XCTestCase {
    func testSyncthingLogFilteringKeepsErrorsOnly() {
        let store = AttentionLogStore()
        store.mergeSyncthingLogs([
            SyncthingLogMessage(when: .now, level: "INF", message: "INFO main: idle"),
            SyncthingLogMessage(when: .now, level: "WRN", message: "update ready"),
            SyncthingLogMessage(when: .now, level: "ERR", message: "db: could not open")
        ])

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.map(\.level), [.error])
    }

    func testPortMappingWarningsAreSuppressed() {
        let store = AttentionLogStore()
        store.mergeSyncthingLogs([
            SyncthingLogMessage(
                when: .now,
                level: "WRN",
                message: "Failed to acquire open port (mapping=0.0.0.0:22000/UDP id=NAT-PMP@192.168.50.1 error=\"recvfrom: connection refused\")"
            )
        ])

        XCTAssertTrue(store.entries.isEmpty)
    }

    func testRouterPortMappingErrorsAreSuppressed() {
        let store = AttentionLogStore()
        store.mergeSyncthingErrors([
            SyncthingSystemError(
                when: .now,
                message: "UPnP port mapping failed on gateway 192.168.50.1 while renewing lease"
            )
        ])

        XCTAssertTrue(store.entries.isEmpty)
    }

    func testSyncthingWarningWithErrorSubstringIsSuppressed() {
        let store = AttentionLogStore()
        store.mergeSyncthingLogs([
            SyncthingLogMessage(
                when: .now,
                level: "WRN",
                message: "Connection retry scheduled error=\"temporary timeout\""
            )
        ])

        XCTAssertTrue(store.entries.isEmpty)
    }

    func testDuplicateAttentionMessagesAreCollapsedBriefly() {
        let store = AttentionLogStore()
        let now = Date()

        store.addRunner(level: .warning, message: "Retrying update.", at: now)
        store.addRunner(level: .warning, message: "Retrying update.", at: now.addingTimeInterval(5))

        XCTAssertEqual(store.entries.count, 1)
    }
}
