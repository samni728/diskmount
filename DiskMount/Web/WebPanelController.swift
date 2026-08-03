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
    private var language = "en"
    private var authorizedProtectedDeviceIDs: Set<String> = []

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

        if let requestedLanguage = payload["language"] as? String,
           ["en", "zh"].contains(requestedLanguage) {
            language = requestedLanguage
        }
        let deviceID = payload["deviceID"] as? String
        switch action {
        case "ready", "refresh":
            refresh()
        case "setLanguage":
            self.message = nil
            errorMessage = nil
            publish()
        case "setProMode":
            proMode = payload["enabled"] as? Bool ?? false
            if !proMode {
                authorizedProtectedDeviceIDs.removeAll()
                self.message = nil
                errorMessage = nil
            }
            refresh()
        case "authorizeProtected":
            guard proMode,
                  let deviceID,
                  let device = devices.first(where: { $0.id == deviceID }),
                  device.isProtected else {
                publish(error: localized(
                    zh: "只能在专家模式中对当前可见的高级卷授权。",
                    en: "Only a visible advanced volume can be authorized while Expert Mode is active."
                ))
                return
            }
            authorizedProtectedDeviceIDs.insert(deviceID)
            self.message = localized(
                zh: "已解锁 \(device.name) 的本次会话访问；操作前请确保已备份重要数据。",
                en: "Unlocked \(device.name) for this session. Back up important data before making changes."
            )
            errorMessage = nil
            publish()
        case "openProject", "starProject":
            openProjectPage()
        case "quit":
            NSApp.terminate(nil)
        case "mount", "unmount", "eject", "mountNTFS", "open", "mountProtected", "unmountProtected":
            guard let deviceID, let device = devices.first(where: { $0.id == deviceID }) else {
                publish(error: localized(
                    zh: "设备状态已变化，请刷新后重试。",
                    en: "The device state has changed. Refresh and try again."
                ))
                return
            }
            if device.isProtected {
                let allowedAction = ["mountProtected", "unmountProtected", "open"].contains(action)
                guard proMode, authorizedProtectedDeviceIDs.contains(device.id), allowedAction else {
                    publish(error: localized(
                        zh: "该高级卷尚未通过二次安全确认，或该操作对受保护磁盘不可用。",
                        en: "This advanced volume has not passed the second safety confirmation, or the requested operation is blocked for protected disks."
                    ))
                    return
                }
            } else if ["mountProtected", "unmountProtected"].contains(action) {
                publish(error: localized(zh: "已拒绝无效的高级卷操作。", en: "Invalid advanced-volume operation was blocked."))
                return
            }
            perform(action: action, on: device)
        default:
            publish(error: localized(zh: "不支持的操作：\(action)", en: "Unsupported operation: \(action)"))
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
                    self.authorizedProtectedDeviceIDs.formIntersection(devices.map(\.id))
                    if !silent {
                        self.errorMessage = nil
                    }
                    self.publish()
                }
            } catch {
                DispatchQueue.main.async {
                    self.publish(error: self.localized(
                        zh: "读取外接磁盘失败：\(error.localizedDescription)",
                        en: "Failed to read external disks: \(error.localizedDescription)"
                    ))
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
                    successMessage = self.localized(zh: "已加载 \(device.name)", en: "Mounted \(device.name)")
                case "mountProtected":
                    try self.diskService.mountProtected(device)
                    successMessage = self.localized(
                        zh: "已加载高级卷 \(device.name)；实际读写能力由文件系统与 macOS 安全策略决定。",
                        en: "Mounted advanced volume \(device.name). Actual write access depends on its file system and macOS security policy."
                    )
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
                    successMessage = self.localized(zh: "已卸载 \(device.name)", en: "Unmounted \(device.name)")
                case "unmountProtected":
                    try self.diskService.unmountProtected(device)
                    successMessage = self.localized(zh: "已卸载高级卷 \(device.name)", en: "Unmounted advanced volume \(device.name)")
                case "eject":
                    try self.diskService.eject(device)
                    successMessage = self.localized(zh: "已安全弹出 \(device.name)", en: "Safely ejected \(device.name)")
                case "mountNTFS":
                    guard device.isNTFS else { throw PanelError.notNTFS }
                    try self.anyLinuxFS.mountReadWrite(devicePath: device.devicePath)
                    successMessage = self.localized(
                        zh: "已将 \(device.name) 以 NTFS 读写模式加载",
                        en: "Mounted \(device.name) with NTFS read/write access"
                    )
                case "open":
                    try self.diskService.openInFinder(device)
                    successMessage = self.localized(zh: "已在 Finder 打开 \(device.name)", en: "Opened \(device.name) in Finder")
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
                    self.publish(error: self.localizedErrorDescription(error))
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
            publish(error: localized(
                zh: "无法打开项目页面，请访问 github.com/samni728/diskmount",
                en: "Could not open the project page. Visit github.com/samni728/diskmount"
            ))
            return
        }
    }

    private func localized(zh: String, en: String) -> String {
        language == "zh" ? zh : en
    }

    private func localizedErrorDescription(_ error: Error) -> String {
        if error is AnyLinuxFSError {
            return localized(
                zh: "NTFS 运行时不可用，无法进行读写加载。",
                en: "The NTFS runtime is unavailable, so read/write mounting cannot continue."
            )
        }
        if error is DiskServiceError {
            return localized(zh: "无法在 Finder 中打开该磁盘。", en: "Could not open this disk in Finder.")
        }
        if let panelError = error as? PanelError {
            switch panelError {
            case .notNTFS:
                return localized(zh: "该分区不是 NTFS，已拒绝 NTFS 读写加载。", en: "This partition is not NTFS. Read/write mounting was blocked.")
            case .unsupportedAction:
                return localized(zh: "不支持的磁盘操作。", en: "Unsupported disk operation.")
            }
        }
        return error.localizedDescription
    }

    private func publish() {
        let state = PanelState(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0",
            devices: devices,
            dependency: anyLinuxFS.dependencyState(),
            proMode: proMode,
            language: language,
            authorizedProtectedDeviceIDs: authorizedProtectedDeviceIDs.sorted(),
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
