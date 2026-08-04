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

    func mountReadWrite(devicePath: String) throws {
        guard let path = executablePath else {
            throw AnyLinuxFSError.notInstalled
        }
        do {
            _ = try CommandRunner.runNTFSMountAsAdministrator(
                path,
                devicePath: devicePath,
                arguments: ["mount", devicePath, "--remount", "--ignore-permissions", "--window", "false"]
            )
        } catch {
            if Self.isRawDiskPermissionError(error) {
                throw AnyLinuxFSError.fullDiskAccessRequired
            }
            throw error
        }
    }

    func unmount(devicePath: String) throws {
        guard let path = executablePath else {
            throw AnyLinuxFSError.notInstalled
        }
        _ = try CommandRunner.runAnyLinuxFSUnmountAsAdministrator(path, devicePath: devicePath)
    }

    static func isRawDiskPermissionError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("cannot probe")
            || message.contains("insufficient permissions")
            || message.contains("operation not permitted")
            || message.contains("file-read-data")
    }
}

enum AnyLinuxFSError: LocalizedError {
    case notInstalled
    case fullDiskAccessRequired

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "未检测到 anylinuxfs。请先执行：brew tap nohajc/anylinuxfs && brew install anylinuxfs"
        case .fullDiskAccessRequired:
            return "macOS 阻止了 NTFS 引擎读取原始磁盘。"
        }
    }
}
