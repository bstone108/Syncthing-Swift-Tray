import Foundation

enum DebugLog {
    private static let logURL = URL(fileURLWithPath: "/tmp/SyncthingTray-debug.log")
    private static let isEnabled = ProcessInfo.processInfo.environment["SYNCTHING_TRAY_DEBUG"] == "1"

    static func write(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message())\n"

        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)

            if FileManager.default.fileExists(atPath: logURL.path) == false {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }

            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                try? handle.write(contentsOf: data)
            }
        }
    }
}
