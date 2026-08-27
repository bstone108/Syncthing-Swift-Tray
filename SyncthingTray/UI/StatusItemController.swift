import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private static let popoverVerticalOffset: CGFloat = 12

    private let appModel: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()

    private var cancellables: Set<AnyCancellable> = []
    private var animationTask: Task<Void, Never>?
    private var spinFrameIndex = 0
    private var spinningFrames: [NSImage] = []

    init(appModel: AppModel) {
        self.appModel = appModel
        super.init()
    }

    func install() {
        DebugLog.write("StatusItemController.install begin")
        let contentView = PopoverContentView(appModel: appModel, attentionLogStore: appModel.attentionLogStore)
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.contentSize = NSSize(width: 390, height: 470)
        DebugLog.write("popover configured")

        if let button = statusItem.button {
            DebugLog.write("status item button exists")
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "Syncthing Tray"
            button.image = makeBaseImage()
            button.isEnabled = true
            button.alphaValue = 1
            button.appearsDisabled = false
            DebugLog.write("status item button configured imageSize=\(button.image?.size.width ?? -1)x\(button.image?.size.height ?? -1)")
        } else {
            DebugLog.write("status item button missing")
        }

        appModel.$statusSnapshot
            .sink { [weak self] snapshot in
                Task { @MainActor in
                    self?.updateIcon(for: snapshot)
                }
            }
            .store(in: &cancellables)

        updateIcon(for: appModel.statusSnapshot)
        DebugLog.write("StatusItemController.install end")
    }

    func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    func invalidate() {
        stopSpinAnimation()
        cancellables.removeAll()
        closePopover()
        statusItem.button?.target = nil
        statusItem.button?.action = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // NSStatusItem delivers this via objc_msgSend, not the Swift MainActor
    // executor. Hop before touching isolated state; a MainActor-isolated
    // @objc thunk is what SIGSEGV'd in _checkExpectedExecutor.
    @objc
    nonisolated private func handleStatusItemClick(_ sender: AnyObject?) {
        Task { @MainActor in
            self.togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            var anchorRect = button.bounds
            anchorRect.origin.y -= Self.popoverVerticalOffset
            popover.show(relativeTo: anchorRect, of: button, preferredEdge: .minY)
        }
    }

    private func updateIcon(for snapshot: StatusSnapshot) {
        statusItem.button?.toolTip = snapshot.summaryText

        switch snapshot.mode {
        case .syncing:
            startSpinAnimation()
        case .error:
            stopSpinAnimation()
            statusItem.button?.image = makeErrorImage()
        default:
            stopSpinAnimation()
            statusItem.button?.image = makeBaseImage()
        }
    }

    private func startSpinAnimation() {
        if spinningFrames.isEmpty {
            spinningFrames = stride(from: 0.0, to: 360.0, by: 45.0).compactMap { angle in
                rotatedImage(makeBaseImage(), degrees: angle)
            }
        }

        guard animationTask == nil else { return }

        animationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.advanceSpinFrame()
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    private func stopSpinAnimation() {
        animationTask?.cancel()
        animationTask = nil
        spinFrameIndex = 0
    }

    private func advanceSpinFrame() {
        guard spinningFrames.isEmpty == false else { return }
        statusItem.button?.image = spinningFrames[spinFrameIndex]
        spinFrameIndex = (spinFrameIndex + 1) % spinningFrames.count
    }

    private func makeBaseImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        let frame = NSRect(origin: .zero, size: image.size).insetBy(dx: 1.5, dy: 1.5)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let radius = min(frame.width, frame.height) / 2
        let ringRadius = radius - 1.2
        let nodeRadius: CGFloat = 2.1
        let strokeColor = NSColor.labelColor

        let nodeAngles: [CGFloat] = [140, 20, 285]
        let orbitNodes = nodeAngles.map { angle -> CGPoint in
            let radians = angle * .pi / 180
            return CGPoint(
                x: center.x + cos(radians) * (ringRadius - 0.7),
                y: center.y + sin(radians) * (ringRadius - 0.7)
            )
        }

        strokeColor.setStroke()
        strokeColor.setFill()

        let ringPath = NSBezierPath()
        ringPath.lineWidth = 1.8
        ringPath.appendArc(withCenter: center, radius: ringRadius, startAngle: 0, endAngle: 360)
        ringPath.stroke()

        let hubPath = NSBezierPath(ovalIn: NSRect(
            x: center.x - nodeRadius,
            y: center.y - nodeRadius,
            width: nodeRadius * 2,
            height: nodeRadius * 2
        ))
        hubPath.fill()

        for node in orbitNodes {
            let spokePath = NSBezierPath()
            spokePath.lineWidth = 1.6
            spokePath.lineCapStyle = .round
            spokePath.move(to: center)
            spokePath.line(to: node)
            spokePath.stroke()

            let nodePath = NSBezierPath(ovalIn: NSRect(
                x: node.x - nodeRadius,
                y: node.y - nodeRadius,
                width: nodeRadius * 2,
                height: nodeRadius * 2
            ))
            nodePath.fill()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func makeErrorImage() -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        let baseImage = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "Error")?
            .withSymbolConfiguration(configuration) ?? NSImage(size: NSSize(width: 18, height: 18))
        baseImage.size = NSSize(width: 18, height: 18)
        baseImage.isTemplate = false
        return baseImage.tinted(with: .systemRed)
    }

    private func rotatedImage(_ image: NSImage, degrees: CGFloat) -> NSImage {
        let rotated = NSImage(size: image.size)
        rotated.lockFocus()

        let transform = NSAffineTransform()
        transform.translateX(by: image.size.width / 2, yBy: image.size.height / 2)
        transform.rotate(byDegrees: degrees)
        transform.translateX(by: -image.size.width / 2, yBy: -image.size.height / 2)
        transform.concat()

        image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1)
        rotated.unlockFocus()
        rotated.isTemplate = false
        return rotated
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let tintedImage = copy() as? NSImage ?? NSImage(size: size)
        tintedImage.lockFocus()
        color.set()
        let imageRect = NSRect(origin: .zero, size: size)
        imageRect.fill(using: .sourceAtop)
        draw(in: imageRect, from: imageRect, operation: .destinationIn, fraction: 1)
        tintedImage.unlockFocus()
        tintedImage.isTemplate = false
        return tintedImage
    }
}
