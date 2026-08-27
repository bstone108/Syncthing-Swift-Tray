import Foundation

struct RuntimeState: Codable, Equatable {
    var currentVersion: String?
    var lastKnownGoodVersion: String?
    var stagedVersion: String?
    var failedRuntimeWrapperVersions: [String: String]
    var apiKey: String?
    var lastSuccessfulCheckAt: Date?
    var nextDueAt: Date?

    static let initial = RuntimeState(
        currentVersion: nil,
        lastKnownGoodVersion: nil,
        stagedVersion: nil,
        failedRuntimeWrapperVersions: [:],
        apiKey: nil,
        lastSuccessfulCheckAt: nil,
        nextDueAt: nil
    )
}
