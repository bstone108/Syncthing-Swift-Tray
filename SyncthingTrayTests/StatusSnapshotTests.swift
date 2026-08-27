import XCTest
@testable import SyncthingTray

final class StatusSnapshotTests: XCTestCase {
    func testScanningDoesNotCountAsSyncing() {
        let snapshot = StatusSnapshot.from(
            agentLoaded: true,
            apiResponding: true,
            folderStatuses: [FolderStatus(id: "docs", state: "scanning", needBytes: 0, pullErrors: 0, lastChanged: nil)],
            errors: [],
            isUpdating: false
        )

        XCTAssertEqual(snapshot.mode, .healthy)
        XCTAssertFalse(snapshot.isSyncing)
    }

    func testErrorOverridesSyncingState() {
        let snapshot = StatusSnapshot.from(
            agentLoaded: true,
            apiResponding: true,
            folderStatuses: [FolderStatus(id: "docs", state: "syncing", needBytes: 42, pullErrors: 1, lastChanged: nil)],
            errors: ["Folder docs failed."],
            isUpdating: false
        )

        XCTAssertEqual(snapshot.mode, .error)
        XCTAssertEqual(snapshot.actionableError, "Folder docs failed.")
    }
}
