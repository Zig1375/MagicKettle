import Foundation
@testable import MagicKettleKit
import Testing

@Suite struct WebView2PreparationTests {
    @Test func workaroundRequiresBothAWebViewHostAndCapableWine() throws {
        let manifest = try RuntimeManifest.bundled()
        var runtime = try #require(manifest.runtimes.last)
        #expect(runtime.wineHas(WebView2.surfaceFeature))
        let extra = WebView2.environment(used: true, runtime: runtime)
        #expect(extra["WINE_CROSS_PROCESS_GDI"] == "1")
        #expect(extra["WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS"] == WebView2.browserArguments)
        #expect(!WebView2.browserArguments.contains("logging"))
        #expect(WebView2.environment(used: false, runtime: runtime).isEmpty)
        runtime.components = runtime.components.map { component in
            var component = component
            component.features = (component.features ?? []).filter { $0 != WebView2.surfaceFeature }
            return component
        }
        #expect(WebView2.environment(used: true, runtime: runtime).isEmpty)
        let environment = WineEnvironment.make(host: [:], bottle: "/test",
            extra: extra.merging(["WINE_CROSS_PROCESS_GDI": "0"]) { _, user in user })
        #expect(environment["WINE_CROSS_PROCESS_GDI"] == "0")
    }

    @Test func installerPayloadIsConfinedToEdgeUpdatesOfflineFolder() throws {
        let temp = try TempFolder()
        let outside = temp.url.appending(path: "drive_c/MicrosoftEdge_X64_157.exe")
        try FileManager.default.createDirectory(at: outside.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data().write(to: outside)
        #expect(RedistInstaller.webView2Payload(in: temp.url, version: "157") == nil)
        let payload = temp.url.appending(path:
            "drive_c/Program Files (x86)/Microsoft/EdgeUpdate/Offline/a/b/MicrosoftEdge_X64_157.exe")
        try FileManager.default.createDirectory(at: payload.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data().write(to: payload)
        let found = try #require(RedistInstaller.webView2Payload(in: temp.url, version: "157"))
        #expect(found.resolvingSymlinksInPath().path == payload.resolvingSymlinksInPath().path)
        #expect(RedistInstaller.webView2Payload(in: temp.url, version: "156") == nil)
    }
}
