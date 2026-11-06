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
        try Data("Wine placeholder".utf8).write(to: stub)
        let written = try PowerShell.install(in: temp.url)
        #expect(written.map(\.lastPathComponent) == ["powershell.exe"])
        #expect(try Data(contentsOf: stub).range(of: PowerShell.marker) != nil)
        // Already in place: nothing to do. A bottle without the 32-bit folder gets no 32-bit one.
        #expect(try PowerShell.install(in: temp.url).isEmpty)
    }

    @Test func powerShellRunsMagicKettlesFirst() {
        let overrides = WineEnvironment.make(host: [:], bottle: "/b")["WINEDLLOVERRIDES"] ?? ""
        #expect(overrides.split(separator: ";").contains("powershell.exe=n,b"))
    }
}
