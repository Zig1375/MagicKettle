import Foundation
@testable import MagicKettleKit
import Testing

@Suite struct StoreSyncTests {
    let temp: TempFolder

    init() throws { temp = try TempFolder() }

    @Test func steamGameStaysWhileItsManifestIsBeingRewritten() throws {
        let steamapps = temp.url.appending(path: "steamapps", directoryHint: .isDirectory)
        let folder = steamapps.appending(path: "common/Banished", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Probes.url("d3d9-x86"), to: folder.appending(path: "Banished.exe"))
        let manifest = steamapps.appending(path: "appmanifest_242920.acf")
        try Data("\"AppState\" {".utf8).write(to: manifest)
        let banished = StoreLibrary.Game(store: .steam, id: "242920", name: "Banished", folder: folder)
        var library = GameLibrary()
        #expect(StoreLibrary.merge([.steam: [banished]], into: &library, now: Date()))
        let id = try #require(library.games.first?.id)

        // Steam is halfway through writing the manifest: the scan can't read it, the game keeps its record.
        #expect(!StoreLibrary.merge([.steam: []], into: &library, now: Date()))
        #expect(library.games.map(\.id) == [id])

        // Uninstalled: the manifest goes, and so does the game.
        try FileManager.default.removeItem(at: manifest)
        #expect(StoreLibrary.merge([.steam: []], into: &library, now: Date()))
        #expect(library.games.isEmpty)
    }

    @Test func aNewStoreGameGetsTheRetinaDefault() throws {
        let folder = temp.url.appending(path: "common/Banished", directoryHint: .isDirectory)
        let banished = StoreLibrary.Game(store: .steam, id: "242920", name: "Banished", folder: folder,
                                         executable: folder.appending(path: "Banished.exe"))
        var library = GameLibrary()
        #expect(StoreLibrary.merge([.steam: [banished]], into: &library, now: Date(), retina: .off))
        #expect(library.games.first?.retina == .off)
    }

    @Test func aCrashHandlerPickedAsTheProgramIsPickedAgain() throws {
        let folder = temp.url.appending(path: "common/Kerbal Space Program", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let game = folder.appending(path: "KSP_x64.exe")
        let handler = folder.appending(path: "UnityCrashHandler64.exe")
        try FileManager.default.copyItem(at: Probes.url("d3d11-x64"), to: game)
        try FileManager.default.copyItem(at: Probes.url("d3d11-x64"), to: handler)
        var record = GameRecord(id: .make(), name: "Kerbal Space Program",
                                executable: handler.path(percentEncoded: false),
                                folder: folder.path(percentEncoded: false), hasMarker: false, addedAt: Date())
        record.store = .steam
        record.storeID = "220200"
        var library = GameLibrary()
        library.games = [record]
        let ksp = StoreLibrary.Game(store: .steam, id: "220200", name: "Kerbal Space Program", folder: folder)
        #expect(StoreLibrary.merge([.steam: [ksp]], into: &library, now: Date()))
        #expect(library.games.first.map { URL(filePath: $0.executable).lastPathComponent } == game.lastPathComponent)
        #expect(!StoreLibrary.merge([.steam: [ksp]], into: &library, now: Date()))
    }
}
