import Foundation

@MainActor
final class UpdateCoordinator {
    private let binaryManager: BinaryManager
    private let runtimeStateStore: RuntimeStateStore
    private let preferences: PreferencesStore
    private let networkMonitor: NetworkMonitor
    private let wrapperVersionProvider: () -> String
    private let logHandler: (AttentionLogLevel, String) -> Void
    private let applyHandler: () async -> Bool
    private let guiWindowOpenProvider: () -> Bool

    private var hourlyTask: Task<Void, Never>?
    private var delayedApplyTask: Task<Void, Never>?

    private(set) var updateBannerMessage: String?
    private(set) var isApplyingUpdate = false
    var stateDidChange: (() -> Void)?

    init(
        binaryManager: BinaryManager,
        runtimeStateStore: RuntimeStateStore,
        preferences: PreferencesStore,
        networkMonitor: NetworkMonitor,
        wrapperVersionProvider: @escaping () -> String,
        logHandler: @escaping (AttentionLogLevel, String) -> Void,
        applyHandler: @escaping () async -> Bool,
        guiWindowOpenProvider: @escaping () -> Bool
    ) {
        self.binaryManager = binaryManager
        self.runtimeStateStore = runtimeStateStore
        self.preferences = preferences
        self.networkMonitor = networkMonitor
        self.wrapperVersionProvider = wrapperVersionProvider
        self.logHandler = logHandler
        self.applyHandler = applyHandler
        self.guiWindowOpenProvider = guiWindowOpenProvider
    }

    func start() {
        if runtimeStateStore.load().nextDueAt == nil {
            _ = try? runtimeStateStore.mutate { state in
                state.nextDueAt = .now
            }
        }

        hourlyTask = Task { [weak self] in
            guard let self else { return }
            await self.performCheckIfDue()
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(3600))
                await self.performCheckIfDue()
            }
        }
    }

    func stop() {
        hourlyTask?.cancel()
        delayedApplyTask?.cancel()
    }

    func handleConnectivityChanged(_ isConnected: Bool) {
        guard isConnected else { return }
        Task { [weak self] in
            await self?.performCheckIfDue()
        }
    }

    func handleGUIWindowChanged(isOpen: Bool) {
        if isOpen {
            delayedApplyTask?.cancel()
            if let stagedVersion = binaryManager.stagedVersion() {
                updateBannerMessage = "Syncthing \(stagedVersion) is ready. Close the GUI to apply it."
                stateDidChange?()
            }
            return
        }

        guard binaryManager.stagedVersion() != nil else {
            updateBannerMessage = nil
            stateDidChange?()
            return
        }

        updateBannerMessage = nil
        stateDidChange?()
        delayedApplyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(300))
            guard let self, Task.isCancelled == false else { return }
            _ = await self.applyStagedUpdate()
        }
    }

    func performCheckIfDue(force: Bool = false) async {
        guard preferences.autoCheckUpdates else { return }

        let state = runtimeStateStore.load()
        let dueDate = state.nextDueAt ?? .distantPast

        if force == false && Date() < dueDate {
            return
        }

        guard networkMonitor.isConnected else { return }

        do {
            let stagedRelease = try await binaryManager.stageLatestReleaseIfNeeded(wrapperVersion: wrapperVersionProvider())
            _ = try runtimeStateStore.mutate { state in
                state.lastSuccessfulCheckAt = .now
                state.nextDueAt = Calendar.current.date(byAdding: .day, value: 7, to: .now)
            }

            guard let stagedRelease else { return }
            logHandler(.info, "Downloaded Syncthing \(stagedRelease.version).")

            if guiWindowOpenProvider() {
                updateBannerMessage = "Syncthing \(stagedRelease.version) is ready. Close the GUI to apply it."
                stateDidChange?()
                return
            }

            _ = await applyStagedUpdate()
        } catch {
            logHandler(.warning, "Runtime update check failed: \(error.localizedDescription)")
        }
    }

    private func applyStagedUpdate() async -> Bool {
        isApplyingUpdate = true
        stateDidChange?()
        defer {
            isApplyingUpdate = false
            updateBannerMessage = nil
            stateDidChange?()
        }

        let applied = await applyHandler()
        if applied {
            logHandler(.info, "Syncthing runtime update applied successfully.")
        }
        return applied
    }
}
