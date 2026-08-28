import AppKit
import Foundation
@preconcurrency import Sparkle

/// Sparkle 2 updater for the tray wrapper itself.
///
/// Syncthing *daemon* binary updates stay in `UpdateCoordinator` and are not
/// handled here.
final class AppUpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private enum DefaultsKey {
        static let postponedVersion = "appUpdate.postponedVersion"
    }

    private let logHandler: (AttentionLogLevel, String) -> Void
    private let defaults: UserDefaults
    private var updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    var onCanCheckForUpdatesChange: ((Bool) -> Void)?

    init(
        logHandler: @escaping (AttentionLogLevel, String) -> Void,
        defaults: UserDefaults = .standard
    ) {
        self.logHandler = logHandler
        self.defaults = defaults
        super.init()
    }

    func start() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        updaterController = controller

        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            DispatchQueue.main.async {
                self?.onCanCheckForUpdatesChange?(canCheck)
            }
        }

        do {
            try controller.updater.start()
            logHandler(.info, "App update checks enabled (Sparkle, about every two days).")
        } catch {
            logHandler(.warning, "App updater could not start: \(error.localizedDescription)")
        }
    }

    func checkForUpdates() {
        guard let updaterController else {
            logHandler(.warning, "App updater is not available.")
            return
        }
        updaterController.checkForUpdates(nil)
    }

    // MARK: - SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        []
    }

    func bestValidUpdate(in appcast: SUAppcast, for updater: SPUUpdater) -> SUAppcastItem? {
        let architecture = AppUpdateArchitecture.currentCPU
        let matching = appcast.items.filter { item in
            guard let filename = item.fileURL?.lastPathComponent else {
                return false
            }
            return AppUpdateArchitecture.matchesDedicatedArchive(filename, architecture: architecture)
        }

        guard matching.isEmpty == false else {
            // Do not fall back to a universal extra (or any other slice).
            return SUAppcastItem.emptyAppcastItem()
        }

        let comparator = SUStandardVersionComparator.defaultComparator
        var best = matching[0]
        for candidate in matching.dropFirst() {
            if comparator.compareVersion(best.versionString, toVersion: candidate.versionString) == .orderedAscending {
                best = candidate
            }
        }
        return best
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        defaults.set(item.versionString, forKey: DefaultsKey.postponedVersion)
        logHandler(.info, "App update \(item.displayVersionString) will install the next time Syncthing Tray quits.")
        // Return false so Sparkle keeps installing on quit without us taking over
        // immediateInstallHandler. Scheduled UI for this version is suppressed separately.
        return false
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        // SUNoUpdateError (1001): scheduled check found nothing newer.
        if nsError.domain == SUSparkleErrorDomain, nsError.code == 1001 {
            return
        }
        logHandler(.warning, "App update check failed: \(error.localizedDescription)")
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        logHandler(.info, "A newer Syncthing Tray \(item.displayVersionString) is available.")
    }

    // MARK: - SPUStandardUserDriverDelegate

    @objc var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        if postponedVersion == update.versionString {
            return false
        }
        return true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        NSApp.dockTile.badgeLabel = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.dockTile.badgeLabel = nil
    }

    private var postponedVersion: String? {
        defaults.string(forKey: DefaultsKey.postponedVersion)
    }
}
