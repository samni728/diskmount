import XCTest
@testable import DiskMount

final class CommandRunnerTests: XCTestCase {
    func testShellQuoteHandlesSpacesAndSingleQuotes() {
        XCTAssertEqual(CommandRunner.shellQuote("/dev/disk 1's2"), "'/dev/disk 1'\\''s2'")
    }

    func testShellQuoteKeepsSubstitutionLiteral() {
        XCTAssertEqual(CommandRunner.shellQuote("$(touch /tmp/nope)"), "'$(touch /tmp/nope)'")
    }

    func testAdministratorCommandPreservesInvokingUserForAnyLinuxFS() {
        let command = CommandRunner.administratorShellCommand(
            "/Applications/Disk Mount/anylinuxfs",
            arguments: ["mount", "/dev/disk6s1"],
            invokingUID: 501,
            invokingGID: 20
        )

        XCTAssertEqual(
            command,
            "'/usr/bin/sudo' '-n' '-u' '#0' '/usr/bin/env' 'SUDO_UID=501' 'SUDO_GID=20' '/Applications/Disk Mount/anylinuxfs' 'mount' '/dev/disk6s1'"
        )
    }

    func testAnyLinuxFSRecognizesRawDiskPrivacyDenial() {
        let error = CommandError.failed(
            executable: "/path/to/anylinuxfs",
            exitCode: 1,
            message: "macOS: Error: Cannot probe /dev/disk6s1: LibErr(0); Insufficient permissions?"
        )

        XCTAssertTrue(AnyLinuxFSService.isRawDiskPermissionError(error))
    }

    func testAnyLinuxFSDoesNotMisclassifyGenericFailure() {
        let error = CommandError.failed(
            executable: "/path/to/anylinuxfs",
            exitCode: 1,
            message: "VM exited with status 1"
        )

        XCTAssertFalse(AnyLinuxFSService.isRawDiskPermissionError(error))
    }

}
