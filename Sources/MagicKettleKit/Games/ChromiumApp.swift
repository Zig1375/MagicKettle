import Foundation

/// Programs built on Chromium: NW.js games (RPG Maker MV and MZ ship as one), Electron apps and launchers, and
/// programs embedding CEF. In Wine on a Mac their window stays white or black: Chromium draws in a separate GPU
/// process, and what that process draws never reaches the window the Mac shows. With the GPU work inside the
/// browser process the picture appears and stays hardware-accelerated (WebGL games keep their speed); without
/// any GPU work is the fallback. Tested with NW.js 0.92 and Electron 33 on Wine 11.20.
///
/// Chromium also can't read the graphics driver's version under Wine, and older builds then put the GPU on their
/// blocklist and draw in software. RPG Maker MZ asks WebGL for real hardware only, so Celina's Calling (NW.js 0.48)
/// showed "Failed to initialize graphics" until the blocklist was switched off.
public enum ChromiumApp {
    public enum Mode: String, Codable, Sendable, Equatable {
        /// `--in-process-gpu`: the fix, with acceleration, and the GPU blocklist off (it is
        /// `--ignore-gpu-blacklist` up to Chromium 85 and `--ignore-gpu-blocklist` since; each ignores the other).
        case inProcessGPU
        /// Software drawing: for a program the first doesn't fix.
        case noGPU

        public var arguments: [String] {
            switch self {
            case .inProcessGPU: ["--in-process-gpu", "--ignore-gpu-blacklist", "--ignore-gpu-blocklist"]
            case .noGPU: ["--disable-gpu", "--disable-gpu-compositing", "--in-process-gpu"]
            }
        }

        /// What to try after this one; nil when nothing is left.
        public var next: Mode? { self == .inProcessGPU ? .noGPU : nil }

        /// The switches for the program in `folder`, with V8's flags (`jsFlags`) joined to any it sets itself.
        public func arguments(forProgramIn folder: URL) -> [String] {
            let package = try? Data(contentsOf: folder.appending(path: "package.json"))
            return arguments + ["--js-flags=" + ChromiumApp.jsFlags(packageJSON: package)]
        }
    }

    /// V8 flags every Chromium program gets.
    ///
    /// V8 (Chromium 106 and later) makes its own flags read-only once it has started and checks that the page
    /// was read-write before. Under Wine the page of a DLL's data doesn't report that, so the check fails and the
    /// program quits at once: "Inquisitor White Prison" (RPG Maker MZ, NW.js 0.69) showed no window, its log
    /// saying `Check failed: 0x04 == old_protection`. Older V8 doesn't know the flag and goes on without it.
    static let v8Flags = "--no-freeze-flags-after-init"

    /// The value for `--js-flags`: V8's flags an NW.js game sets in its `package.json` (`js-flags`, as RPG Maker MV
    /// writes `--expose-gc`, and any in `chromium-args`), then `v8Flags`. The command line's would otherwise replace
    /// the game's instead of adding to them.
    static func jsFlags(packageJSON: Data?) -> String {
        guard let data = packageJSON,
              let package = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return v8Flags }
        var flags = (package["js-flags"] as? String).map { [$0] } ?? []
        if let switches = package["chromium-args"] as? String,
           let match = switches.firstMatch(of: /--js-flags=(?:"([^"]*)"|'([^']*)'|(\S+))/) {
            flags.append(String(match.1 ?? match.2 ?? match.3 ?? ""))
        }
        return (flags + [v8Flags]).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Whether the program at `executable` is a Chromium browser itself, from its imports and the files next to
    /// it, or packed inside it (`packed`, `EnigmaVirtualBox`). Its helper processes and Chromium in another folder
    /// (a launcher's web pages) don't count: flags reach Chromium only on its main program's command line.
    public static func isChromium(executable: URL, imports: Set<String>, packed: Set<String> = []) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: executable.deletingLastPathComponent().path))
            ?? []
        return isChromium(imports: imports, filesBeside: Set(names.map { $0.lowercased() }).union(packed))
    }

    static func isChromium(imports: Set<String>, filesBeside files: Set<String>) -> Bool {
        // NW.js: nw.exe (an RPG Maker game's Game.exe) loads nw_elf.dll, with nw.dll beside it.
        if imports.contains("nw_elf.dll") || imports.contains("nw.dll") { return true }
        // CEF: the program links libcef.dll itself.
        if imports.contains("libcef.dll") { return true }
        // Electron and other Chromium builds: Chromium's data files beside the program.
        let hasPak = files.contains { $0.hasSuffix(".pak") }
        let hasEngine = files.contains("libegl.dll") || files.contains("v8_context_snapshot.bin")
        return files.contains("icudtl.dat") && hasPak && hasEngine
    }

    /// The way a Chromium program starts before any launch found one for it.
    ///
    /// A single-file Electron program (electron-builder's "portable") draws without the GPU from the start. It is
    /// a tool, not a game: r2modman drew its own title bar as a see-through strip with the GPU in-process, a
    /// problem no blank-window check sees, and nothing in it needs the speed.
    public static func firstMode(for info: ExecutableInfo) -> Mode? {
        info.electronPortable ? .noGPU : info.chromium ? .inProcessGPU : nil
    }

    /// The way a launch draws: what an earlier one found, except that a single-file Electron program always draws
    /// without the GPU. r2modman had kept the in-process GPU from before Magic Kettle knew it, and its title bar
    /// stayed see-through.
    public static func mode(remembered: Mode?, info: ExecutableInfo) -> Mode? {
        info.electronPortable ? .noGPU : remembered ?? firstMode(for: info)
    }

    /// Where a single-file Electron program runs once unpacked, as Windows sees it: the user's temporary folder
    /// (`%TEMP%\<id>\r2modman.exe`). Its window belongs to that process, not to the exe that was opened.
    public static func portableFolder(user: String = NSUserName()) -> String {
        #"C:\users\"# + user + #"\AppData\Local\Temp"#
    }

    /// Whether `data`, the start of an NSIS exe, is electron-builder's single-file build of an Electron program:
    /// it unpacks the program to a temporary folder and runs it, setting `PORTABLE_EXECUTABLE_DIR` for it. Its
    /// script keeps that name in UTF-16, within its first megabyte (360 KB into r2modman 3.2.21).
    static func isElectronPortable(_ data: Data) -> Bool {
        data.range(of: portableMarker) != nil
    }

    private static let portableMarker = Data("PORTABLE_EXECUTABLE_DIR".utf16.flatMap { [UInt8($0 & 0xFF), 0] })

    /// A Chromium GPU process running in the bottle: the program is Chromium even if its files didn't say so (a
    /// launcher that unpacks it at start, say).
    public static func runsGPUProcess(in bottle: URL) -> Bool {
        WineProcesses.running(in: bottle).contains { $0.arguments.contains("--type=gpu-process") }
    }
}
