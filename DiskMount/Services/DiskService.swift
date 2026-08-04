import AppKit
import Foundation
import IOKit

final class DiskService {
    private let diskutil = "/usr/sbin/diskutil"
    private let mountTool = "/sbin/mount"

    struct AnyLinuxFSMount: Equatable {
        let deviceIdentifier: String
        let mountPoint: String
        let writable: Bool
    }

    private struct Candidate {
        let identifier: String
        let wholeDisk: String
        let content: String
        let size: UInt64
        let wholeDiskSize: UInt64
        let forceProtected: Bool
    }

    private struct APFSScan {
        let candidates: [Candidate]
        let systemWholeDisks: Set<String>
    }

    func listExternalVolumes(includeAdvanced: Bool = false) throws -> [DiskDevice] {
        let anyLinuxFSMounts = activeAnyLinuxFSMounts()
        let listResult = try CommandRunner.run(diskutil, arguments: ["list", "-plist", "external", "physical"])
        let plist = try PropertyListSerialization.propertyList(from: listResult.stdout, options: [], format: nil)
        guard let root = plist as? [String: Any],
              let disks = root["AllDisksAndPartitions"] as? [[String: Any]] else {
            return []
        }

        var candidates: [Candidate] = []
        for disk in disks {
            guard let wholeDisk = disk["DeviceIdentifier"] as? String else { continue }
            collectPartitions(
                from: disk,
                wholeDisk: wholeDisk,
                wholeDiskSize: unsignedInteger(disk["Size"]),
                into: &candidates
            )
        }

        let bootWholeDisks = bootRelatedWholeDisks(in: candidates)
        let apfsScan = scanAPFSVolumes(from: candidates)
        candidates.append(contentsOf: apfsScan.candidates)
        let protectedWholeDisks = bootWholeDisks.union(apfsScan.systemWholeDisks)

        return candidates.compactMap { candidate in
            try? makeDevice(
                identifier: candidate.identifier,
                wholeDisk: candidate.wholeDisk,
                fallbackContent: candidate.content,
                fallbackSize: candidate.size,
                wholeDiskSize: candidate.wholeDiskSize,
                forceProtected: candidate.forceProtected || protectedWholeDisks.contains(candidate.wholeDisk),
                anyLinuxFSMounts: anyLinuxFSMounts
            )
        }.filter { includeAdvanced || !$0.isProtected }.sorted { lhs, rhs in
            if lhs.wholeDiskIdentifier == rhs.wholeDiskIdentifier { return lhs.id < rhs.id }
            return lhs.wholeDiskIdentifier < rhs.wholeDiskIdentifier
        }
    }

    func mount(_ device: DiskDevice) throws {
        _ = try CommandRunner.run(diskutil, arguments: ["mount", device.devicePath])
    }

    func mountProtected(_ device: DiskDevice) throws {
        _ = try CommandRunner.runAsAdministrator(diskutil, arguments: ["mount", device.devicePath])
    }

    func unmount(_ device: DiskDevice) throws {
        _ = try CommandRunner.run(diskutil, arguments: ["unmount", device.devicePath])
    }

    func unmountProtected(_ device: DiskDevice) throws {
        _ = try CommandRunner.runAsAdministrator(diskutil, arguments: ["unmount", device.devicePath])
    }

    func eject(_ device: DiskDevice) throws {
        do {
            _ = try CommandRunner.run(
                diskutil,
                arguments: ["eject", "/dev/\(device.wholeDiskIdentifier)"],
                timeout: 30
            )
        } catch CommandError.timedOut {
            throw DiskServiceError.ejectTimedOut
        } catch {
            if Self.isBusyEjectErrorMessage(error.localizedDescription) {
                throw DiskServiceError.ejectBusy
            }
            throw error
        }
    }

    func openInFinder(_ device: DiskDevice) throws {
        guard let mountPoint = device.mountPoint else { return }
        guard NSWorkspace.shared.open(URL(fileURLWithPath: mountPoint)) else {
            throw DiskServiceError.cannotOpenFinder
        }
    }

    func isMountedByAnyLinuxFS(deviceIdentifier: String) -> Bool {
        activeAnyLinuxFSMounts()[deviceIdentifier] != nil
    }

    /// Returns every anylinuxfs-backed partition that belongs to the selected physical disk.
    /// Stopping all of them before `diskutil eject` prevents the VM from racing disk arbitration
    /// while it is still releasing its raw block-device lock.
    func activeAnyLinuxFSDevicePaths(onWholeDisk wholeDiskIdentifier: String) -> [String] {
        let identifiers = Set(activeAnyLinuxFSMounts().keys)
        let parentPairs: [(String, String)] = identifiers.compactMap { identifier in
            guard let parent = diskInfo(identifier: identifier)?["ParentWholeDisk"] as? String else {
                return nil
            }
            return (identifier, parent)
        }
        let parents = Dictionary(uniqueKeysWithValues: parentPairs)
        return Self.matchingAnyLinuxFSIdentifiers(
            wholeDiskIdentifier: wholeDiskIdentifier,
            activeIdentifiers: identifiers,
            parentWholeDisks: parents
        ).map { "/dev/\($0)" }
    }

    static func matchingAnyLinuxFSIdentifiers(
        wholeDiskIdentifier: String,
        activeIdentifiers: Set<String>,
        parentWholeDisks: [String: String]
    ) -> [String] {
        activeIdentifiers
            .filter { parentWholeDisks[$0] == wholeDiskIdentifier }
            .sorted()
    }

    static func isBusyEjectErrorMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("resource busy")
            || normalized.contains("could not be unmounted")
            || normalized.contains("dissented")
            || normalized.contains("in use")
    }

    /// Removes only a duplicate macOS read-only NTFS mount when the same device is already
    /// available through anylinuxfs. The anylinuxfs/NFS mount is left untouched.
    @discardableResult
    func removeDuplicateNativeMounts() -> [String] {
        let anyLinuxFSMounts = activeAnyLinuxFSMounts()
        var removed: [String] = []

        for (identifier, anyLinuxFSMount) in anyLinuxFSMounts {
            guard anyLinuxFSMount.writable,
                  let info = diskInfo(identifier: identifier),
                  bool(info["Mounted"]),
                  !bool(info["Writable"]),
                  let nativeMountPoint = info["MountPoint"] as? String,
                  !nativeMountPoint.isEmpty,
                  nativeMountPoint != anyLinuxFSMount.mountPoint else { continue }

            let combinedType = [
                string(info["FilesystemType"]),
                string(info["FilesystemName"]),
                string(info["Content"])
            ].joined(separator: " ").lowercased()
            guard combinedType.contains("ntfs") || combinedType.contains("windows_ntfs") else { continue }

            if (try? CommandRunner.run(diskutil, arguments: ["unmount", "/dev/\(identifier)"])) != nil {
                removed.append(identifier)
            }
        }
        return removed
    }

    func activeAnyLinuxFSMounts() -> [String: AnyLinuxFSMount] {
        guard let result = try? CommandRunner.run(mountTool, arguments: []) else { return [:] }
        return Self.parseAnyLinuxFSMounts(result.stdoutText)
    }

    static func parseAnyLinuxFSMounts(_ output: String) -> [String: AnyLinuxFSMount] {
        var mounts: [String: AnyLinuxFSMount] = [:]

        for line in output.split(whereSeparator: { $0.isNewline }).map(String.init) {
            guard let sourceEnd = line.range(of: ".local:"),
                  let onRange = line.range(of: " on ", range: sourceEnd.upperBound..<line.endIndex),
                  let optionsRange = line.range(of: " (", options: .backwards),
                  onRange.upperBound <= optionsRange.lowerBound else { continue }

            let identifier = String(line[..<sourceEnd.lowerBound])
            guard identifier.range(of: #"^disk[0-9]+(?:s[0-9]+)?$"#, options: .regularExpression) != nil else {
                continue
            }

            let optionsStart = optionsRange.upperBound
            guard line.last == ")", optionsStart < line.index(before: line.endIndex) else { continue }
            let options = String(line[optionsStart..<line.index(before: line.endIndex)])
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            guard options.contains("nfs") else { continue }

            let encodedMountPoint = String(line[onRange.upperBound..<optionsRange.lowerBound])
            let mountPoint = decodeMountPath(encodedMountPoint)
            let readOnly = options.contains("read-only") || options.contains("ro")
            mounts[identifier] = AnyLinuxFSMount(
                deviceIdentifier: identifier,
                mountPoint: mountPoint,
                writable: !readOnly
            )
        }
        return mounts
    }

    private func collectPartitions(
        from item: [String: Any],
        wholeDisk: String,
        wholeDiskSize: UInt64,
        into output: inout [Candidate]
    ) {
        if let partitions = item["Partitions"] as? [[String: Any]] {
            for partition in partitions {
                if let identifier = partition["DeviceIdentifier"] as? String {
                    output.append(Candidate(
                        identifier: identifier,
                        wholeDisk: wholeDisk,
                        content: partition["Content"] as? String ?? "",
                        size: unsignedInteger(partition["Size"]),
                        wholeDiskSize: wholeDiskSize,
                        forceProtected: false
                    ))
                }
                collectPartitions(
                    from: partition,
                    wholeDisk: wholeDisk,
                    wholeDiskSize: wholeDiskSize,
                    into: &output
                )
            }
        }
    }

    private func makeDevice(
        identifier: String,
        wholeDisk: String,
        fallbackContent: String,
        fallbackSize: UInt64,
        wholeDiskSize: UInt64,
        forceProtected: Bool,
        anyLinuxFSMounts: [String: AnyLinuxFSMount]
    ) throws -> DiskDevice {
        let result = try CommandRunner.run(diskutil, arguments: ["info", "-plist", "/dev/\(identifier)"])
        let plist = try PropertyListSerialization.propertyList(from: result.stdout, options: [], format: nil)
        let info = plist as? [String: Any] ?? [:]

        let volumeName = string(info["VolumeName"])
        let mediaName = string(info["MediaName"])
        let fileSystem = string(info["FilesystemType"])
        let typeBundle = string(info["FilesystemName"])
        let content = string(info["Content"]).isEmpty ? fallbackContent : string(info["Content"])
        let combinedType = [fileSystem, typeBundle, content].joined(separator: " ").lowercased()
        let isNTFS = combinedType.contains("ntfs") || combinedType.contains("windows_ntfs")
        let mountPointValue = info["MountPoint"] as? String
        let diskutilMountPoint = mountPointValue?.isEmpty == false ? mountPointValue : nil
        let anyLinuxFSMount = isNTFS ? anyLinuxFSMounts[identifier] : nil
        // Prefer the exact anylinuxfs source match. After wake, macOS can temporarily add a
        // second read-only mount (for example "SYSDISK 1") while the original NFS mount lives.
        let mountPoint = anyLinuxFSMount?.mountPoint ?? diskutilMountPoint
        let unnamedAndUnavailable = volumeName.isEmpty && mountPoint == nil && !isNTFS && fileSystem.isEmpty
        let isProtected = forceProtected || isAuxiliaryContent(content) || unnamedAndUnavailable
        let partitionOffset = unsignedInteger(info["PartitionMapPartitionOffset"])
        let serial = hardwareSerial(for: wholeDisk)
        let identitySource: String
        if let serial, !serial.isEmpty {
            identitySource = "serial:\(serial)|offset:\(partitionOffset)|size:\(fallbackSize)"
        } else {
            identitySource = "disk-size:\(wholeDiskSize)|offset:\(partitionOffset)|size:\(fallbackSize)|name:\(volumeName.lowercased())|type:\(combinedType)"
        }

        return DiskDevice(
            id: identifier,
            persistentID: stableHash(identitySource),
            wholeDiskIdentifier: wholeDisk,
            name: volumeName.isEmpty ? (mediaName.isEmpty ? identifier : mediaName) : volumeName,
            fileSystem: fileSystem.isEmpty ? (typeBundle.isEmpty ? content : typeBundle) : fileSystem,
            content: content,
            mountPoint: mountPoint,
            size: unsignedInteger(info["TotalSize"]) == 0 ? fallbackSize : unsignedInteger(info["TotalSize"]),
            mounted: bool(info["Mounted"]) || mountPoint != nil,
            writable: anyLinuxFSMount?.writable
                ?? (bool(info["Writable"]) || mountPoint.map(FileManager.default.isWritableFile(atPath:)) == true),
            isNTFS: isNTFS,
            isProtected: isProtected
        )
    }

    private func bootRelatedWholeDisks(in candidates: [Candidate]) -> Set<String> {
        guard let result = try? CommandRunner.run(diskutil, arguments: ["info", "-plist", "/"]),
              let plist = try? PropertyListSerialization.propertyList(from: result.stdout, options: [], format: nil),
              let info = plist as? [String: Any] else { return [] }

        var protected: Set<String> = []
        let candidateByIdentifier = Dictionary(uniqueKeysWithValues: candidates.map { ($0.identifier, $0.wholeDisk) })
        if let stores = info["APFSPhysicalStores"] as? [[String: Any]] {
            for store in stores {
                guard let identifier = store["APFSPhysicalStore"] as? String,
                      let wholeDisk = candidateByIdentifier[identifier] else { continue }
                protected.insert(wholeDisk)
            }
        }
        if let parent = info["ParentWholeDisk"] as? String,
           candidates.contains(where: { $0.wholeDisk == parent }) {
            protected.insert(parent)
        }
        return protected
    }

    private func scanAPFSVolumes(from candidates: [Candidate]) -> APFSScan {
        let stores = Dictionary(uniqueKeysWithValues: candidates
            .filter { $0.content.caseInsensitiveCompare("Apple_APFS") == .orderedSame }
            .map { ($0.identifier, $0) })
        guard !stores.isEmpty,
              let result = try? CommandRunner.run(diskutil, arguments: ["apfs", "list", "-plist"]),
              let plist = try? PropertyListSerialization.propertyList(from: result.stdout, options: [], format: nil),
              let root = plist as? [String: Any],
              let containers = root["Containers"] as? [[String: Any]] else {
            return APFSScan(candidates: [], systemWholeDisks: [])
        }

        var output: [Candidate] = []
        var systemWholeDisks: Set<String> = []
        for container in containers {
            guard let physicalStores = container["PhysicalStores"] as? [[String: Any]],
                  let store = physicalStores.compactMap({ $0["DeviceIdentifier"] as? String }).compactMap({ stores[$0] }).first,
                  let volumes = container["Volumes"] as? [[String: Any]] else { continue }

            let containsSystemVolume = volumes.contains { volume in
                (volume["Roles"] as? [String] ?? []).contains { $0.caseInsensitiveCompare("System") == .orderedSame }
            }
            if containsSystemVolume {
                systemWholeDisks.insert(store.wholeDisk)
            }

            for volume in volumes {
                guard let identifier = volume["DeviceIdentifier"] as? String else { continue }
                let roles = volume["Roles"] as? [String] ?? []
                let technicalRole = roles.contains { role in
                    ["System", "Preboot", "Recovery", "VM", "Update", "xART", "Hardware"].contains {
                        $0.caseInsensitiveCompare(role) == .orderedSame
                    }
                }
                output.append(Candidate(
                    identifier: identifier,
                    wholeDisk: store.wholeDisk,
                    content: "Apple_APFS_Volume",
                    size: unsignedInteger(volume["CapacityInUse"]),
                    wholeDiskSize: store.wholeDiskSize,
                    forceProtected: technicalRole
                ))
            }
        }
        return APFSScan(candidates: output, systemWholeDisks: systemWholeDisks)
    }

    private func isAuxiliaryContent(_ content: String) -> Bool {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let exact: Set<String> = [
            "efi", "apple_boot", "apple_apfs", "apple_apfs_isc", "apple_apfs_recovery",
            "microsoft reserved", "windows_recovery", "0x1b"
        ]
        return exact.contains(normalized)
            || normalized.contains("recovery")
            || normalized.contains("preboot")
    }

    private func hardwareSerial(for wholeDisk: String) -> String? {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, wholeDisk),
              case let service = IOServiceGetMatchingService(kIOMainPortDefault, matching),
              service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        for key in ["USB Serial Number", "Serial Number"] {
            guard let value = IORegistryEntrySearchCFProperty(
                service,
                kIOServicePlane,
                key as CFString,
                kCFAllocatorDefault,
                options
            ) else { continue }
            if let serial = value as? String,
               !serial.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                return serial.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private func diskInfo(identifier: String) -> [String: Any]? {
        guard let result = try? CommandRunner.run(diskutil, arguments: ["info", "-plist", "/dev/\(identifier)"]),
              let plist = try? PropertyListSerialization.propertyList(from: result.stdout, options: [], format: nil) else {
            return nil
        }
        return plist as? [String: Any]
    }

    private static func decodeMountPath(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\040", with: " ")
            .replacingOccurrences(of: "\\011", with: "\t")
            .replacingOccurrences(of: "\\012", with: "\n")
            .replacingOccurrences(of: "\\134", with: "\\")
    }

    private func string(_ value: Any?) -> String {
        value as? String ?? ""
    }

    private func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return false
    }

    private func unsignedInteger(_ value: Any?) -> UInt64 {
        if let value = value as? UInt64 { return value }
        if let value = value as? NSNumber { return value.uint64Value }
        return 0
    }
}

enum DiskServiceError: LocalizedError {
    case cannotOpenFinder
    case ejectBusy
    case ejectTimedOut

    var errorDescription: String? {
        switch self {
        case .cannotOpenFinder:
            return "无法在 Finder 中打开该磁盘。"
        case .ejectBusy:
            return "磁盘仍被 Finder 或其他 App 使用，暂时无法安全弹出。"
        case .ejectTimedOut:
            return "安全弹出等待超时。"
        }
    }
}
