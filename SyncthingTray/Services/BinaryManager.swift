import CryptoKit
import Foundation

enum BinaryManagerError: LocalizedError {
    case missingCurrentBinary
    case checksumMismatch(expected: String, actual: String)
    case extractedBinaryMissing
    case missingLastKnownGoodBinary

    var errorDescription: String? {
        switch self {
        case .missingCurrentBinary:
            return "No Syncthing runtime is currently installed."
        case .checksumMismatch(let expected, let actual):
            return "Syncthing runtime checksum mismatch. Expected \(expected), got \(actual)."
        case .extractedBinaryMissing:
            return "The downloaded Syncthing archive did not contain a runnable binary."
        case .missingLastKnownGoodBinary:
            return "The last known good Syncthing binary is no longer available on disk."
        }
    }
}

final class BinaryManager: @unchecked Sendable {
    private let paths: AppPaths
    private let catalog: BinaryCatalog
    private let stateStore: RuntimeStateStore
    private let session: URLSession

    init(
        paths: AppPaths,
        catalog: BinaryCatalog,
        stateStore: RuntimeStateStore,
        session: URLSession = .shared
    ) {
        self.paths = paths
        self.catalog = catalog
        self.stateStore = stateStore
        self.session = session
    }

    func ensureRuntimeAvailable(wrapperVersion: String) async throws -> URL {
        try paths.prepareDirectories()

        let state = stateStore.load()
        if let currentVersion = state.currentVersion {
            let binaryURL = paths.binaryURL(for: currentVersion)
            if FileManager.default.isExecutableFile(atPath: binaryURL.path),
               SupportedRuntime.isSupported(version: currentVersion) {
                try await ensureCurrentSymlink(for: currentVersion)
                return paths.currentBinarySymlinkURL
            }
        }

        let release = try await catalog.fetchLatestStableRelease()
        guard SupportedRuntime.isSupported(version: release.version) else {
            throw BinaryManagerError.missingCurrentBinary
        }
        try await install(release: release)
        _ = try stateStore.mutate { state in
            state.currentVersion = release.version
            state.stagedVersion = nil
            if state.lastKnownGoodVersion == nil {
                state.lastKnownGoodVersion = release.version
            }
        }
        try await ensureCurrentSymlink(for: release.version)
        return paths.currentBinarySymlinkURL
    }

    func stageLatestReleaseIfNeeded(wrapperVersion: String) async throws -> ReleaseDescriptor? {
        let release = try await catalog.fetchLatestStableRelease()
        let state = stateStore.load()

        if Self.shouldAttemptStage(releaseVersion: release.version, state: state, wrapperVersion: wrapperVersion) == false {
            return nil
        }

        try await install(release: release)
        _ = try stateStore.mutate { state in
            state.stagedVersion = release.version
        }
        return release
    }

    func activateStagedVersion() async throws -> String? {
        let state = stateStore.load()
        guard let stagedVersion = state.stagedVersion else {
            return nil
        }

        _ = try await activate(version: stagedVersion)
        return stagedVersion
    }

    @discardableResult
    func activate(version: String) async throws -> URL {
        let binaryURL = paths.binaryURL(for: version)
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            throw BinaryManagerError.missingCurrentBinary
        }

        try await ensureCurrentSymlink(for: version)
        _ = try stateStore.mutate { state in
            state.currentVersion = version
            if state.stagedVersion == version {
                state.stagedVersion = nil
            }
        }
        return paths.currentBinarySymlinkURL
    }

    func markCurrentVersionHealthy() throws {
        _ = try stateStore.mutate { state in
            if let currentVersion = state.currentVersion {
                state.lastKnownGoodVersion = currentVersion
                state.failedRuntimeWrapperVersions.removeValue(forKey: currentVersion)
            }
        }
    }

    func markVersionFailed(_ version: String, wrapperVersion: String) throws {
        _ = try stateStore.mutate { state in
            state.failedRuntimeWrapperVersions[version] = wrapperVersion
            if state.stagedVersion == version {
                state.stagedVersion = nil
            }
        }
    }

    func rollbackToLastKnownGood() async throws -> URL {
        let state = stateStore.load()
        guard let lastKnownGoodVersion = state.lastKnownGoodVersion else {
            throw BinaryManagerError.missingLastKnownGoodBinary
        }

        let binaryURL = paths.binaryURL(for: lastKnownGoodVersion)
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            throw BinaryManagerError.missingLastKnownGoodBinary
        }

        return try await activate(version: lastKnownGoodVersion)
    }

    func repairRuntime(wrapperVersion: String) async throws -> URL {
        let release = try await catalog.fetchLatestStableRelease()
        try await removeVersionDirectory(for: release.version)
        try await install(release: release)
        return try await activate(version: release.version)
    }

    func currentVersion() -> String? {
        stateStore.load().currentVersion
    }

    func stagedVersion() -> String? {
        stateStore.load().stagedVersion
    }

    func isCurrentRuntimeSupported() -> Bool {
        guard let currentVersion = stateStore.load().currentVersion else {
            return false
        }
        return SupportedRuntime.isSupported(version: currentVersion)
    }

    static func shouldAttemptStage(releaseVersion: String, state: RuntimeState, wrapperVersion: String) -> Bool {
        if releaseVersion == state.currentVersion || releaseVersion == state.stagedVersion {
            return false
        }

        if state.failedRuntimeWrapperVersions[releaseVersion] == wrapperVersion {
            return false
        }

        return true
    }

    private func install(release: ReleaseDescriptor) async throws {
        let destinationBinary = paths.binaryURL(for: release.version)
        if FileManager.default.isExecutableFile(atPath: destinationBinary.path) {
            return
        }

        let checksumText = try await downloadText(from: release.checksumURL)
        let expectedChecksum = try BinaryCatalog.parseSHA256Checksum(in: checksumText, assetName: release.assetName)
        let archiveURL = try await downloadArchive(from: release.artifactURL, suggestedName: release.assetName)
        let actualChecksum = try await Task.detached(priority: .utility) {
            try Self.sha256Hex(for: archiveURL)
        }.value

        guard actualChecksum == expectedChecksum else {
            throw BinaryManagerError.checksumMismatch(expected: expectedChecksum, actual: actualChecksum)
        }

        let extractedBinaryURL = try await Task.detached(priority: .utility) {
            try Self.unpackBinary(from: archiveURL, into: self.paths.versionDirectory(for: release.version))
        }.value

        try await Task.detached(priority: .utility) {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = extractedBinaryURL
            try url.setResourceValues(values)
        }.value
    }

    private func downloadText(from url: URL) async throws -> String {
        let (data, response) = try await session.data(from: url)
        try validateHTTP(response)
        return String(decoding: data, as: UTF8.self)
    }

    private func downloadArchive(from url: URL, suggestedName: String) async throws -> URL {
        let (temporaryURL, response) = try await session.download(from: url)
        try validateHTTP(response)

        let destinationURL = paths.cacheDirectory.appendingPathComponent(UUID().uuidString + "-" + suggestedName)
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private func ensureCurrentSymlink(for version: String) async throws {
        let destination = paths.binaryURL(for: version)
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            try? fileManager.removeItem(at: self.paths.currentBinarySymlinkURL)
            try fileManager.createSymbolicLink(at: self.paths.currentBinarySymlinkURL, withDestinationURL: destination)
        }.value
    }

    private func removeVersionDirectory(for version: String) async throws {
        let directory = paths.versionDirectory(for: version)
        try await Task.detached(priority: .utility) {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }.value
    }

    private func validateHTTP(_ response: URLResponse) throws {
        if let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) == false {
            throw URLError(.badServerResponse)
        }
    }

    private static func sha256Hex(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func unpackBinary(from archiveURL: URL, into versionDirectory: URL) throws -> URL {
        let fileManager = FileManager.default
        let extractionDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? fileManager.removeItem(at: extractionDirectory)
            try? fileManager.removeItem(at: archiveURL)
        }

        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: versionDirectory, withIntermediateDirectories: true)

        let output = try CommandRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-o", archiveURL.path, "-d", extractionDirectory.path]
        )
        guard output.exitCode == 0 else {
            throw NSError(domain: "BinaryManager", code: Int(output.exitCode), userInfo: [NSLocalizedDescriptionKey: output.stderr])
        }

        guard let enumerator = fileManager.enumerator(at: extractionDirectory, includingPropertiesForKeys: nil) else {
            throw BinaryManagerError.extractedBinaryMissing
        }

        for case let candidateURL as URL in enumerator {
            if candidateURL.lastPathComponent == "syncthing" {
                let destinationURL = versionDirectory.appendingPathComponent("syncthing", isDirectory: false)
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: candidateURL, to: destinationURL)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
                return destinationURL
            }
        }

        throw BinaryManagerError.extractedBinaryMissing
    }
}
