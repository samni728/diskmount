import AppKit
import Foundation
import WebKit

final class WebPanelController: NSViewController, WKScriptMessageHandler {
    private let diskService = DiskService()
    private let anyLinuxFS = AnyLinuxFSService()
    private let workerQueue = DispatchQueue(label: "com.samni.DiskMount.worker", qos: .userInitiated)
    private var webView: WKWebView!
    private var devices: [DiskDevice] = []
    private var busyDeviceID: String?
    private var message: String?
    private var errorMessage: String?
    private var refreshTimer: Timer?
    private var proMode = false

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        observeVolumeChanges()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        observeVolumeChanges()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "bridge")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        view = webView

        guard let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") else {
            webView.loadHTMLString("<h3>DiskMount WebUI 资源缺失</h3>", baseURL: nil)
            return
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh(silent: true)
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func observeVolumeChanges() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(volumeDidChange(_:)), name: NSWorkspace.didMountNotification, object: nil)
        center.addObserver(self, selector: #selector(volumeDidChange(_:)), name: NSWorkspace.didUnmountNotification, object: nil)
        center.addObserver(self, selector: #selector(volumeDidChange(_:)), name: NSWorkspace.didRenameVolumeNotification, object: nil)
    }

    @objc private func volumeDidChange(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refresh(silent: true)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "bridge", let payload = message.body as? [String: Any],
              let action = payload["action"] as? String else { return }

        let deviceID = payload["deviceID"] as? String
        switch action {
        case "ready", "refresh":
            refresh()
        case "setProMode":
            proMode = payload["enabled"] as? Bool ?? false
            refresh()
        case "openProject", "starProject":
            openProjectPage()
        case "quit":
            NSApp.terminate(nil)
        case "mount", "unmount", "eject", "mountNTFS", "open":
            guard let deviceID, let device = devices.first(where: { $0.id == deviceID }) else {
                publish(error: "设备状态已变化，请刷新后重试。")
                return
            }
            guard !device.isProtected else {
                publish(error: "这是系统或辅助分区，只允许在 PRO 模式中查看，禁止执行磁盘操作。")
                return
            }
            perform(action: action, on: device)
        default:
            publish(error: "不支持的操作：\(action)")
        }
    }

    func refresh(silent: Bool = false) {
        guard busyDeviceID == nil else { return }
        workerQueue.async { [weak self] in
            guard let self else { return }
            do {
                let devices = try self.diskService.listExternalVolumes(includeAdvanced: self.proMode)
                DispatchQueue.main.async {
                    self.devices = devices
                    if !silent {
                        self.errorMessage = nil
                    }
                    self.publish()
                }
            } catch {
                DispatchQueue.main.async {
                    self.publish(error: "读取外接磁盘失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func perform(action: String, on device: DiskDevice) {
        busyDeviceID = device.id
        message = nil
        errorMessage = nil
        publish()

        workerQueue.async { [weak self] in
            guard let self else { return }
            do {
                let successMessage: String
                switch action {
                case "mount":
                    try self.diskService.mount(device)
                    successMessage = "已加载 \(device.name)"
                case "unmount":
                    if device.isNTFS, self.anyLinuxFS.executablePath != nil {
                        do {
                            try self.anyLinuxFS.unmount(devicePath: device.devicePath)
                        } catch {
                            // A read-only NTFS volume may have been mounted by macOS rather than anylinuxfs.
                            try self.diskService.unmount(device)
                        }
                    } else {
                        try self.diskService.unmount(device)
                    }
                    successMessage = "已卸载 \(device.name)"
                case "eject":
                    try self.diskService.eject(device)
                    successMessage = "已安全弹出 \(device.name)"
                case "mountNTFS":
                    guard device.isNTFS else { throw PanelError.notNTFS }
                    try self.anyLinuxFS.mountReadWrite(devicePath: device.devicePath)
                    successMessage = "已将 \(device.name) 以 NTFS 读写模式加载"
                case "open":
                    try self.diskService.openInFinder(device)
                    successMessage = "已在 Finder 打开 \(device.name)"
                default:
                    throw PanelError.unsupportedAction
                }

                let refreshed = (try? self.diskService.listExternalVolumes(includeAdvanced: self.proMode)) ?? self.devices
                DispatchQueue.main.async {
                    self.devices = refreshed
                    self.busyDeviceID = nil
                    self.message = successMessage
                    self.errorMessage = nil
                    self.publish()
                }
            } catch {
                DispatchQueue.main.async {
                    self.busyDeviceID = nil
                    self.publish(error: error.localizedDescription)
                }
            }
        }
    }

    private func publish(error: String) {
        errorMessage = error
        message = nil
        publish()
    }

    private func openProjectPage() {
        guard let url = URL(string: "https://github.com/samni728/diskmount"),
              NSWorkspace.shared.open(url) else {
            publish(error: "无法打开项目页面，请访问 github.com/samni728/diskmount")
            return
        }
    }

    private func publish() {
        let state = PanelState(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.2",
            devices: devices,
            dependency: anyLinuxFS.dependencyState(),
            proMode: proMode,
            busyDeviceID: busyDeviceID,
            message: message,
            error: errorMessage
        )
        guard let data = try? JSONEncoder().encode(state),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.DiskMount && window.DiskMount.receive(\(json));")
    }
}

enum PanelError: LocalizedError {
    case notNTFS
    case unsupportedAction

    var errorDescription: String? {
        switch self {
        case .notNTFS: return "该分区不是 NTFS，已拒绝 NTFS 读写挂载。"
        case .unsupportedAction: return "不支持的磁盘操作。"
        }
    }
}
