import XCTest
@testable import SyncthingTray

final class LaunchAgentControllerTests: XCTestCase {
    func testStopSynchronouslyRemovesRuntimePIDFiles() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppPaths(rootDirectory: temporaryRoot)
        try paths.prepareDirectories()

        try "123\n".write(to: paths.syncthingPIDURL, atomically: true, encoding: .utf8)
        try "456\n".write(to: paths.syncthingSupervisorPIDURL, atomically: true, encoding: .utf8)

        let controller = LaunchAgentController(paths: paths)
        controller.stopSynchronously()

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.syncthingPIDURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.syncthingSupervisorPIDURL.path))
    }

    func testStatusIsUnloadedWithoutSupervisorOrRuntimePID() async {
        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppPaths(rootDirectory: temporaryRoot)
        let controller = LaunchAgentController(paths: paths)

        let status = await controller.status()

        XCTAssertEqual(status, .unloaded)
    }
}
