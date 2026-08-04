import Foundation

struct DiskDevice: Codable, Identifiable, Equatable {
    let id: String
    let persistentID: String
    let wholeDiskIdentifier: String
    let name: String
    let fileSystem: String
    let content: String
    let mountPoint: String?
    let size: UInt64
    let mounted: Bool
    let writable: Bool
    let isNTFS: Bool
    let isProtected: Bool

    var devicePath: String { "/dev/\(id)" }
}

struct DependencyState: Codable {
    let available: Bool
    let path: String?
    let version: String?
    let bundled: Bool
}

struct AppUpdateState: Codable, Equatable {
    let available: Bool
    let latestVersion: String?
    let releaseURL: String?

    static let noUpdate = AppUpdateState(
        available: false,
        latestVersion: nil,
        releaseURL: nil
    )
}

struct PanelState: Codable {
    let version: String
    let devices: [DiskDevice]
    let dependency: DependencyState
    let proMode: Bool
    let language: String
    let authorizedProtectedDeviceIDs: [String]
    let autoMountNTFSPersistentIDs: [String]
    let busyDeviceID: String?
    let message: String?
    let error: String?
    let removableVolumePermissionRequired: Bool
    let update: AppUpdateState
}
