import Foundation

extension RedistNeeds {
    /// How deep and how widely `helperFrameworks` looks: Vortex's FOMOD installer is six folders down, in
    /// `resources/app.asar.unpacked/node_modules/@nexusmods/fomod-installer-ipc/dist`, among about 1,100 files.
    static let helperDepth = 7
    static let helperEntryLimit = 5000

    /// The frameworks each `.NET` helper below `folder` asks for, by the helper's bitness. A helper is a
    /// `<name>.runtimeconfig.json` beside its own `<name>.exe`. Vortex runs its FOMOD installer on .NET 9's
    /// desktop runtime: in Steam's Windows it had none and stopped with "Vortex requires .NET Desktop Runtime 9".
    static func helperFrameworks(under folder: URL, excluding config: URL) -> [String: [String]] {
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles]) else { return [:] }
        let depth = folder.standardizedFileURL.pathComponents.count
        let excluded = config.standardizedFileURL.path
        var found: [String: [String]] = [:]
        var seen = 0
        for case let item as URL in items {
            seen += 1
            if seen > helperEntryLimit { break }
            if item.standardizedFileURL.pathComponents.count - depth >= helperDepth { items.skipDescendants() }
            let name = item.lastPathComponent
            guard name.lowercased().hasSuffix(".runtimeconfig.json"), item.standardizedFileURL.path != excluded
            else { continue }
            let base = String(name.dropLast(".runtimeconfig.json".count))
            let exe = item.deletingLastPathComponent().appending(path: base + ".exe")
            guard let info = try? ExecutableInfo.read(exe), let bitness = architecture(of: info.format),
                  let data = try? Data(contentsOf: item) else { continue }
            let beside = Set(((try? FileManager.default.contentsOfDirectory(atPath: exe.deletingLastPathComponent()
                .path)) ?? []).map { $0.lowercased() })
            for framework in frameworks(inRuntimeConfig: data, files: beside)
            where !(found[bitness]?.contains(framework) ?? false) {
                found[bitness, default: []].append(framework)
            }
        }
        return found
    }
}
