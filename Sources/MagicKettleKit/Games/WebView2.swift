import Foundation

/// Programs whose window is a web page drawn by Microsoft's WebView2 (Edge's Chromium), which Windows 10 and 11
/// ship and Wine doesn't: Tauri apps such as the Gale mod manager, and many launchers. Without it Gale only said
/// "Could not find the WebView2 Runtime", so Magic Kettle installs Microsoft's runtime like a game's Visual C++
/// (`RedistNeeds`, kind `webview2`). Build 16 also needs shared GDI drawing and browser-only compatibility
/// settings (`WebView2.prepare`); host command-line switches alone cannot configure its browser process.
public enum WebView2 {
    /// The DLL WebView2's loader looks for in the runtime. Programs link the loader in (Tauri's `webview2-com`
    /// does, 16 MB into gale.exe) or carry it as `WebView2Loader.dll`; either way this name is in it as UTF-16.
    static let loaderMarker = Data("EmbeddedBrowserWebView".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
    static let loaderDLL = "webview2loader.dll"

    /// Whether the program at `executable` uses WebView2: it imports or carries the loader, or has it linked in.
    public static func isUsed(by executable: URL, imports: Set<String>, filesBeside files: Set<String>) -> Bool {
        if imports.contains(loaderDLL) || files.contains(loaderDLL) { return true }
        guard let data = try? Data(contentsOf: executable, options: .alwaysMapped) else { return false }
        return containsLoader(data)
    }

    static func containsLoader(_ data: Data) -> Bool {
        data.range(of: loaderMarker) != nil
    }
}
