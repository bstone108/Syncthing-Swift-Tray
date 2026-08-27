import XCTest
@testable import SyncthingTray

final class RuntimeRestartPolicyTests: XCTestCase {
    func testFreshPolicyAttemptsImmediately() {
        let policy = RuntimeRestartPolicy()

        XCTAssertTrue(policy.shouldAttempt(at: Date()))
        XCTAssertNil(policy.remainingDelay(at: Date()))
    }

    func testFailureSchedulesBackoff() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        var policy = RuntimeRestartPolicy()

        let delay = policy.recordFailure(at: now)

        XCTAssertEqual(delay, 5, accuracy: 0.001)
        XCTAssertFalse(policy.shouldAttempt(at: now.addingTimeInterval(4)))
        XCTAssertTrue(policy.shouldAttempt(at: now.addingTimeInterval(5)))
    }

    func testResetClearsBackoffState() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        var policy = RuntimeRestartPolicy()
        _ = policy.recordFailure(at: now)

        policy.reset()

        XCTAssertTrue(policy.shouldAttempt(at: now))
        XCTAssertNil(policy.remainingDelay(at: now))
    }
}
