import Foundation

/// A game's Advanced settings (Advanced.dc.html), and what "Auto" would do for it, so the screen can say why.
/// Usually nothing here needs changing: every setting starts at Auto or off.
public enum GameSettings {
    /// Retina: games that declare high-DPI support draw for it; others would get a tiny interface.
    public static func retina(_ setting: GameScaling.Setting?, dpiAware: Bool) -> Bool {
        switch setting ?? .auto {
        case .auto: dpiAware
        case .on: true
        case .off: false
        }
    }

    /// The variables the game starts with on top of Magic Kettle's own: the frame counter's, then the player's.
    public static func environment(of game: GameRecord) -> [String: String] {
        var result: [String: String] = [:]
        // Metal's own HUD: frame rate and frame time over anything drawn with Metal (DXVK, DXMT, WineD3D).
        if game.fpsCounter == true { result["MTL_HUD_ENABLED"] = "1" }
        result.merge(parseEnvironment(game.environment ?? "")) { _, player in player }
        return result
    }

    /// One `NAME=value` per line; blank lines and `#` comments are skipped, as the field's placeholder shows.
    public static func parseEnvironment(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { continue }
            let name = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains(" ") else { continue }
            result[name] = String(trimmed[trimmed.index(after: equals)...])
        }
        return result
    }

    /// Launch parameters as the game gets them: split at spaces, with quotes keeping a value with spaces whole
    /// (`-mod "My Mod"`).
    public static func arguments(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        var started = false
        for character in text {
            if character == "\"" {
                quoted.toggle()
                started = true
            } else if character.isWhitespace, !quoted {
                if started { result.append(current) }
                current = ""
                started = false
            } else {
                current.append(character)
                started = true
            }
        }
        if started { result.append(current) }
        return result
    }

    // MARK: - What Auto does

    /// Why Auto picks the backend it does.
    public enum BackendReason: Sendable, Equatable {
        /// It worked for this game last time.
        case workedBefore
        case directDraw, directX9, directX11, directX12
        /// The game imports no DirectX: it draws with GDI or OpenGL.
        case noDirectX
    }

    /// The backend Auto starts with, and why; nil when the game can't run at all.
    public static func autoBackend(for game: GameRecord, info: ExecutableInfo) -> (GraphicsBackend, BackendReason)? {
        guard case let .attempts(plan) = BackendPlan.forTraits(info.traits), let first = plan.first else { return nil }
        if let worked = game.backend { return (worked, .workedBefore) }
        let reason: BackendReason = switch info.directX.max() {
        case .legacy?: .directDraw
        case .d3d9?: .directX9
        case .d3d11?: .directX11
        case .d3d12?: .directX12
        case nil: .noDirectX
        }
        return (first, reason)
    }

    /// What Auto scaling does for the game now.
    public enum ScalingStatus: Sendable, Equatable {
        /// The game hasn't been seen yet: its window's size decides.
        case notSeenYet
        /// Full screen: Wine fits it to the screen without touching the Mac's display.
        case fullScreen
        case enlarged(width: Int, height: Int, scale: Double)
        /// The window is already large enough.
        case largeEnough(width: Int, height: Int)
        /// It draws for Retina itself.
        case drawsForRetina
    }

    public static func autoScaling(for game: GameRecord, retina: Bool,
                                   screen: GameScaling.Size = GameScaling.availableScreen()) -> ScalingStatus {
        if retina { return .drawsForRetina }
        guard let window = game.window else { return .notSeenYet }
        if window.fullScreen { return .fullScreen }
        let scale = GameScaling.scale(setting: .auto, learned: window, dpiAware: false, screen: screen)
        return scale > 1 ? .enlarged(width: window.width, height: window.height, scale: scale)
            : .largeEnough(width: window.width, height: window.height)
    }

    /// A reset makes the bottle again from the template. Not for a game installed inside its own Windows
    /// (`C:\Program Files\…`): the reset would delete the game itself.
    public static func canReset(_ game: GameRecord, paths: AppPaths) -> Bool {
        let bottle = paths.bottle(forGame: game.id).standardized.path(percentEncoded: false)
        return !URL(filePath: game.executable).standardized.path(percentEncoded: false).hasPrefix(bottle)
    }

    /// Whether the player can have a program run with a store's games (`GameRecord.runsWith`): only their own
    /// programs, not a store's game, and not one installed inside its own Windows, whose files and settings would
    /// stay behind there. Nor one inside a store's Windows (ManiaModManager in Sonic Mania's folder): it can only
    /// run with that store.
    public static func canRunWithStore(_ game: GameRecord, paths: AppPaths) -> Bool {
        game.store == nil && canReset(game, paths: paths) && !isInStoreBottle(game, paths: paths)
    }

    static func isInStoreBottle(_ game: GameRecord, paths: AppPaths) -> Bool {
        let exe = URL(filePath: game.executable).standardized.path(percentEncoded: false).lowercased()
        return Store.allCases.contains { store in
            let bottle = paths.bottle(forGame: store.bottleID).standardized.path(percentEncoded: false).lowercased()
            return exe.hasPrefix(bottle.hasSuffix("/") ? bottle : bottle + "/")
        }
    }
}

extension GameRecord {
    var hasRendererArguments: Bool {
        GameSettings.arguments(arguments ?? "").contains { argument in
            ["--rendering-driver", "--rendering-method"].contains {
                argument == $0 || argument.hasPrefix($0 + "=")
            }
        }
    }

    var launchArguments: [String] {
        let entered = GameSettings.arguments(arguments ?? "")
        guard godotOpenGL == true, store == nil, !hasRendererArguments else { return entered }
        return ["--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3"] + entered
    }
}
