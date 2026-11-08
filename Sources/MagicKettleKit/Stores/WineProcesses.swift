import Darwin
import Foundation

/// Wine's processes as macOS sees them. Wine puts the Windows program's path in each process's first argument
/// (`C:\Program Files (x86)\Steam\steam.exe`), and the bottle in its `WINEPREFIX`, so a store game can be told
/// from its store's client in the same bottle.
public enum WineProcesses {
    public struct Process: Sendable, Equatable {
        public var pid: pid_t
        /// The Mac executable: Wine's loader, inside the Wine tree that runs it.
        public var executable: String
        /// The Windows program.
        public var program: String
        /// Started with osync on (`WineEnvironment`).
        public var fastSync = false
        /// The Windows program's arguments.
        public var arguments: [String] = []
        /// When macOS started the process.
        public var started: Date?
    }

    /// Every process running in `bottle`.
    public static func running(in bottle: URL) -> [Process] {
        let prefix = bottle.path(percentEncoded: false)
        let trimmed = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        return allPIDs().compactMap { pid in
            let process = GameWindows.procArguments(of: pid)
            guard let wanted = process.environment["WINEPREFIX"],
                  wanted == trimmed || wanted == trimmed + "/",
                  let executable = GameWindows.executablePath(of: pid) else { return nil }
            return Process(pid: pid, executable: executable, program: process.arguments.first ?? "",
                           fastSync: WineEnvironment.fastSyncIsOn(process.environment),
                           arguments: Array(process.arguments.dropFirst()), started: startTime(of: pid))
        }
    }

    static func startTime(of pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)
            + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
    }

    /// CPU time the process has used, in the kernel's own units: only for comparing processes.
    static func cpuTime(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        return result == 0 ? info.ri_user_time + info.ri_system_time : nil
    }

    /// CPU seconds the processes have used, together; nil when none can be read.
    public static func cpuSeconds(of pids: [pid_t]) -> TimeInterval? {
        let times = pids.compactMap(cpuTime)
        guard !times.isEmpty else { return nil }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = Double(times.reduce(0, +))
        return ticks * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }

    /// Processes in `bottle` started from a program in the Windows folder `folder`.
    public static func game(in bottle: URL, folder: String) -> [pid_t] {
        running(in: bottle).filter { runs($0.program, from: folder, bottle: bottle) }.map(\.pid)
    }

    /// Whether the Windows program `program` is inside `folder`, compared as Windows does: without case, with
    /// either slash. A program Magic Kettle started by its Mac path keeps that path as its command line, so it is
    /// turned into the Windows one first (C: inside `bottle`, Z: elsewhere): HedgeModManager, run with Steam from
    /// Downloads, had its window up for four minutes and was closed as never having shown one.
    static func runs(_ program: String, from folder: String, bottle: URL? = nil) -> Bool {
        func normalized(_ path: String) -> String {
            path.replacingOccurrences(of: "/", with: "\\").lowercased()
        }
        let root = URL(filePath: "/", directoryHint: .isDirectory)
        let program = program.hasPrefix("/")
            ? WindowsPath.windowsPath(of: URL(filePath: program), inBottle: bottle ?? root) : program
        let base = normalized(folder)
        let prefix = base.hasSuffix("\\") ? base : base + "\\"
        if normalized(program).hasPrefix(prefix) { return true }
        guard let bottle, let url = WindowsPath.macURL(for: program, bottle: bottle) else { return false }
        return normalized(WindowsPath.windowsPath(of: url, inBottle: bottle)).hasPrefix(prefix)
    }

    /// The Wine tree a process runs from: its loader is `<tree>/bin/…` or `<tree>/lib/…`.
    static func wineTree(of executable: String) -> URL? {
        let parts = executable.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = parts.lastIndex(where: { $0 == "bin" || $0 == "lib" }), index > 0 else { return nil }
        return URL(filePath: parts[..<index].joined(separator: "/"), directoryHint: .isDirectory)
    }

    static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let found = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(Int(max(found, 0)))).filter { $0 > 0 }
    }
}

extension WindowsPath {
    /// The path a Mac folder has inside `bottle`, as Wine names it: on the drive whose folder holds it most closely
    /// (`drive_c/…` is `C:\…`, the home folder `H:\…`), else on `Z:`, the Mac's `/`. With `H:` added, a program
    /// in `~/Games` runs as `H:\Games\…`, and taking it for `Z:\Users\…` would lose its window.
    public static func windowsPath(of url: URL, inBottle bottle: URL) -> String {
        let resolved = url.resolvingSymlinksInPath()
        let closest = drives(in: bottle)
            .compactMap { drive, root in windowsPath(of: resolved, under: root, drive: drive).map { (root, $0) } }
            .max { $0.0.path(percentEncoded: false).count < $1.0.path(percentEncoded: false).count }
        if let closest { return closest.1 }
        return windowsPath(of: resolved, under: URL(filePath: "/", directoryHint: .isDirectory), drive: "Z") ?? ""
    }

    /// The bottle's drive letters and the folders they lead to (`dosdevices/c:` → `drive_c`); `C:` is `drive_c`
    /// even when the bottle's links can't be read.
    static func drives(in bottle: URL) -> [(Character, URL)] {
        let fileManager = FileManager.default
        let devices = bottle.appending(path: "dosdevices", directoryHint: .isDirectory)
        let names = (try? fileManager.contentsOfDirectory(atPath: devices.path)) ?? []
        let linked: [(Character, URL)] = names.compactMap { name in
            guard name.count == 2, name.hasSuffix(":"), let letter = name.first, letter.isLetter,
                  let target = try? fileManager.destinationOfSymbolicLink(atPath: devices.appending(path: name).path)
            else { return nil }
            let root = target.hasPrefix("/") ? URL(filePath: target, directoryHint: .isDirectory)
                : devices.appending(path: target, directoryHint: .isDirectory)
            return (Character(letter.uppercased()), root.resolvingSymlinksInPath())
        }
        guard !linked.contains(where: { $0.0 == "C" }) else { return linked }
        let driveC = bottle.appending(path: "drive_c", directoryHint: .isDirectory)
        return linked + [("C", driveC.resolvingSymlinksInPath())]
    }
}
