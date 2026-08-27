import Foundation

enum AttentionLogSource: String, Codable, Equatable {
    case runner
    case syncthing
}

enum AttentionLogLevel: String, Codable, Equatable {
    case info
    case warning
    case error
}

struct AttentionLogEntry: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let timestamp: Date
    let source: AttentionLogSource
    let level: AttentionLogLevel
    let message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: AttentionLogSource,
        level: AttentionLogLevel,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.level = level
        self.message = message
    }
}
