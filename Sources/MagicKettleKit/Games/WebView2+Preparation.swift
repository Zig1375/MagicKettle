import Foundation

extension WebView2 {
    static let surfaceFeature = "cross-process-gdi"
    static let browserArguments = "--disable-gpu --disable-direct-composition "
        + "--disable-features=RemoveRedirectionBitmap"
    static let browserKey = #"HKCU\Software\Wine\AppDefaults\msedgewebview2.exe"#

    /// Only WebView2 hosts need the shared GDI path; ordinary games retain their existing presentation.
    /// User launch settings are merged afterwards, so a player can override these defaults.
    static func environment(used: Bool, runtime: RuntimeManifest.Runtime) -> [String: String] {
        guard used, runtime.wineHas(surfaceFeature) else { return [:] }
        return ["WINE_CROSS_PROCESS_GDI": "1", "WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS": browserArguments]
    }

    private struct Settings: Codable {
        var key: String
        var previousVersion: String?
        var appliedVersion: String
    }

    /// WebView2 157 selects unavailable DirectComposition on Wine's Windows 10 path. Only its browser process
    /// uses Windows 7 compatibility; Gale and the store keep their own Windows version. Use live registry calls:
    /// a mod manager can share a running store's wineserver, which would overwrite edits to user.reg.
    static func prepare(in bottle: URL, wine: Wine, environment: [String: String]) async throws {
        let query = try await ProcessRunner.run(wine.wine.path, ["reg", "query", browserKey, "/v", "Version"],
                                                environment: environment, timeout: 30)
        guard query.status == 0 || query.status == 1 else {
            throw ProcessRunner.Failure(tool: "reg query", status: query.status, output: query.output)
        }
        let previous = query.output.components(separatedBy: "REG_SZ").dropFirst().first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if previous == "win7" { return }
        let marker = bottle.appending(path: "WEBVIEW2.json")
        // Record before mutation, including the original value, even if the app exits during reg add.
        if !FileManager.default.fileExists(atPath: marker.path) {
            let settings = Settings(key: browserKey, previousVersion: previous, appliedVersion: "win7")
            try JSONEncoder().encode(settings).write(to: marker, options: .atomic)
        }
        let result = try await ProcessRunner.run(wine.wine.path,
            ["reg", "add", browserKey, "/v", "Version", "/t", "REG_SZ", "/d", "win7", "/f"],
            environment: environment, timeout: 30)
        guard result.status == 0 else {
            throw ProcessRunner.Failure(tool: "reg add", status: result.status, output: result.output)
        }
    }
}
