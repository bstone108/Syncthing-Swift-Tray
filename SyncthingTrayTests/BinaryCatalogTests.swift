import XCTest
@testable import SyncthingTray

final class BinaryCatalogTests: XCTestCase {
    func testReleaseDescriptorPrefersUniversalMacOSArtifact() throws {
        let release = GitHubReleaseResponse(
            tagName: "v2.0.15",
            assets: [
                GitHubAssetResponse(
                    name: "sha256sum.txt.asc",
                    browserDownloadURL: URL(string: "https://example.com/checksums.asc")!
                ),
                GitHubAssetResponse(
                    name: "syncthing-macos-arm64-v2.0.15.zip",
                    browserDownloadURL: URL(string: "https://example.com/arm64.zip")!
                ),
                GitHubAssetResponse(
                    name: "syncthing-macos-universal-v2.0.15.zip",
                    browserDownloadURL: URL(string: "https://example.com/universal.zip")!
                )
            ]
        )

        let descriptor = try BinaryCatalog.releaseDescriptor(from: release, architecture: .arm64)

        XCTAssertEqual(descriptor.version, "2.0.15")
        XCTAssertEqual(descriptor.assetName, "syncthing-macos-universal-v2.0.15.zip")
        XCTAssertEqual(descriptor.artifactURL.absoluteString, "https://example.com/universal.zip")
    }

    func testChecksumParserFindsMatchingArtifact() throws {
        let checksumFile = """
        -----BEGIN PGP SIGNED MESSAGE-----
        Hash: SHA256

        1111111111111111111111111111111111111111111111111111111111111111 syncthing-macos-arm64-v2.0.15.zip
        abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd syncthing-macos-universal-v2.0.15.zip
        -----BEGIN PGP SIGNATURE-----
        ...
        """

        let checksum = try BinaryCatalog.parseSHA256Checksum(
            in: checksumFile,
            assetName: "syncthing-macos-universal-v2.0.15.zip"
        )

        XCTAssertEqual(checksum, "abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd")
    }
}
