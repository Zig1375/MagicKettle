import Foundation

/// "Remove from Magic Kettle": forgets the game without touching the game itself or its saves.
public enum GameRemover {
    /// Deletes the game's entry, its bottle, its logs and its `.magickettle` file. The game folder and the shared
    /// profile (saves) stay; opening the exe again adds the game back as new.
    public static func removeFromApp(_ id: GameID, paths: AppPaths) throws {
        try GameLibrary.modify(paths.library) { library in
            guard let game = library[id] else { return }
            forget(game, paths: paths)
            library[id] = nil
        }
    }

    /// What "Delete from disk" moves to the Trash: the game's folder, or only its program when that folder is a
    /// shared one. r2modman opened from Downloads had Downloads as its folder, and deleting it from disk would have
    /// put the player's whole Downloads in the Trash; the same for a game on the Desktop or at the top of a disk.
    public static func trashTarget(for game: GameRecord, identifier: GameIdentifier) -> URL {
        let folder = URL(filePath: game.folder, directoryHint: .isDirectory)
        // A mod manager kept in a store game's folder: that folder is the game's, only the manager's exe is its own.
        let inStore = game.store == nil && identifier.storeBottle(containing: URL(filePath: game.executable)) != nil
        return identifier.isStopFolder(folder) || inStore ? URL(filePath: game.executable) : folder
    }

    private static func forget(_ game: GameRecord, paths: AppPaths) {
        let id = game.id
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: paths.bottle(forGame: id))
        try? fileManager.removeItem(at: paths.logs(forGame: id))
        if game.hasMarker {
            let marker = URL(filePath: game.folder, directoryHint: .isDirectory)
                .appending(path: GameIdentifier.markerName)
            // Only a .magickettle that still names this game: the folder may have been reused by another one.
            if let data = try? Data(contentsOf: marker),
               let found = try? JSONDecoder().decode(GameIdentifier.Marker.self, from: data), found.id == id {
                try? fileManager.removeItem(at: marker)
            }
        }
    }
}
