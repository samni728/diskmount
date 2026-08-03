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
    case failed(executable: String, exitCode: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return "无法启动系统命令：\(message)"
        case .failed(_, let exitCode, let message):
            return message.isEmpty ? "命令执行失败（退出码 \(exitCode)）" : message
        }
    }
}

enum CommandRunner {
    static func run(_ executable: String, arguments: [String], requireSuccess: Bool = true) throws -> CommandResult {
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
        // `do shell script ... with administrator privileges` starts the child directly as root,
        // unlike sudo it does not populate SUDO_UID/SUDO_GID. anylinuxfs uses those values to
        // resolve the real desktop user and intentionally rejects a bare root process.
        let environment = [
            "/usr/bin/env",
            "SUDO_UID=\(invokingUID)",
            "SUDO_GID=\(invokingGID)"
        ]
        return (environment + [executable] + arguments).map(shellQuote).joined(separator: " ")
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
