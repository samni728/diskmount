import Foundation

struct DiskDevice: Codable, Identifiable, Equatable {
    let id: String
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
}

struct PanelState: Codable {
    let version: String
    let devices: [DiskDevice]
    let dependency: DependencyState
    let proMode: Bool
    let busyDeviceID: String?
    let message: String?
    let error: String?
}
