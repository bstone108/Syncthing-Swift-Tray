import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var statusSnapshot: StatusSnapshot = .stopped
    @Published private(set) var currentRuntimeVersion = "Not installed"
    @Published private(set) var minimumRuntimeVersion = SupportedRuntime.minimumSyncthingVersion
    @Published private(set) var stagedRuntimeVersion: String?
    @Published private(set) var updateBannerMessage: String?
    @Published private(set) var guiURLText = "http://127.0.0.1:8384"

    let attentionLogStore: AttentionLogStore
    let preferences: PreferencesStore

    private let paths: AppPaths
    private let runtimeStateStore: RuntimeStateStore
    private let binaryCatalog: BinaryCatalog
    private let binaryManager: BinaryManager
    private let configManager: ConfigManager
    private let launchAgentController: LaunchAgentController
    private let launchAtLoginController: LaunchAtLoginController
    private let networkMonitor: NetworkMonitor
    private let syncthingClient: SyncthingClient
    private let embeddedGUIController: EmbeddedGUIController

    private lazy var updateCoordinator: UpdateCoordinator = {
        let coordinator = UpdateCoordinator(
            binaryManager: binaryManager,
            runtimeStateStore: runtimeStateStore,
            preferences: preferences,
            networkMonitor: networkMonitor,
            wrapperVersionProvider: { Bundle.main.appVersionString },
            logHandler: { [weak self] level, message in
                self?.attentionLogStore.addRunner(level: level, message: message)
            },
            applyHandler: { [weak self] in
                await self?.applyStagedUpdateIfPossible() ?? false
            },
            guiWindowOpenProvider: { [weak self] in
                self?.embeddedGUIController.isWindowOpen ?? false
            }
        )
        coordinator.stateDidChange = { [weak self] in
            self?.syncUpdatePresentation()
        }
        return coordinator
    }()

    private var statusItemController: StatusItemController?
    private var bootstrapTask: Task<Void, Never>?
    private var statusRefreshTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?

    private var guiURL = URL(string: "http://127.0.0.1:8384")!
    private var apiKey = ""
    private var desiredRuntimeRunning: Bool
    private var runtimeRestartPolicy = RuntimeRestartPolicy()
    private var runtimeRecoveryInFlight = false

    init(
        paths: AppPaths = .standard,
        attentionLogStore: AttentionLogStore = AttentionLogStore(),
        preferences: PreferencesStore = PreferencesStore(),
        binaryCatalog: BinaryCatalog = BinaryCatalog(),
        networkMonitor: NetworkMonitor = NetworkMonitor(),
        syncthingClient: SyncthingClient = SyncthingClient(),
        launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController(),
        embeddedGUIController: EmbeddedGUIController = EmbeddedGUIController()
    ) {
        self.paths = paths
        self.attentionLogStore = attentionLogStore
        self.preferences = preferences
        self.binaryCatalog = binaryCatalog
        runtimeStateStore = RuntimeStateStore(url: paths.stateFileURL)
        binaryManager = BinaryManager(paths: paths, catalog: binaryCatalog, stateStore: runtimeStateStore)
        configManager = ConfigManager(paths: paths, stateStore: runtimeStateStore)
        launchAgentController = LaunchAgentController(paths: paths)
        self.networkMonitor = networkMonitor
        self.syncthingClient = syncthingClient
        self.launchAtLoginController = launchAtLoginController
        self.embeddedGUIController = embeddedGUIController
        desiredRuntimeRunning = preferences.startSyncthingAutomatically

        embeddedGUIController.onWindowOpenChanged = { [weak self] isOpen in
            Task { @MainActor in
                self?.handleGUIWindowChanged(isOpen)
            }
        }

        networkMonitor.onStatusChange = { [weak self] isConnected in
            Task { @MainActor in
                self?.updateCoordinator.handleConnectivityChanged(isConnected)
            }
        }
    }

    func start() {
        DebugLog.write("AppModel.start begin")
        statusItemController = StatusItemController(appModel: self)
        DebugLog.write("StatusItemController created")
        statusItemController?.install()
        DebugLog.write("StatusItemController install returned")
        networkMonitor.start()
        DebugLog.write("Network monitor started")
        synchronizeLaunchAtLoginPreference()
        DebugLog.write("Launch at login synchronized")

        bootstrapTask = Task { [weak self] in
            DebugLog.write("Bootstrap task scheduled")
            await self?.bootstrap()
        }
    }

    func shutdown() {
        desiredRuntimeRunning = false
        bootstrapTask?.cancel()
        statusRefreshTask?.cancel()
        eventTask?.cancel()
        updateCoordinator.stop()
        networkMonitor.stop()
        launchAgentController.stopSynchronously()
    }

    func requestStart() {
        desiredRuntimeRunning = true
        Task { [weak self] in
            await self?.startSyncthing()
        }
    }

    func requestStop() {
        desiredRuntimeRunning = false
        runtimeRestartPolicy.reset()
        Task { [weak self] in
            await self?.stopSyncthing()
        }
    }

    func requestRestart() {
        Task { [weak self] in
            await self?.restartSyncthing()
        }
    }

    func requestRepairRuntime() {
        Task { [weak self] in
            await self?.repairRuntime()
        }
    }

    func requestOpenGUI() {
        Task { [weak self] in
            await self?.openGUI()
        }
    }

    func requestQuit() {
        NSApp.terminate(nil)
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        let previousValue = preferences.launchAtLoginEnabled
        preferences.launchAtLoginEnabled = enabled

        do {
            try launchAtLoginController.setEnabled(enabled)
            attentionLogStore.addRunner(level: .info, message: enabled ? "Launch at login enabled." : "Launch at login disabled.")
        } catch {
            preferences.launchAtLoginEnabled = previousValue
            attentionLogStore.addRunner(level: .warning, message: "Unable to change launch at login: \(error.localizedDescription)")
        }
    }

    func setStartSyncthingAutomatically(_ enabled: Bool) {
        preferences.startSyncthingAutomatically = enabled
        attentionLogStore.addRunner(level: .info, message: enabled ? "Syncthing will start automatically." : "Automatic Syncthing start disabled.")

        if enabled {
            desiredRuntimeRunning = true
            Task { [weak self] in
                _ = await self?.recoverRuntimeIfNeeded(force: true, reason: "auto-start enabled") ?? false
                await self?.refreshStatus()
            }
        } else if statusSnapshot.mode == .stopped {
            desiredRuntimeRunning = false
            runtimeRestartPolicy.reset()
        }
    }

    func setAutoCheckUpdates(_ enabled: Bool) {
        preferences.autoCheckUpdates = enabled
        attentionLogStore.addRunner(level: .info, message: enabled ? "Runtime update checks enabled." : "Runtime update checks disabled.")

        if enabled {
            Task { [weak self] in
                await self?.updateCoordinator.performCheckIfDue(force: true)
            }
        }
    }

    private func bootstrap() async {
        DebugLog.write("bootstrap begin")
        do {
            try paths.prepareDirectories()
            DebugLog.write("paths prepared")

            if let previousVersion = binaryManager.currentVersion(), SupportedRuntime.isSupported(version: previousVersion) == false {
                attentionLogStore.addRunner(
                    level: .warning,
                    message: "Managed Syncthing \(previousVersion) is below the minimum supported version \(SupportedRuntime.minimumSyncthingVersion). Attempting an immediate runtime update."
                )
            }

            let binaryURL = try await binaryManager.ensureRuntimeAvailable(wrapperVersion: Bundle.main.appVersionString)
            DebugLog.write("runtime available at \(binaryURL.path)")
            currentRuntimeVersion = binaryManager.currentVersion() ?? "Unknown"

            let configuration = try await configManager.prepareManagedConfiguration(binaryURL: binaryURL)
            DebugLog.write("configuration prepared guiURL=\(configuration.guiURL.absoluteString)")
            guiURL = configuration.guiURL
            guiURLText = configuration.guiURL.absoluteString
            apiKey = configuration.apiKey

            await syncthingClient.configure(baseURL: configuration.guiURL, apiKey: configuration.apiKey)
            DebugLog.write("syncthing client configured")
            try await launchAgentController.installOrUpdatePlist()
            DebugLog.write("launch agent installed")

            if configuration.wasCreated || preferences.startSyncthingAutomatically {
                desiredRuntimeRunning = true
                try await launchAgentController.start()
                DebugLog.write("launch agent started")
            }

            startMonitoring()
            DebugLog.write("monitoring started")
            updateCoordinator.start()
            DebugLog.write("update coordinator started")
            syncUpdatePresentation()
            await refreshStatus()
            DebugLog.write("initial status refreshed")

            if configuration.wasCreated {
                attentionLogStore.addRunner(level: .info, message: "Managed Syncthing home initialized.")
                await openGUI()
                DebugLog.write("GUI opened for first launch")
            }
        } catch {
            DebugLog.write("bootstrap failed: \(error.localizedDescription)")
            statusSnapshot = .bootstrapError(error.localizedDescription)
            attentionLogStore.addRunner(level: .error, message: "Bootstrap failed: \(error.localizedDescription)")
        }
    }

    private func startMonitoring() {
        statusRefreshTask?.cancel()
        eventTask?.cancel()

        statusRefreshTask = Task { [weak self] in
            guard let self else { return }
            while Task.isCancelled == false {
                await self.refreshStatus()
                try? await Task.sleep(for: .seconds(5))
            }
        }

        eventTask = Task { [weak self] in
            guard let self else { return }
            while Task.isCancelled == false {
                do {
                    let events = try await self.syncthingClient.pollEvents()
                    if events.contains(where: Self.eventRequiresRefresh(_:)) {
                        await self.refreshStatus()
                    }
                } catch {
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    private func refreshStatus() async {
        let agentState = await launchAgentController.status()
        currentRuntimeVersion = binaryManager.currentVersion() ?? currentRuntimeVersion
        stagedRuntimeVersion = binaryManager.stagedVersion()

        guard agentState.isLoaded else {
            if await recoverRuntimeIfNeeded(reason: "runtime missing during status refresh") {
                statusSnapshot = StatusSnapshot.from(
                    agentLoaded: true,
                    apiResponding: false,
                    folderStatuses: [],
                    errors: [],
                    isUpdating: updateCoordinator.isApplyingUpdate
                )
                return
            }
            statusSnapshot = .stopped
            return
        }

        runtimeRestartPolicy.reset()

        do {
            let snapshot = try await syncthingClient.fetchSnapshot()
            attentionLogStore.mergeSyncthingLogs(snapshot.logs)
            attentionLogStore.mergeSyncthingErrors(snapshot.errors)
            statusSnapshot = StatusSnapshot.from(
                agentLoaded: true,
                apiResponding: true,
                folderStatuses: snapshot.folderStatuses,
                errors: snapshot.errors.map(\.message),
                isUpdating: updateCoordinator.isApplyingUpdate
            )
            try? binaryManager.markCurrentVersionHealthy()
        } catch {
            statusSnapshot = StatusSnapshot.from(
                agentLoaded: true,
                apiResponding: false,
                folderStatuses: [],
                errors: [],
                isUpdating: updateCoordinator.isApplyingUpdate
            )
        }
    }

    private func startSyncthing() async {
        do {
            try await launchAgentController.start()
            runtimeRestartPolicy.reset()
            attentionLogStore.addRunner(level: .info, message: "Syncthing started.")
            await refreshStatus()
        } catch {
            attentionLogStore.addRunner(level: .error, message: "Unable to start Syncthing: \(error.localizedDescription)")
        }
    }

    private func stopSyncthing() async {
        do {
            try await launchAgentController.stop()
            attentionLogStore.addRunner(level: .info, message: "Syncthing stopped.")
            statusSnapshot = .stopped
        } catch {
            attentionLogStore.addRunner(level: .error, message: "Unable to stop Syncthing: \(error.localizedDescription)")
        }
    }

    private func restartSyncthing() async {
        do {
            try await launchAgentController.restart()
            desiredRuntimeRunning = true
            runtimeRestartPolicy.reset()
            attentionLogStore.addRunner(level: .info, message: "Syncthing restarted.")
            await refreshStatus()
        } catch {
            attentionLogStore.addRunner(level: .error, message: "Unable to restart Syncthing: \(error.localizedDescription)")
        }
    }

    private func repairRuntime() async {
        do {
            let binaryURL = try await binaryManager.repairRuntime(wrapperVersion: Bundle.main.appVersionString)
            let configuration = try await configManager.prepareManagedConfiguration(binaryURL: binaryURL)
            guiURL = configuration.guiURL
            guiURLText = configuration.guiURL.absoluteString
            apiKey = configuration.apiKey
            await syncthingClient.configure(baseURL: configuration.guiURL, apiKey: configuration.apiKey)
            try await launchAgentController.restart()
            desiredRuntimeRunning = true
            runtimeRestartPolicy.reset()
            attentionLogStore.addRunner(level: .info, message: "Syncthing runtime repaired and restarted.")
            await refreshStatus()
        } catch {
            attentionLogStore.addRunner(level: .error, message: "Runtime repair failed: \(error.localizedDescription)")
        }
    }

    private func openGUI() async {
        embeddedGUIController.showLoading(
            title: "Syncthing Web GUI",
            message: statusSnapshot.mode == .stopped ? "Starting Syncthing..." : "Connecting to Syncthing..."
        )

        if await launchAgentController.status().isLoaded == false {
            desiredRuntimeRunning = true
            _ = await recoverRuntimeIfNeeded(force: true, reason: "web GUI requested")
        }

        guard await waitForGUIAvailability() else {
            let message = "Syncthing web GUI is unavailable. Check the attention log for startup details."
            embeddedGUIController.showError(title: "Syncthing Web GUI", message: message, baseURL: guiURL)
            attentionLogStore.addRunner(level: .warning, message: message)
            await refreshStatus()
            return
        }

        embeddedGUIController.show(url: guiURL)
    }

    private func synchronizeLaunchAtLoginPreference() {
        do {
            if launchAtLoginController.isEnabled() != preferences.launchAtLoginEnabled {
                try launchAtLoginController.setEnabled(preferences.launchAtLoginEnabled)
            }
        } catch {
            attentionLogStore.addRunner(level: .warning, message: "Launch at login could not be synchronized: \(error.localizedDescription)")
        }
    }

    private func handleGUIWindowChanged(_ isOpen: Bool) {
        updateCoordinator.handleGUIWindowChanged(isOpen: isOpen)
        syncUpdatePresentation()
    }

    private func recoverRuntimeIfNeeded(force: Bool = false, reason: String) async -> Bool {
        guard desiredRuntimeRunning else {
            return false
        }

        if runtimeRecoveryInFlight {
            return true
        }

        let now = Date()
        if runtimeRestartPolicy.shouldAttempt(at: now, force: force) == false {
            return true
        }

        runtimeRecoveryInFlight = true
        defer {
            runtimeRecoveryInFlight = false
        }

        do {
            try await launchAgentController.start()
            runtimeRestartPolicy.reset()
            attentionLogStore.addRunner(level: .warning, message: "Syncthing was restarted automatically.")
            return true
        } catch {
            let delay = runtimeRestartPolicy.recordFailure(at: now)
            let seconds = max(1, Int(delay.rounded()))
            attentionLogStore.addRunner(
                level: .warning,
                message: "Syncthing failed to start (\(reason)). Retrying automatically in \(seconds)s."
            )
            return true
        }
    }

    private func syncUpdatePresentation() {
        updateBannerMessage = updateCoordinator.updateBannerMessage
        stagedRuntimeVersion = binaryManager.stagedVersion()
        embeddedGUIController.setUpdateBanner(updateBannerMessage)

        if updateCoordinator.isApplyingUpdate, statusSnapshot.mode != .error, statusSnapshot.mode != .stopped {
            statusSnapshot = StatusSnapshot.from(
                agentLoaded: true,
                apiResponding: true,
                folderStatuses: statusSnapshot.folderStatuses,
                errors: statusSnapshot.errors,
                isUpdating: true
            )
        }
    }

    private func applyStagedUpdateIfPossible() async -> Bool {
        guard let stagedVersion = binaryManager.stagedVersion() else {
            return true
        }

        attentionLogStore.addRunner(level: .info, message: "Applying Syncthing \(stagedVersion).")
        defer {
            syncUpdatePresentation()
        }

        do {
            _ = try await binaryManager.activateStagedVersion()
            currentRuntimeVersion = binaryManager.currentVersion() ?? currentRuntimeVersion

            let configuration = try await configManager.prepareManagedConfiguration(binaryURL: paths.currentBinarySymlinkURL)
            guiURL = configuration.guiURL
            guiURLText = configuration.guiURL.absoluteString
            apiKey = configuration.apiKey
            await syncthingClient.configure(baseURL: configuration.guiURL, apiKey: configuration.apiKey)

            try await launchAgentController.restart()

            guard await validateCurrentRuntime() else {
                throw NSError(
                    domain: "SyncthingTray.Update",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The updated runtime did not pass monitor-only API validation."]
                )
            }

            try binaryManager.markCurrentVersionHealthy()
            currentRuntimeVersion = stagedVersion
            await refreshStatus()
            return true
        } catch {
            attentionLogStore.addRunner(level: .error, message: "Syncthing \(stagedVersion) failed validation. Rolling back.")

            do {
                try binaryManager.markVersionFailed(stagedVersion, wrapperVersion: Bundle.main.appVersionString)
                _ = try await binaryManager.rollbackToLastKnownGood()
                currentRuntimeVersion = binaryManager.currentVersion() ?? currentRuntimeVersion
                let configuration = try await configManager.prepareManagedConfiguration(binaryURL: paths.currentBinarySymlinkURL)
                guiURL = configuration.guiURL
                guiURLText = configuration.guiURL.absoluteString
                apiKey = configuration.apiKey
                await syncthingClient.configure(baseURL: configuration.guiURL, apiKey: configuration.apiKey)
                try await launchAgentController.restart()
                await refreshStatus()
            } catch {
                attentionLogStore.addRunner(level: .error, message: "Rollback failed: \(error.localizedDescription)")
            }

            return false
        }
    }

    private func validateCurrentRuntime() async -> Bool {
        for _ in 0..<12 {
            if await syncthingClient.performMonitorOnlyHealthCheck() {
                return true
            }
            try? await Task.sleep(for: .seconds(5))
        }
        return false
    }

    private func waitForGUIAvailability() async -> Bool {
        for _ in 0..<20 {
            if await syncthingClient.performMonitorOnlyHealthCheck() {
                return true
            }
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }

    private static func eventRequiresRefresh(_ event: SyncthingEvent) -> Bool {
        switch event.kind {
        case .stateChanged, .folderErrors, .folderSummary:
            return true
        case .unknown:
            return false
        }
    }
}
