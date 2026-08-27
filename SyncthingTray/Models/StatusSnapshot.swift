import Foundation

enum RuntimeStatusMode: String, Equatable {
    case stopped
    case starting
    case healthy
    case syncing
    case error
    case updating
}

struct FolderStatus: Equatable {
    let id: String
    let state: String
    let needBytes: Int64
    let pullErrors: Int
    let lastChanged: Date?

    var hasActionableError: Bool {
        state.caseInsensitiveCompare("error") == .orderedSame || pullErrors > 0
    }

    var isSyncing: Bool {
        state.caseInsensitiveCompare("syncing") == .orderedSame
    }
}

struct StatusSnapshot: Equatable {
    let mode: RuntimeStatusMode
    let folderStatuses: [FolderStatus]
    let errors: [String]
    let lastUpdated: Date

    static let stopped = StatusSnapshot(mode: .stopped, folderStatuses: [], errors: [], lastUpdated: .now)

    static func from(
        agentLoaded: Bool,
        apiResponding: Bool,
        folderStatuses: [FolderStatus],
        errors: [String],
        isUpdating: Bool
    ) -> StatusSnapshot {
        let mode: RuntimeStatusMode

        if agentLoaded == false {
            mode = .stopped
        } else if errors.isEmpty == false || folderStatuses.contains(where: \.hasActionableError) {
            mode = .error
        } else if isUpdating {
            mode = .updating
        } else if folderStatuses.contains(where: \.isSyncing) {
            mode = .syncing
        } else if apiResponding {
            mode = .healthy
        } else {
            mode = .starting
        }

        return StatusSnapshot(mode: mode, folderStatuses: folderStatuses, errors: errors, lastUpdated: .now)
    }

    static func bootstrapError(_ message: String) -> StatusSnapshot {
        StatusSnapshot(mode: .error, folderStatuses: [], errors: [message], lastUpdated: .now)
    }

    var summaryText: String {
        switch mode {
        case .stopped:
            return "Syncthing stopped"
        case .starting:
            return "Starting Syncthing"
        case .healthy:
            if folderStatuses.isEmpty {
                return "Syncthing running"
            }
            return "\(folderStatuses.count) folder\(folderStatuses.count == 1 ? "" : "s") idle"
        case .syncing:
            let syncingCount = folderStatuses.filter(\.isSyncing).count
            return "\(syncingCount) folder\(syncingCount == 1 ? "" : "s") syncing"
        case .error:
            return actionableError ?? "Syncthing needs attention"
        case .updating:
            return "Applying update"
        }
    }

    var actionableError: String? {
        if let firstError = errors.first {
            return firstError
        }

        if let folder = folderStatuses.first(where: \.hasActionableError) {
            return "Folder \(folder.id) needs attention"
        }

        return nil
    }

    var isSyncing: Bool {
        mode == .syncing
    }
}
