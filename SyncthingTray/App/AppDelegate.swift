import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appModel: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.write("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)
        DebugLog.write("activationPolicy=\(NSApp.activationPolicy().rawValue)")

        let model = AppModel()
        appModel = model
        DebugLog.write("appModel created")
        model.start()
        DebugLog.write("appModel start returned")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        DebugLog.write("applicationWillTerminate")
        appModel?.shutdown()
    }
}
