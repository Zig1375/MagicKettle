import Foundation

extension RedistInstaller {
    /// EdgeUpdate can wait for its service indefinitely and removes Offline on exit. Preserve the extracted
    /// payload while it is still running, before the bootstrapper timeout, then install that verified payload.
    static func installWebView2(
        setup: URL, redist: RuntimeManifest.Redist, bottle: URL, wine: Wine, environment: [String: String]
    ) async throws -> ProcessRunner.Output {
        let saved = setup.deletingLastPathComponent().appending(path: "magickettle-webview2-offline.exe")
        try? FileManager.default.removeItem(at: saved)
        defer { try? FileManager.default.removeItem(at: saved) }
        async let bootstrap = ProcessRunner.run(wine.wine.path, [setup.path] + redist.arguments,
                                                environment: environment, timeout: 60)
        let deadline = Date().addingTimeInterval(50)
        var preserved = false
        while Date() < deadline, !isInstalled(redist, in: bottle) {
            if let payload = webView2Payload(in: bottle, version: redist.version) {
                try FileManager.default.copyItem(at: payload, to: saved)
                preserved = true
                break
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        let result = try await bootstrap
        guard preserved, !isInstalled(redist, in: bottle) else { return result }
        return try await ProcessRunner.run(wine.wine.path,
            [saved.path, "--msedgewebview", "--system-level"], environment: environment, timeout: 120)
    }

    /// Only the offline payload extracted by Microsoft's verified download, never a search of user folders.
    static func webView2Payload(in bottle: URL, version: String) -> URL? {
        let root = bottle.appending(path: "drive_c/Program Files (x86)/Microsoft/EdgeUpdate/Offline")
        guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                            options: [.skipsHiddenFiles]) else { return nil }
        for case let file as URL in entries {
            let name = file.lastPathComponent.lowercased()
            guard name == "microsoftedge_x64_\(version.lowercased()).exe",
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            return file
        }
        return nil
    }
}
