import Foundation
@testable import MagicKettleKit
import Testing

/// Vortex's folder picker in Steam's Windows started at the Mac's root: Open boxes offer the home folder and external
/// disks instead, and paths keep matching the way Wine names them.
@Suite struct BottleDrivesTests {
    /// A bottle with Wine's own drives: `C:` and `Z:` → `/`, as `wineboot` leaves them.
    static func bottle(in temp: TempFolder) throws -> URL {
        let bottle = temp.url.appending(path: "bottle", directoryHint: .isDirectory)
        let devices = bottle.appending(path: "dosdevices")
        try FileManager.default.createDirectory(at: devices, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bottle.appending(path: "drive_c/users/me"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: devices.appending(path: "c:").path,
                                                   withDestinationPath: "../drive_c")
        try FileManager.default.createSymbolicLink(atPath: devices.appending(path: "z:").path, withDestinationPath: "/")
        try "WINE REGISTRY Version 2\n".write(to: bottle.appending(path: "user.reg"), atomically: true,
                                              encoding: .utf8)
        return bottle
    }

    @Test func homeAndDisksAreDrivesAndFolders() throws {
        let temp = try TempFolder()
        let bottle = try Self.bottle(in: temp)
        let home = temp.url.appending(path: "home", directoryHint: .isDirectory)
        let disks = temp.url.appending(path: "Disks", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home.appending(path: "Games/Vortex"),
                                                withIntermediateDirectories: true)
        // A real folder the player made keeps its contents.
        try FileManager.default.createDirectory(at: bottle.appending(path: "drive_c/users/me/Disks"),
                                                withIntermediateDirectories: true)
        try BottleManager.linkHomeAndDisks(bottle: bottle, disks: disks, home: home)
        try BottleManager.linkHomeAndDisks(bottle: bottle, disks: disks, home: home)
        let link = { (path: String) in
            try? FileManager.default.destinationOfSymbolicLink(atPath: bottle.appending(path: path).path)
        }
        #expect(link("dosdevices/h:") == home.path(percentEncoded: false).dropLast().description)
        #expect(link("dosdevices/v:") == disks.path(percentEncoded: false).dropLast().description)
        #expect(link("drive_c/users/me/Home") == home.path(percentEncoded: false).dropLast().description)
        #expect(link("drive_c/users/me/Disks") == nil)

        // Wine names a program by the closest drive: `H:\Games\…` now, not `Z:\…\home\Games\…`.
        let vortex = home.appending(path: "Games/Vortex/Vortex.exe")
        #expect(WindowsPath.windowsPath(of: vortex, inBottle: bottle) == #"H:\Games\Vortex\Vortex.exe"#)
        #expect(WindowsPath.windowsPath(of: bottle.appending(path: "drive_c/users/me"), inBottle: bottle)
            == #"C:\users\me"#)
        #expect(WindowsPath.windowsPath(of: URL(filePath: "/usr/bin"), inBottle: bottle) == #"Z:\usr\bin"#)
        #expect(WineProcesses.runs(vortex.path(percentEncoded: false), from: #"H:\Games\Vortex"#, bottle: bottle))
        #expect(WineProcesses.runs(#"H:\Games\Vortex\Vortex.exe"#, from: #"h:\games\vortex"#))
    }

    @Test func rootIsHiddenAndOtherDrivesStayHidden() throws {
        let temp = try TempFolder()
        let bottle = try Self.bottle(in: temp)
        let namespace = #"Microsoft\\Windows\\CurrentVersion\\Explorer\\Desktop\\Namespace\\"#
        let system = """
            WINE REGISTRY Version 2

            [Software\\\\\(namespace){450D8FBA-AD25-11D0-98A8-0800361B1103}] 1
            @="My Documents"

            [Software\\\\\(namespace){9D20AAE8-0625-44B0-9CA7-71889C2254D9}] 1
            @="/"

            [Software\\\\Wow6432Node\\\\\(namespace){9D20AAE8-0625-44B0-9CA7-71889C2254D9}] 1
            @="/"

            """
        try system.write(to: bottle.appending(path: "system.reg"), atomically: true, encoding: .utf8)
        let key = #"Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"#
        let user = bottle.appending(path: "user.reg")
        try WineRegistry.setDWord(in: String(contentsOf: user, encoding: .utf8), key: key, name: "NoDrives", value: 1)
            .write(to: user, atomically: true, encoding: .utf8)

        try BottleManager.hideRoot(bottle: bottle)
        let after = try String(contentsOf: bottle.appending(path: "system.reg"), encoding: .utf8)
        #expect(!after.contains("9D20AAE8"))
        #expect(after.contains(#"@="My Documents""#))
        #expect(WineRegistry.dword(in: try String(contentsOf: user, encoding: .utf8), key: key, name: "NoDrives")
            == 1 | 1 << 25)
    }

    @Test func onlyExternalDisksAreOffered() throws {
        let wanted = ExternalDisks.wanted([
            (path: "/", isRoot: true), (path: "/Volumes/Macintosh HD", isRoot: true),
            (path: "/Volumes/Games SSD", isRoot: false), (path: "/System/Volumes/Data", isRoot: false),
        ])
        #expect(wanted == ["Games SSD": "/Volumes/Games SSD"])

        let temp = try TempFolder()
        let folder = temp.url.appending(path: "Disks", directoryHint: .isDirectory)
        ExternalDisks.sync(folder, to: ["Old": "/Volumes/Old", "Games SSD": "/Volumes/Games SSD"])
        try "keep".write(to: folder.appending(path: "note.txt"), atomically: true, encoding: .utf8)
        ExternalDisks.sync(folder, to: wanted)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["Games SSD", "note.txt"])
    }

    @Test func aKeyIsRemovedWithoutItsNeighbours() {
        let text = "WINE REGISTRY Version 2\n\n[A\\\\B] 1\n\"x\"=\"1\"\n\n[A\\\\B\\\\C] 1\n\"y\"=\"2\"\n"
        let without = WineRegistry.removeKey(in: text, key: #"A\B"#)
        #expect(WineRegistry.string(in: without, key: #"A\B"#, name: "x") == nil)
        #expect(WineRegistry.string(in: without, key: #"A\B\C"#, name: "y") == "2")
        #expect(WineRegistry.removeKey(in: text, key: #"Q"#) == text)
    }
}
