import Foundation

extension GameLauncher {
    /// How many times larger Wine will draw the game on this launch, and the system DPI that does it
    /// (`GameScaling`): what `configure` writes into the bottle, and what a client that keeps the bottle is
    /// measured against (`StoreClient.prepareForGame`).
    /// - Parameter predicted: the game's window known before it ever ran (`GameFiles.window`); what was seen on a
    ///   launch wins over it.
    static func drawing(for game: GameRecord, retina: Bool, predicted: GameScaling.LearnedWindow? = nil,
                        screen: GameScaling.Size = GameScaling.availableScreen()) -> (scale: Double, dpi: Int) {
        // Mod managers are resizable tools, not fixed-size old games. Gale's earlier error dialog was learned
        // as a small game window, which enlarged its entire desktop and cursor to 214 DPI on the next launch.
        let program = game.isProgram || game.storeChoices != nil
            || ModManagers.isModManager(productName: game.name,
                                        exeName: URL(filePath: game.executable).lastPathComponent)
        let setting: GameScaling.Setting = program && (game.scaling ?? .auto) == .auto ? .off : game.scaling ?? .auto
        let scale = GameScaling.scale(setting: setting, learned: game.window ?? predicted,
                                      dpiAware: retina, screen: screen)
        return (scale, GameScaling.dpi(for: scale))
    }

    /// The folder, as Windows sees it, whose processes are the game when it shares a store's bottle: the client
    /// keeps the bottle busy, so the game is over when they are. Nil for a game in a bottle of its own. A
    /// single-file Electron program runs from where it unpacked itself (`ChromiumApp.portableFolder`).
    static func watchedFolder(of game: GameRecord, info: ExecutableInfo, bottle: URL) -> String? {
        guard game.bottleStore != nil else { return nil }
        return info.electronPortable ? ChromiumApp.portableFolder()
            : WindowsPath.windowsPath(of: URL(filePath: game.folder, directoryHint: .isDirectory), inBottle: bottle)
    }

    /// What every launch puts into the bottle besides the game's settings: the backend's own files
    /// (`BackendTree`) and the PowerShell stand-in (`PowerShell`).
    static func prepareBottle(_ bottle: URL, for backend: GraphicsBackend, wine: Wine) throws {
        try BackendTree.prepareBottle(bottle, for: backend, wine: wine)
        try PowerShell.install(in: bottle)
    }

    /// A program that runs with a store starts the store's client after the bottle's registry is written, so the
    /// store runs with those settings and takes the program's requests.
    func startStoreProgram(for game: GameRecord, wine: Wine) async throws {
        guard let store = game.runsWith else { return }
        _ = try await StoreClient(paths: paths, host: host).startInBackground(store, wine: wine, prepared: true)
    }
}
