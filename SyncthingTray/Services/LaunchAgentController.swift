import Darwin
import Foundation

enum LaunchAgentJobState: Equatable {
    case unloaded
    case loaded(pid: Int?)

    var isLoaded: Bool {
        if case .unloaded = self {
            return false
        }
        return true
    }
}

enum LaunchAgentControllerError: LocalizedError {
    case runtimeFailedToStart

    var errorDescription: String? {
        switch self {
        case .runtimeFailedToStart:
            return "Syncthing failed to start."
        }
    }
}

final class LaunchAgentController: @unchecked Sendable {
    static let label = "com.brandonstone.syncthingtray.syncthing"

    private static let supervisorScript = """
    set -eu

    parent_pid="$1"
    parent_command="$2"
    child_pid_file="$3"
    supervisor_pid_file="$4"
    log_path="$5"
    shift 5

    echo $$ > "$supervisor_pid_file"
    "$@" >>"$log_path" 2>&1 &
    child_pid=$!
    echo "$child_pid" > "$child_pid_file"

    cleanup() {
      if kill -0 "$child_pid" 2>/dev/null; then
        kill "$child_pid" 2>/dev/null || true
        wait "$child_pid" 2>/dev/null || true
      fi
      rm -f "$child_pid_file" "$supervisor_pid_file"
    }

    trap cleanup EXIT INT TERM HUP

    while kill -0 "$child_pid" 2>/dev/null; do
      current_parent_command=$(/bin/ps -p "$parent_pid" -o command= 2>/dev/null || true)
      if [ -z "$current_parent_command" ]; then
        break
      fi

      case "$current_parent_command" in
        *"$parent_command"*) ;;
        *) break ;;
      esac

      sleep 1
    done
    """

    private let paths: AppPaths
    private let launchctlURL = URL(fileURLWithPath: "/bin/launchctl")
    private let psURL = URL(fileURLWithPath: "/bin/ps")
    private let shellURL = URL(fileURLWithPath: "/bin/zsh")
    private let userDomain = "gui/\(getuid())"

    init(paths: AppPaths) {
        self.paths = paths
    }

    func installOrUpdatePlist() async throws {
        try await uninstallLegacyLaunchAgent()
    }

    func start() async throws {
        try await installOrUpdatePlist()
        stopSynchronously()
        try removePIDFiles()

        let parentPID = ProcessInfo.processInfo.processIdentifier
        let parentCommand = CommandLine.arguments.first ?? Bundle.main.executablePath ?? "Syncthing Tray"

        let process = Process()
        process.executableURL = shellURL
        process.arguments = [
            "-c", Self.supervisorScript,
            "--",
            String(parentPID),
            parentCommand,
            paths.syncthingPIDURL.path,
            paths.syncthingSupervisorPIDURL.path,
            paths.syncthingLogURL.path,
            paths.currentBinarySymlinkURL.path,
            "serve",
            "--home", paths.syncthingHomeDirectory.path,
            "--no-browser",
            "--no-upgrade",
            "--log-level=warn"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let pid = readPID(from: paths.syncthingPIDURL), processIsRunning(pid) {
                return
            }

            if process.isRunning == false {
                break
            }

            try await Task.sleep(nanoseconds: 250_000_000)
        }

        stopSynchronously()
        throw LaunchAgentControllerError.runtimeFailedToStart
    }

    func stop() async throws {
        try await installOrUpdatePlist()
        stopSynchronously()
    }

    func stopSynchronously() {
        killProcessIfNeeded(readPID(from: paths.syncthingSupervisorPIDURL))
        killProcessIfNeeded(readPID(from: paths.syncthingPIDURL))
        killUntrackedManagedProcessesIfNeeded()
        try? removePIDFiles()
    }

    func restart() async throws {
        try await stop()
        try await start()
    }

    func status() async -> LaunchAgentJobState {
        if let pid = readPID(from: paths.syncthingPIDURL), processIsRunning(pid) {
            return .loaded(pid: Int(pid))
        }

        if let pid = readPID(from: paths.syncthingSupervisorPIDURL), processIsRunning(pid) {
            return .loaded(pid: nil)
        }

        return .unloaded
    }

    private func uninstallLegacyLaunchAgent() async throws {
        _ = try? await launchctl(["bootout", userDomain, paths.launchAgentPlistURL.path])
        try? FileManager.default.removeItem(at: paths.launchAgentPlistURL)
    }

    private func removePIDFiles() throws {
        try? FileManager.default.removeItem(at: paths.syncthingPIDURL)
        try? FileManager.default.removeItem(at: paths.syncthingSupervisorPIDURL)
    }

    private func readPID(from url: URL) -> Int32? {
        guard
            let rawValue = try? String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let pid = Int32(rawValue)
        else {
            return nil
        }

        return pid
    }

    private func killProcessIfNeeded(_ pid: Int32?) {
        guard let pid, processIsRunning(pid) else {
            return
        }

        kill(pid, SIGTERM)

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if processIsRunning(pid) == false {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        kill(pid, SIGKILL)
    }

    private func processIsRunning(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }

        return errno == EPERM
    }

    private func killUntrackedManagedProcessesIfNeeded() {
        guard let output = try? CommandRunner.run(executableURL: psURL, arguments: ["-axo", "pid=,command="]) else {
            return
        }

        let managedBinaryPath = paths.currentBinarySymlinkURL.path
        let managedHomePath = paths.syncthingHomeDirectory.path

        for line in output.stdout.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.isEmpty == false else { continue }

            let components = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard
                components.count == 2,
                let pid = Int32(components[0]),
                pid != ProcessInfo.processInfo.processIdentifier
            else {
                continue
            }

            let command = String(components[1])
            guard command.contains(managedBinaryPath), command.contains(managedHomePath) else {
                continue
            }

            killProcessIfNeeded(pid)
        }
    }

    private func launchctl(_ arguments: [String]) async throws -> CommandOutput {
        try CommandRunner.run(executableURL: launchctlURL, arguments: arguments)
    }
}
