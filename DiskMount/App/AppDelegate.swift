import AppKit
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let logger = Logger(subsystem: "com.samni.DiskMount", category: "lifecycle")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
        logger.info("DiskMount application finished launching")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.statusBarController?.showPopover()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("DiskMount application will terminate")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBarController?.showPopover()
        return true
    }
}
