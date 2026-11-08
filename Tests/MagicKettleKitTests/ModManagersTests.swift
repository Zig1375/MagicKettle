import Foundation
@testable import MagicKettleKit
import Testing

@Suite struct ModManagersTests {
    /// r2modman's one-file download says "r2modman"; a game never counts, whatever its file is called.
    @Test func modManagersAreKnownByTheirProductName() {
        #expect(ModManagers.isModManager(productName: "r2modman", exeName: "r2modman-3.2.21.exe"))
        #expect(ModManagers.isModManager(productName: "HedgeModManager", exeName: "HedgeModManager.exe"))
        // HedgeModManager 7.15's exe spells its name with spaces; the Nexus Mods app with a dot.
        #expect(ModManagers.isModManager(productName: "Hedge Mod Manager", exeName: "HedgeModManager.exe"))
        #expect(ModManagers.isModManager(productName: "NexusMods.App", exeName: "NexusMods.App.exe"))
        #expect(ModManagers.isModManager(productName: nil, exeName: "HedgeModManager.exe"))
        // HedgeModManager 8.0 beta 7, as downloaded: its exe's ProductName is its main assembly's.
        #expect(ModManagers.isModManager(productName: "HedgeModManager.UI", exeName: "HedgeModManager.exe"))
        #expect(ModManagers.isModManager(productName: nil, exeName: "NexusMods.App-0.9.exe"))
        #expect(ModManagers.isModManager(productName: nil, exeName: "Thunderstore Mod Manager - Installer.exe"))
        #expect(!ModManagers.isModManager(productName: nil, exeName: "Galeforce-1.0.exe"))
        #expect(ModManagers.isModManager(productName: nil, exeName: "r2modman-Setup-3.2.21.exe"))
        // Read from each one's own download on 6 November 2026: the installers of Vortex 2.10.1 and the Nexus Mods
        // app 0.21.1, SA Mod Manager 1.3.7 and ManiaModManager.
        #expect(ModManagers.isModManager(productName: "Vortex", exeName: "vortex-setup-2.10.1.exe"))
        #expect(ModManagers.isModManager(productName: "Nexus Mods App", exeName: "NexusMods.App.x64.exe"))
        #expect(ModManagers.isModManager(productName: "SAModManager", exeName: "SAModManager.exe"))
        #expect(ModManagers.isModManager(productName: "ManiaModManager", exeName: "ManiaModManager.exe"))
        #expect(!ModManagers.isModManager(productName: "Muck", exeName: "Muck.exe"))
        #expect(!ModManagers.isModManager(productName: "Muck", exeName: "r2modman.exe"))
    }

    /// Every known manager works with Steam's and Epic's games, so it asks between them; anything else never asks.
    @Test func aManagerAsksBetweenTheStoresItWorksWith() {
        let hedge = ModManagers.stores(productName: "HedgeModManager.UI", exeName: "HedgeModManager.exe")
        #expect(hedge == [.steam, .epic])
        #expect(GameRecord.storeChoices(supported: hedge) == [.steam, .epic])
        #expect(ModManagers.stores(productName: nil, exeName: "r2modman-Setup-3.2.21.exe") == [.steam, .epic])
        #expect(ModManagers.stores(productName: "Muck", exeName: "r2modman.exe").isEmpty)
        // SA Mod Manager's games are only in Steam: a manager for one store only has nothing to ask.
        let sonicAdventure = ModManagers.stores(productName: "SAModManager", exeName: "SAModManager.exe")
        #expect(sonicAdventure == [.steam])
        #expect(GameRecord.storeChoices(supported: sonicAdventure) == nil)
        #expect(GameRecord.storeChoices(supported: [.steam]) == nil)
        #expect(GameRecord.storeChoices(supported: []) == nil)
    }

    /// It starts with Steam when Steam is there, else Epic, else on its own; with both, each launch asks.
    @Test func aModManagerRunsWithTheFirstInstalledStore() {
        #expect(ModManagers.store(installed: [.steam, .epic]) == .steam)
        #expect(ModManagers.store(installed: [.epic]) == .epic)
        #expect(ModManagers.store(installed: []) == nil)
    }
}

/// r2modman finds Steam by asking PowerShell; Wine's stub answers nothing, so Magic Kettle puts its own in place.
@Suite struct PowerShellTests {
    @Test func theStandInReplacesWinesStubAndStays() throws {
        let temp = try TempFolder()
        let folder = temp.url.appending(path: "drive_c/windows/system32/WindowsPowerShell/v1.0",
                                        directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stub = folder.appending(path: "powershell.exe")
        try Data("Wine placeholder DLL".utf8).write(to: stub)
        let written = try PowerShell.install(in: temp.url)
        #expect(written.map(\.lastPathComponent) == ["powershell.exe"])
        #expect(try Data(contentsOf: stub).range(of: PowerShell.marker) != nil)
        // Already in place: nothing to do. A bottle without the 32-bit folder gets no 32-bit one.
        #expect(try PowerShell.install(in: temp.url).isEmpty)
    }

    @Test func aPlayersPowerShellIsKeptAndAnOlderStandInIsUpdated() throws {
        let temp = try TempFolder()
        let target = temp.url.appending(path: "powershell.exe")
        let real = Data("MZ player-installed PowerShell".utf8)
        let replacement = PowerShell.marker + Data(" new".utf8)
        try real.write(to: target)
        #expect(try !PowerShell.install(replacement, at: target))
        #expect(try Data(contentsOf: target) == real)
        try (PowerShell.marker + Data(" old".utf8)).write(to: target)
        #expect(try PowerShell.install(replacement, at: target))
        #expect(try Data(contentsOf: target) == replacement)
    }

    @Test func powerShellRunsMagicKettlesFirst() {
        let overrides = WineEnvironment.make(host: [:], bottle: "/b")["WINEDLLOVERRIDES"] ?? ""
        #expect(overrides.split(separator: ";").contains("powershell.exe=n,b"))
    }
}

/// A mod manager put down by its installer went into a Windows of its own and found none of Steam's games.
@Suite struct InstalledModManagerTests {
    @Test func anInstalledManagerRunsWithTheStore() throws {
        let temp = try TempFolder()
        let paths = AppPaths(root: temp.url, games: temp.url.appending(path: "Games"))
        let drive = paths.bottle(forGame: Store.steam.bottleID).appending(path: "drive_c")
        let client = try #require(Store.steam.module.clientPaths.first.map { drive.appending(path: $0) })
        try FileManager.default.createDirectory(at: client.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: client)
        let exe = URL(filePath: "/Users/me/Games/Vortex/Vortex.exe")
        var vortex = GameRecord(id: .make(), name: "Vortex", executable: exe.path, folder: "/Users/me/Games/Vortex",
                                hasMarker: true, addedAt: Date())
        ModManagers.setUp(&vortex, exe: exe, productName: "Vortex", paths: paths)
        #expect(vortex.runsWith == .steam)
        #expect(vortex.storeChoices == [.steam, .epic])
        #expect(vortex.isProgram)
        var game = GameRecord(id: .make(), name: "Heroes", executable: "/Games/Heroes/h3.exe", folder: "/Games/Heroes",
                              hasMarker: true, addedAt: Date())
        ModManagers.setUp(&game, exe: URL(filePath: game.executable), productName: "Heroes", paths: paths)
        #expect(game.runsWith == nil && game.storeChoices == nil)
        #expect(!game.isProgram)
    }

    /// Finishing an install of a mod manager removes its temporary install bottle when it runs with a store, and
    /// leaves a program installed inside its own bottle's `drive_c` in that bottle.
    @Test func finishingCleansUpTheInstallBottleOrKeepsInBottleInstall() throws {
        let temp = try TempFolder()
        let paths = AppPaths(root: temp.url, games: temp.url.appending(path: "Games"))
        let steamDrive = paths.bottle(forGame: Store.steam.bottleID).appending(path: "drive_c")
        let client = try #require(Store.steam.module.clientPaths.first.map { steamDrive.appending(path: $0) })
        try FileManager.default.createDirectory(at: client.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: client)

        let installer = GameInstaller(paths: paths)
        let id = GameID.make()
        let installBottle = paths.bottle(forGame: id)
        try FileManager.default.createDirectory(at: installBottle, withIntermediateDirectories: true)
        let folder = paths.games.appending(path: "Gale", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let exe = folder.appending(path: "gale.exe")
        try Data("MZ".utf8).write(to: exe)
        let plan = GameInstaller.Plan(installer: temp.url.appending(path: "Gale.msi"), kind: .windowsInstaller,
                                      name: "Gale", folder: folder)
        let installed = GameInstaller.Installed(
            id: id, plan: plan,
            found: InstalledPrograms.Found(programs: [.init(url: exe, role: .game, hasShortcut: true, size: 2)],
                                           uninstaller: nil),
            log: temp.url.appending(path: "install.log"))
        let record = try installer.finish(installed, program: exe, keepDisc: false)
        #expect(record.runsWith == .steam)
        #expect(!FileManager.default.fileExists(atPath: installBottle.path))

        // Installed into the install bottle's own `drive_c`: keeps its bottle rather than pointing at Steam's.
        let inBottleID = GameID.make()
        let inBottle = paths.bottle(forGame: inBottleID)
        let inBottleExe = inBottle.appending(path: "drive_c/Program Files/Gale/gale.exe")
        try FileManager.default.createDirectory(at: inBottleExe.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: inBottleExe)
        let inBottleInstalled = GameInstaller.Installed(
            id: inBottleID, plan: plan,
            found: InstalledPrograms.Found(programs: [.init(url: inBottleExe, role: .game, hasShortcut: true, size: 2)],
                                           uninstaller: nil),
            log: temp.url.appending(path: "install2.log"))
        let inBottleRecord = try installer.finish(inBottleInstalled, program: inBottleExe, keepDisc: false)
        #expect(inBottleRecord.runsWith == nil)
        #expect(FileManager.default.fileExists(atPath: inBottle.path))
    }
}

@Suite struct UnsupportedModManagerStoreTests {
    @Test func steamOnlyManagerDoesNotUseEpic() throws {
        let temp = try TempFolder()
        let paths = AppPaths(root: temp.url, games: temp.url.appending(path: "Games"))
        let drive = paths.bottle(forGame: Store.epic.bottleID).appending(path: "drive_c")
        let client = try #require(Store.epic.module.clientPaths.first.map { drive.appending(path: $0) })
        try FileManager.default.createDirectory(at: client.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: client)
        let exe = temp.url.appending(path: "SAModManager.exe")
        var record = GameRecord(id: .make(), name: "SA Mod Manager", executable: exe.path,
                                folder: temp.url.path, hasMarker: true, addedAt: Date())
        ModManagers.setUp(&record, exe: exe, productName: "SAModManager", paths: paths)
        #expect(record.runsWith == nil)
        #expect(record.storeChoices == nil)
    }
}
