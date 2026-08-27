import Foundation

@MainActor
final class AttentionLogStore: ObservableObject {
    @Published private(set) var entries: [AttentionLogEntry] = []

    private var lastSeenKeys: [String: Date] = [:]
    private let maxEntryCount = 200

    func addRunner(level: AttentionLogLevel, message: String, at date: Date = .now) {
        append(AttentionLogEntry(timestamp: date, source: .runner, level: level, message: message))
    }

    func mergeSyncthingLogs(_ logs: [SyncthingLogMessage]) {
        for log in logs {
            guard shouldSuppressSyncthingMessage(log.message) == false,
                  let level = levelForSyncthingMessage(log) else {
                continue
            }
            append(AttentionLogEntry(timestamp: log.when, source: .syncthing, level: level, message: log.message))
        }
    }

    func mergeSyncthingErrors(_ errors: [SyncthingSystemError]) {
        for error in errors {
            guard shouldSuppressSyncthingMessage(error.message) == false else {
                continue
            }
            append(AttentionLogEntry(timestamp: error.when, source: .syncthing, level: .error, message: error.message))
        }
    }

    private func append(_ entry: AttentionLogEntry) {
        let dedupeKey = "\(entry.source.rawValue)|\(entry.level.rawValue)|\(entry.message)"
        if let lastTimestamp = lastSeenKeys[dedupeKey], entry.timestamp.timeIntervalSince(lastTimestamp) < 30 {
            return
        }

        lastSeenKeys[dedupeKey] = entry.timestamp
        entries.insert(entry, at: 0)

        if entries.count > maxEntryCount {
            entries.removeLast(entries.count - maxEntryCount)
        }
    }

    private func levelForSyncthingMessage(_ log: SyncthingLogMessage) -> AttentionLogLevel? {
        if let level = log.level?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
            switch level {
            case "ERR":
                return .error
            case "WRN", "INF":
                // Syncthing emits warnings for routine, self-healing conditions.
                // They are useful in its full log but do not belong in the tray's
                // action-focused attention list.
                return nil
            default:
                break
            }
        }

        let message = log.message
        let lowercase = message.lowercased()
        if lowercase.contains("error") || lowercase.contains("fatal") {
            return .error
        }
        return nil
    }

    private func shouldSuppressSyncthingMessage(_ message: String) -> Bool {
        let lowercase = message.lowercased()
        let mentionsRouterPortMapping =
            lowercase.contains("failed to acquire open port") ||
            lowercase.contains("port mapping") ||
            lowercase.contains("log.pkg=nat")
        let mentionsRouterProtocol =
            lowercase.contains("nat-pmp") ||
            lowercase.contains("upnp") ||
            lowercase.contains("pcp")

        return mentionsRouterPortMapping && mentionsRouterProtocol
    }
}
