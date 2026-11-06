import AppKit
import Foundation
import MagicKettleKit

/// The game page's actions: details, files, logs, settings that change a game's record.
extension LibraryModel {
    /// Applied to the bottle at the next launch (the registry can't change while the game runs).
    func setWindowsVersion(_ version: WindowsVersion, for game: GameRecord) {
        guard !isPlaying(game.id) else { return }
        // A warm bottle's registry can't change under its running Wine.
        Task { await warmer.cool(game.id) }
        update(game.id) { $0.windowsVersion = version }
    }

    func runs(for game: GameRecord) -> [LaunchHistory.Run] {
        LaunchHistory.runs(in: paths.logs(forGame: game.id))
    }

    /// Size of the game's folder on disk.
    /// The size of what "Delete from disk" would remove (`GameRemover.trashTarget`): the game's folder, or only
    /// its program when it sits in Downloads or another shared folder.
    func folderSize(of game: GameRecord) async -> Int64 {
        let folder = GameRemover.trashTarget(for: game, identifier: GameIdentifier(paths: paths))
        return await Task.detached(priority: .utility) { LibraryModel.allocatedSize(of: folder) }.value
    }

    nonisolated static func allocatedSize(of folder: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        if (try? folder.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            let values = try? folder.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            return Int64(values?.totalFileAllocatedSize ?? 0)
        }
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            let values = try? file.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    /// "From disk": the game's folder goes to the Trash (recoverable), then Magic Kettle forgets the game.
    func moveToTrash(_ game: GameRecord) {
        let folder = GameRemover.trashTarget(for: game, identifier: GameIdentifier(paths: paths))
        NSWorkspace.shared.recycle([folder]) { _, error in
            Task { @MainActor in
                if let error {
                    self.notice = Notice(title: String(localized: "Couldn't move \(game.name) to the Trash"),
                                         message: error.localizedDescription)
                } else {
                    self.removeFromApp(game)
                }
            }
        }
    }

    /// The player's own name, on the card and the page. Only for their own games (`GameRecord.canRename`).
    func rename(_ game: GameRecord, to name: String) {
        update(game.id) { $0.rename(to: name) }
    }

    /// Back to the name Magic Kettle gave the game (`GameRecord.originalName`).
    func restoreName(of game: GameRecord) {
        update(game.id) { $0.restoreName() }
    }

    /// "Run with Steam": a mod manager like r2modman starts in Steam's Windows, where it sees Steam's games and
    /// starts them through it; nil runs it on its own again. What was found for it elsewhere is looked for again.
    func run(_ game: GameRecord, with store: Store?) {
        guard GameSettings.canRunWithStore(game, paths: paths) else { return }
        guard store != game.runsWith else { return }
        update(game.id) { record in
            record.runsWith = store
            record.forgetLaunchSettings()
        }
    }

    /// The stores a mod manager works with, by its exe; empty for other programs.
    func supportedStores(of game: GameRecord) -> Set<Store> {
        let exe = URL(filePath: game.executable)
        return ModManagers.stores(productName: (try? ExecutableInfo.read(exe))?.productName,
                                  exeName: exe.lastPathComponent)
    }

    /// "Ask Which Store at Launch" in the card's menu (`GameRecord.storeChoices`); off, it always runs with the store
    /// ticked there.
    func setAsksForStore(_ game: GameRecord, _ asks: Bool) {
        let choices = asks ? GameRecord.storeChoices(supported: supportedStores(of: game)) : nil
        update(game.id) { $0.storeChoices = choices }
    }

    /// The installed stores a mod manager asks between, the one it ran with last first; fewer than two never ask.
    func storeChoices(for game: GameRecord) -> [Store] {
        let stores = (game.storeChoices ?? []).filter(installedStores.contains)
        return stores.filter { $0 == game.runsWith } + stores.filter { $0 != game.runsWith }
    }

    /// A mod manager that works with several stores asks before each launch which store's games it works with this
    /// time, when more than one of them is installed. True when it asked.
    func askedForStore(_ game: GameRecord) -> Bool {
        guard storeChoices(for: game).count > 1, GameSettings.canRunWithStore(game, paths: paths) else { return false }
        launch = nil
        problem = Problem(kind: .chooseStore(game.id))
        NSApp.activate()
        return true
    }

    /// The player's answer: this launch runs with `store`, and it is offered first next time.
    func choose(_ store: Store, for id: GameID) {
        problem = nil
        guard let game = game(id) else { return }
        run(game, with: store)
        if let updated = self.game(id) { play(updated, askingForStore: false) }
    }

    func update(_ id: GameID, _ change: (inout GameRecord) -> Void) {
        do {
            try GameLibrary.modify(paths.library) { library in
                guard var game = library[id] else { return }
                change(&game)
                library[id] = game
            }
            reload()
        } catch {
            notice = Notice(title: String(localized: "Couldn't save the change"), message: String(describing: error))
        }
    }

    /// With the program gone, the nearest folder that's still there: selecting a missing file did nothing at all.
    func showInFinder(_ game: GameRecord) {
        var url = URL(filePath: game.executable)
        while !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)), url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func latestLog(for game: GameRecord) -> URL? {
        let folder = paths.logs(forGame: game.id)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".log") }.max().map { folder.appending(path: $0) }
    }

    func openLog(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
