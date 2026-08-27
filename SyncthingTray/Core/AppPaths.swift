import Foundation

struct AppPaths {
    let rootDirectory: URL

    static let standard = AppPaths(
        rootDirectory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("SyncthingTray", isDirectory: true)
    )

    var binariesDirectory: URL {
        rootDirectory.appendingPathComponent("bin", isDirectory: true)
    }

    var versionsDirectory: URL {
        binariesDirectory.appendingPathComponent("versions", isDirectory: true)
    }

    var currentBinarySymlinkURL: URL {
        binariesDirectory.appendingPathComponent("current", isDirectory: false)
    }

    var syncthingHomeDirectory: URL {
        rootDirectory.appendingPathComponent("syncthing-home", isDirectory: true)
    }

    var logsDirectory: URL {
        rootDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    var cacheDirectory: URL {
        rootDirectory.appendingPathComponent("cache", isDirectory: true)
    }

    var stateFileURL: URL {
        rootDirectory.appendingPathComponent("state.json", isDirectory: false)
    }

    var configFileURL: URL {
        syncthingHomeDirectory.appendingPathComponent("config.xml", isDirectory: false)
    }

    var runnerLogURL: URL {
        logsDirectory.appendingPathComponent("runner.log", isDirectory: false)
    }

    var syncthingLogURL: URL {
        logsDirectory.appendingPathComponent("syncthing.log", isDirectory: false)
    }

    var syncthingPIDURL: URL {
        cacheDirectory.appendingPathComponent("syncthing.pid", isDirectory: false)
    }

    var syncthingSupervisorPIDURL: URL {
        cacheDirectory.appendingPathComponent("syncthing-supervisor.pid", isDirectory: false)
    }

    var launchAgentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent(LaunchAgentController.label + ".plist", isDirectory: false)
    }

    func prepareDirectories() throws {
        let fileManager = FileManager.default
        for directory in [rootDirectory, binariesDirectory, versionsDirectory, syncthingHomeDirectory, logsDirectory, cacheDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func versionDirectory(for version: String) -> URL {
        versionsDirectory.appendingPathComponent(version, isDirectory: true)
    }

    func binaryURL(for version: String) -> URL {
        versionDirectory(for: version).appendingPathComponent("syncthing", isDirectory: false)
    }
}
