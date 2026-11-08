import Foundation
@testable import MagicKettleKit
import Testing

@Suite struct StoreSharpnessTests {
    @Test func storeClientsDrawAtTheScreensResolution() throws {
        let temp = try TempFolder()
        let userReg = temp.url.appending(path: "user.reg")
        try "WINE REGISTRY Version 2\n".write(to: userReg, atomically: true, encoding: .utf8)

        try StoreClient.drawSharp(temp.url, scale: 2)
        var text = try String(contentsOf: userReg, encoding: .utf8)
        #expect(WineRegistry.string(in: text, key: #"Software\Wine\Mac Driver"#, name: "RetinaMode") == "y")
        #expect(WineRegistry.contains(text, key: #"Control Panel\Desktop"#, entry: #""LogPixels"=dword:000000c0"#))

        // A display without Retina: Wine's defaults, or everything would be drawn twice as large.
        try StoreClient.drawSharp(temp.url, scale: 1)
        text = try String(contentsOf: userReg, encoding: .utf8)
        #expect(WineRegistry.string(in: text, key: #"Software\Wine\Mac Driver"#, name: "RetinaMode") == "n")
        #expect(WineRegistry.contains(text, key: #"Control Panel\Desktop"#, entry: #""LogPixels"=dword:00000060"#))
    }

    @Test func gamesStartedByTheClientNeverSwitchTheMacsDisplay() throws {
        let temp = try TempFolder()
        let userReg = temp.url.appending(path: "user.reg")
        try "WINE REGISTRY Version 2\n".write(to: userReg, atomically: true, encoding: .utf8)
        try StoreClient.setUpForGames(temp.url)
        let text = try String(contentsOf: userReg, encoding: .utf8)
        #expect(WineRegistry.string(in: text, key: #"Software\Wine\X11 Driver"#, name: "EmulateModeset") == "y")
        #expect(WineRegistry.string(in: text, key: #"Software\Wine\X11 Driver"#, name: "StretchWindows") == "y")
        #expect(WineRegistry.string(in: text, key: #"Software\Wine\Mac Driver"#, name: "LeftCommandIsCtrl") == "y")
        // SA Mod Manager's WPF window stayed blank through DXVK, the only graphics tried in Steam's Windows.
        #expect(WineRegistry.dword(in: text, key: #"Software\Microsoft\Avalon.Graphics"#,
                                   name: "DisableHWAcceleration") == 1)
    }

    /// Vortex went transparent on a 4K monitor in Steam's Windows: programs run with the store keep the real
    /// displays, the store's games keep the emulated mode.
    @Test func programsRunWithTheStoreKeepTheRealDisplays() throws {
        let temp = try TempFolder()
        let userReg = temp.url.appending(path: "user.reg")
        try "WINE REGISTRY Version 2\n".write(to: userReg, atomically: true, encoding: .utf8)
        try StoreClient.setUpForGames(temp.url, programs: ["Vortex.exe", "Vortex.exe", ""])
        let text = try String(contentsOf: userReg, encoding: .utf8)
        let own = #"Software\Wine\AppDefaults\Vortex.exe\X11 Driver"#
        #expect(WineRegistry.string(in: text, key: own, name: "EmulateModeset") == "n")
        #expect(WineRegistry.string(in: text, key: own, name: "StretchWindows") == "n")
        #expect(BottleManager.keepsRealDisplay(bottle: temp.url, program: "Vortex.exe"))
        #expect(!BottleManager.keepsRealDisplay(bottle: temp.url, program: "gale.exe"))
        #expect(WineRegistry.string(in: text, key: #"Software\Wine\X11 Driver"#, name: "EmulateModeset") == "y")
        #expect(!text.contains(#"AppDefaults\\\\X11"#))
    }

    @Test func aClientWithFixedPixelWindowsKeepsWinesDefaults() throws {
        // Steam draws its launch window and its dialogs at a fixed pixel size: in Retina mode they came out at
        // half the size of the rest of its interface, too small to read.
        #expect(Store.steam.drawsAtScreenResolution == false)
        #expect(Store.epic.drawsAtScreenResolution)

        let temp = try TempFolder()
        try "WINE REGISTRY Version 2\n".write(to: temp.url.appending(path: "user.reg"), atomically: true,
                                              encoding: .utf8)
        try StoreClient.drawSharp(temp.url, scale: 2, retina: false)
        let text = try String(contentsOf: temp.url.appending(path: "user.reg"), encoding: .utf8)
        #expect(WineRegistry.string(in: text, key: #"Software\Wine\Mac Driver"#, name: "RetinaMode") == "n")
        #expect(WineRegistry.contains(text, key: #"Control Panel\Desktop"#, entry: #""LogPixels"=dword:00000060"#))
        #expect(StoreClient.drawn(temp.url) == StoreClient.Drawn(retina: false, dpi: 96))
    }

    @Test func aClientsGamesKeepItsWayOfDrawing() {
        // Among Us started from Magic Kettle with Steam closed: Retina was written into the bottle for the game, Steam
        // started in the same bottle, and its own window came out at half its size.
        #expect(StoreClient.retina(true, for: .steam) == false)
        #expect(StoreClient.retina(true, for: .epic))
        #expect(StoreClient.retina(false, for: nil) == false)
        #expect(StoreClient.retina(true, for: nil))
    }

    @Test func aRetinaClientIsKnownFromItsBottle() throws {
        let temp = try TempFolder()
        try "WINE REGISTRY Version 2\n".write(to: temp.url.appending(path: "user.reg"), atomically: true,
                                              encoding: .utf8)
        // Nothing wrote to the bottle: Wine's own defaults.
        #expect(StoreClient.drawn(temp.url) == StoreClient.Drawn(retina: false, dpi: 96))
        try StoreClient.drawSharp(temp.url, scale: 2)
        #expect(StoreClient.drawn(temp.url) == StoreClient.Drawn(retina: true, dpi: 192))
        try StoreClient.drawSharp(temp.url, scale: 1)
        #expect(StoreClient.drawn(temp.url) == StoreClient.Drawn(retina: false, dpi: 96))
    }
}
