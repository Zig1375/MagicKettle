import Foundation

/// A program its installer started on its last page ("Run Vortex", ticked by default or by the player). It runs in
/// the installer's Windows before Magic Kettle knows it: Vortex came up as a white window, without what Magic
/// Kettle gives an Electron program, and the install never finished, since that waits for the bottle to go quiet.
/// Once only such programs are left, they are closed; Magic Kettle starts the program itself afterwards.
extension GameInstaller {
    /// What still runs in the bottle once the installer's own process has exited.
    enum Leftovers: Equatable {
        /// Nothing but Wine's own services: the install is done.
        case none
        /// The installer's work goes on in other processes (Inno's `setup.tmp`, msiexec, a runtime's setup).
        case installing
        /// Only programs the installer started for the player.
        case launched
    }

    /// Sorts the bottle's processes by their Windows programs. Wine's own don't count: those in `C:\windows\`, and
    /// `wineserver` and the loaders, whose command line is a Mac path. Counting `wineserver` kept the Nexus Mods
    /// app's install waiting with the app open. Anything in a temporary folder, or named like a setup, an
    /// uninstaller or a runtime package, is still installing. Unknown helpers are also left running;
    /// only recognized mod managers may be closed automatically.
    static func leftovers(_ programs: [String], bottle: URL? = nil) -> Leftovers {
        let normalized = programs.map { program in
            if let bottle, program.hasPrefix("/"), program.lowercased().hasSuffix(".exe") {
                return WindowsPath.windowsPath(of: URL(filePath: program), inBottle: bottle)
            }
            return program
        }
        let own = normalized.map { $0.replacingOccurrences(of: "/", with: "\\").lowercased() }
            .filter {
                $0.wholeMatch(of: /[a-z]:\\.+/) != nil
                    && (!$0.hasPrefix(#"c:\windows\"#) || $0.hasSuffix(#"\msiexec.exe"#))
            }
        guard !own.isEmpty else { return .none }
        let installing = own.contains { program in
            let name = program.split(separator: "\\").last.map(String.init) ?? program
            return program.contains(#"\temp\"#) || program.contains(#"\tmp\"#)
                || ["setup", "install", "unins", "redist", "au_.exe", "msiexec", "dxsetup"]
                    .contains { name.contains($0) }
                || !ModManagers.isModManager(productName: nil, exeName: name)
        }
        return installing ? .installing : .launched
    }

    /// Waits for the installer's work to end, closing what it started for the player. `wineserver -w` alone
    /// waited for the player to close that program.
    static func waitForInstall(_ wine: Wine, bottle: URL, environment: [String: String]) async {
        var launchedSince: Date?
        while !Task.isCancelled {
            switch leftovers(WineProcesses.running(in: bottle).map(\.program), bottle: bottle) {
            case .none:
                _ = try? await ProcessRunner.run(wine.wineserver.path, ["-w"], environment: environment)
                return
            case .installing:
                launchedSince = nil
            case .launched:
                // A moment's grace: an installer may still be starting its next step.
                let since = launchedSince ?? Date()
                launchedSince = since
                if Date().timeIntervalSince(since) >= 3 {
                    _ = try? await ProcessRunner.run(wine.wineserver.path, ["-k"], environment: environment)
                    _ = try? await ProcessRunner.run(wine.wineserver.path, ["-w"], environment: environment)
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}
