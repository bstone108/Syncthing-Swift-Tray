import XCTest
@testable import SyncthingTray

final class CommandRunnerTests: XCTestCase {
    func testRunDrainsLargeStdoutWithoutDeadlocking() throws {
        let output = try CommandRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/seq"),
            arguments: ["1", "20000"]
        )

        XCTAssertEqual(output.exitCode, 0)
        XCTAssertTrue(output.stdout.contains("20000"))
        XCTAssertTrue(output.stderr.isEmpty)
    }
}
