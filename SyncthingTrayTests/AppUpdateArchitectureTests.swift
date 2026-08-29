import XCTest
@testable import SyncthingTray

final class AppUpdateArchitectureTests: XCTestCase {
    func testDedicatedArchiveNames() {
        XCTAssertEqual(
            AppUpdateArchitecture.dedicatedArchiveName(version: "2026.8.28.1", architecture: .arm64),
            "SyncthingTray-2026.8.28.1-macos-arm64.zip"
        )
        XCTAssertEqual(
            AppUpdateArchitecture.dedicatedArchiveName(version: "2026.8.28.1", architecture: .x86_64),
            "SyncthingTray-2026.8.28.1-macos-x86_64.zip"
        )
    }

    func testMatchesDedicatedArchiveAndSkipsUniversal() {
        let arm = "SyncthingTray-2026.8.28.1-macos-arm64.zip"
        let intel = "SyncthingTray-2026.8.28.1-macos-x86_64.zip"
        let universal = "SyncthingTray-2026.8.28.1-macos-universal.zip"

        XCTAssertTrue(AppUpdateArchitecture.matchesDedicatedArchive(arm, architecture: .arm64))
        XCTAssertFalse(AppUpdateArchitecture.matchesDedicatedArchive(arm, architecture: .x86_64))
        XCTAssertTrue(AppUpdateArchitecture.matchesDedicatedArchive(intel, architecture: .x86_64))
        XCTAssertFalse(AppUpdateArchitecture.matchesDedicatedArchive(intel, architecture: .arm64))
        XCTAssertFalse(AppUpdateArchitecture.matchesDedicatedArchive(universal, architecture: .arm64))
        XCTAssertFalse(AppUpdateArchitecture.matchesDedicatedArchive(universal, architecture: .x86_64))
    }

    func testPreferredArchiveIgnoresUniversalEvenWhenListedFirst() {
        let names = [
            "SyncthingTray-2026.8.28.1-macos-universal.zip",
            "SyncthingTray-2026.8.28.1-macos-arm64.zip",
            "SyncthingTray-2026.8.28.1-macos-x86_64.zip"
        ]

        XCTAssertEqual(
            AppUpdateArchitecture.preferredArchiveName(in: names, architecture: .arm64),
            "SyncthingTray-2026.8.28.1-macos-arm64.zip"
        )
        XCTAssertEqual(
            AppUpdateArchitecture.preferredArchiveName(in: names, architecture: .x86_64),
            "SyncthingTray-2026.8.28.1-macos-x86_64.zip"
        )
        XCTAssertNil(
            AppUpdateArchitecture.preferredArchiveName(
                in: ["SyncthingTray-2026.8.28.1-macos-universal.zip"],
                architecture: .arm64
            )
        )
    }
}
