import Foundation

extension GameLauncher {
    struct EnvironmentOptions {
        var bottle: URL
        var backend: GraphicsBackend
        var fastSync: Bool
        var verboseLog: Bool
        var prepare: Bool
    }

    /// Build the host environment before starting WebView2 preparation, using the same synchronization mode
    /// as the game and its store. Compatibility changes must happen after all offline registry preparation.
    func launchEnvironment(for game: GameRecord, files: GameFiles, runtime: RuntimeManifest.Runtime, wine: Wine,
                           options: EnvironmentOptions) async throws -> [String: String] {
        let extra = WebView2.environment(used: files.webView2, runtime: runtime)
            .merging(game.bottleStore?.environment ?? [:]) { _, store in store }
            .merging(GameSettings.environment(of: game)) { _, user in user }
        let environment = WineEnvironment.make(host: host, bottle: options.bottle.path, extra: extra,
                                               verboseLog: options.verboseLog || game.verboseLog == true,
                                               fastSync: options.fastSync, locale: files.locale,
                                               backend: options.backend)
        if files.webView2, runtime.wineHas(WebView2.surfaceFeature), options.prepare {
            try await WebView2.prepare(in: options.bottle, wine: wine, environment: environment)
        }
        return environment
    }
}
