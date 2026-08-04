import AppKit
import Darwin
import Foundation

struct CommandResult {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32

    var stdoutText: String {
        String(data: stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var stderrText: String {
        String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum CommandError: LocalizedError {
    case launchFailed(String)
    case authorizationCanceled
    case timedOut(executable: String, seconds: TimeInterval)
    case failed(executable: String, exitCode: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return "无法启动系统命令：\(message)"
        case .authorizationCanceled:
            return "已取消管理员授权。"
        case .timedOut(let executable, let seconds):
            return "命令 \(executable) 在 \(Int(seconds.rounded())) 秒内未完成。"
        case .failed(_, let exitCode, let message):
            return message.isEmpty ? "命令执行失败（退出码 \(exitCode)）" : message
        }
    }
}

enum CommandRunner {
    private static let sudoSession = SudoSession()

    static func run(
        _ executable: String,
        arguments: [String],
        requireSuccess: Bool = true,
        timeout: TimeInterval? = nil
    ) throws -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed(error.localizedDescription)
        }

        if let timeout {
            let deadline = Date(timeIntervalSinceNow: timeout)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
                let terminationDeadline = Date(timeIntervalSinceNow: 0.5)
                while process.isRunning, Date() < terminationDeadline {
                    Thread.sleep(forTimeInterval: 0.02)
                }
                if process.isRunning {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                }
                process.waitUntilExit()
                _ = outputPipe.fileHandleForReading.readDataToEndOfFile()
                _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
                throw CommandError.timedOut(executable: executable, seconds: timeout)
            }
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let result = CommandResult(stdout: output, stderr: error, exitCode: process.terminationStatus)
        if requireSuccess, result.exitCode != 0 {
            let message = result.stderrText.isEmpty ? result.stdoutText : result.stderrText
            throw CommandError.failed(executable: executable, exitCode: result.exitCode, message: message)
        }
        return result
    }

    static func runAsAdministrator(_ executable: String, arguments: [String]) throws -> CommandResult {
        let command = administratorShellCommand(
            executable,
            arguments: arguments,
            invokingUID: getuid(),
            invokingGID: getgid()
        )
        let escapedForAppleScript = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escapedForAppleScript)\" with administrator privileges"
        return try run("/usr/bin/osascript", arguments: ["-e", script])
    }

    static func administratorShellCommand(
        _ executable: String,
        arguments: [String],
        invokingUID: uid_t,
        invokingGID: gid_t
    ) -> String {
        // AppleScript starts its shell directly as root. Keep a real sudo process in the launch
        // chain because anylinuxfs explicitly requires sudo, then restore the desktop user's IDs
        // after sudo has initialized its own environment.
        let environment = [
            "/usr/bin/sudo",
            "-n",
            "-u",
            "#0",
            "/usr/bin/env",
            "SUDO_UID=\(invokingUID)",
            "SUDO_GID=\(invokingGID)"
        ]
        return (environment + [executable] + arguments).map(shellQuote).joined(separator: " ")
    }

    static func runNTFSMountAsAdministrator(
        _ executable: String,
        devicePath: String,
        arguments: [String]
    ) throws -> CommandResult {
        let privilegedMount = ([executable] + arguments).map(shellQuote).joined(separator: " ")
        let fallbackMount = ["/usr/sbin/diskutil", "mount", devicePath]
            .map(shellQuote).joined(separator: " ")
        let deviceIdentifier = URL(fileURLWithPath: devicePath).lastPathComponent
        let activeAnyLinuxFSMount = "/sbin/mount | /usr/bin/grep -F -q -- "
            + shellQuote("\(deviceIdentifier).local:")

        // Run anylinuxfs through a real user-launched sudo process. If the engine fails after
        // unmounting the read-only volume, restore the normal macOS mount before returning.
        // Never create a duplicate read-only mount if a surviving anylinuxfs NFS mount still
        // owns this device after system wake.
        let command = "status=0; \(privilegedMount) || status=$?; "
            + "if [ \"$status\" -ne 0 ] && ! \(activeAnyLinuxFSMount); then "
            + "\(fallbackMount) >/dev/null 2>&1 || true; fi; "
            + "(exit \"$status\")"
        return try sudoSession.run(command)
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private final class SudoSession {
    private let keepAliveQueue = DispatchQueue(label: "com.samni.DiskMount.sudo-keepalive")
    private var keepAliveTimer: DispatchSourceTimer?

    func run(_ command: String) throws -> CommandResult {
        let password: String?
        if hasCachedAuthorization() {
            password = nil
        } else {
            password = try requestAdministratorPassword()
        }
        let result = try executeSudo(command: command, password: password)
        if result.exitCode != 0 {
            let message = result.stderrText.isEmpty ? result.stdoutText : result.stderrText
            throw CommandError.failed(
                executable: "/usr/bin/sudo",
                exitCode: result.exitCode,
                message: message
            )
        }
        startKeepAlive()
        return result
    }

    private func hasCachedAuthorization() -> Bool {
        guard let result = try? CommandRunner.run(
            "/usr/bin/sudo",
            arguments: ["-n", "-v"],
            requireSuccess: false
        ) else { return false }
        return result.exitCode == 0
    }

    private func requestAdministratorPassword() throws -> String {
        let showPrompt: () throws -> String = {
            NSApp.setActivationPolicy(.regular)
            defer { NSApp.setActivationPolicy(.accessory) }
            NSApp.windows.forEach { $0.orderOut(nil) }
            NSApp.activate(ignoringOtherApps: true)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "DiskMount 需要管理员授权 / Administrator Authorization"
            alert.informativeText = """
            此授权仅用于 DiskMount 的 NTFS 读写挂载与失败恢复。密码只通过标准输入交给 macOS sudo，不保存、不记录、不上传。

            This authorization is used only for DiskMount NTFS mounting and failure recovery. The password is passed to macOS sudo via standard input and is never stored, logged, or uploaded.

            原始磁盘访问还可能需要在“隐私与安全性”中开启“完全磁盘访问权限”和“可移动卷”。
            """
            let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
            passwordField.placeholderString = "macOS 管理员密码"
            alert.accessoryView = passwordField
            alert.addButton(withTitle: "继续 / Continue")
            alert.addButton(withTitle: "取消 / Cancel")
            alert.window.initialFirstResponder = passwordField
            alert.window.level = .popUpMenu
            alert.window.center()
            alert.window.orderFrontRegardless()
            guard alert.runModal() == .alertFirstButtonReturn else {
                throw CommandError.authorizationCanceled
            }
            let password = passwordField.stringValue
            passwordField.stringValue = ""
            guard !password.isEmpty else {
                throw CommandError.authorizationCanceled
            }
            return password
        }
        if Thread.isMainThread {
            return try showPrompt()
        }
        return try DispatchQueue.main.sync(execute: showPrompt)
    }

    private func executeSudo(command: String, password: String?) throws -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        if password == nil {
            process.arguments = ["-n", "/bin/sh", "-c", command]
        } else {
            process.arguments = ["-S", "-p", "", "/bin/sh", "-c", command]
            process.standardInput = inputPipe
        }
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed(error.localizedDescription)
        }
        if let password {
            inputPipe.fileHandleForWriting.write(Data((password + "\n").utf8))
            try? inputPipe.fileHandleForWriting.close()
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(stdout: output, stderr: error, exitCode: process.terminationStatus)
    }

    private func startKeepAlive() {
        guard keepAliveTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: keepAliveQueue)
        timer.schedule(deadline: .now() + 90, repeating: 90)
        timer.setEventHandler {
            _ = try? CommandRunner.run(
                "/usr/bin/sudo",
                arguments: ["-n", "-v"],
                requireSuccess: false
            )
        }
        keepAliveTimer = timer
        timer.resume()
    }

    deinit {
        keepAliveTimer?.cancel()
    }
}
