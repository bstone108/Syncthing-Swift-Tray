import AppKit
import Combine
import Foundation
@preconcurrency import Sparkle

private enum AppUpdateDefaultsKey {
    static let postponedVersion = "appUpdate.postponedVersion"
}

/// Sparkle 2 updater for the tray wrapper itself.
///
/// Syncthing *daemon* binary updates stay in `UpdateCoordinator` and are not
/// handled here.
///
/// Two delegates on purpose: `SPUUpdaterDelegate` is main-actor isolated in
/// Sparkle (`NS_SWIFT_UI_ACTOR`), while `SPUStandardUserDriverDelegate` is
/// nonisolated. Conforming to both from one class infers a single isolation and
/// breaks one of the two conformances under Swift 6.
@MainActor
final class AppUpdateController: NSObject, SPUUpdaterDelegate {
    private let logHandler: (AttentionLogLevel, String) -> Void
    private let defaults: UserDefaults
    private let userDriverDelegate: AppUpdateUserDriverDelegate
    private var updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: AnyCancellable?

    var onCanCheckForUpdatesChange: ((Bool) -> Void)?

    init(
        logHandler: @escaping (AttentionLogLevel, String) -> Void,
        defaults: UserDefaults = .standard
    ) {
        self.logHandler = logHandler
        self.defaults = defaults
        self.userDriverDelegate = AppUpdateUserDriverDelegate(defaults: defaults)
        super.init()
    }

    func start() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: userDriverDelegate
        )
        updaterController = controller

        // Bridge Sparkle's KVO property without reading the main-actor isolated
        // `canCheckForUpdates` getter from a Sendable observation closure.
        canCheckObservation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canCheck in
                MainActor.assumeIsolated {
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
            return SUAppcastItem.empty()
        }

        let comparator = SUStandardVersionComparator.default
        var best = matching[0]
        for candidate in matching.dropFirst() {
            if comparator.compareVersion(best.versionString, toVersion: candidate.versionString) == .orderedAscending {
                best = candidate
            }
        }
        return best
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        defaults.set(item.versionString, forKey: AppUpdateDefaultsKey.postponedVersion)
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
}

/// Accessory-app activation and postpone-once reminders.
///
/// Sparkle invokes these callbacks on the main thread; the type itself stays
/// nonisolated so it can satisfy `SPUStandardUserDriverDelegate`.
private final class AppUpdateUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        super.init()
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        defaults.string(forKey: AppUpdateDefaultsKey.postponedVersion) != update.versionString
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.accessory)
            NSApp.dockTile.badgeLabel = nil
        }
    }
}
