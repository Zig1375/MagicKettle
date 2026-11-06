import Foundation

/// Mod managers: programs that install mods into a store's games and start them through the store. Such a program
/// has to run beside the games (`GameRecord.runsWith`): r2modman in a bottle of its own found none of the
/// player's Steam games. Known by the product name in their exe, so opening one is all the player does.
public enum ModManagers {
    /// Product names as `normalized` makes them. HedgeModManager 7's exe says "Hedge Mod Manager", the Nexus Mods
    /// app "NexusMods.App": compared letter for letter, the first wasn't known and ran in a bottle of its own.
    /// HedgeModManager 8 is a single-file .NET program whose exe carries the name of its main assembly,
    /// "HedgeModManager.UI".
    ///
    /// Each with the stores whose games it works with, of those Magic Kettle has, as each project's source says:
    /// r2modman's and Thunderstore's `StorePlatform`, Gale's `Platform`, HedgeModManager's list of games, Vortex's
    /// `EpicGamesLauncher`, the Nexus Mods app's `EpicGameStore`. It is what the program can do, not a list of games,
    /// so a game a manager learns needs no change here. A manager with one of them never asks which store to use.
    /// SA Mod Manager is for Sonic Adventure DX and 2, both only in Steam; Sonic Mania's ManiaModManager knows its
    /// Steam and its Epic copy (`Platform.cs`).
    static let managers: [String: Set<Store>] = [
        "r2modman": [.steam, .epic], "thunderstoremodmanager": [.steam, .epic], "gale": [.steam, .epic],
        "hedgemodmanager": [.steam, .epic], "hedgemodmanagerui": [.steam, .epic], "vortex": [.steam, .epic],
        "nexusmodsapp": [.steam, .epic], "samodmanager": [.steam], "maniamodmanager": [.steam, .epic],
    ]

    /// Whether the exe is a mod manager, by its ProductName or, without one, its file name.
    public static func isModManager(productName: String?, exeName: String) -> Bool {
        known(productName: productName, exeName: exeName) != nil
    }

    /// The stores the mod manager works with; empty for any other program.
    public static func stores(productName: String?, exeName: String) -> Set<Store> {
        known(productName: productName, exeName: exeName).flatMap { managers[$0] } ?? []
    }

    /// The manager's key in `managers`, if the exe is one.
    static func known(productName: String?, exeName: String) -> String? {
        if let product = productName.map(normalized), !product.isEmpty {
            return managers[product] != nil ? product : nil
        }
        // Downloads add a version or "Setup" after a dash: "r2modman-Setup-3.2.21.exe", "NexusMods.App-0.9.exe".
        let base = (exeName as NSString).deletingPathExtension
        let name = base.split(separator: "-", maxSplits: 1).first.map(String.init) ?? base
        return [normalized(base), normalized(name)].first { managers[$0] != nil }
    }

    /// Lowercased letters and digits only, so spaces, dots and dashes in a product name don't matter.
    static func normalized(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// The store a new mod manager runs with at first: the first installed one, in the app's order (Steam first,
    /// where most modded games are). Nil when no store is installed: it then runs on its own. With several stores,
    /// each launch asks which one (`GameRecord.storeChoices`), and this is only the first answer offered.
    public static func store(installed: Set<Store>) -> Store? {
        Store.allCases.first { installed.contains($0) }
    }
}
