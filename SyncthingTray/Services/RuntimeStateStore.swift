import Foundation

final class RuntimeStateStore: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL) {
        self.url = url

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    func load() -> RuntimeState {
        lock.withLock {
            loadUnlocked()
        }
    }

    @discardableResult
    func mutate(_ mutation: (inout RuntimeState) -> Void) throws -> RuntimeState {
        try lock.withLock {
            var state = loadUnlocked()
            mutation(&state)
            try saveUnlocked(state)
            return state
        }
    }

    func save(_ state: RuntimeState) throws {
        try lock.withLock {
            try saveUnlocked(state)
        }
    }

    private func loadUnlocked() -> RuntimeState {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .initial
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(RuntimeState.self, from: data)
        } catch {
            return .initial
        }
    }

    private func saveUnlocked(_ state: RuntimeState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }
}
