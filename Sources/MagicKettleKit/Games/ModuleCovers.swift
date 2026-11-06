import CryptoKit
import Foundation

/// A cover from the game modules (`GameModule.cover`) for a program that has no store cover. Mod managers are
/// known for sure (`ModManagers`), but r2modman's or HedgeModManager's card showed only the small icon from their
/// exe. MagicKettle-Games keeps a cover made from each one's own logo, and the module that knows the program names it.
///
/// The picture is fetched once, from the commit the index was built from, and kept in `Artwork/module-<sha256>.<ext>`
/// only when its SHA-256, its size and its first bytes (PNG or JPEG) are what the index says: it is shown, never run.
/// Fetching it tells GitHub which program it is for, as a store's cover does.
public enum ModuleCovers {
    static let prefix = "module-"
    /// The same limit as MagicKettle-Games' `tools/check.py`.
    static let maxSize = 1024 * 1024
    static let repository = "Zig1375/MagicKettle-Games"

    /// The kept picture for `cover`, or where it goes.
    static func file(for cover: GameModule.Cover, paths: AppPaths) -> URL {
        let ext = (cover.from as NSString).pathExtension.lowercased()
        return paths.artwork.appending(path: "\(prefix)\(cover.sha256.lowercased()).\(ext.isEmpty ? "img" : ext)")
    }

    /// Where the picture is fetched from: `raw.githubusercontent.com`, at the index's commit so the file can't
    /// change under its SHA-256; `main` for an index built outside git.
    static func url(for cover: GameModule.Cover, commit: String?) -> URL? {
        guard isSafePath(cover.from) else { return nil }
        let reference = commit.flatMap { $0.isEmpty ? nil : $0 } ?? "main"
        return URL(string: "https://raw.githubusercontent.com/\(repository)/\(reference)/files/\(cover.from)")
    }

    /// `<module>/<file>.png|jpg` under `files/`, nothing above it.
    static func isSafePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        let ext = (path as NSString).pathExtension.lowercased()
        return parts.count >= 2 && !parts.contains { $0.isEmpty || $0 == "." || $0 == ".." }
            && ["png", "jpg"].contains(ext) && !path.contains("\\") && !path.contains("?") && !path.contains("#")
    }

    /// Whether `data` is the picture the index pins.
    static func isPinned(_ data: Data, by cover: GameModule.Cover) -> Bool {
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count == cover.size, data.count <= maxSize,
              data.starts(with: png) || data.starts(with: [0xFF, 0xD8, 0xFF]) else { return false }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest == cover.sha256.lowercased()
    }

    /// A module's cover on the Mac: the picture, and where the program's icon goes over it.
    public struct Found: Sendable, Equatable {
        public var file: URL
        public var icon: GameModule.IconPlace?
    }

    /// The module cover for `record`: the kept one, or fetched and checked. Nil when no module gives one.
    public static func cover(for record: GameRecord, productName: String?, index: GameModuleIndex, paths: AppPaths,
                             fetch: (URL) async -> Data? = ModuleCovers.fetch) async -> Found? {
        let game = GameModules.Game(record, productName: productName)
        guard let module = GameModules.find(for: game, in: index.modules, app: GameModules.appVersion),
              let cover = module.cover else { return nil }
        let found = Found(file: file(for: cover, paths: paths), icon: cover.icon.flatMap { $0.isUsable ? $0 : nil })
        if FileManager.default.fileExists(atPath: found.file.path) { return found }
        guard let url = url(for: cover, commit: index.commit), let data = await fetch(url),
              isPinned(data, by: cover) else { return nil }
        try? FileManager.default.createDirectory(at: paths.artwork, withIntermediateDirectories: true)
        guard (try? data.write(to: found.file, options: .atomic)) != nil else { return nil }
        return found
    }

    public static func fetch(_ url: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// Removes the kept covers no module of `index` names any more.
    public static func prune(keeping index: GameModuleIndex, paths: AppPaths) {
        let kept = Set(index.modules.compactMap { $0.cover.map { file(for: $0, paths: paths).lastPathComponent } })
        let files = (try? FileManager.default.contentsOfDirectory(at: paths.artwork, includingPropertiesForKeys: nil))
            ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) && !kept.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
