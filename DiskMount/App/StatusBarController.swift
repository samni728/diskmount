import AppKit
import OSLog

final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let webPanelController = WebPanelController()
    private let logger = Logger(subsystem: "com.samni.DiskMount", category: "status-bar")

    override init() {
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "externaldrive.fill", accessibilityDescription: "DiskMount")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.title = " DiskMount"
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            button.toolTip = version.isEmpty ? "DiskMount" : "DiskMount \(version)"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        popover.contentSize = NSSize(width: 420, height: 440)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = webPanelController
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }

        showPopover()
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        webPanelController.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.state = .on
        logger.info("Popover requested; shown=\(self.popover.isShown, privacy: .public)")
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.state = .off
    }
}
