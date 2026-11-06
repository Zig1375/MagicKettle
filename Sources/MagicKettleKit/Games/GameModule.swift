import Foundation

/// What one game needs in Magic Kettle, as data, from the MagicKettle-Games repository (`docs/GAME-MODULES.md`): a fix
/// for a game reaches every player without an app release. Before We Leave from the Epic Games Store showed a black
/// window with DXVK, the automatic choice for Direct3D 11, and runs with DXMT; its module says so.
///
/// Only what this app applies is read: the `launch` action and the `cover`. Other actions and fields are skipped, and
/// values are kept as strings, so a module written for a newer app is applied in part instead of making the index
/// unreadable.
public struct GameModule: Codable, Sendable, Equatable {
    public var id: String
    public var revision: Int
    public var format: Int
    public var name: String
    public var match: Match?
    public var requires: Requires?
    /// Empty for a module that only gives a cover.
    public var fixes: [Group]
    public var cover: Cover?

    public init(id: String, revision: Int, format: Int, name: String, match: Match?, requires: Requires? = nil,
                fixes: [Group], cover: Cover? = nil) {
        self.id = id
        self.revision = revision
        self.format = format
        self.name = name
        self.match = match
        self.requires = requires
        self.fixes = fixes
        self.cover = cover
    }

    enum CodingKeys: String, CodingKey { case id, revision, format, name, match, requires, fixes, cover }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        revision = try container.decode(Int.self, forKey: .revision)
        format = try container.decode(Int.self, forKey: .format)
        name = try container.decode(String.self, forKey: .name)
        match = try container.decodeIfPresent(Match.self, forKey: .match)
        requires = try container.decodeIfPresent(Requires.self, forKey: .requires)
        fixes = try container.decodeIfPresent([Group].self, forKey: .fixes) ?? []
        // A cover this app can't read leaves the module's fixes working.
        cover = try? container.decodeIfPresent(Cover.self, forKey: .cover)
    }

    /// The picture for the game's card (`ModuleCovers`): `from` is its path under the repository's `files/`, pinned
    /// by the SHA-256 and size the index gives it.
    public struct Cover: Codable, Sendable, Equatable {
        public var from: String
        public var sha256: String
        public var size: Int
        /// Where the program's own icon, from the player's exe, goes over the picture.
        public var icon: IconPlace?

        public init(from: String, sha256: String, size: Int, icon: IconPlace? = nil) {
            self.from = from
            self.sha256 = sha256
            self.size = size
            self.icon = icon
        }
    }

    /// The icon's centre (`x`, `y` from the top left) and side (`size`), as fractions of the cover's width and
    /// height. Sonic Mania's mod manager has no license, so MagicKettle-Games can't carry its icon, but the player's
    /// own copy has it: the cover leaves room, and the app draws it there.
    public struct IconPlace: Codable, Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var size: Double

        public init(x: Double, y: Double, size: Double) {
            self.x = x
            self.y = y
            self.size = size
        }

        /// Inside the cover and not empty; anything else is not drawn.
        public var isUsable: Bool {
            (0...1).contains(x) && (0...1).contains(y) && size > 0 && size <= 1
        }
    }

    public struct Match: Codable, Sendable, Equatable {
        public var steam: [String]?
        public var gog: [String]?
        /// `namespace:item:app`, as `GameRecord.storeID` keeps an Epic game.
        public var epic: [String]?
        /// ProductNames, whatever the exe is called: r2modman's download carries its version in its file name.
        public var product: [String]?
        public var exe: [Exe]?

        public init(steam: [String]? = nil, gog: [String]? = nil, epic: [String]? = nil, product: [String]? = nil,
                    exe: [Exe]? = nil) {
            self.steam = steam
            self.gog = gog
            self.epic = epic
            self.product = product
            self.exe = exe
        }
    }

    public struct Exe: Codable, Sendable, Equatable {
        /// The file name, compared without case.
        public var name: String
        /// The ProductName from the exe's version info.
        public var product: String?
        public var sha256: [String]?

        public init(name: String, product: String? = nil, sha256: [String]? = nil) {
            self.name = name
            self.product = product
            self.sha256 = sha256
        }
    }

    public struct Requires: Codable, Sendable, Equatable {
        public var minApp: String?
        public var modules: [String]?
        public var wine: Range?
        public var features: [String]?

        public init(minApp: String? = nil, wine: Range? = nil) {
            self.minApp = minApp
            self.wine = wine
        }
    }

    /// Versions from `from` (included) to `below` (not included); either may be missing.
    public struct Range: Codable, Sendable, Equatable {
        public var from: String?
        public var below: String?

        public init(from: String? = nil, below: String? = nil) {
            self.from = from
            self.below = below
        }

        public func contains(_ version: Version) -> Bool {
            if let from = from.flatMap(Version.init), version < from { return false }
            if let below = below.flatMap(Version.init), version >= below { return false }
            return true
        }
    }

    /// Actions applied together when every condition in `when` holds.
    public struct Group: Codable, Sendable, Equatable {
        public var when: When?
        public var optional: Bool?
        public var launch: Launch?

        public init(when: When? = nil, launch: Launch? = nil) {
            self.when = when
            self.launch = launch
        }
    }

    public struct When: Codable, Sendable, Equatable {
        public var wine: Range?
        public var exeSha256: [String]?
        public var steamBuild: BuildRange?
        /// `steam`, `epic`, `gog`, … or `none` for a game without a store.
        public var store: [String]?
        public var backend: [String]?

        public init(wine: Range? = nil, store: [String]? = nil, backend: [String]? = nil) {
            self.wine = wine
            self.store = store
            self.backend = backend
        }
    }

    public struct BuildRange: Codable, Sendable, Equatable {
        public var from: Int?
        public var below: Int?
    }

    public struct Launch: Codable, Sendable, Equatable {
        /// The first attempt; the usual search goes on if the game doesn't start.
        public var prefer: Settings?
        /// Fixed, like a choice in Advanced.
        public var require: Settings?
        public var arguments: [String]?
        public var environment: [String: String]?

        public init(prefer: Settings? = nil, require: Settings? = nil) {
            self.prefer = prefer
            self.require = require
        }
    }

    public struct Settings: Codable, Sendable, Equatable {
        /// In order; `require` names one, `prefer` a list.
        public var backend: [String]?
        public var windows: String?
        public var retina: String?
        public var scaling: String?
        public var chromium: String?
        public var fastSync: Bool?

        enum CodingKeys: String, CodingKey { case backend, windows, retina, scaling, chromium, fastSync }

        public init(backend: [String]? = nil, windows: String? = nil) {
            self.backend = backend
            self.windows = windows
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let one = try? container.decode(String.self, forKey: .backend) {
                backend = [one]
            } else {
                backend = try container.decodeIfPresent([String].self, forKey: .backend)
            }
            windows = try container.decodeIfPresent(String.self, forKey: .windows)
            retina = try container.decodeIfPresent(String.self, forKey: .retina)
            scaling = try container.decodeIfPresent(String.self, forKey: .scaling)
            chromium = try container.decodeIfPresent(String.self, forKey: .chromium)
            fastSync = try container.decodeIfPresent(Bool.self, forKey: .fastSync)
        }
    }

    /// The format this app reads; a module in a newer one is skipped whole.
    public static let knownFormat = 1
}

/// `games.json`: every module, so the player's games are found on the Mac without asking for any one of them.
public struct GameModuleIndex: Codable, Sendable, Equatable {
    public var format: Int
    /// The newest module change in it; the newer of the app's copy and the downloaded one wins.
    public var generated: Date?
    public var commit: String?
    public var modules: [GameModule]
    public var shared: [GameModule]?

    enum CodingKeys: String, CodingKey { case format, generated, commit, modules, shared }

    public init(format: Int = GameModule.knownFormat, generated: Date? = nil, commit: String? = nil,
                modules: [GameModule], shared: [GameModule]? = nil) {
        self.format = format
        self.generated = generated
        self.commit = commit
        self.modules = modules
        self.shared = shared
    }

    /// A module that doesn't decode is left out, not the whole index: one broken entry mustn't cost every game
    /// its fixes.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(Int.self, forKey: .format)
        generated = try container.decodeIfPresent(Date.self, forKey: .generated)
        commit = try container.decodeIfPresent(String.self, forKey: .commit)
        modules = try container.decode([Lenient<GameModule>].self, forKey: .modules).compactMap(\.value)
        shared = try container.decodeIfPresent([Lenient<GameModule>].self, forKey: .shared)?.compactMap(\.value)
    }

    public static func decode(_ data: Data) throws -> GameModuleIndex {
        try JSONDecoder.iso.decode(GameModuleIndex.self, from: data)
    }

    public static func bundled() throws -> GameModuleIndex {
        guard let url = Bundle.module.url(forResource: "game-modules", withExtension: "json") else {
            throw ManifestError.missingBundledManifest
        }
        return try decode(Data(contentsOf: url))
    }
}

/// An element that decodes to nil instead of failing its array.
struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
