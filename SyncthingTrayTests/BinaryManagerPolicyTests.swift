import XCTest
@testable import SyncthingTray

final class BinaryManagerPolicyTests: XCTestCase {
    func testFailedRuntimeIsSkippedForSameWrapperVersion() {
        let state = RuntimeState(
            currentVersion: "2.0.14",
            lastKnownGoodVersion: "2.0.14",
            stagedVersion: nil,
            failedRuntimeWrapperVersions: ["2.0.15": "1.0"],
            apiKey: nil,
            lastSuccessfulCheckAt: nil,
            nextDueAt: nil
        )

        XCTAssertFalse(BinaryManager.shouldAttemptStage(releaseVersion: "2.0.15", state: state, wrapperVersion: "1.0"))
    }

    func testFailedRuntimeCanRetryAfterWrapperVersionChanges() {
        let state = RuntimeState(
            currentVersion: "2.0.14",
            lastKnownGoodVersion: "2.0.14",
            stagedVersion: nil,
            failedRuntimeWrapperVersions: ["2.0.15": "1.0"],
            apiKey: nil,
            lastSuccessfulCheckAt: nil,
            nextDueAt: nil
        )

        XCTAssertTrue(BinaryManager.shouldAttemptStage(releaseVersion: "2.0.15", state: state, wrapperVersion: "1.1"))
    }

    func testNewRuntimeVersionAlwaysRetries() {
        let state = RuntimeState(
            currentVersion: "2.0.14",
            lastKnownGoodVersion: "2.0.14",
            stagedVersion: nil,
            failedRuntimeWrapperVersions: ["2.0.15": "1.0"],
            apiKey: nil,
            lastSuccessfulCheckAt: nil,
            nextDueAt: nil
        )

        XCTAssertTrue(BinaryManager.shouldAttemptStage(releaseVersion: "2.0.16", state: state, wrapperVersion: "1.0"))
    }
}
