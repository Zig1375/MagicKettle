import Foundation

/// Mod managers: programs that install mods into a store's games and start them through the store. Such a program
/// has to run beside the games (`GameRecord.runsWith`): r2modman in a bottle of its own found none of the
/// player's Steam games. Known by the product name in their exe, so opening one is all the player does.
public enum ModManagers {
    /// Product names, lowercased, as each manager's exe gives it.
    static let productNames: Set<String> = [
        "r2modman", "thunderstore mod manager", "gale", "hedgemodmanager", "hedge mod manager", "vortex",
        "nexusmods.app", "nexus mods app",
    ]

    /// Whether the exe is a mod manager, by its ProductName or its file name.
    public static func isModManager(productName: String?, exeName: String) -> Bool {
        if let product = productName?.trimmingCharacters(in: .whitespaces).lowercased(), !product.isEmpty,
           productNames.contains(product) {
            return true
        }
        let base = (exeName as NSString).deletingPathExtension.lowercased()
        return productNames.contains { base == $0 || base.hasPrefix($0 + "-") }
    }

    /// The store the program at `exe` runs with when it is a mod manager; nil for anything else.
    public static func store(for exe: URL, paths: AppPaths) -> Store? {
        guard isModManager(productName: (try? ExecutableInfo.read(exe))?.productName, exeName: exe.lastPathComponent)
        else { return nil }
        let client = StoreClient(paths: paths)
        return store(installed: Set(Store.allCases.filter(client.isInstalled)))
    }

    /// The store a mod manager runs with: the first installed one, in the app's order (Steam first, where most
    /// modded games are). Nil when no store is installed: it then runs on its own.
    public static func store(installed: Set<Store>) -> Store? {
        Store.allCases.first { installed.contains($0) }
    }
}
