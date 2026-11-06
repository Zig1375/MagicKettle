import CryptoKit
import Foundation
@testable import MagicKettleKit
import Testing

/// Mod managers get their cover from MagicKettle-Games; r2modman's card showed only its exe's small icon.
@Suite struct ModuleCoversTests {
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 7, count: 100)

    static func cover(for data: Data, from path: String = "r2modman/cover.png") -> GameModule.Cover {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return GameModule.Cover(from: path, sha256: digest, size: data.count)
    }

    static func index(cover: GameModule.Cover?, commit: String? = "abc123") -> GameModuleIndex {
        GameModuleIndex(commit: commit, modules: [
            GameModule(id: "r2modman", revision: 1, format: 1, name: "r2modman",
                       match: GameModule.Match(product: ["r2modman"]), fixes: [], cover: cover),
        ])
    }

    let record = GameRecord(id: .make(), name: "r2modman", executable: "/Users/me/Downloads/r2modman-3.2.21.exe",
                            folder: "/Users/me/Downloads", hasMarker: false, addedAt: Date())

    /// The index as MagicKettle-Games' tools/build_index.py writes it: a module with a cover and no fixes.
    @Test func aModuleWithOnlyACoverDecodes() throws {
        let icon = #"{"from": "m/cover.png", "sha256": "ab", "size": 1, "icon": {"x": 0.5, "y": 0.36, "size": 0.33}}"#
        let place = try JSONDecoder().decode(GameModule.Cover.self, from: Data(icon.utf8)).icon
        #expect(place == GameModule.IconPlace(x: 0.5, y: 0.36, size: 0.33))
        let json = """
            {"format": 1, "generated": "2026-11-06T00:00:00Z", "commit": "abc", "modules": [
              {"id": "r2modman", "revision": 1, "format": 1, "name": "r2modman", "note": "Why.",
               "match": {"product": ["r2modman"]},
               "cover": {"from": "r2modman/cover.png", "sha256": "\(String(repeating: "a", count: 64))", "size": 5}}
            ]}
            """
        let module = try #require(GameModuleIndex.decode(Data(json.utf8)).modules.first)
        #expect(module.fixes.isEmpty)
        #expect(module.match?.product == ["r2modman"])
        #expect(module.cover?.from == "r2modman/cover.png")
    }

    /// A download named by its version is found by its ProductName alone; any other program isn't.
    @Test func aProgramIsFoundByItsProductNameAlone() {
        let modules = Self.index(cover: nil).modules
        let game = { (product: String?) in
            GameModules.Game(store: nil, storeID: nil, executable: URL(filePath: "/d/r2modman-3.2.21.exe"),
                             productName: product)
        }
        #expect(GameModules.find(for: game("R2ModMan"), in: modules, app: nil)?.id == "r2modman")
        #expect(GameModules.find(for: game("Muck"), in: modules, app: nil) == nil)
        #expect(GameModules.find(for: game(nil), in: modules, app: nil) == nil)
    }

    @Test func onlyAPictureUnderFilesIsFetched() throws {
        let cover = Self.cover(for: Self.png)
        #expect(ModuleCovers.url(for: cover, commit: "abc123")?.absoluteString
            == "https://raw.githubusercontent.com/Zig1375/MagicKettle-Games/abc123/files/r2modman/cover.png")
        #expect(ModuleCovers.url(for: cover, commit: nil)?.absoluteString.contains("/main/files/") == true)
        for path in ["cover.png", "r2modman/../x.png", "r2modman/cover.exe", "/r2modman/cover.png", "a/b?.png"] {
            #expect(ModuleCovers.url(for: Self.cover(for: Self.png, from: path), commit: "abc") == nil, "\(path)")
        }
    }

    @Test func onlyThePinnedPictureIsKept() {
        let cover = Self.cover(for: Self.png)
        #expect(ModuleCovers.isPinned(Self.png, by: cover))
        #expect(!ModuleCovers.isPinned(Self.png + Data([0]), by: cover))
        let exe = Data("MZ".utf8) + Data(repeating: 7, count: 106)
        #expect(!ModuleCovers.isPinned(exe, by: Self.cover(for: exe)))
    }

    @Test func theCoverIsFetchedOnceAndKept() async throws {
        let temp = try TempFolder()
        let paths = AppPaths(root: temp.url, games: temp.url)
        let index = Self.index(cover: Self.cover(for: Self.png))
        let fetched = Counter()
        let file = try #require(await ModuleCovers.cover(for: record, productName: "r2modman", index: index,
                                                         paths: paths) { url in
            await fetched.add(url)
            return Self.png
        }?.file)
        #expect(try Data(contentsOf: file) == Self.png)
        #expect(file.deletingLastPathComponent() == paths.artwork)
        let again = await ModuleCovers.cover(for: record, productName: "r2modman", index: index, paths: paths) { _ in
            Issue.record("fetched twice")
            return nil
        }
        #expect(again?.file == file)
        #expect(again?.icon == nil)
        #expect(await fetched.urls.map(\.lastPathComponent) == ["cover.png"])

        // A cover that leaves room for the program's own icon says where; a place off the cover draws none.
        var withIcon = Self.cover(for: Self.png)
        withIcon.icon = GameModule.IconPlace(x: 0.5, y: 0.36, size: 0.33)
        let placed = await ModuleCovers.cover(for: record, productName: "r2modman", index: Self.index(cover: withIcon),
                                              paths: paths) { _ in nil }
        #expect(placed?.icon == GameModule.IconPlace(x: 0.5, y: 0.36, size: 0.33))
        withIcon.icon = GameModule.IconPlace(x: 2, y: 0.36, size: 0.33)
        let offCover = await ModuleCovers.cover(for: record, productName: "r2modman",
                                                index: Self.index(cover: withIcon), paths: paths) { _ in nil }
        #expect(offCover != nil && offCover?.icon == nil)

        // The program's next cover replaces it: the old file goes.
        ModuleCovers.prune(keeping: Self.index(cover: Self.cover(for: Self.png + Data([1]))), paths: paths)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aWrongDownloadIsNotKept() async throws {
        let temp = try TempFolder()
        let paths = AppPaths(root: temp.url, games: temp.url)
        let index = Self.index(cover: Self.cover(for: Self.png))
        let file = await ModuleCovers.cover(for: record, productName: "r2modman", index: index, paths: paths) { _ in
            Self.png + Data([0])
        }
        #expect(file == nil)
        #expect(await ModuleCovers.cover(for: record, productName: "Muck", index: index, paths: paths) { _ in
            Self.png
        } == nil)
    }

    /// The real covers in the app's copy of the index: every mod manager Magic Kettle knows by name and has a
    /// logo for gets one.
    @Test func bundledModManagersHaveCovers() throws {
        let modules = try GameModuleIndex.bundled().modules
        let find = { (product: String, exe: String) in
            GameModules.find(for: GameModules.Game(store: nil, storeID: nil, executable: URL(filePath: "/d/\(exe)"),
                                                   productName: product), in: modules, app: nil)?.cover
        }
        #expect(find("r2modman", "r2modman-3.2.21.exe") != nil)
        #expect(find("HedgeModManager.UI", "HedgeModManager.exe") != nil)
        #expect(find("Hedge Mod Manager", "HedgeModManager.exe") != nil)
        #expect(find("Gale", "gale.exe") != nil)
        #expect(find("NexusMods.App", "NexusMods.App.exe") != nil)
        #expect(find("SAModManager", "SAModManager.exe") != nil)
        #expect(find("ManiaModManager", "ManiaModManager.exe") != nil)
        #expect(find("Gale", "Gale Force.exe") == nil)
    }
}

private actor Counter {
    var urls: [URL] = []
    func add(_ url: URL) { urls.append(url) }
}
