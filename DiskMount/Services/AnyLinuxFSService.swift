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
            return DependencyState(available: false, path: nil, version: nil)
        }
        let rawVersion = try? CommandRunner.run(path, arguments: ["--version"]).stdoutText
        let bundledSuffix = path.contains("DiskMount.app/Contents/Resources/anylinuxfs") ? " · App 内嵌" : " · 开发环境"
        let version = (rawVersion ?? "anylinuxfs") + bundledSuffix
        return DependencyState(available: true, path: path, version: version)
    }

    func mountReadWrite(devicePath: String) throws {
        guard let path = executablePath else {
            throw AnyLinuxFSError.notInstalled
        }
        _ = try CommandRunner.runAsAdministrator(
            path,
            arguments: ["mount", devicePath, "--remount", "--ignore-permissions", "--window", "false"]
        )
    }

    func unmount(devicePath: String) throws {
        guard let path = executablePath else {
            throw AnyLinuxFSError.notInstalled
        }
        _ = try CommandRunner.runAsAdministrator(path, arguments: ["unmount", devicePath])
    }
}

enum AnyLinuxFSError: LocalizedError {
    case notInstalled

    var errorDescription: String? {
        "未检测到 anylinuxfs。请先执行：brew tap nohajc/anylinuxfs && brew install anylinuxfs"
    }
}
