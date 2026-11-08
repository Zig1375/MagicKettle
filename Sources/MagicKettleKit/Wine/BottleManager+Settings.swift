import Foundation

extension BottleManager {
    /// Wine's Mac driver: Retina mode, and both ⌘ keys.
    static let macDriverKey = #"Software\Wine\Mac Driver"#
    /// Windows' desktop: the system DPI Wine draws a DPI-unaware program with (`GameScaling`).
    static let desktopKey = #"Control Panel\Desktop"#

    /// `EmulateModeset` lets a game switch to a low resolution without touching the Mac's display.
    /// `StretchWindows` (Magic Kettle's Wine) lets the player drag the corner of a game window that can't be resized:
    /// a Unity game with a fixed 1440×800 window was half the screen on a Retina Mac and couldn't be made bigger.
    /// The window keeps its size for the game and Wine scales the picture and the mouse. Both keys are the X11
    /// driver's by name, but Wine's core reads them for every driver.
    static func enableScaling(bottle: URL) throws {
        let key = #"Software\Wine\X11 Driver"#
        try setRegistryString(bottle: bottle, key: key, name: "EmulateModeset", value: "y")
        try setRegistryString(bottle: bottle, key: key, name: "StretchWindows", value: "y")
    }

    /// The bottle's scaling, which a program run with a store (`GameRecord.isProgram`) keeps out of, and Open boxes
    /// without the Mac's root (`hideRoot`).
    static func setUpDisplays(bottle: URL, for game: GameRecord) throws {
        try enableScaling(bottle: bottle)
        try hideRoot(bottle: bottle)
        guard game.isProgram else { return }
        try keepRealDisplay(bottle: bottle, programs: [URL(filePath: game.executable).lastPathComponent])
    }

    /// Programs run beside a store's games (mod managers) see the Mac's displays as they are. The emulated display
    /// mode is for games; Vortex, an Electron program, went transparent in Steam's Windows once moved from a
    /// MacBook's screen to a 4K monitor, and white when maximized. Wine reads both keys for each program from
    /// `AppDefaults\<exe>\X11 Driver` before the bottle's own, so the store's games keep them.
    static func keepRealDisplay(bottle: URL, programs: [String]) throws {
        for exe in Set(programs) where !exe.isEmpty {
            let key = #"Software\Wine\AppDefaults\"# + exe + #"\X11 Driver"#
            try setRegistryString(bottle: bottle, key: key, name: "EmulateModeset", value: "n")
            try setRegistryString(bottle: bottle, key: key, name: "StretchWindows", value: "n")
        }
    }

    static func keepsRealDisplay(bottle: URL, program: String) -> Bool {
        guard !program.isEmpty,
              let text = try? String(contentsOf: bottle.appending(path: "user.reg"), encoding: .utf8) else {
            return false
        }
        let key = #"Software\Wine\AppDefaults\"# + program + #"\X11 Driver"#
        return WineRegistry.string(in: text, key: key, name: "EmulateModeset") == "n"
            && WineRegistry.string(in: text, key: key, name: "StretchWindows") == "n"
    }

    /// Both ⌘ keys reach Windows as Ctrl (`GameRecord.commandAsControl`); off, they are the Windows key.
    static func setCommandAsControl(bottle: URL, _ on: Bool) throws {
        for side in ["LeftCommandIsCtrl", "RightCommandIsCtrl"] {
            try setRegistryString(bottle: bottle, key: macDriverKey, name: side, value: on ? "y" : "n")
        }
    }

    /// WPF programs draw without the GPU. Through DXVK their windows stayed blank: SA Mod Manager in Steam's Windows,
    /// where WineD3D isn't tried, showed an empty white "Select a Language" box and the launch gave up. WPF's own
    /// switch draws them on the CPU, as on a PC without a graphics card; games don't use WPF.
    static func drawWPFWithoutGPU(bottle: URL) throws {
        try setRegistryDWord(bottle: bottle, key: #"Software\Microsoft\Avalon.Graphics"#,
                             name: "DisableHWAcceleration", value: 1)
    }

    static func disableCrashDialog(bottle: URL) throws {
        let userReg = bottle.appending(path: "user.reg")
        let text = try String(contentsOf: userReg, encoding: .utf8)
        let key = #"Software\Wine\WineDbg"#
        guard !WineRegistry.contains(text, key: key, entry: #""ShowCrashDialog"=dword:00000000"#) else { return }
        try WineRegistry.setDWord(in: text, key: key, name: "ShowCrashDialog", value: 0)
            .write(to: userReg, atomically: true, encoding: .utf8)
    }

    /// Sets a DWORD in the bottle's `user.reg`, writing only if it changes. Only while the bottle is idle.
    static func setRegistryDWord(bottle: URL, key: String, name: String, value: UInt32) throws {
        let userReg = bottle.appending(path: "user.reg")
        let text = try String(contentsOf: userReg, encoding: .utf8)
        let hex = String(value, radix: 16)
        let entry = "\"\(name)\"=dword:\(String(repeating: "0", count: 8 - hex.count))\(hex)"
        guard !WineRegistry.contains(text, key: key, entry: entry) else { return }
        try WineRegistry.setDWord(in: text, key: key, name: name, value: value)
            .write(to: userReg, atomically: true, encoding: .utf8)
    }

    /// Sets a string in the bottle's `user.reg` (or `system.reg`, for keys under HKLM), writing only if it
    /// changes. Only while the bottle is idle.
    static func setRegistryString(bottle: URL, key: String, name: String, value: String,
                                  file: String = "user.reg") throws {
        let userReg = bottle.appending(path: file)
        let text = try String(contentsOf: userReg, encoding: .utf8)
        guard WineRegistry.string(in: text, key: key, name: name) != value else { return }
        try WineRegistry.setString(in: text, key: key, name: name, value: value)
            .write(to: userReg, atomically: true, encoding: .utf8)
    }
}
