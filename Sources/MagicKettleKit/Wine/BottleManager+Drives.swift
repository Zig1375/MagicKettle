import Foundation

/// What a program's Open and Save boxes show. Wine's `Z:` is the Mac's whole disk and its desktop has a "/" item,
/// so Vortex's folder picker in Steam's Windows started at the Mac's root, where a folder the player has no access to
/// closed it. The player's home folder and external disks are offered instead, both as drives (`H:`, `V:`) and as
/// folders in the Windows user folder (`Home`, `Disks`); `Z:` and "/" are hidden but keep working, since every
/// program's path outside a drive still goes through `Z:`.
extension BottleManager {
    static let homeDrive: Character = "h"
    static let disksDrive: Character = "v"
    /// The folders in `C:\users\<name>` that lead to the same places.
    static let homeFolderName = "Home"
    static let disksFolderName = "Disks"
    /// Wine's "/" item on the Windows desktop (`shell32.rgs`).
    static let unixRootFolder = "{9D20AAE8-0625-44B0-9CA7-71889C2254D9}"
    static let explorerPolicies = #"Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"#
    /// `NoDrives` hides a drive from "This PC" and Open boxes by its bit: A is bit 0, Z bit 25.
    static let hiddenDrives: UInt32 = 1 << 25

    /// The drives and folders, as links Magic Kettle makes and replaces; a real file or folder of that name is left
    /// alone. Links only, so this can run while the bottle's Wine is up.
    static func linkHomeAndDisks(bottle: URL, disks: URL,
                                 home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let devices = bottle.appending(path: "dosdevices", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: devices.path) else { return }
        try link(devices.appending(path: "\(homeDrive):"), to: home)
        try link(devices.appending(path: "\(disksDrive):"), to: disks)
        if let user = try? userFolder(in: bottle) {
            try link(user.appending(path: homeFolderName), to: home)
            try link(user.appending(path: disksFolderName), to: disks)
        }
    }

    private static func link(_ link: URL, to target: URL) throws {
        let fileManager = FileManager.default
        let wanted = target.path(percentEncoded: false)
        let wantedPath = wanted.count > 1 && wanted.hasSuffix("/") ? String(wanted.dropLast()) : wanted
        if let current = try? fileManager.destinationOfSymbolicLink(atPath: link.path) {
            guard current != wantedPath else { return }
            try fileManager.removeItem(at: link)
        } else if fileManager.fileExists(atPath: link.path) {
            return
        }
        try fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: wantedPath)
    }

    /// Hides `Z:` and Wine's "/" desktop item. Registry, so only while the bottle's Wine is down.
    static func hideRoot(bottle: URL) throws {
        let userReg = bottle.appending(path: "user.reg")
        let user = try String(contentsOf: userReg, encoding: .utf8)
        let hidden = WineRegistry.dword(in: user, key: explorerPolicies, name: "NoDrives") ?? 0
        try setRegistryDWord(bottle: bottle, key: explorerPolicies, name: "NoDrives", value: hidden | hiddenDrives)

        let systemReg = bottle.appending(path: "system.reg")
        guard let system = try? String(contentsOf: systemReg, encoding: .utf8) else { return }
        let namespace = #"Microsoft\Windows\CurrentVersion\Explorer\Desktop\Namespace\"# + unixRootFolder
        let without = [#"Software\"# + namespace, #"Software\Wow6432Node\"# + namespace]
            .reduce(system) { WineRegistry.removeKey(in: $0, key: $1) }
        if without != system { try without.write(to: systemReg, atomically: true, encoding: .utf8) }
    }
}

/// `V:`: the Mac's external disks, as links in a folder of Magic Kettle's own. `/Volumes` itself also holds the
/// startup disk ("Macintosh HD"), a way back to the root that `V:` must not offer.
public enum ExternalDisks {
    /// Each disk's name and where it is mounted, of the volumes given: only those under `/Volumes` that aren't the
    /// startup disk.
    static func wanted(_ volumes: [(path: String, isRoot: Bool)]) -> [String: String] {
        var result: [String: String] = [:]
        for volume in volumes where !volume.isRoot && volume.path.hasPrefix("/Volumes/") {
            let name = URL(filePath: volume.path).lastPathComponent
            if !name.isEmpty { result[name] = volume.path }
        }
        return result
    }

    /// Brings the folder up to date with the disks mounted now: a disk unplugged since loses its link.
    public static func refresh(_ folder: URL) {
        let keys: [URLResourceKey] = [.volumeIsRootFileSystemKey]
        let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                            options: [.skipHiddenVolumes]) ?? []
        let volumes = mounted.map { url in
            (path: url.path(percentEncoded: false).trimmingSuffix("/"),
             isRoot: (try? url.resourceValues(forKeys: Set(keys)).volumeIsRootFileSystem) ?? false)
        }
        sync(folder, to: wanted(volumes))
    }

    /// Only links are removed: the folder is Magic Kettle's, and nothing else is ever put there.
    static func sync(_ folder: URL, to wanted: [String: String]) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [] {
            let link = folder.appending(path: name)
            guard let target = try? fileManager.destinationOfSymbolicLink(atPath: link.path) else { continue }
            if wanted[name] != target { try? fileManager.removeItem(at: link) }
        }
        for (name, target) in wanted {
            let link = folder.appending(path: name)
            if (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) == nil {
                try? fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: target)
            }
        }
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        count > suffix.count && hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
