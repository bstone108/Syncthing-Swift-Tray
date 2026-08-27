import Foundation

struct ManagedSyncthingConfiguration: Equatable {
    let apiKey: String
    let guiURL: URL
    let wasCreated: Bool
}

enum ConfigManagerError: LocalizedError {
    case configGenerationFailed
    case invalidConfig

    var errorDescription: String? {
        switch self {
        case .configGenerationFailed:
            return "Syncthing Tray could not generate a valid Syncthing configuration."
        case .invalidConfig:
            return "Syncthing Tray found an invalid Syncthing configuration."
        }
    }
}

final class ConfigManager: @unchecked Sendable {
    private let paths: AppPaths
    private let stateStore: RuntimeStateStore

    init(paths: AppPaths, stateStore: RuntimeStateStore) {
        self.paths = paths
        self.stateStore = stateStore
    }

    func prepareManagedConfiguration(binaryURL: URL) async throws -> ManagedSyncthingConfiguration {
        try paths.prepareDirectories()
        let configAlreadyExists = FileManager.default.fileExists(atPath: paths.configFileURL.path)

        if configAlreadyExists == false {
            try await generateDefaultConfig(using: binaryURL)
        }

        guard FileManager.default.fileExists(atPath: paths.configFileURL.path) else {
            throw ConfigManagerError.configGenerationFailed
        }

        let apiKey = stateStore.load().apiKey ?? Self.generateAPIKey()
        try await Task.detached(priority: .utility) {
            try Self.applyManagedConfiguration(to: self.paths.configFileURL, apiKey: apiKey)
        }.value

        _ = try stateStore.mutate { state in
            state.apiKey = apiKey
        }

        return ManagedSyncthingConfiguration(
            apiKey: apiKey,
            guiURL: URL(string: "http://127.0.0.1:8384")!,
            wasCreated: configAlreadyExists == false
        )
    }

    private func generateDefaultConfig(using binaryURL: URL) async throws {
        let homePath = paths.syncthingHomeDirectory.path

        let candidateCommands: [[String]] = [
            ["generate", "--home", homePath],
            ["generate", "--home", homePath, "--no-default-folder"],
            ["--generate=\(homePath)"]
        ]

        for arguments in candidateCommands {
            let output = try await Task.detached(priority: .utility) {
                try CommandRunner.run(executableURL: binaryURL, arguments: arguments)
            }.value

            if output.exitCode == 0 && FileManager.default.fileExists(atPath: self.paths.configFileURL.path) {
                return
            }
        }

        try await bootstrapByTemporaryServe(binaryURL: binaryURL)
    }

    private func bootstrapByTemporaryServe(binaryURL: URL) async throws {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = binaryURL
            process.arguments = [
                "serve",
                "--home", self.paths.syncthingHomeDirectory.path,
                "--no-browser",
                "--no-upgrade",
                "--log-level=warn"
            ]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            defer {
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                }
            }

            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline {
                if FileManager.default.fileExists(atPath: self.paths.configFileURL.path) {
                    return
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }

            throw ConfigManagerError.configGenerationFailed
        }.value
    }

    private static func applyManagedConfiguration(to configURL: URL, apiKey: String) throws {
        let document = try XMLDocument(contentsOf: configURL, options: [.nodePreserveAll])
        guard let root = document.rootElement() else {
            throw ConfigManagerError.invalidConfig
        }

        let gui = upsertChild(named: "gui", under: root)
        upsertChild(named: "address", under: gui, stringValue: "127.0.0.1:8384")
        upsertChild(named: "apikey", under: gui, stringValue: apiKey)
        gui.setAttributesWith(["enabled": "true", "tls": "false", "sendBasicAuthPrompt": "false"])

        let options = upsertChild(named: "options", under: root)
        upsertChild(named: "autoUpgradeIntervalH", under: options, stringValue: "0")
        upsertChild(named: "startBrowser", under: options, stringValue: "false")

        let data = document.xmlData(options: .nodePrettyPrint)
        try data.write(to: configURL, options: .atomic)
    }

    @discardableResult
    private static func upsertChild(named name: String, under parent: XMLElement, stringValue: String? = nil) -> XMLElement {
        let child = parent.elements(forName: name).first ?? {
            let element = XMLElement(name: name)
            parent.addChild(element)
            return element
        }()
        if let stringValue {
            child.stringValue = stringValue
        }
        return child
    }

    private static func generateAPIKey() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}
