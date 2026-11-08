import Foundation

/// Puts Magic Kettle's stand-in for Windows PowerShell (`tools/powershell`) where Windows keeps PowerShell, in place
/// of Wine's stub, which runs nothing and prints nothing. r2modman asks PowerShell where Steam is
/// (`Get-ItemProperty -Path HKLM:\SOFTWARE\WOW6432Node\Valve\Steam -Name InstallPath`); with the stub it said
/// "Unable to resolve steam install folder" and couldn't start any modded game. The stand-in answers registry
/// questions like that one; Wine runs it because `powershell.exe` is native first (`WineEnvironment`).
///
/// Only Wine's stub or an older stand-in is ever replaced; the stand-in carries `marker`. A bottle update that
/// brings the stub back is undone by the next launch.
public enum PowerShell {
    /// Written into the stand-in; tells it from Wine's stub.
    static let marker = Data("magickettle-powershell/1".utf8)

    /// Where PowerShell is, relative to the bottle's `drive_c/windows`, and the stand-in built for it.
    static let places = [
        ("system32/WindowsPowerShell/v1.0/powershell.exe", "powershell-x64"),
        ("syswow64/WindowsPowerShell/v1.0/powershell.exe", "powershell-x86"),
    ]

    /// Puts the stand-in into `bottle` where its PowerShell folder exists. Returns the files it wrote.
    @discardableResult
    public static func install(in bottle: URL) throws -> [URL] {
        let windows = bottle.appending(path: "drive_c/windows", directoryHint: .isDirectory)
        var written: [URL] = []
        for (place, resource) in places {
            guard let standIn = Bundle.module.url(forResource: resource, withExtension: "exe")
                .flatMap({ try? Data(contentsOf: $0) }) else { continue }
            let target = windows.appending(path: place)
            if try install(standIn, at: target) { written.append(target) }
        }
        return written
    }

    /// Returns whether it changed anything.
    static func install(_ standIn: Data, at target: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: target.deletingLastPathComponent().path) else { return false }
        if FileManager.default.fileExists(atPath: target.path) {
            let current = try Data(contentsOf: target, options: .alwaysMapped)
            guard current != standIn else { return false }
            guard current.range(of: marker) != nil || RedistInstaller.isWineStandIn(target) else { return false }
        }
        try standIn.write(to: target, options: .atomic)
        return true
    }
}
