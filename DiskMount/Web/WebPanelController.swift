import AppKit
import Foundation
import OSLog
import WebKit

final class WebPanelController: NSViewController, WKScriptMessageHandler {
    private static let autoMountPreferenceKey = "AutoMountNTFSPersistentIDs"
    private let diskService = DiskService()
    private let anyLinuxFS = AnyLinuxFSService()
    private let workerQueue = DispatchQueue(label: "com.samni.DiskMount.worker", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.samni.DiskMount", category: "disk-actions")
    private var webView: WKWebView!
    private var devices: [DiskDevice] = []
    private var busyDeviceID: String?
    private var message: String?
    private var errorMessage: String?
    private var removableVolumePermissionRequired = false
    private var refreshTimer: Timer?
    private var proMode = false
    private var language = "en"
    private var authorizedProtectedDeviceIDs: Set<String> = []
    private var autoMountNTFSPersistentIDs = Set(
        UserDefaults.standard.stringArray(forKey: WebPanelController.autoMountPreferenceKey) ?? []
    )
    private var autoMountAttempts: Set<String> = []

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
        case "openPrivacySettings":
            openRemovableVolumePrivacySettings()
        case "setAutoMountNTFS":
            guard let deviceID,
                  let device = devices.first(where: { $0.id == deviceID }),
                  device.isNTFS,
                  !device.isProtected else {
                publish(error: localized(zh: "无法为该卷更改自动读写设置。", en: "Automatic read/write settings are unavailable for this volume."))
                return
            }
            let enabled = payload["enabled"] as? Bool ?? false
            if enabled {
                autoMountNTFSPersistentIDs.insert(device.persistentID)
            } else {
                autoMountNTFSPersistentIDs.remove(device.persistentID)
            }
            saveAutoMountPreferences()
            self.message = localized(
                zh: enabled ? "已记住 \(device.name)；下次插入时将自动尝试 NTFS 读写加载。" : "已关闭 \(device.name) 的自动 NTFS 读写加载。",
                en: enabled ? "Remembered \(device.name). DiskMount will try read/write mounting when it is inserted again." : "Disabled automatic NTFS read/write mounting for \(device.name)."
            )
            errorMessage = nil
            publish()
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
                    self.autoMountAttempts.formIntersection(devices.map(\.persistentID))
                    if !silent {
                        self.errorMessage = nil
                    }
                    self.publish()
                    self.performNextAutomaticMountIfNeeded()
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
        if action == "mountNTFS" {
            autoMountAttempts.insert(device.persistentID)
        }
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
                    if action == "mountNTFS" {
                        self.autoMountNTFSPersistentIDs.insert(device.persistentID)
                        self.saveAutoMountPreferences()
                    }
                    self.busyDeviceID = nil
                    self.message = successMessage
                    self.errorMessage = nil
                    self.removableVolumePermissionRequired = false
                    self.publish()
                    self.performNextAutomaticMountIfNeeded()
                }
            } catch {
                self.logger.error("Action \(action, privacy: .public) on \(device.devicePath, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async {
                    self.busyDeviceID = nil
                    if case AnyLinuxFSError.fullDiskAccessRequired = error {
                        self.removableVolumePermissionRequired = true
                    }
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

    private func saveAutoMountPreferences() {
        UserDefaults.standard.set(
            autoMountNTFSPersistentIDs.sorted(),
            forKey: Self.autoMountPreferenceKey
        )
    }

    private func performNextAutomaticMountIfNeeded() {
        guard busyDeviceID == nil,
              let device = devices.first(where: {
                  $0.isNTFS
                      && !$0.isProtected
                      && !$0.writable
                      && autoMountNTFSPersistentIDs.contains($0.persistentID)
                      && !autoMountAttempts.contains($0.persistentID)
              }) else { return }
        autoMountAttempts.insert(device.persistentID)
        message = localized(
            zh: "已识别记住的磁盘 \(device.name)，正在自动启用 NTFS 读写…",
            en: "Recognized \(device.name). Enabling NTFS read/write automatically…"
        )
        perform(action: "mountNTFS", on: device)
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

    private func openRemovableVolumePrivacySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
        publish(error: localized(
            zh: "无法打开系统设置。请手动前往“隐私与安全性”→“完全磁盘访问权限”。",
            en: "Could not open System Settings. Go to Privacy & Security → Full Disk Access."
        ))
    }

    private func localized(zh: String, en: String) -> String {
        language == "zh" ? zh : en
    }

    private func localizedErrorDescription(_ error: Error) -> String {
        if let anyLinuxFSError = error as? AnyLinuxFSError {
            switch anyLinuxFSError {
            case .notInstalled:
                return localized(
                    zh: "NTFS 运行时不可用，无法进行读写加载。",
                    en: "The NTFS runtime is unavailable, so read/write mounting cannot continue."
                )
            case .fullDiskAccessRequired:
                return localized(
                    zh: "macOS 已阻止 NTFS 引擎读取原始磁盘。DiskMount 已尝试恢复普通只读挂载；请确认已为 DiskMount 开启“完全磁盘访问权限”和“可移动卷”权限，完全退出并重新打开 App 后再试。",
                    en: "macOS blocked the NTFS engine from reading the raw disk. DiskMount attempted to restore the normal read-only mount. Enable Full Disk Access and Removable Volumes access for DiskMount, fully quit and reopen the app, then try again."
                )
            }
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
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.3",
            devices: devices,
            dependency: anyLinuxFS.dependencyState(),
            proMode: proMode,
            language: language,
            authorizedProtectedDeviceIDs: authorizedProtectedDeviceIDs.sorted(),
            autoMountNTFSPersistentIDs: autoMountNTFSPersistentIDs.sorted(),
            busyDeviceID: busyDeviceID,
            message: message,
            error: errorMessage,
            removableVolumePermissionRequired: removableVolumePermissionRequired
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
