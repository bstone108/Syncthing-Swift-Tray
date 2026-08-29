import Foundation

/// CPU slice used for tray-app Sparkle updates.
///
/// Dedicated `macos-arm64` / `macos-x86_64` archives are required. Universal
/// extras exist on GitHub Releases but must not be selected for auto-update.
enum AppUpdateArchitecture: String, Equatable, Sendable {
    case arm64
    case x86_64

    var assetToken: String { "macos-\(rawValue)" }

    /// Running CPU, not the process slice. An Intel binary under Rosetta on
    /// Apple Silicon should still move to the arm64 tray app.
    static var currentCPU: AppUpdateArchitecture {
        var isArm: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &isArm, &size, nil, 0) == 0, isArm == 1 {
            return .arm64
        }
        return .x86_64
    }

    static func dedicatedArchiveName(version: String, architecture: AppUpdateArchitecture) -> String {
        "SyncthingTray-\(version)-\(architecture.assetToken).zip"
    }

    static func matchesDedicatedArchive(_ filename: String, architecture: AppUpdateArchitecture) -> Bool {
        let name = (filename as NSString).lastPathComponent.lowercased()
        if name.contains("universal") {
            return false
        }
        return name.contains(architecture.assetToken.lowercased())
    }

    static func preferredArchiveName(in names: [String], architecture: AppUpdateArchitecture) -> String? {
        names.first { matchesDedicatedArchive($0, architecture: architecture) }
    }
}
