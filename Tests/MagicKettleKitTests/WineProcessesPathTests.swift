import Foundation
@testable import MagicKettleKit
import Testing

extension WineProcessesTests {
    /// A program Magic Kettle started by its Mac path keeps that path as its command line: HedgeModManager from
    /// Downloads, run with Steam, had its window up for four minutes and was closed as "no window".
    @Test func aProgramStartedByItsMacPathIsInItsWindowsFolder() {
        let bottle = URL(filePath: "/B/bottle", directoryHint: .isDirectory)
        #expect(WineProcesses.runs("/Users/me/Downloads/HedgeModManager.exe", from: #"Z:\Users\me\Downloads"#,
                                   bottle: bottle))
        #expect(WineProcesses.runs("/B/bottle/drive_c/Games/Hedge/HedgeModManager.exe", from: #"C:\Games\Hedge"#,
                                   bottle: bottle))
        #expect(!WineProcesses.runs("/Users/me/Desktop/other.exe", from: #"Z:\Users\me\Downloads"#, bottle: bottle))
        // Without the bottle, a Mac path is on Wine's Z: drive.
        #expect(WineProcesses.runs("/Users/me/Downloads/H.exe", from: #"Z:\Users\me\Downloads"#))
    }
}
