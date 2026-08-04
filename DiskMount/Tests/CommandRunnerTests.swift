import XCTest
@testable import DiskMount

final class CommandRunnerTests: XCTestCase {
    func testShellQuoteHandlesSpacesAndSingleQuotes() {
        XCTAssertEqual(CommandRunner.shellQuote("/dev/disk 1's2"), "'/dev/disk 1'\\''s2'")
    }

    func testShellQuoteKeepsSubstitutionLiteral() {
        XCTAssertEqual(CommandRunner.shellQuote("$(touch /tmp/nope)"), "'$(touch /tmp/nope)'")
    }

    func testCommandTimeoutStopsHungProcess() {
        XCTAssertThrowsError(
            try CommandRunner.run("/bin/sleep", arguments: ["2"], timeout: 0.1)
        ) { error in
            guard case CommandError.timedOut(let executable, let seconds) = error else {
                return XCTFail("Expected timeout, got \(error)")
            }
            XCTAssertEqual(executable, "/bin/sleep")
            XCTAssertEqual(seconds, 0.1, accuracy: 0.001)
        }
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

    func testAnyLinuxFSUnmountUsesQuotedCachedSudoCommand() {
        XCTAssertEqual(
            CommandRunner.anyLinuxFSUnmountCommand(
                "/Applications/Disk Mount/anylinuxfs",
                devicePath: "/dev/disk 6s1"
            ),
            "'/Applications/Disk Mount/anylinuxfs' 'unmount' '/dev/disk 6s1'"
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

    func testChineseVolumeNameUsesASCIICustomMountPoint() {
        XCTAssertEqual(
            AnyLinuxFSService.customMountPoint(
                deviceIdentifier: "disk35s1",
                volumeName: "大白菜U盘"
            ),
            "/Volumes/DiskMount-disk35s1"
        )
        XCTAssertEqual(
            AnyLinuxFSService.mountArguments(
                devicePath: "/dev/disk35s1",
                deviceIdentifier: "disk35s1",
                volumeName: "大白菜U盘"
            ),
            [
                "mount", "/dev/disk35s1", "/Volumes/DiskMount-disk35s1",
                "--remount", "--ignore-permissions", "--window", "false"
            ]
        )
    }

    func testASCIINameKeepsAnyLinuxFSDefaultMountPoint() {
        XCTAssertNil(
            AnyLinuxFSService.customMountPoint(
                deviceIdentifier: "disk66s1",
                volumeName: "SYSDISK"
            )
        )
        XCTAssertEqual(
            AnyLinuxFSService.mountArguments(
                devicePath: "/dev/disk66s1",
                deviceIdentifier: "disk66s1",
                volumeName: "SYSDISK"
            ),
            [
                "mount", "/dev/disk66s1",
                "--remount", "--ignore-permissions", "--window", "false"
            ]
        )
    }

    func testUnsafeDeviceIdentifierIsSanitizedForMountPoint() {
        XCTAssertEqual(
            AnyLinuxFSService.safeMountPoint(deviceIdentifier: "磁盘 disk 35/s1;$()"),
            "/Volumes/DiskMount-disk35s1"
        )
    }

    func testNTFSMountCommandVerifiesNFSPostconditionAndRestoresNativeMount() {
        let command = CommandRunner.ntfsMountShellCommand(
            "/Applications/Disk Mount/anylinuxfs",
            devicePath: "/dev/disk35s1",
            arguments: [
                "mount", "/dev/disk35s1", "/Volumes/DiskMount-disk35s1",
                "--remount", "--ignore-permissions", "--window", "false"
            ],
            customMountPoint: "/Volumes/DiskMount-disk35s1"
        )

        XCTAssertTrue(command.contains("'disk35s1.local:'"))
        XCTAssertTrue(command.contains("/bin/mkdir -p '/Volumes/DiskMount-disk35s1'"))
        XCTAssertTrue(command.contains("[ -L '/Volumes/DiskMount-disk35s1' ]"))
        XCTAssertTrue(command.contains(CommandRunner.mountPointPreparationMarker))
        XCTAssertTrue(command.contains("/bin/sleep 0.25"))
        XCTAssertTrue(command.contains(CommandRunner.ntfsMountVerificationMarker))
        XCTAssertTrue(command.contains("'/usr/sbin/diskutil' 'mount' '/dev/disk35s1'"))
        XCTAssertTrue(command.contains("/bin/rmdir '/Volumes/DiskMount-disk35s1'"))

        XCTAssertNoThrow(
            try CommandRunner.run("/bin/sh", arguments: ["-n", "-c", command])
        )
    }

    func testAnyLinuxFSUnmountRemovesOnlyEmptyManagedMountPointAfterSuccess() {
        let command = CommandRunner.anyLinuxFSUnmountCommand(
            "/Applications/Disk Mount/anylinuxfs",
            devicePath: "/dev/disk35s1",
            cleanupMountPoint: "/Volumes/DiskMount-disk35s1"
        )

        XCTAssertTrue(command.contains("'/Applications/Disk Mount/anylinuxfs' 'unmount' '/dev/disk35s1'"))
        XCTAssertTrue(command.contains("if [ \"$status\" -eq 0 ]"))
        XCTAssertTrue(command.contains("'/bin/rmdir' '/Volumes/DiskMount-disk35s1'"))
        XCTAssertNoThrow(
            try CommandRunner.run("/bin/sh", arguments: ["-n", "-c", command])
        )
    }

    func testFailedNTFSMountCreatesThenRemovesEmptyCustomMountPoint() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskMountTests-\(UUID().uuidString)")
        let mountPoint = base.appendingPathComponent("DiskMount-test").path
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let command = CommandRunner.ntfsMountShellCommand(
            "/usr/bin/false",
            devicePath: "/dev/DiskMountNonexistentTest",
            arguments: [],
            customMountPoint: mountPoint
        )
        let result = try CommandRunner.run(
            "/bin/sh",
            arguments: ["-c", command],
            requireSuccess: false
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mountPoint))
    }

    func testCustomMountPointRejectsSymbolicLink() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskMountTests-\(UUID().uuidString)")
        let target = base.appendingPathComponent("target")
        let mountPoint = base.appendingPathComponent("DiskMount-link")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: mountPoint, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: base) }

        let command = CommandRunner.ntfsMountShellCommand(
            "/usr/bin/true",
            devicePath: "/dev/DiskMountNonexistentTest",
            arguments: [],
            customMountPoint: mountPoint.path
        )
        let result = try CommandRunner.run(
            "/bin/sh",
            arguments: ["-c", command],
            requireSuccess: false
        )

        XCTAssertEqual(result.exitCode, 71)
        XCTAssertTrue(result.stderrText.contains(CommandRunner.mountPointPreparationMarker))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testMissingMountVerificationErrorIsRecognized() {
        let error = CommandError.failed(
            executable: "/usr/bin/sudo",
            exitCode: 70,
            message: CommandRunner.ntfsMountVerificationMarker
        )

        XCTAssertTrue(AnyLinuxFSService.isMissingMountVerificationError(error))
    }

    func testNTFSSuccessRequiresExactWritableMount() {
        let writable = DiskService.AnyLinuxFSMount(
            deviceIdentifier: "disk35s1",
            mountPoint: "/Volumes/DiskMount-disk35s1",
            writable: true
        )
        let readOnly = DiskService.AnyLinuxFSMount(
            deviceIdentifier: "disk35s1",
            mountPoint: "/Volumes/DiskMount-disk35s1",
            writable: false
        )

        XCTAssertTrue(AnyLinuxFSService.hasVerifiedWritableMount(
            deviceIdentifier: "disk35s1",
            mounts: ["disk35s1": writable]
        ))
        XCTAssertFalse(AnyLinuxFSService.hasVerifiedWritableMount(
            deviceIdentifier: "disk35s1",
            mounts: ["disk35s1": readOnly]
        ))
        XCTAssertFalse(AnyLinuxFSService.hasVerifiedWritableMount(
            deviceIdentifier: "disk35s1",
            mounts: ["disk66s1": writable]
        ))
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

    func testMatchesEveryAnyLinuxFSMountOnSelectedWholeDisk() {
        let identifiers = DiskService.matchingAnyLinuxFSIdentifiers(
            wholeDiskIdentifier: "disk34",
            activeIdentifiers: ["disk34s1", "disk34s2", "disk66s1"],
            parentWholeDisks: [
                "disk34s1": "disk34",
                "disk34s2": "disk34",
                "disk66s1": "disk66"
            ]
        )

        XCTAssertEqual(identifiers, ["disk34s1", "disk34s2"])
    }

    func testRecognizesBusyDiskEjectErrors() {
        XCTAssertTrue(DiskService.isBusyEjectErrorMessage("Resource busy"))
        XCTAssertTrue(DiskService.isBusyEjectErrorMessage("Disk dissented by PID 123"))
        XCTAssertTrue(DiskService.isBusyEjectErrorMessage("At least one volume could not be unmounted"))
        XCTAssertFalse(DiskService.isBusyEjectErrorMessage("Media not found"))
    }

    func testWholeDiskVolumeWithoutPartitionTableIsDiscoverable() {
        let wholeDisk: [String: Any] = [
            "DeviceIdentifier": "disk35",
            "Content": "",
            "VolumeName": "LENOVO_ESXI6.7U3-17700523_202111",
            "MountPoint": "/Volumes/LENOVO_ESXI6.7U3-17700523_202111",
            "Size": 124_218_507_264
        ]

        XCTAssertEqual(
            DiskService.wholeDiskVolumeIdentifier(from: wholeDisk),
            "disk35"
        )
    }

    func testPartitionedWholeDiskIsNotDuplicatedAsVolume() {
        let partitionedDisk: [String: Any] = [
            "DeviceIdentifier": "disk4",
            "Content": "GUID_partition_scheme",
            "Partitions": [[
                "DeviceIdentifier": "disk4s1",
                "Content": "EFI"
            ]]
        ]

        XCTAssertNil(DiskService.wholeDiskVolumeIdentifier(from: partitionedDisk))
    }

    func testUpdateVersionComparison() {
        XCTAssertTrue(UpdateService.isVersion("v0.2.7", newerThan: "0.2.6"))
        XCTAssertTrue(UpdateService.isVersion("1.0.0", newerThan: "0.9.9"))
        XCTAssertFalse(UpdateService.isVersion("0.2.6", newerThan: "0.2.6"))
        XCTAssertFalse(UpdateService.isVersion("0.2.5", newerThan: "0.2.6"))
    }

    func testUpdateStateAcceptsOnlyNewerStableGitHubRelease() throws {
        let data = Data("""
        {
          "tag_name": "v0.3.0",
          "html_url": "https://github.com/samni728/diskmount/releases/tag/v0.3.0",
          "draft": false,
          "prerelease": false
        }
        """.utf8)

        XCTAssertEqual(
            try UpdateService.updateState(from: data, currentVersion: "0.2.6"),
            AppUpdateState(
                available: true,
                latestVersion: "0.3.0",
                releaseURL: "https://github.com/samni728/diskmount/releases/tag/v0.3.0"
            )
        )
    }

    func testUpdateCheckerRejectsUntrustedReleaseURL() throws {
        let data = Data("""
        {
          "tag_name": "v99.0.0",
          "html_url": "https://example.com/fake-release",
          "draft": false,
          "prerelease": false
        }
        """.utf8)

        XCTAssertEqual(
            try UpdateService.updateState(from: data, currentVersion: "0.2.6"),
            .noUpdate
        )
    }

    func testEjectedDiskStaysHiddenWhileStillPhysicallyConnectedAndUnmounted() {
        let disk = makeTestDisk(
            id: "disk35s1",
            persistentID: "sysdisk",
            wholeDisk: "disk35",
            mounted: false
        )
        let suppression = EjectedDiskSuppression(
            persistentIDs: ["sysdisk"],
            hasObservedDetachedState: false
        )

        let result = WebPanelController.reconcileEjectedDevices(
            [disk],
            suppressions: ["disk35": suppression]
        )

        XCTAssertTrue(result.visibleDevices.isEmpty)
        XCTAssertEqual(result.suppressions["disk35"]?.hasObservedDetachedState, false)
    }

    func testMissingEjectedDiskRecordsPhysicalDetachment() {
        let suppression = EjectedDiskSuppression(
            persistentIDs: ["sysdisk"],
            hasObservedDetachedState: false
        )

        let result = WebPanelController.reconcileEjectedDevices(
            [],
            suppressions: ["disk35": suppression]
        )

        XCTAssertTrue(result.visibleDevices.isEmpty)
        XCTAssertEqual(result.suppressions["disk35"]?.hasObservedDetachedState, true)
    }

    func testEjectedDiskReturnsOnlyAfterPhysicalDetachmentAndReappearance() {
        let disk = makeTestDisk(
            id: "disk35s1",
            persistentID: "sysdisk",
            wholeDisk: "disk35",
            mounted: true
        )
        let suppression = EjectedDiskSuppression(
            persistentIDs: ["sysdisk"],
            hasObservedDetachedState: true
        )

        let result = WebPanelController.reconcileEjectedDevices(
            [disk],
            suppressions: ["disk35": suppression]
        )

        XCTAssertEqual(result.visibleDevices, [disk])
        XCTAssertNil(result.suppressions["disk35"])
    }

    func testBackgroundRemountDoesNotUndoEjectBeforePhysicalDetachment() {
        let staleDisk = makeTestDisk(
            id: "disk35s1",
            persistentID: "sysdisk",
            wholeDisk: "disk35",
            mounted: true
        )
        let suppression = EjectedDiskSuppression(
            persistentIDs: ["sysdisk"],
            hasObservedDetachedState: false
        )

        let result = WebPanelController.reconcileEjectedDevices(
            [staleDisk],
            suppressions: ["disk35": suppression]
        )

        XCTAssertTrue(result.visibleDevices.isEmpty)
        XCTAssertNotNil(result.suppressions["disk35"])
    }

    func testReusedDiskNumberDoesNotHideAnotherPhysicalDisk() {
        let replacement = makeTestDisk(
            id: "disk35s1",
            persistentID: "different-device",
            wholeDisk: "disk35",
            mounted: false
        )
        let suppression = EjectedDiskSuppression(
            persistentIDs: ["sysdisk"],
            hasObservedDetachedState: true
        )

        let result = WebPanelController.reconcileEjectedDevices(
            [replacement],
            suppressions: ["disk35": suppression]
        )

        XCTAssertEqual(result.visibleDevices, [replacement])
        XCTAssertNil(result.suppressions["disk35"])
    }

    func testDeviceIdentityChangeClearsStatusForPreviousDisk() {
        let previous = makeTestDisk(
            id: "disk35s1",
            persistentID: "chinese-usb",
            wholeDisk: "disk35",
            mounted: false
        )
        let replacement = makeTestDisk(
            id: "disk35s1",
            persistentID: "efi-usb",
            wholeDisk: "disk35",
            mounted: true
        )

        XCTAssertTrue(WebPanelController.deviceIdentitySetChanged(
            from: [previous],
            to: [replacement]
        ))
        XCTAssertFalse(WebPanelController.deviceIdentitySetChanged(
            from: [replacement],
            to: [replacement]
        ))
    }

    private func makeTestDisk(
        id: String,
        persistentID: String,
        wholeDisk: String,
        mounted: Bool
    ) -> DiskDevice {
        DiskDevice(
            id: id,
            persistentID: persistentID,
            wholeDiskIdentifier: wholeDisk,
            name: "Test Disk",
            fileSystem: "ntfs",
            content: "Windows_NTFS",
            mountPoint: mounted ? "/Volumes/Test Disk" : nil,
            size: 1_000,
            mounted: mounted,
            writable: mounted,
            isNTFS: true,
            isProtected: false
        )
    }

}
