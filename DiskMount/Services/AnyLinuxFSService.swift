import Foundation

final class AnyLinuxFSService {
    private var candidatePaths: [String] {
        var paths: [String] = []
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("anylinuxfs/bin/anylinuxfs").path {
            paths.append(bundled)
        }
        // Development fallback only. Release DMGs embed their own runtime.
        paths.append("/opt/homebrew/bin/anylinuxfs")
        return paths
    }

    var executablePath: String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func dependencyState() -> DependencyState {
        guard let path = executablePath else {
            return DependencyState(available: false, path: nil, version: nil, bundled: false)
        }
        let rawVersion = try? CommandRunner.run(path, arguments: ["--version"]).stdoutText
        let bundled = path.contains("DiskMount.app/Contents/Resources/anylinuxfs")
        return DependencyState(available: true, path: path, version: rawVersion ?? "anylinuxfs", bundled: bundled)
    }

    func mountReadWrite(
        devicePath: String,
        deviceIdentifier: String,
        volumeName: String
    ) throws {
        guard let path = executablePath else {
            throw AnyLinuxFSError.notInstalled
        }
        let arguments = Self.mountArguments(
            devicePath: devicePath,
            deviceIdentifier: deviceIdentifier,
            volumeName: volumeName
        )
        let customMountPoint = Self.customMountPoint(
            deviceIdentifier: deviceIdentifier,
            volumeName: volumeName
        )
        do {
            _ = try CommandRunner.runNTFSMountAsAdministrator(
                path,
                devicePath: devicePath,
                arguments: arguments,
                customMountPoint: customMountPoint
            )
            let mounts = DiskService().activeAnyLinuxFSMounts()
            guard Self.hasVerifiedWritableMount(
                deviceIdentifier: deviceIdentifier,
                mounts: mounts
            ) else {
                if mounts[deviceIdentifier] != nil {
                    _ = try? CommandRunner.runAnyLinuxFSUnmountAsAdministrator(
                        path,
                        devicePath: devicePath,
                        cleanupMountPoint: customMountPoint
                    )
                }
                _ = try? CommandRunner.run(
                    "/usr/sbin/diskutil",
                    arguments: ["mount", devicePath]
                )
                throw AnyLinuxFSError.mountVerificationFailed
            }
        } catch {
            if Self.isRawDiskPermissionError(error) {
                throw AnyLinuxFSError.fullDiskAccessRequired
            }
            if Self.isMissingMountVerificationError(error) {
                throw AnyLinuxFSError.mountVerificationFailed
            }
            throw error
        }
    }

    func unmount(devicePath: String) throws {
        guard let path = executablePath else {
            throw AnyLinuxFSError.notInstalled
        }
        let deviceIdentifier = URL(fileURLWithPath: devicePath).lastPathComponent
        let activeMountPoint = DiskService().activeAnyLinuxFSMounts()[deviceIdentifier]?.mountPoint
        let cleanupMountPoint = activeMountPoint?.hasPrefix("/Volumes/DiskMount-") == true
            ? activeMountPoint
            : nil
        _ = try CommandRunner.runAnyLinuxFSUnmountAsAdministrator(
            path,
            devicePath: devicePath,
            cleanupMountPoint: cleanupMountPoint
        )
    }

    static func isRawDiskPermissionError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("cannot probe")
            || message.contains("insufficient permissions")
            || message.contains("operation not permitted")
            || message.contains("file-read-data")
    }

    static func mountArguments(
        devicePath: String,
        deviceIdentifier: String,
        volumeName: String
    ) -> [String] {
        var arguments = ["mount", devicePath]
        if let customMountPoint = customMountPoint(
            deviceIdentifier: deviceIdentifier,
            volumeName: volumeName
        ) {
            arguments.append(customMountPoint)
        }
        arguments.append(contentsOf: ["--remount", "--ignore-permissions", "--window", "false"])
        return arguments
    }

    static func customMountPoint(deviceIdentifier: String, volumeName: String) -> String? {
        guard requiresASCIIMountPoint(volumeName) else { return nil }
        return safeMountPoint(deviceIdentifier: deviceIdentifier)
    }

    static func requiresASCIIMountPoint(_ volumeName: String) -> Bool {
        let forbidden = CharacterSet(charactersIn: "/:").union(.controlCharacters)
        return volumeName.isEmpty
            || volumeName.data(using: .ascii, allowLossyConversion: false) == nil
            || volumeName.rangeOfCharacter(from: forbidden) != nil
    }

    static func safeMountPoint(deviceIdentifier: String) -> String {
        let allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        let safeIdentifier = deviceIdentifier.filter { allowed.contains($0) }
        let suffix = safeIdentifier.isEmpty ? "External" : safeIdentifier
        return "/Volumes/DiskMount-\(suffix)"
    }

    static func isMissingMountVerificationError(_ error: Error) -> Bool {
        error.localizedDescription.contains(CommandRunner.ntfsMountVerificationMarker)
    }

    static func hasVerifiedWritableMount(
        deviceIdentifier: String,
        mounts: [String: DiskService.AnyLinuxFSMount]
    ) -> Bool {
        mounts[deviceIdentifier]?.writable == true
    }
}

enum AnyLinuxFSError: LocalizedError {
    case notInstalled
    case fullDiskAccessRequired
    case mountVerificationFailed

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "未检测到 anylinuxfs。请先执行：brew tap nohajc/anylinuxfs && brew install anylinuxfs"
        case .fullDiskAccessRequired:
            return "macOS 阻止了 NTFS 引擎读取原始磁盘。"
        case .mountVerificationFailed:
            return "NTFS 引擎未能建立可用的 NFS 挂载。"
        }
    }
}
