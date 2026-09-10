import XCTest
@testable import SyncthingTray

@MainActor
final class UpdateCoordinatorTests: XCTestCase {
    func testClosingGUIWithStagedRuntimeAppliesPromptly() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpdateCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let paths = AppPaths(rootDirectory: rootDirectory)
        let stateStore = RuntimeStateStore(url: paths.stateFileURL)
        try stateStore.mutate { state in
            state.stagedVersion = "2.0.0"
        }

        let defaults = UserDefaults(suiteName: "UpdateCoordinatorTests-\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: defaults.description)
        let preferences = PreferencesStore(defaults: defaults)
        preferences.autoCheckUpdates = false

        let applied = expectation(description: "staged runtime applies after the GUI closes")
        let coordinator = UpdateCoordinator(
            binaryManager: BinaryManager(paths: paths, catalog: BinaryCatalog(), stateStore: stateStore),
            runtimeStateStore: stateStore,
            preferences: preferences,
            networkMonitor: NetworkMonitor(),
            wrapperVersionProvider: { "test-wrapper" },
            logHandler: { _, _ in },
            applyHandler: {
                applied.fulfill()
                return true
            },
            guiWindowOpenProvider: { false }
        )

        coordinator.handleGUIWindowChanged(isOpen: false)
        await fulfillment(of: [applied], timeout: 2)
    }
}
