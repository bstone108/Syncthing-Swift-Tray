import AppKit
import WebKit

@MainActor
final class EmbeddedGUIController {
    var onWindowOpenChanged: ((Bool) -> Void)?

    private(set) var isWindowOpen = false

    private var window: NSWindow?
    private var windowBridge: GUIWindowBridge?
    private var webView: WKWebView?
    private var bannerContainer: NSVisualEffectView?
    private var bannerLabel: NSTextField?
    private var pendingBannerMessage: String?

    func show(url: URL) {
        let window = ensureWindow()
        present(window: window)
        webView?.load(URLRequest(url: url))
    }

    func showLoading(title: String, message: String) {
        let window = ensureWindow()
        present(window: window)
        webView?.loadHTMLString(htmlShell(title: title, message: message, accentHex: "#58C4E8"), baseURL: nil)
    }

    func showError(title: String, message: String, baseURL: URL?) {
        let window = ensureWindow()
        present(window: window)
        webView?.loadHTMLString(htmlShell(title: title, message: message, accentHex: "#FF6B6B"), baseURL: baseURL)
    }

    func setUpdateBanner(_ message: String?) {
        pendingBannerMessage = message

        guard let bannerContainer, let bannerLabel else { return }
        bannerLabel.stringValue = message ?? ""
        bannerContainer.isHidden = message == nil
    }

    func close() {
        webView?.stopLoading()
        window?.orderOut(nil)
        handleWindowWillClose()
    }

    private func handleWindowWillClose() {
        updateWindowState(isOpen: false)
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Syncthing Tray"
        window.minSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SyncthingTray.WebUI")

        let bridge = GUIWindowBridge { [weak self] in
            Task { @MainActor in
                self?.handleWindowWillClose()
            }
        }
        windowBridge = bridge
        window.delegate = bridge

        guard let contentView = window.contentView else {
            preconditionFailure("NSWindow created without a contentView")
        }
        contentView.wantsLayer = true

        let bannerContainer = NSVisualEffectView()
        bannerContainer.translatesAutoresizingMaskIntoConstraints = false
        bannerContainer.material = .headerView
        bannerContainer.blendingMode = .behindWindow
        bannerContainer.state = .active
        bannerContainer.isHidden = true

        let bannerLabel = NSTextField(labelWithString: "")
        bannerLabel.translatesAutoresizingMaskIntoConstraints = false
        bannerLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        bannerLabel.lineBreakMode = .byWordWrapping

        bannerContainer.addSubview(bannerLabel)

        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: contentView.bounds, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(bannerContainer)
        contentView.addSubview(webView)

        NSLayoutConstraint.activate([
            bannerContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            bannerContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bannerContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            bannerLabel.topAnchor.constraint(equalTo: bannerContainer.topAnchor, constant: 10),
            bannerLabel.bottomAnchor.constraint(equalTo: bannerContainer.bottomAnchor, constant: -10),
            bannerLabel.leadingAnchor.constraint(equalTo: bannerContainer.leadingAnchor, constant: 14),
            bannerLabel.trailingAnchor.constraint(equalTo: bannerContainer.trailingAnchor, constant: -14),

            webView.topAnchor.constraint(equalTo: bannerContainer.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        self.window = window
        self.webView = webView
        self.bannerContainer = bannerContainer
        self.bannerLabel = bannerLabel
        setUpdateBanner(pendingBannerMessage)

        return window
    }

    private func present(window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        updateWindowState(isOpen: true)
    }

    private func htmlShell(title: String, message: String, accentHex: String) -> String {
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let escapedMessage = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br/>")

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              color-scheme: dark;
              --bg: #0b0f14;
              --panel: #111821;
              --text: #f5f7fa;
              --muted: #a7b3c2;
              --accent: \(accentHex);
            }
            body {
              margin: 0;
              min-height: 100vh;
              display: grid;
              place-items: center;
              background:
                radial-gradient(circle at top, rgba(88, 196, 232, 0.18), transparent 45%),
                linear-gradient(180deg, #0a0e13, var(--bg));
              color: var(--text);
              font: 15px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            }
            .panel {
              width: min(520px, calc(100vw - 48px));
              padding: 28px;
              border-radius: 18px;
              background: rgba(17, 24, 33, 0.92);
              border: 1px solid rgba(255, 255, 255, 0.08);
              box-shadow: 0 24px 60px rgba(0, 0, 0, 0.35);
            }
            .eyebrow {
              margin: 0 0 10px;
              color: var(--accent);
              font-size: 12px;
              font-weight: 700;
              letter-spacing: 0.08em;
              text-transform: uppercase;
            }
            h1 {
              margin: 0 0 10px;
              font-size: 28px;
              line-height: 1.1;
            }
            p {
              margin: 0;
              color: var(--muted);
              line-height: 1.5;
            }
          </style>
        </head>
        <body>
          <section class="panel">
            <div class="eyebrow">Syncthing Tray</div>
            <h1>\(escapedTitle)</h1>
            <p>\(escapedMessage)</p>
          </section>
        </body>
        </html>
        """
    }

    private func updateWindowState(isOpen: Bool) {
        guard isWindowOpen != isOpen else { return }
        isWindowOpen = isOpen
        onWindowOpenChanged?(isOpen)
    }
}

/// AppKit window callbacks are objc_msgSend, not Swift MainActor hops.
/// Keep the delegate off `@MainActor` so WebKit layer commits do not enter
/// `_checkExpectedExecutor` / `swift_task_isMainExecutorImpl`.
private final class GUIWindowBridge: NSObject, NSWindowDelegate {
    private let onWillClose: @Sendable () -> Void

    init(onWillClose: @escaping @Sendable () -> Void) {
        self.onWillClose = onWillClose
    }

    func windowWillClose(_ notification: Notification) {
        onWillClose()
    }
}
