import Foundation

enum BinaryCatalogError: LocalizedError {
    case missingCompatibleArtifact
    case missingChecksumAsset
    case missingChecksumEntry(String)
    case invalidReleaseMetadata

    var errorDescription: String? {
        switch self {
        case .missingCompatibleArtifact:
            return "No compatible macOS Syncthing artifact was found in the latest release."
        case .missingChecksumAsset:
            return "The latest Syncthing release does not include a SHA256 checksum asset."
        case .missingChecksumEntry(let assetName):
            return "No SHA256 checksum entry was found for \(assetName)."
        case .invalidReleaseMetadata:
            return "Syncthing release metadata was missing required fields."
        }
    }
}

enum BinaryArchitecture {
    case arm64
    case amd64

    static var current: BinaryArchitecture {
        #if arch(arm64)
        .arm64
        #else
        .amd64
        #endif
    }

    var candidateFragments: [String] {
        switch self {
        case .arm64:
            return ["syncthing-macos-universal-", "syncthing-macos-arm64-"]
        case .amd64:
            return ["syncthing-macos-universal-", "syncthing-macos-amd64-"]
        }
    }
}

final class BinaryCatalog: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLatestStableRelease() async throws -> ReleaseDescriptor {
        let releaseURL = URL(string: "https://api.github.com/repos/syncthing/syncthing/releases/latest")!
        let (data, response) = try await session.data(from: releaseURL)
        try Self.validateHTTP(response)

        let release = try decoder.decode(GitHubReleaseResponse.self, from: data)
        return try Self.releaseDescriptor(from: release, architecture: .current)
    }

    static func releaseDescriptor(
        from release: GitHubReleaseResponse,
        architecture: BinaryArchitecture
    ) throws -> ReleaseDescriptor {
        let version = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        guard version.isEmpty == false else {
            throw BinaryCatalogError.invalidReleaseMetadata
        }

        guard let checksumAsset = release.assets.first(where: { $0.name == "sha256sum.txt.asc" }) else {
            throw BinaryCatalogError.missingChecksumAsset
        }

        let compatibleAsset = architecture.candidateFragments
            .lazy
            .compactMap { fragment in
                release.assets.first(where: { $0.name.contains(fragment) && $0.name.hasSuffix(".zip") })
            }
            .first

        guard let compatibleAsset else {
            throw BinaryCatalogError.missingCompatibleArtifact
        }

        return ReleaseDescriptor(
            version: version,
            assetName: compatibleAsset.name,
            artifactURL: compatibleAsset.browserDownloadURL,
            checksumURL: checksumAsset.browserDownloadURL
        )
    }

    static func parseSHA256Checksum(in text: String, assetName: String) throws -> String {
        let pattern = #"(?im)^([A-Fa-f0-9]{64})\s+\*?([^\r\n]+)$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        for match in regex.matches(in: text, range: range) {
            guard match.numberOfRanges == 3,
                  let checksumRange = Range(match.range(at: 1), in: text),
                  let filenameRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let fileName = String(text[filenameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if fileName == assetName {
                return String(text[checksumRange]).lowercased()
            }
        }

        throw BinaryCatalogError.missingChecksumEntry(assetName)
    }

    private static func validateHTTP(_ response: URLResponse) throws {
        if let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) == false {
            throw URLError(.badServerResponse)
        }
    }
}
