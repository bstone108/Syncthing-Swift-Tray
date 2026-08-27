import Foundation

struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let assets: [GitHubAssetResponse]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

struct GitHubAssetResponse: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

struct ReleaseDescriptor: Equatable {
    let version: String
    let assetName: String
    let artifactURL: URL
    let checksumURL: URL
}

struct SyncthingSystemConfiguration: Decodable {
    let folders: [SyncthingFolderConfiguration]
}

struct SyncthingFolderConfiguration: Decodable {
    let id: String
}

struct SyncthingFolderStatusResponse: Decodable {
    let folder: String?
    let needBytes: Int64
    let pullErrors: Int
    let state: String
    let stateChanged: Date?

    enum CodingKeys: String, CodingKey {
        case folder
        case needBytes
        case pullErrors
        case state
        case stateChanged
    }
}

struct SyncthingSystemErrorEnvelope: Decodable {
    let errors: [SyncthingSystemError]?
}

struct SyncthingSystemError: Decodable, Equatable {
    let when: Date
    let message: String
}

struct SyncthingSystemLogEnvelope: Decodable {
    let messages: [SyncthingLogMessage]?
}

struct SyncthingLogMessage: Decodable, Equatable {
    let when: Date
    let level: String?
    let message: String
}

struct SyncthingRemoteSnapshot: Equatable {
    let folderStatuses: [FolderStatus]
    let errors: [SyncthingSystemError]
    let logs: [SyncthingLogMessage]
}

enum SyncthingEventKind: Equatable {
    case stateChanged(folder: String, toState: String)
    case folderErrors(folder: String)
    case folderSummary(folder: String)
    case unknown(type: String)
}

struct SyncthingEvent: Equatable {
    let id: Int
    let timestamp: Date
    let kind: SyncthingEventKind
}
