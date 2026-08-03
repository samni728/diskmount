import AppKit
import Foundation

final class DiskService {
    private let diskutil = "/usr/sbin/diskutil"

    private struct Candidate {
        let identifier: String
        let wholeDisk: String
        let content: String
        let size: UInt64
        let forceProtected: Bool
    }

    private struct APFSScan {
        let candidates: [Candidate]
        let systemWholeDisks: Set<String>
    }

    func listExternalVolumes(includeAdvanced: Bool = false) throws -> [DiskDevice] {
        let listResult = try CommandRunner.run(diskutil, arguments: ["list", "-plist", "external", "physical"])
        let plist = try PropertyListSerialization.propertyList(from: listResult.stdout, options: [], format: nil)
        guard let root = plist as? [String: Any],
              let disks = root["AllDisksAndPartitions"] as? [[String: Any]] else {
            return []
        }

        var candidates: [Candidate] = []
        for disk in disks {
            guard let wholeDisk = disk["DeviceIdentifier"] as? String else { continue }
            collectPartitions(from: disk, wholeDisk: wholeDisk, into: &candidates)
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
                forceProtected: candidate.forceProtected || protectedWholeDisks.contains(candidate.wholeDisk)
            )
        }.filter { includeAdvanced || !$0.isProtected }.sorted { lhs, rhs in
            if lhs.wholeDiskIdentifier == rhs.wholeDiskIdentifier { return lhs.id < rhs.id }
            return lhs.wholeDiskIdentifier < rhs.wholeDiskIdentifier
        }
    }

    func mount(_ device: DiskDevice) throws {
        _ = try CommandRunner.run(diskutil, arguments: ["mount", device.devicePath])
    }

    func unmount(_ device: DiskDevice) throws {
        _ = try CommandRunner.run(diskutil, arguments: ["unmount", device.devicePath])
    }

    func eject(_ device: DiskDevice) throws {
        _ = try CommandRunner.run(diskutil, arguments: ["eject", "/dev/\(device.wholeDiskIdentifier)"])
    }

    func openInFinder(_ device: DiskDevice) throws {
        guard let mountPoint = device.mountPoint else { return }
        guard NSWorkspace.shared.open(URL(fileURLWithPath: mountPoint)) else {
            throw DiskServiceError.cannotOpenFinder
        }
    }

    private func collectPartitions(
        from item: [String: Any],
        wholeDisk: String,
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
                        forceProtected: false
                    ))
                }
                collectPartitions(from: partition, wholeDisk: wholeDisk, into: &output)
            }
        }
    }

    private func makeDevice(
        identifier: String,
        wholeDisk: String,
        fallbackContent: String,
        fallbackSize: UInt64,
        forceProtected: Bool
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
        let anyLinuxFSMountPoint = volumeName.isEmpty ? nil : "/Volumes/\(volumeName)"
        let fallbackMountPoint = anyLinuxFSMountPoint.flatMap {
            FileManager.default.fileExists(atPath: $0) ? $0 : nil
        }
        let mountPoint = diskutilMountPoint ?? fallbackMountPoint
        let unnamedAndUnavailable = volumeName.isEmpty && mountPoint == nil && !isNTFS && fileSystem.isEmpty
        let isProtected = forceProtected || isAuxiliaryContent(content) || unnamedAndUnavailable

        return DiskDevice(
            id: identifier,
            wholeDiskIdentifier: wholeDisk,
            name: volumeName.isEmpty ? (mediaName.isEmpty ? identifier : mediaName) : volumeName,
            fileSystem: fileSystem.isEmpty ? (typeBundle.isEmpty ? content : typeBundle) : fileSystem,
            content: content,
            mountPoint: mountPoint,
            size: unsignedInteger(info["TotalSize"]) == 0 ? fallbackSize : unsignedInteger(info["TotalSize"]),
            mounted: bool(info["Mounted"]) || mountPoint != nil,
            writable: bool(info["Writable"]) || mountPoint.map(FileManager.default.isWritableFile(atPath:)) == true,
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

    var errorDescription: String? {
        "无法在 Finder 中打开该磁盘。"
    }
}
