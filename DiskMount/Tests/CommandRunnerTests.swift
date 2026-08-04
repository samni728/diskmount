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

    func testParsesAnyLinuxFSMountByDeviceIdentifier() {
        let output = """
        /dev/disk3s1 on /System/Volumes/Data (apfs, local, journaled)
        disk66s1.local:/mnt/SYSDISK on /Volumes/SYSDISK (nfs, nodev, nosuid, noowners, mounted by samni)
        """

        let mounts = DiskService.parseAnyLinuxFSMounts(output)

        XCTAssertEqual(
            mounts["disk66s1"],
            DiskService.AnyLinuxFSMount(
                deviceIdentifier: "disk66s1",
                mountPoint: "/Volumes/SYSDISK",
                writable: true
            )
        )
        XCTAssertNil(mounts["disk3s1"])
    }

    func testParsesEscapedReadOnlyAnyLinuxFSMount() {
        let output = "disk9s2.local:/mnt/MyDisk on /Volumes/My\\040Disk (nfs, read-only, noowners)"

        let mounts = DiskService.parseAnyLinuxFSMounts(output)

        XCTAssertEqual(mounts["disk9s2"]?.mountPoint, "/Volumes/My Disk")
        XCTAssertEqual(mounts["disk9s2"]?.writable, false)
    }

}
