import Foundation

struct CommandOutput {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private final class PipeCollector: @unchecked Sendable {
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var data = Data()

    init(fileHandle: FileHandle) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let collectedData = fileHandle.readDataToEndOfFile()
            lock.withLock {
                data = collectedData
            }
            group.leave()
        }
    }

    func waitForData() -> Data {
        group.wait()
        return lock.withLock { data }
    }
}

enum CommandRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:]
    ) throws -> CommandOutput {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        if environment.isEmpty == false {
            process.environment = ProcessInfo.processInfo.environment.merging(environment, uniquingKeysWith: { _, new in new })
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let stdoutCollector = PipeCollector(fileHandle: stdoutPipe.fileHandleForReading)
        let stderrCollector = PipeCollector(fileHandle: stderrPipe.fileHandleForReading)

        process.waitUntilExit()
        let stdoutData = stdoutCollector.waitForData()
        let stderrData = stderrCollector.waitForData()

        return CommandOutput(
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }
}
